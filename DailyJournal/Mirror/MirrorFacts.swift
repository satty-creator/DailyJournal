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

// MARK: - Small value types

struct FactCount: Identifiable {
    let label: String
    let count: Int
    var id: String { label }

    init(label: String, count: Int) {
        self.label = label
        self.count = count
    }

    /// Decodes `{ "<key>": String, "<countKey>": Int }` — the server writes a
    /// different key name per list (`name`/`mentions`, `phrase`/`count`, …)
    /// so the label reads correctly in logs.
    init?(from data: [String: Any], key: String, countKey: String = "count") {
        guard let label = data[key] as? String else { return nil }
        self.label = label
        self.count = data[countKey] as? Int ?? 0
    }
}

struct TopEmotion {
    let word: String
    let count: Int
    let days: [String]
    /// `"domain:work"` when EVERY occurrence landed in one life domain, else
    /// nil. Only set when the cluster is unanimous — "all on work days" is a
    /// strong claim and a 2-of-3 is not that.
    let clusteredOn: String?

    init?(from data: [String: Any]) {
        guard let word = data["word"] as? String else { return nil }
        self.word = word
        self.count = data["count"] as? Int ?? 0
        self.days = data["days"] as? [String] ?? []
        self.clusteredOn = data["clusteredOn"] as? String
    }

    /// "work" from "domain:work".
    var clusterLabel: String? {
        guard let clusteredOn, let range = clusteredOn.range(of: ":") else { return nil }
        return String(clusteredOn[range.upperBound...])
    }
}

// MARK: - WeekFacts

struct WeekFacts {
    let start: String?
    let end: String?
    let entries: Int
    let activeDays: Int
    let words: Int
    /// False when fewer than 80% of the window's entries have a known word
    /// count — `entries.content` is encrypted, so the server only knows this
    /// for entries analysed by a build that sends it. Any copy quoting `words`
    /// must check this first.
    let wordsKnown: Bool
    let byBand: [String: Int]
    let byWeekday: [Int]
    let byMode: [String: Int]
    let topEmotion: TopEmotion?
    let people: [FactCount]
    let roles: [FactCount]
    let topPhrases: [FactCount]
    let topDomains: [FactCount]
    let bodySignals: [FactCount]
    let moods: [String: Int]

    static let empty = WeekFacts(
        start: nil, end: nil, entries: 0, activeDays: 0, words: 0, wordsKnown: false,
        byBand: [:], byWeekday: [], byMode: [:], topEmotion: nil, people: [],
        roles: [], topPhrases: [], topDomains: [], bodySignals: [], moods: [:]
    )

    init(start: String?, end: String?, entries: Int, activeDays: Int, words: Int,
         wordsKnown: Bool, byBand: [String: Int], byWeekday: [Int], byMode: [String: Int],
         topEmotion: TopEmotion?, people: [FactCount], roles: [FactCount],
         topPhrases: [FactCount], topDomains: [FactCount], bodySignals: [FactCount],
         moods: [String: Int]) {
        self.start = start; self.end = end; self.entries = entries
        self.activeDays = activeDays; self.words = words; self.wordsKnown = wordsKnown
        self.byBand = byBand; self.byWeekday = byWeekday; self.byMode = byMode
        self.topEmotion = topEmotion; self.people = people; self.roles = roles
        self.topPhrases = topPhrases; self.topDomains = topDomains
        self.bodySignals = bodySignals; self.moods = moods
    }

    init(from data: [String: Any]) {
        self.start = data["start"] as? String
        self.end = data["end"] as? String
        self.entries = data["entries"] as? Int ?? 0
        self.activeDays = data["activeDays"] as? Int ?? 0
        self.words = data["words"] as? Int ?? 0
        self.wordsKnown = data["wordsKnown"] as? Bool ?? false
        self.byBand = data["byBand"] as? [String: Int] ?? [:]
        self.byWeekday = data["byWeekday"] as? [Int] ?? []
        self.byMode = data["byMode"] as? [String: Int] ?? [:]
        self.topEmotion = (data["topEmotion"] as? [String: Any]).flatMap { TopEmotion(from: $0) }
        self.people = (data["people"] as? [[String: Any]] ?? [])
            .compactMap { FactCount(from: $0, key: "name", countKey: "mentions") }
        self.roles = (data["roles"] as? [[String: Any]] ?? [])
            .compactMap { FactCount(from: $0, key: "role", countKey: "mentions") }
        self.topPhrases = (data["topPhrases"] as? [[String: Any]] ?? [])
            .compactMap { FactCount(from: $0, key: "phrase") }
        self.topDomains = (data["topDomains"] as? [[String: Any]] ?? [])
            .compactMap { FactCount(from: $0, key: "domain") }
        self.bodySignals = (data["bodySignals"] as? [[String: Any]] ?? [])
            .compactMap { FactCount(from: $0, key: "signal") }
        self.moods = data["moods"] as? [String: Int] ?? [:]
    }

    /// Entries written in the `late` band (21:00–04:59).
    var lateEntries: Int { byBand["late"] ?? 0 }

    /// The band the most entries landed in, with its count.
    var dominantBand: (band: String, count: Int)? {
        byBand.max { $0.value < $1.value }.flatMap { $0.value > 0 ? ($0.key, $0.value) : nil }
    }
}

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
    let week: WeekFacts
    let month: WeekFacts
    /// entryId → local `yyyy-MM-dd`. Present so the Threads dot strip and the
    /// proof sheet never have to re-read `entries`.
    let entryDates: [String: String]
    let unlock: UnlockState

    static func empty(userId: String) -> MirrorFacts {
        MirrorFacts(userId: userId, computedAt: .distantPast, timezone: TimeZone.current.identifier,
                    entriesTotal: 0, coverage: [:], week: .empty, month: .empty,
                    entryDates: [:], unlock: .empty)
    }

    init(userId: String, computedAt: Date, timezone: String, entriesTotal: Int,
         coverage: [String: Int], week: WeekFacts, month: WeekFacts,
         entryDates: [String: String], unlock: UnlockState) {
        self.userId = userId; self.computedAt = computedAt; self.timezone = timezone
        self.entriesTotal = entriesTotal; self.coverage = coverage
        self.week = week; self.month = month; self.entryDates = entryDates
        self.unlock = unlock
    }

    init?(from data: [String: Any]) {
        guard let userId = data["userId"] as? String else { return nil }
        self.userId = userId
        self.computedAt = (data["computedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        self.timezone = data["timezone"] as? String ?? TimeZone.current.identifier
        self.entriesTotal = data["entriesTotal"] as? Int ?? 0
        self.coverage = data["coverage"] as? [String: Int] ?? [:]
        self.week = WeekFacts(from: data["week"] as? [String: Any] ?? [:])
        self.month = WeekFacts(from: data["month"] as? [String: Any] ?? [:])
        self.entryDates = data["entryDates"] as? [String: String] ?? [:]
        self.unlock = UnlockState(from: data["unlock"] as? [String: Any] ?? [:])
    }

    /// True once the nightly job has actually run for this user.
    var isFresh: Bool { computedAt > .distantPast }

    /// Yesterday's numbers are still worth showing; a week-old set is not.
    var isStale: Bool { Date().timeIntervalSince(computedAt) > 48 * 3600 }
}
