//
//  EchoService.swift
//  DailyJournal
//
//  Firestore CRUD for the `users/{uid}/echoes` subcollection.
//
//  Write pattern: same fire-and-forget approach as JournalService — we write to
//  Firestore's local cache immediately and let the SDK sync in the background.
//  Reads use the cache-first default behaviour.
//

import Foundation
import FirebaseFirestore

final class EchoService {

    private let db = Firestore.firestore()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("echoes")
    }

    // Cache-first read (mirrors JournalService): serve the warm on-disk cache
    // instantly and only hit the network when the cache is cold. Keeps echoes
    // surfacing offline and on first paint.
    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return cached
        }
        return try await query.getDocuments(source: .default)
    }

    // MARK: - Create

    /// Fire-and-forget. Writes to local cache immediately.
    func createEcho(_ echo: Echo) {
        collection(for: echo.userId)
            .document(echo.id)
            .setData(echo.toFirestoreData())
    }

    // MARK: - Fetch

    /// Returns the single highest-confidence pending echo whose surface date has
    /// passed. Returns nil if none exists.
    ///
    /// Also schedules a background decay pass to expire stale echoes — this
    /// runs fire-and-forget and never blocks the caller.
    func fetchTopPendingEcho(for userId: String) async throws -> Echo? {
        let now = Date()

        // Single-field equality only (auto-indexed) — combining an inequality with
        // an order-by on a *different* field (confidence) previously required a
        // composite index that wasn't deployed, so this query silently threw and
        // no echo ever surfaced. We now fetch pending echoes and do the surface-date
        // gate + highest-confidence pick on the client. Cache-first so it works
        // offline and on first paint.
        // FirestoreCacheFirst rather than the local `getDocuments`: "no pending
        // echoes" is the normal answer, and `getDocuments` reads an empty cache
        // result as a miss — so this hit the server on every Home load while
        // gating first paint.
        let snapshot = try await FirestoreCacheFirst.documents(
            collection(for: userId)
                .whereField("status", isEqualTo: EchoStatus.pending.rawValue)
                .limit(to: 50),
            key: "pendingEchoes.\(userId)"
        )

        // Schedule decay asynchronously — never awaited
        Task.detached(priority: .background) { [weak self] in
            try? await self?.decayExpiredEchoes(for: userId)
        }

        return snapshot.documents
            .compactMap { Echo(from: $0.data()) }
            .filter { $0.surfaceAfterDate <= now }
            // Highest confidence first; tie-break on the oldest surface date.
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.surfaceAfterDate < $1.surfaceAfterDate
            }
            .first
    }

    // MARK: - Skip / decay

    /// Call when the user taps "skip" or "not yet".
    ///
    /// Rule: skip once → increment count, still pending.
    ///       skip twice → mark dismissed permanently.
    ///
    /// Fire-and-forget.
    func skipEcho(id: String, userId: String, currentSkipCount: Int) {
        let newCount = currentSkipCount + 1
        var fields: [String: Any] = ["skipCount": newCount]
        if newCount >= 2 {
            fields["status"] = EchoStatus.dismissed.rawValue
        }
        collection(for: userId).document(id).updateData(fields)
    }

    // MARK: - Answer

    /// Call when the user confirms an echo (taps "done", "it happened", etc.).
    /// `response` is the optional "how did it go?" text, in the user's own words.
    /// Fire-and-forget.
    func markAnswered(_ echo: Echo, response: String?) {
        let trimmed = response?.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "status":     EchoStatus.answered.rawValue,
            "answeredAt": Timestamp(date: Date())
        ]
        if let trimmed, !trimmed.isEmpty { fields["response"] = trimmed }
        collection(for: echo.userId).document(echo.id).updateData(fields)

        if let trimmed, !trimmed.isEmpty {
            recordOutcome(for: echo, response: trimmed)
        }
    }

    /// An answered echo is the only place the app learns what actually HAPPENED
    /// after something the user said they would do — everything else it stores is
    /// an intention or an interpretation. Episodes are the one unit the nightly
    /// miner can build an action→outcome claim from, so the outcome is appended
    /// to the source entry's analysis as one.
    ///
    /// Three constraints worth knowing (all in `mineHypothesesForUser`,
    /// functions/index.js): `arrayUnion` rather than read-modify-write, because
    /// `analyzeEntry` owns this document and persists it with `setData`; a later
    /// re-analysis (only triggered by editing the entry text) drops the episode;
    /// and the miner reads only the first 3 episodes, so an entry that already
    /// produced 3 will not carry this one to the model.
    private func recordOutcome(for echo: Echo, response: String) {
        let episode = EpisodeFrame(
            episodeId: "echo-\(echo.id)",
            situation: echo.quote,
            emotions: [],
            bodySignals: [],
            outcome: response
        )
        db.collection("users").document(echo.userId)
            .collection("entryAnalyses").document(echo.sourceEntryId)
            .updateData(["episodes": FieldValue.arrayUnion([episode.toFirestoreData()])])
    }

    // MARK: - Decay

    /// Marks any pending echo as expired once 7 days have passed since it FIRST
    /// became surfaceable — not 7 days since it was created.
    ///
    /// This used to key off `createdAt`, which is wrong: `surfaceAfterHours` can
    /// itself be up to 336h (14 days, for `.mood_marker`), so a fixed 7-day
    /// cutoff from creation could expire an echo before, or at the exact moment,
    /// it was first allowed to surface at all (`.theme` surfaces at 168h/7 days —
    /// the same instant it became decay-eligible under the old rule). Filtering
    /// in Swift rather than a single range query, same pattern as
    /// `fetchTopPendingEcho` just above: this mixes an equality filter with a
    /// derived-field comparison, not a single indexed inequality.
    private func decayExpiredEchoes(for userId: String) async throws {
        let now = Date()

        let snapshot = try await collection(for: userId)
            .whereField("status", isEqualTo: EchoStatus.pending.rawValue)
            .getDocuments()

        let expired = snapshot.documents.filter { doc in
            guard let echo = Echo(from: doc.data()) else { return false }
            return echo.surfaceAfterDate.addingTimeInterval(7 * 24 * 3600) < now
        }
        guard !expired.isEmpty else { return }

        let batch = db.batch()
        for doc in expired {
            batch.updateData(["status": EchoStatus.expired.rawValue], forDocument: doc.reference)
        }
        try await batch.commit()

        for _ in expired {
            await AnalyticsManager.shared.logEvent(.echoExpired)
        }
    }
}
