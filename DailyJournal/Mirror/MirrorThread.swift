//
//  MirrorThread.swift
//  DailyJournal
//
//  Tier 3 — `users/{uid}/derived/threads` (mirror-v3-prd-2026-09-10.md §5.4).
//
//  At most three. A thread is something that happened on three different days
//  with a contrast set, and survived the counter-evidence audit — or that the
//  user confirmed outright. Everything below that bar stays in
//  `patternHypotheses` as substrate: invisible, still accruing evidence, still
//  decaying at 45 days.
//
//  A row carries a plain-English title, `n`, a first-seen date and a 30-day dot
//  strip. No type label, no lifecycle chip, no confidence caption, no buttons —
//  the internal ontology is used to FIND a thread, never to name one.
//

import Foundation
import FirebaseFirestore

/// One day in the dot strip.
struct ThreadDot: Identifiable {
    let date: String
    /// The thread appeared on this day.
    let filled: Bool
    /// This is the exception — the day the pattern did NOT hold.
    let isException: Bool
    var id: String { date }

    init?(from data: [String: Any]) {
        guard let date = data["d"] as? String else { return nil }
        self.date = date
        self.filled = data["f"] as? Bool ?? false
        self.isException = data["x"] as? Bool ?? false
    }
}

struct MirrorThread: Identifiable {
    let hypothesisId: String
    let title: String
    let titleSource: String
    /// Derived from counts ONLY: once / twice / recurring / confirmed.
    let label: String
    /// Distinct supporting entries. This is the number the dot strip makes
    /// credible — "n 9" with nine visible dots is checkable; "Seen 9×" alone
    /// is a claim.
    let n: Int
    let sinceDate: String?
    let lastDate: String?
    let dots: [ThreadDot]
    let exceptionDate: String?
    let observationIds: [String]
    let counterEvidenceCount: Int

    var id: String { hypothesisId }

    init?(from data: [String: Any]) {
        guard let hypothesisId = data["hypothesisId"] as? String,
              let title = data["title"] as? String, !title.isEmpty else { return nil }
        self.hypothesisId = hypothesisId
        self.title = title
        self.titleSource = data["titleSource"] as? String ?? "hypothesis"
        self.label = data["label"] as? String ?? "recurring"
        self.n = data["n"] as? Int ?? 0
        self.sinceDate = data["sinceDate"] as? String
        self.lastDate = data["lastDate"] as? String
        self.dots = (data["dots"] as? [[String: Any]] ?? []).compactMap { ThreadDot(from: $0) }
        self.exceptionDate = data["exceptionDate"] as? String
        self.observationIds = data["observationIds"] as? [String] ?? []
        self.counterEvidenceCount = data["counterEvidenceCount"] as? Int ?? 0
    }

    /// "n 9 · since 3 Aug" — the meta line to the right of the title.
    var metaLine: String {
        var parts = ["n \(n)"]
        if let since = sinceDate.flatMap(MirrorThread.shortDate) { parts.append("since \(since)") }
        return parts.joined(separator: " · ")
    }

    /// "softened Tue 3 Sep" — shown only when an exception actually exists.
    var softenedLine: String? {
        guard let exceptionDate, let short = MirrorThread.shortDate(exceptionDate) else { return nil }
        return "softened \(short)"
    }

    /// "12 Aug" from "2026-08-12". Deliberately not a DateFormatter round-trip:
    /// these keys are already in the USER's local calendar (the server built
    /// them in their timezone), so re-parsing them as instants would shift them
    /// back into the device's timezone and could move the date by a day.
    static func shortDate(_ key: String) -> String? {
        guard key.count >= 10 else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthIndex = Int(key.dropFirst(5).prefix(2)) ?? 0
        let day = Int(key.dropFirst(8).prefix(2)) ?? 0
        guard monthIndex >= 1, monthIndex <= 12, day >= 1 else { return nil }
        return "\(day) \(months[monthIndex - 1])"
    }
}

/// The whole `derived/threads` document.
struct MirrorThreads {
    let threads: [MirrorThread]
    let emptyReason: String?
    let computedAt: Date

    static let empty = MirrorThreads(threads: [], emptyReason: nil, computedAt: .distantPast)

    init(threads: [MirrorThread], emptyReason: String?, computedAt: Date) {
        self.threads = threads; self.emptyReason = emptyReason; self.computedAt = computedAt
    }

    init(from data: [String: Any]) {
        self.threads = (data["threads"] as? [[String: Any]] ?? []).compactMap { MirrorThread(from: $0) }
        self.emptyReason = data["emptyReason"] as? String
        self.computedAt = (data["computedAt"] as? Timestamp)?.dateValue() ?? .distantPast
    }

    /// What to say when there are none. Says what would fill it, rather than
    /// implying the user has failed to produce one.
    var emptyCopy: String {
        switch emptyReason {
        case "no_hypotheses": return "None yet — threads need the same thing on three different days."
        default:              return "None yet — threads need the same thing on three different days."
        }
    }
}
