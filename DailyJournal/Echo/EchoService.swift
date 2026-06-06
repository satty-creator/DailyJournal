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
        let now = Timestamp(date: Date())

        let snapshot = try await collection(for: userId)
            .whereField("status",          isEqualTo: EchoStatus.pending.rawValue)
            .whereField("surfaceAfterDate", isLessThanOrEqualTo: now)
            .order(by: "surfaceAfterDate", descending: false) // oldest surface date first
            .order(by: "confidence",       descending: true)  // highest confidence wins
            .limit(to: 1)
            .getDocuments()

        // Schedule decay asynchronously — never awaited
        Task.detached(priority: .background) { [weak self] in
            try? await self?.decayExpiredEchoes(for: userId)
        }

        return snapshot.documents.compactMap { Echo(from: $0.data()) }.first
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
    /// Fire-and-forget.
    func markAnswered(id: String, userId: String) {
        collection(for: userId).document(id).updateData([
            "status":     EchoStatus.answered.rawValue,
            "answeredAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Decay

    /// Marks any pending echoes older than 7 days as expired in a single batch.
    /// Runs in the background — failure is intentionally silent.
    private func decayExpiredEchoes(for userId: String) async throws {
        let cutoff = Timestamp(date: Date().addingTimeInterval(-7 * 24 * 3600))

        let snapshot = try await collection(for: userId)
            .whereField("status",    isEqualTo: EchoStatus.pending.rawValue)
            .whereField("createdAt", isLessThan: cutoff)
            .getDocuments()

        guard !snapshot.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snapshot.documents {
            batch.updateData(["status": EchoStatus.expired.rawValue], forDocument: doc.reference)
        }
        try await batch.commit()
    }
}
