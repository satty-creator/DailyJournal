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

    /// The most recent session in `mode` for `userId`, if any — used to offer
    /// "resume where you left off" on a fresh Daily Chat open.
    ///
    /// Filters by `mode` server-side and orders by `updatedAt` — a user with 5+
    /// recent sessions in the OTHER mode used to silently get no resume offer at
    /// all, because the old query fetched the 5 most-recently-updated sessions
    /// across BOTH modes and filtered for `mode` in Swift afterward.
    ///
    /// REQUIRES the `chatSessions` composite index (mode ASC, updatedAt DESC)
    /// declared in `firestore.indexes.json` — deploy it with
    /// `firebase deploy --only firestore:indexes` before this ships, or the query
    /// throws "the query requires an index" and this silently returns nil (same
    /// degradation as any other failed read here, but resume would never work
    /// until the index exists). A plain equality-only query without `order(by:)`
    /// was deliberately rejected: `.limit(to: N)` with no ordering returns an
    /// UNDEFINED N documents, not necessarily the N most recent, so sorting the
    /// result in Swift wouldn't reliably find the true most-recent session once a
    /// mode has accumulated more than N total documents (see AIService+Chat.swift's
    /// PRD note that abandoned conversations are never pruned).
    func fetchMostRecent(userId: String, mode: ChatMode) async -> ChatSession? {
        let cacheKey = "recentChatSessions.\(userId).\(mode.rawValue)"
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            collection(for: userId)
                .whereField("mode", isEqualTo: mode.rawValue)
                .order(by: "updatedAt", descending: true)
                .limit(to: 1),
            key: cacheKey
        ) else { return nil }

        return snapshot.documents.compactMap { ChatSession(from: $0.data()) }.first
    }
}
