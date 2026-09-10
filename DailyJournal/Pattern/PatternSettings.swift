//
//  PatternSettings.swift
//  DailyJournal
//
//  What remains here after the Pattern Callback system was cut (see
//  PATTERNS_MERGE_PLAN.md): local, on-device state for PatternDetectionService's
//  crisis-corpus scan — the throttle that keeps it to ~once/20h, and the
//  cooldown on the safety resource card so it doesn't re-surface on every load.
//  Namespaced by user id so multiple accounts on one device stay independent.
//

import Foundation

struct PatternSettings {

    let userId: String

    private var defaults: UserDefaults { .standard }
    private func key(_ name: String) -> String { "pattern_\(name)_\(userId)" }

    init(userId: String) { self.userId = userId }

    // MARK: Detection throttle

    /// Last time the crisis scan actually ran. Rate-limited to roughly once per
    /// 20 hours so Home loads stay cheap.
    var lastDetection: Date? {
        get {
            let t = defaults.double(forKey: key("lastDetection"))
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        nonmutating set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: key("lastDetection")) }
    }

    var shouldRunDetection: Bool {
        guard let last = lastDetection else { return true }
        return Date().timeIntervalSince(last) >= 20 * 3600
    }

    // MARK: Resource card cooldown (safety flow)

    /// When a crisis signal routes the user to the soft resource card, we record
    /// the last time we showed it so we don't re-surface it every single load.
    var lastResourceCardShown: Date? {
        get {
            let t = defaults.double(forKey: key("resourceShown"))
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        nonmutating set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: key("resourceShown")) }
    }

    /// Show the soft resource card at most once every 3 days.
    var shouldShowResourceCard: Bool {
        guard let last = lastResourceCardShown else { return true }
        return Date().timeIntervalSince(last) >= 3 * 86400
    }
}
