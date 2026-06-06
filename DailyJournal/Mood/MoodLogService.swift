//
//  MoodLogService.swift
//  DailyJournal
//
//  Firestore CRUD for daily mood check-ins. Same fire-and-forget write pattern
//  as JournalService — writes hit the local cache instantly and sync later.
//

import Foundation
import FirebaseFirestore

final class MoodLogService {

    private let db = Firestore.firestore()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("moodLogs")
    }

    /// Logs (or overwrites) today's mood. Fire-and-forget.
    func logMood(userId: String, mood: Mood, date: Date = Date()) {
        let log = MoodLog(userId: userId, mood: mood, date: date)
        collection(for: userId)
            .document(log.id)
            .setData(log.toFirestoreData(), merge: true)
    }

    /// Fetches today's mood log, if one exists. Cache-first so the Home widget's
    /// "already logged" state resolves instantly instead of awaiting the server.
    func fetchToday(for userId: String, date: Date = Date()) async throws -> MoodLog? {
        let ref = collection(for: userId).document(MoodLog.dayKey(for: date))
        if let cached = try? await ref.getDocument(source: .cache), cached.exists {
            return cached.data().flatMap { MoodLog(from: $0) }
        }
        let doc = try await ref.getDocument(source: .default)
        guard let data = doc.data() else { return nil }
        return MoodLog(from: data)
    }

    /// Fetches mood logs from the last `days` days (for Patterns analytics).
    /// Cache-first; falls back to the network when the cache is cold.
    func fetchRecent(for userId: String, days: Int = 30) async throws -> [MoodLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let query = collection(for: userId)
            .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: cutoff))
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return cached.documents.compactMap { MoodLog(from: $0.data()) }
        }
        let snapshot = try await query.getDocuments(source: .default)
        return snapshot.documents.compactMap { MoodLog(from: $0.data()) }
    }
}
