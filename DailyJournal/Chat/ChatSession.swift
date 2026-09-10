//
//  ChatSession.swift
//  DailyJournal
//
//  One Daily Chat conversation, persisted so a backgrounded session survives
//  and can be resumed. Firestore path: users/{uid}/chatSessions/{id}
//
//  The transcript is encrypted client-side exactly like `entries.content` (see
//  EntryEncryption.swift) — same posture, same device-local key. Weaving
//  (conversation → journal entry) still happens entirely client-side; this
//  document exists so the raw conversation survives being backgrounded, not so
//  a server could ever read it.
//

import Foundation
import FirebaseFirestore

struct ChatSession: Identifiable {

    let id: String
    let userId: String
    let mode: ChatMode
    var messages: [ChatMessage]
    let startedAt: Date
    var updatedAt: Date
    /// Set once the conversation is woven into a journal entry. A session with
    /// this nil and a recent `updatedAt` is what "resume where you left off"
    /// looks for.
    var wovenEntryId: String?

    /// Real user replies, not Spilr's lines — matches `DailyChatViewModel.userTurnCount`.
    var turnCount: Int { messages.filter { $0.role == .user }.count }

    init(
        id: String = UUID().uuidString,
        userId: String,
        mode: ChatMode,
        messages: [ChatMessage],
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        wovenEntryId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.mode = mode
        self.messages = messages
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.wovenEntryId = wovenEntryId
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id            = data["id"]        as? String,
            let userId        = data["userId"]    as? String,
            let modeRaw       = data["mode"]      as? String,
            let mode          = ChatMode(rawValue: modeRaw),
            let startedAt     = (data["startedAt"] as? Timestamp)?.dateValue(),
            let updatedAt     = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let encryptedTranscript = data["transcript"] as? String,
            let decrypted     = EntryEncryption.decrypt(encryptedTranscript),
            let transcriptData = decrypted.data(using: .utf8),
            let messages      = try? JSONDecoder().decode([ChatMessage].self, from: transcriptData)
        else { return nil }

        self.id           = id
        self.userId       = userId
        self.mode         = mode
        self.messages     = messages
        self.startedAt    = startedAt
        self.updatedAt    = updatedAt
        self.wovenEntryId = data["wovenEntryId"] as? String
    }

    // MARK: - Firestore serialisation

    /// Returns nil (rather than a plaintext-fallback document) when encryption fails.
    ///
    /// Previously `EntryEncryption.encrypt(transcriptJSON) ?? transcriptJSON` wrote
    /// the RAW transcript to Firestore on encryption failure while still labelling
    /// the document `"encrypted": true` — a double bug: the plaintext conversation
    /// leaked server-side, AND the document became permanently undecryptable anyway,
    /// since `ChatSession.init?(from:)` always attempts to decrypt whatever string is
    /// in `transcript`. `ChatSessionService.save` skips the write entirely when this
    /// returns nil, which just means the autosave for this turn is missed — the same
    /// degradation every other AI/network failure in this app already has.
    func toFirestoreData() -> [String: Any]? {
        let transcriptJSON = (try? JSONEncoder().encode(messages))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        guard let encryptedTranscript = EntryEncryption.encrypt(transcriptJSON) else { return nil }

        var data: [String: Any] = [
            "id": id,
            "userId": userId,
            "mode": mode.rawValue,
            "transcript": encryptedTranscript,
            "encrypted": true,
            "turnCount": turnCount,
            "startedAt": Timestamp(date: startedAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        if let wovenEntryId { data["wovenEntryId"] = wovenEntryId }
        return data
    }
}
