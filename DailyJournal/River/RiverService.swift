//
//  RiverService.swift
//  DailyJournal
//
//  Storage + orchestration for the River system.
//
//  Marks live at users/{uid}/riverMarks/{entryId}. Writes are fire-and-forget
//  (Firestore local cache first), matching JournalService. Rivers are built on
//  demand from marks — not persisted — so deleting an entry can't strand a
//  stale artifact.
//

import Foundation
import FirebaseFirestore

final class RiverService {

    private let db = Firestore.firestore()

    private func marksCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("riverMarks")
    }

    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return cached
        }
        return try await query.getDocuments(source: .default)
    }

    // MARK: - Generate + store a mark for one entry
    //
    // Called from both save paths (90-second + free-write) as a detached
    // background task. Saves a LOCAL mark immediately so the river is never
    // empty, then upgrades it with Gemini signals if a key is present.
    func generateMark(
        entryText: String,
        entryId: String,
        userId: String,
        entryCreatedAt: Date
    ) async {
        // 1. Immediate local mark.
        let localSignals = LocalRiver.markSignals(from: entryText)
        store(signals: localSignals, entryId: entryId, userId: userId,
              date: entryCreatedAt, source: "local")

        // 2. Crisis signal → do not enrich; let the safety flow own it.
        guard localSignals.safetyLevel == "none" else { return }

        // 3. Gemini upgrade (silent on failure).
        guard let signals = try? await AIService.shared.extractRiverMarkSignals(from: entryText),
              signals.safetyLevel == "none"
        else { return }
        store(signals: signals, entryId: entryId, userId: userId,
              date: entryCreatedAt, source: "gemini")
    }

    private func store(
        signals: RiverMarkSignals,
        entryId: String,
        userId: String,
        date: Date,
        source: String
    ) {
        let mark = RiverMark(
            entryId: entryId, userId: userId, localDate: date,
            valence: signals.valence, activation: signals.activation,
            clarity: signals.clarity, pressure: signals.pressure,
            selfCompassion: signals.selfCompassion,
            dominantEmotions: signals.dominantEmotions,
            motifs: signals.motifs, themes: signals.themes,
            quoteAnchor: signals.quoteAnchor,
            waterState: signals.waterState, marker: signals.marker,
            safetyLevel: signals.safetyLevel, source: source
        )
        marksCollection(for: userId).document(entryId).setData(mark.toFirestoreData())
    }

    // MARK: - Fetch marks
    func fetchMarks(for userId: String, days: Int = 35) async throws -> [RiverMark] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let snapshot = try await getDocuments(
            marksCollection(for: userId)
                .whereField("localDate", isGreaterThanOrEqualTo: Timestamp(date: cutoff))
        )
        return snapshot.documents.compactMap { RiverMark(from: $0.data()) }
    }

    // MARK: - Build a river for a window
    //
    // `enrich` runs the Gemini narrative pass when a key is present and there's
    // enough data; otherwise the deterministic LocalRiver text is used.
    func buildRiver(window: RiverWindow, for userId: String, enrich: Bool = true) async -> River {
        let marks = (try? await fetchMarks(for: userId)) ?? []

        // Deterministic river first — always works.
        let base = LocalRiver.build(window: window, marks: marks)

        guard enrich, AIService.shared.isAIAvailable, !base.isSparse else { return base }

        let windowMarks = marks.filter { $0.localDate >= base.startDate && $0.localDate <= base.endDate }
        let narrative = try? await AIService.shared.generateRiverNarrative(
            window: window,
            marksSummary: LocalRiver.marksSummary(windowMarks),
            recurringWords: base.recurringWords
        )
        guard let narrative else { return base }
        return LocalRiver.build(window: window, marks: marks, narrative: narrative)
    }

    // MARK: - Delete a mark (called when its entry is deleted)
    func deleteMark(entryId: String, userId: String) {
        marksCollection(for: userId).document(entryId).delete(completion: nil)
    }

    // MARK: - Backfill
    /// Generate marks for past entries that don't have one yet (e.g. first run
    /// after the feature ships). Local-only to stay cheap and offline-safe.
    func backfillLocalMarks(from entries: [JournalEntry], userId: String) async {
        let existing = Set(((try? await fetchMarks(for: userId, days: 40)) ?? []).map { $0.entryId })
        for entry in entries where !existing.contains(entry.id) {
            let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10 else { continue }
            let signals = LocalRiver.markSignals(from: trimmed)
            store(signals: signals, entryId: entry.id, userId: userId,
                  date: entry.createdAt, source: "local")
        }
    }
}
