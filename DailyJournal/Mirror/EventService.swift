// EventService.swift
// DailyJournal
//
// Firestore CRUD + backfill for `users/{uid}/events` — see JournalEvent.swift
// for why this collection exists.

import Foundation
import FirebaseFirestore

final class EventService {

    static let shared = EventService()

    private let db = Firestore.firestore()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("events")
    }

    // MARK: - Promote

    /// Fire-and-forget promotion of one analysis's episodes into first-class
    /// event documents. Idempotent — see `JournalEvent.id` — so calling this
    /// again for an entry whose analysis didn't change (a content-hash cache
    /// hit in `analyzeEntry`) just overwrites with identical data rather than
    /// duplicating. Called from BOTH the fresh-analysis path and the cache-hit
    /// path in `AIService.analyzeEntry`, and from the backfill sweep below —
    /// three different callers converging on the same idempotent write.
    func promote(from analysis: EntryAnalysis) {
        guard !analysis.episodes.isEmpty else { return }
        let batch = db.batch()
        for episode in analysis.episodes {
            let event = JournalEvent(from: analysis, episode: episode)
            let ref = collection(for: analysis.userId).document(event.id)
            batch.setData(event.toFirestoreData(), forDocument: ref, merge: true)
        }
        batch.commit(completion: nil)
    }

    // MARK: - Backfill (existing entries analysed before this collection existed)

    private func doneKey(_ userId: String) -> String { "eventBackfillDone.\(userId)" }
    private func cursorKey(_ userId: String) -> String { "eventBackfillCursor.\(userId)" }

    /// Promotes one page of historical `entryAnalyses` docs that predate this
    /// collection. Pure migration, no AI call — the episodes already exist in
    /// each analysis; this only reads (plaintext, nothing to decrypt) and
    /// writes. Cursor-based and idempotent per page, so calling this once per
    /// app session — same trigger point as `MemoryProfileService.build`, fire-
    /// and-forget from `HomeView`'s load — walks a user's whole history over
    /// several sessions without ever blocking anything or redoing work.
    func backfillIfNeeded(for userId: String, pageSize: Int = 25) async {
        guard !UserDefaults.standard.bool(forKey: doneKey(userId)) else { return }

        // `Date.distantPast` as a "beginning of time" sentinel crashes here —
        // Firestore's `Timestamp(date:)` throws an uncaught NSException
        // ("Timestamp seconds out of range") because `distantPast`'s
        // underlying value falls outside what it can represent. The app's own
        // history can't predate the Unix epoch, so 1970-01-01 is a real value
        // that means the same thing ("everything") without crossing that line.
        let cursorSeconds = UserDefaults.standard.double(forKey: cursorKey(userId))
        let cursor = cursorSeconds > 0 ? Date(timeIntervalSince1970: cursorSeconds) : Date(timeIntervalSince1970: 0)

        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("entryAnalyses")
            .whereField("createdAt", isGreaterThan: Timestamp(date: cursor))
            .order(by: "createdAt")
            .limit(to: pageSize)
            .getDocuments()
        else { return }

        let analyses = snapshot.documents.compactMap { EntryAnalysis(from: $0.data()) }
        for analysis in analyses { promote(from: analysis) }

        if let last = analyses.last {
            UserDefaults.standard.set(last.createdAt.timeIntervalSince1970, forKey: cursorKey(userId))
        }
        // A page shorter than requested means we've reached the end — stop
        // paying for this read on every future session.
        if snapshot.documents.count < pageSize {
            UserDefaults.standard.set(true, forKey: doneKey(userId))
        }
    }

    // MARK: - Read

    /// The most salient recent events, for grounding a prompt in a specific
    /// remembered moment instead of an aggregate. Cache-first; small collection,
    /// single-field order — no composite index needed.
    func fetchRecent(for userId: String, limit: Int = 20) async -> [JournalEvent] {
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            collection(for: userId)
                .order(by: "occurredAt", descending: true)
                .limit(to: limit),
            key: "recentEvents.\(userId).\(limit)"
        ) else { return [] }

        return snapshot.documents.compactMap { JournalEvent(from: $0.data()) }
    }
}
