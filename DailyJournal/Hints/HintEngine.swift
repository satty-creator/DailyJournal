//
//  HintEngine.swift
//  DailyJournal
//
//  The observable owner of one session's blank-page starter question. Draws
//  from `StarterQuestionBank` via `StarterQuestionPicker` — purely local and
//  synchronous, nothing here ever calls the network — and keeps a small
//  per-user history in UserDefaults so re-rolling (and re-opening the
//  composer) doesn't repeat the same question back to back.
//
//  Used to own `HintLadder`'s pebble-combo starter + a 3-way gentler/direct/
//  weirder re-roll; pebbles were never wired up from any live UI, so that
//  engine always produced the same one fixed question for everyone. Replaced
//  by this context-aware bank (time of day, weekday, first-entry / returning)
//  and a single re-roll.
//
//  Non-blocking and failure-tolerant — a hint never stalls the writing surface.
//

import Foundation

@MainActor
final class HintEngine: ObservableObject {

    private let userId: String
    private var lastKind: StarterKind?

    init(userId: String) {
        self.userId = userId
    }

    /// Draws the next starter question, recording it so the following draw
    /// (a re-roll, or the next time the composer opens) avoids repeating it.
    func next() -> String {
        let question = StarterQuestionPicker.pick(
            profile: MemoryProfileService.shared.cachedProfile(for: userId),
            recentIDs: StarterQuestionHistory.recentIDs(for: userId),
            lastKind: lastKind
        )
        lastKind = question.kind
        StarterQuestionHistory.record(question.id, for: userId)
        return question.text
    }
}

// MARK: - History

/// Tiny per-user "recently shown" ring buffer, kept in UserDefaults so it
/// survives across composer opens without needing a Firestore round trip.
enum StarterQuestionHistory {

    private static let maxRemembered = 30
    private static func key(for userId: String) -> String { "starterRecent-\(userId)" }

    static func recentIDs(for userId: String) -> [String] {
        (UserDefaults.standard.array(forKey: key(for: userId)) as? [String]) ?? []
    }

    static func record(_ id: String, for userId: String) {
        var ids = recentIDs(for: userId)
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > maxRemembered {
            ids.removeFirst(ids.count - maxRemembered)
        }
        UserDefaults.standard.set(ids, forKey: key(for: userId))
    }
}
