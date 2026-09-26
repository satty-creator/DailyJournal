//
//  ChatSessionService.swift
//  DailyJournal
//
//  Firestore CRUD for `users/{uid}/chatSessions` — see ChatSession.swift for
//  why this collection exists. Same fire-and-forget write discipline as
//  JournalService.
//

import Foundation
import FirebaseFirestore

final class ChatSessionService {

    static let shared = ChatSessionService()

    private let db = Firestore.firestore()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("chatSessions")
    }

    /// Fire-and-forget upsert. Called after every completed turn so a
    /// backgrounded session survives, and again — with `wovenEntryId` set —
    /// once the conversation is woven into an entry.
    ///
    /// A nil `toFirestoreData()` (encryption failed) skips the write outright —
    /// see that method's doc comment for why silently degrading here is strictly
    /// better than the plaintext-fallback bug it replaces.
    func save(_ session: ChatSession) {
        guard let data = session.toFirestoreData() else { return }
        collection(for: session.userId).document(session.id)
            .setData(data, merge: true)
    }

    /// Deletes a session outright. Called when the user explicitly discards a
    /// conversation (the "Leave this conversation?" alert's Discard button) —
    /// that alert's own copy promises "won't be saved unless you weave it",
    /// and this is what keeps that true for a conversation that was, in fact,
    /// autosaved for resumability up to that point.
    func delete(id: String, userId: String) {
        collection(for: userId).document(id).delete(completion: nil)
    }

    /// The most recent session for `userId`, if any — used to offer "resume where
    /// you left off" on a fresh Daily Chat open.
    ///
    /// Formerly filtered by `mode` (Casual Vent vs Thought Journal, retired) — that
    /// filter existed because a plain equality-only query without `order(by:)` would
    /// have returned an UNDEFINED N documents rather than the N most recent, so
    /// sorting in Swift couldn't reliably find the true most-recent session once a
    /// user had accumulated more than N total documents. With one mode there's
    /// nothing left to filter on; only the ordering matters now.
    func fetchMostRecent(userId: String) async -> ChatSession? {
        let cacheKey = "recentChatSessions.\(userId)"
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            collection(for: userId)
                .order(by: "updatedAt", descending: true)
                .limit(to: 1),
            key: cacheKey
        ) else { return nil }

        return snapshot.documents.compactMap { ChatSession(from: $0.data()) }.first
    }
}
