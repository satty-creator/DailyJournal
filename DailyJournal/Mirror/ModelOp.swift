// ModelOp.swift
// DailyJournal
//
// The audit trail for Daily Chat's write-back into the Person Model /
// LifeContext (see PersonModelChatContext.swift + AIService+Chat.swift's
// extractModelOps). A conversation may apply a change without a confirmation
// tap — "track this" / "that's not true about me" / "stop tracking work" are
// applied on save, not staged for review — but every write it makes is
// recorded here with the verbatim sentence that licensed it, and is listed
// and undoable in "What changed" (SelfModelView). Silent, never invisible.
//
// Persisted at: users/{uid}/modelOps/{id}

import Foundation
import FirebaseFirestore

enum ModelOpKind: String {
    case track
    case untrackTopic = "untrack_topic"
    case notMe = "not_me"
    case confirm
}

struct ModelOp: Identifiable {
    let id: String
    let op: ModelOpKind
    /// The personModel item this touched — set for `.confirm`/`.notMe`, nil
    /// for `.track`/`.untrackTopic` (those touch LifeContext, not an item).
    let targetItemId: String?
    /// Short label in their own words — what changed ("work", "the Dan thing").
    let subject: String
    /// The exact sentence they typed that licensed this write. Always a real
    /// substring of a real user turn — `extractModelOps` drops anything that
    /// doesn't check out before this doc is ever written (never trust a
    /// hallucinated quote, same discipline as Prompt M's receipt check).
    let quote: String
    let sessionId: String
    let appliedAt: Date
    var undoneAt: Date?

    init(
        id: String = UUID().uuidString,
        op: ModelOpKind,
        targetItemId: String?,
        subject: String,
        quote: String,
        sessionId: String,
        appliedAt: Date = Date(),
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.op = op
        self.targetItemId = targetItemId
        self.subject = subject
        self.quote = quote
        self.sessionId = sessionId
        self.appliedAt = appliedAt
        self.undoneAt = undoneAt
    }

    init?(id: String, from data: [String: Any]) {
        guard
            let opRaw = data["op"] as? String, let op = ModelOpKind(rawValue: opRaw),
            let subject = data["subject"] as? String,
            let quote = data["quote"] as? String,
            let appliedAt = (data["appliedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id = id
        self.op = op
        self.targetItemId = data["targetItemId"] as? String
        self.subject = subject
        self.quote = quote
        self.sessionId = data["sessionId"] as? String ?? ""
        self.appliedAt = appliedAt
        self.undoneAt = (data["undoneAt"] as? Timestamp)?.dateValue()
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "op": op.rawValue,
            "subject": subject,
            "quote": quote,
            "sessionId": sessionId,
            "appliedAt": Timestamp(date: appliedAt)
        ]
        if let targetItemId { d["targetItemId"] = targetItemId }
        if let undoneAt { d["undoneAt"] = Timestamp(date: undoneAt) }
        return d
    }

    var isUndone: Bool { undoneAt != nil }

    /// One line for the "what changed" list.
    var displaySummary: String {
        switch op {
        case .track:        return "Started tracking: \(subject)"
        case .untrackTopic: return "Stopped tracking: \(subject)"
        case .notMe:        return "Marked not true: \(subject)"
        case .confirm:      return "Confirmed: \(subject)"
        }
    }
}
