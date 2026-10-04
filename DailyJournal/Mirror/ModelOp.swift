// ModelOp.swift
// DailyJournal
//
// The kinds of write-back Daily Chat can apply to the Person Model / LifeContext
// (see PersonModelChatContext.swift + AIService+Chat.swift's extractModelOps).
// A conversation may apply a change without a confirmation tap — "track this" /
// "that's not true about me" / "stop tracking work" are applied on save.

import Foundation

enum ModelOpKind: String {
    case track
    case untrackTopic = "untrack_topic"
    case notMe = "not_me"
    case confirm
}
