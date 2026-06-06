//
//  PatternDetectionService.swift
//  DailyJournal
//
//  Orchestrates Pattern Callback detection over a 60-day window:
//    1. Fetch entries; keep the last 60 days.
//    2. HARD SAFETY GATE — if any entry trips PatternSafety, create NOTHING and
//       report .safetyRouted so the caller shows the soft resource card.
//    3. Detect patterns with Gemini (or a modest local fallback when there's no
//       API key), re-filter each result through PatternSafety.
//    4. Score salience, drop muted / out-of-scope / duplicate callbacks.
//    5. Persist up to 2 pending callbacks (the surface gate shows one).
//
//  Always called fire-and-forget from Home load. It MUST NEVER throw into the
//  UI — every failure degrades to "no pattern".
//

import Foundation

enum PatternDetectionOutcome {
    case noPattern
    case created(Int)      // number of callbacks persisted
    case safetyRouted      // crisis signal found — route to resource card
    case skipped           // gating said don't bother
}

final class PatternDetectionService {

    static let shared = PatternDetectionService()
    private init() {}

    private let journalService  = JournalService()
    private let callbackService  = PatternCallbackService()

    private let windowDays = 60
    private let minEntries = 6

    // MARK: - Main entry point

    /// Runs detection if (and only if) gating allows. Sets the throttle stamp
    /// whenever it actually does work.
    func detectIfNeeded(for userId: String) async -> PatternDetectionOutcome {
        let settings = PatternSettings(userId: userId)

        // Cheap local gates first.
        guard settings.frequency != .off else { return .skipped }
        guard settings.shouldRunDetection else { return .skipped }

        // Need the current callback set to decide if detection is worthwhile.
        let existing = (try? await callbackService.fetchAll(for: userId)) ?? []
        guard callbackService.detectionIsWorthwhile(from: existing, settings: settings) else {
            return .skipped
        }

        // Pull the 60-day window.
        let all = (try? await journalService.fetchAllEntries(for: userId)) ?? []
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 86400)
        let window = all.filter { $0.createdAt >= cutoff }
        guard window.count >= minEntries else { return .skipped }

        // Mark that detection ran (so we honour the ~20h throttle even on a
        // null result — we don't want to re-scan every Home load).
        settings.lastDetection = Date()

        // ── HARD SAFETY GATE ───────────────────────────────────────────────
        if PatternSafety.corpusHasCrisisSignal(window.map(\.content)) {
            return .safetyRouted
        }

        // Detect (LLM if we have a key, else local fallback).
        let raws: PatternDetectionRaw
        if AIService.shared.hasApiKey {
            guard let result = try? await AIService.shared
                .detectPatterns(indexedEntries: window.map { snippet(for: $0) })
            else { return .noPattern }
            raws = result
        } else {
            raws = LocalPatternDetector.detect(in: window)
        }

        // The model can also self-report a safety flag.
        if raws.safetyFlag { return .safetyRouted }
        guard !raws.callbacks.isEmpty else { return .noPattern }

        // Map → score → filter → persist.
        let persisted = persist(
            raws.callbacks,
            window: window,
            userId: userId,
            settings: settings,
            existing: existing
        )
        return persisted > 0 ? .created(persisted) : .noPattern
    }

    // MARK: - Persistence pipeline

    private func persist(
        _ raws: [RawPatternCallback],
        window: [JournalEntry],
        userId: String,
        settings: PatternSettings,
        existing: [PatternCallback]
    ) -> Int {

        // Keys already represented by a live (pending/shown/answered) callback,
        // so we never repeat the same observation.
        let liveKeys: Set<String> = Set(
            existing
                .filter { $0.status != .dismissed && $0.status != .muted }
                .map { dedupKey(archetype: $0.archetype, entity: $0.entity) }
        )

        var built: [PatternCallback] = []

        for raw in raws {
            // Defense-in-depth safety re-check on the generated text itself.
            if PatternSafety.containsCrisisSignal(in: raw.callbackLine) { continue }
            if let e = raw.entity, PatternSafety.containsCrisisSignal(in: e) { continue }

            // Honour scope + mute preferences.
            guard settings.scope.allows(raw.archetype) else { continue }
            if let e = raw.entity, settings.isMuted(e) { continue }

            // De-dupe against existing live callbacks and within this batch.
            let key = dedupKey(archetype: raw.archetype, entity: raw.entity)
            guard !liveKeys.contains(key) else { continue }
            guard !built.contains(where: {
                dedupKey(archetype: $0.archetype, entity: $0.entity) == key
            }) else { continue }

            // Map evidence indices back to real entries; re-check each quote.
            let evidence = mapEvidence(raw.evidence, window: window)
            guard evidence.count >= 2 else { continue }

            let score = salience(archetype: raw.archetype,
                                 confidence: raw.confidence,
                                 evidence: evidence,
                                 settings: settings)

            built.append(PatternCallback(
                userId:        userId,
                archetype:     raw.archetype,
                callbackLine:  raw.callbackLine,
                entity:        raw.entity,
                evidence:      evidence,
                salienceScore: score
            ))
        }

        // Keep callbacks scarce: persist at most the 2 most salient.
        let top = built.sorted { $0.salienceScore > $1.salienceScore }.prefix(2)
        for callback in top { callbackService.createCallback(callback) }
        return top.count
    }

    // MARK: - Evidence mapping

    private func mapEvidence(
        _ raw: [(index: Int, quote: String)],
        window: [JournalEntry]
    ) -> [PatternEvidence] {
        raw.compactMap { item in
            guard window.indices.contains(item.index) else { return nil }
            // Final safety net — never carry a crisis quote into a callback.
            if PatternSafety.containsCrisisSignal(in: item.quote) { return nil }
            let entry = window[item.index]
            return PatternEvidence(
                entryId:        entry.id,
                entryCreatedAt: entry.createdAt,
                quote:          item.quote
            )
        }
    }

    // MARK: - Salience

    private func salience(
        archetype: PatternArchetype,
        confidence: Double,
        evidence: [PatternEvidence],
        settings: PatternSettings
    ) -> Double {
        let base = archetype.baseSalience
        let recency = recencyFactor(for: evidence)
        let conf = min(1.0, max(0.3, confidence))
        let boost = settings.salienceBoost(for: archetype)
        return base * recency * conf + boost
    }

    private func recencyFactor(for evidence: [PatternEvidence]) -> Double {
        guard let newest = evidence.map(\.entryCreatedAt).max() else { return 0.6 }
        let days = Date().timeIntervalSince(newest) / 86400
        if days <= 3  { return 1.0 }
        if days <= 7  { return 0.9 }
        if days <= 30 { return 0.75 }
        return 0.6
    }

    // MARK: - Helpers

    private func dedupKey(archetype: PatternArchetype, entity: String?) -> String {
        "\(archetype.rawValue)|\((entity ?? "").lowercased())"
    }

    /// A compact, dated snippet for the detection prompt.
    private func snippet(for entry: JournalEntry) -> String {
        let date = entry.createdAt.formatted(.dateTime.month(.abbreviated).day())
        let body = String(entry.content.prefix(260))
        return "(\(date)) \(body)"
    }
}
