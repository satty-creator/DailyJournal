//
//  MirrorFacts.swift
//  DailyJournal
//
//  Tier 0 of Mirror v3 — the counts, dates and verbatim phrases that are on
//  screen BEFORE any sentence that interprets them
//  (mirror-v3-prd-2026-09-10.md §4).
//
//  Read-only on the client. Written nightly by `functions:computeUserDerived`
//  to `users/{uid}/derived/facts`. Nothing here is inferred: every field is
//  arithmetic over data the app already captured, which is what earns it the
//  right to be the most specific thing on the screen.
//

import Foundation
import FirebaseFirestore

// MARK: - UnlockState

/// "Tell the user what would unlock the next thing" (PRD principle 7, R9).
struct UnlockState {
    let stage: String
    let entriesTotal: Int
    let atEntries: Int?
    let need: Int?
    let unlocks: String?
    let hint: String?
    let counters: [String: Int]

    static let empty = UnlockState(stage: "seed", entriesTotal: 0, atEntries: nil,
                                   need: nil, unlocks: nil, hint: nil, counters: [:])

    init(stage: String, entriesTotal: Int, atEntries: Int?, need: Int?,
         unlocks: String?, hint: String?, counters: [String: Int]) {
        self.stage = stage; self.entriesTotal = entriesTotal
        self.atEntries = atEntries; self.need = need; self.unlocks = unlocks
        self.hint = hint; self.counters = counters
    }

    init(from data: [String: Any]) {
        self.stage = data["stage"] as? String ?? "seed"
        self.entriesTotal = data["entriesTotal"] as? Int ?? 0
        let next = data["next"] as? [String: Any]
        self.atEntries = next?["atEntries"] as? Int
        self.need = next?["need"] as? Int
        self.unlocks = next?["unlocks"] as? String
        self.hint = next?["hint"] as? String
        self.counters = data["counters"] as? [String: Int] ?? [:]
    }
}

// MARK: - MirrorFacts

struct MirrorFacts {
    let userId: String
    let computedAt: Date
    let timezone: String
    let entriesTotal: Int
    let coverage: [String: Int]
    /// entryId → local `yyyy-MM-dd`. Present so the Threads dot strip and the
    /// proof sheet never have to re-read `entries`.
    let entryDates: [String: String]
    let unlock: UnlockState

    static func empty(userId: String) -> MirrorFacts {
        MirrorFacts(userId: userId, computedAt: .distantPast, timezone: TimeZone.current.identifier,
                    entriesTotal: 0, coverage: [:],
                    entryDates: [:], unlock: .empty)
    }

    init(userId: String, computedAt: Date, timezone: String, entriesTotal: Int,
         coverage: [String: Int],
         entryDates: [String: String], unlock: UnlockState) {
        self.userId = userId; self.computedAt = computedAt; self.timezone = timezone
        self.entriesTotal = entriesTotal; self.coverage = coverage
        self.entryDates = entryDates
        self.unlock = unlock
    }

    init?(from data: [String: Any]) {
        guard let userId = data["userId"] as? String else { return nil }
        self.userId = userId
        self.computedAt = (data["computedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        self.timezone = data["timezone"] as? String ?? TimeZone.current.identifier
        self.entriesTotal = data["entriesTotal"] as? Int ?? 0
        self.coverage = data["coverage"] as? [String: Int] ?? [:]
        self.entryDates = data["entryDates"] as? [String: String] ?? [:]
        self.unlock = UnlockState(from: data["unlock"] as? [String: Any] ?? [:])
    }

    /// True once the nightly job has actually run for this user.
    var isFresh: Bool { computedAt > .distantPast }

    /// Yesterday's numbers are still worth showing; a week-old set is not.
    var isStale: Bool { Date().timeIntervalSince(computedAt) > 48 * 3600 }
}
