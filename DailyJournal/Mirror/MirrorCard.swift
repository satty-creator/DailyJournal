// MirrorCard.swift
// DailyJournal
//
// The retired Mirror Engine daily-card pipeline lived here (MirrorCard,
// MirrorReceipt, MirrorComponents, MirrorNarrative). All of it was removed once
// the server-side mirror-line writer became the single source of the daily read.
// Only `MirrorFeedback` survives — the feedback enum the Mirror reading card and
// the StylePreferences/correction path still reference.

import Foundation

// MARK: - MirrorFeedback

enum MirrorFeedback: String {
    case thisIsMe    = "this_is_me"
    case almost      = "almost"
    case notMe       = "not_me"
    case tooIntense  = "too_intense"
    case askTomorrow = "ask_tomorrow"
}
