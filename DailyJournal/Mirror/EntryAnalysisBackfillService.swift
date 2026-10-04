//
//  EntryAnalysisBackfillService.swift
//  DailyJournal
//
//  Closes the gap between "entries written" and "entries analysed".
//
//  The Mirror's whole unlock chain is gated on `entryAnalyses` docs, not on the
//  raw entry count: the server mine needs ≥ MIN_ANALYSES (3) structured
//  EntryAnalysis docs before it will produce a single hypothesis
//  (functions/index.js `mineHypothesesForUser`). But `AIService.analyzeEntry`
//  only PERSISTS an analysis on the AI-success path — when AI was unavailable
//  at save time (offline, signed-out, consent off) or Gemini failed, it returns
//  an unpersisted `EntryAnalysis.local(...)` and nothing is written. So a user
//  can have 3+ entries and 0–2 analyses, and the "unlock at 3" never fires.
//
//  This service re-runs `analyzeEntry` for any recent entry that has no
//  `entryAnalyses/{id}` doc yet, whenever AI is available. `analyzeEntry` is
//  self-persisting, idempotent (content-hash guard), and never throws, so this
//  is a safe, cheap reconciliation pass — not a second writer.
//
//  Short entries (≤ 30 chars) still return a non-persisted local analysis and
//  legitimately don't count: there is nothing for the model to structure. The
//  guarantee is "every SUBSTANTIVE entry gets an analysis", which is what the
//  3-entry unlock actually needs.
//

import Foundation
import FirebaseFirestore

final class EntryAnalysisBackfillService {
    static let shared = EntryAnalysisBackfillService()
    private init() {}

    /// Most-recent entries to reconcile. The mine only reasons over the most
    /// recent `ANALYSIS_LOOKBACK` (20) analyses anyway, so there is no value in
    /// backfilling older history on the hot path.
    private let window = 20

    /// Local cooldown so this doesn't re-sweep on every Mirror open / foreground
    /// within a session. Short on purpose — the point is to catch up quickly
    /// after AI comes back, not to run once a day. Mirrors the per-user cooldown
    /// shape used by `MirrorViewModel.refreshDerivedIfNeeded`.
    private let cooldown: TimeInterval = 10 * 60

    /// Re-analyse any of the most recent entries that lack a persisted analysis.
    /// No-ops when AI is unavailable (nothing would persist) or within the
    /// cooldown. Never throws.
    func run(for userId: String) async {
        guard AIService.shared.isAIAvailable, !userId.isEmpty else { return }

        let cooldownKey = "entryAnalysisBackfillAttempt_\(userId)"
        if let last = UserDefaults.standard.object(forKey: cooldownKey) as? Date,
           Date().timeIntervalSince(last) < cooldown {
            return
        }
        UserDefaults.standard.set(Date(), forKey: cooldownKey)

        let entries: [JournalEntry]
        do {
            entries = try await JournalService().fetchEntriesForMirror(for: userId, limit: window)
        } catch {
            return
        }
        guard !entries.isEmpty else { return }

        let analysedIds = await existingAnalysisIds(for: userId)

        for entry in entries {
            // Same substance floor as `analyzeEntry` — a sub-30-char entry would
            // only bounce back a local, unpersisted analysis, so skip the call.
            guard entry.content.count > 30 else { continue }
            guard !analysedIds.contains(entry.id) else { continue }

            // Self-persisting and idempotent; we don't need the return value.
            _ = await AIService.shared.analyzeEntry(
                entryId: entry.id,
                userId: userId,
                text: entry.content,
                entryCreatedAt: entry.createdAt
            )
        }
    }

    /// The set of entry ids that already have an `entryAnalyses/{id}` doc.
    /// Cache-first, then server, mirroring the app's read strategy. Returns an
    /// empty set on failure, which just means the backfill is conservative (it
    /// may re-issue an analyze call that `analyzeEntry`'s own content-hash guard
    /// then short-circuits) rather than wrong.
    private func existingAnalysisIds(for userId: String) async -> Set<String> {
        let query = Firestore.firestore()
            .collection("users").document(userId)
            .collection("entryAnalyses")
            .limit(to: 100)

        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return Set(cached.documents.map(\.documentID))
        }
        if let server = try? await query.getDocuments() {
            return Set(server.documents.map(\.documentID))
        }
        return []
    }
}
