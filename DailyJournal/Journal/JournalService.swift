//
//  JournalService.swift
//  DailyJournal
//

import Foundation
import FirebaseFirestore

final class JournalService {

    private let db = Firestore.firestore()

    private func entriesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("entries")
    }

    // Cache-first read: serve the local on-disk cache instantly when it's warm,
    // and only fall back to the network when the cache is cold (first run / new
    // user). This is what makes Home, Patterns and the entry list paint without
    // waiting on a server round-trip. `.default` (not `.server`) is the fallback
    // so the call still succeeds when offline.
    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return cached
        }
        return try await query.getDocuments(source: .default)
    }

    // MARK: - Create
    // Fire-and-forget: Firestore writes to local cache immediately and syncs to the
    // server in the background. We never await server ACK for writes — that's what
    // caused the spinner to hang on any slow / offline connection.
    func createEntry(_ entry: JournalEntry) {
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .setData(entry.toFirestoreData())
    }

    // MARK: - Update
    func updateEntry(_ entry: JournalEntry) {
        var data = entry.toFirestoreData()
        data["updatedAt"] = Timestamp(date: Date())
        // setData(merge:true) is the fire-and-forget equivalent of updateData
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .setData(data, merge: true)
    }

    // MARK: - Schedule future-self letter
    func scheduleFutureSelf(entryId: String, userId: String, deliveryDate: Date) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData([
                "futureSelfDeliveryDate": Timestamp(date: deliveryDate),
                "futureSelfOpened": false
            ])
    }

    // MARK: - Mark arrived letter as opened
    func markLetterOpened(entryId: String, userId: String) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData(["futureSelfOpened": true])
    }

    // MARK: - Delete
    func deleteEntry(_ entry: JournalEntry) {
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .delete(completion: nil)
    }

    // MARK: - Update AI insights (called after Gemini returns)
    // Fire-and-forget: same pattern as all other writes.
    func updateEntryInsights(entryId: String, userId: String, insights: JournalInsights) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData([
                "aiSummaryBullets": insights.bullets,
                "aiQuestion":       insights.question,
                "sentimentLabel":   insights.sentiment
            ])
    }

    // MARK: - Fetch all (descending)
    func fetchEntries(for userId: String) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: true)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch recent (home screen)
    func fetchRecentEntries(for userId: String, limit: Int = 5) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch arrived letters
    func fetchArrivedLetters(for userId: String) async throws -> [JournalEntry] {
        let now = Timestamp(date: Date())
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .whereField("futureSelfDeliveryDate", isLessThanOrEqualTo: now)
                .whereField("futureSelfOpened", isEqualTo: false)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch all (ascending) for pattern analysis
    func fetchAllEntries(for userId: String) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: false)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }
}
