//
//  PatternSettings.swift
//  DailyJournal
//
//  User-facing controls + lightweight local state for Pattern Callbacks.
//  All on-device (UserDefaults), mirroring how the Gemini API key is stored.
//  Nothing here is private/sensitive enough to warrant Firestore, and keeping
//  it local means the detection gate works offline.
//

import Foundation

// MARK: - Frequency preference

enum PatternFrequency: String, CaseIterable, Identifiable {
    case off      = "off"        // never surface callbacks
    case weekly   = "weekly"     // at most one a week, regardless of account age
    case whenever = "whenever"   // follow the default cadence rules

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:      return "Off"
        case .weekly:   return "Weekly"
        case .whenever: return "Whenever"
        }
    }

    var blurb: String {
        switch self {
        case .off:      return "No callbacks. Ever."
        case .weekly:   return "At most one a week."
        case .whenever: return "When something really recurs."
        }
    }
}

// MARK: - Scope preference

enum PatternScope: String, CaseIterable, Identifiable {
    case names      = "names"       // recurring people / places
    case emotions   = "emotions"    // feelings, contradictions, avoidance
    case cycles     = "cycles"      // loops and resolutions
    case everything = "everything"  // all archetypes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .names:      return "Names"
        case .emotions:   return "Emotions"
        case .cycles:     return "Cycles"
        case .everything: return "Everything"
        }
    }

    /// Whether a given archetype's scope is allowed under this preference.
    func allows(_ archetype: PatternArchetype) -> Bool {
        self == .everything || archetype.scope == self
    }
}

// MARK: - Settings store

/// Per-device store for callback preferences and local training signals.
/// Keys are namespaced by user id so multiple accounts on one device stay
/// independent.
struct PatternSettings {

    let userId: String

    private var defaults: UserDefaults { .standard }
    private func key(_ name: String) -> String { "pattern_\(name)_\(userId)" }

    init(userId: String) { self.userId = userId }

    // MARK: Frequency

    // Pattern callbacks are always-on and no longer user-configurable. The
    // cadence is governed entirely by the detection throttle + surface gates,
    // so this is hardcoded to `.whenever` rather than read from preferences.
    var frequency: PatternFrequency { .whenever }

    // MARK: Scope

    var scope: PatternScope {
        get { PatternScope(rawValue: defaults.string(forKey: key("scope")) ?? "") ?? .everything }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key("scope")) }
    }

    // MARK: Muted entities ("stop watching [entity]")

    var mutedEntities: Set<String> {
        get { Set((defaults.array(forKey: key("muted")) as? [String]) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: key("muted")) }
    }

    func isMuted(_ entity: String) -> Bool {
        mutedEntities.contains(entity.lowercased())
    }

    func mute(_ entity: String) {
        var set = mutedEntities
        set.insert(entity.lowercased())
        mutedEntities = set
    }

    // MARK: Detection throttle

    /// Last time detection actually ran. Detection is rate-limited to roughly
    /// once per 20 hours so Home loads stay cheap and the model isn't hammered.
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

    // MARK: Resource card (safety flow)

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

    // MARK: Feedback signals (salience boost / damping)

    /// Archetypes the user has affirmed via "I needed that". Used to nudge
    /// salience up next time a similar archetype appears.
    var affirmedArchetypes: Set<String> {
        get { Set((defaults.array(forKey: key("affirmed")) as? [String]) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: key("affirmed")) }
    }

    func recordAffirmation(_ archetype: PatternArchetype) {
        var set = affirmedArchetypes
        set.insert(archetype.rawValue)
        affirmedArchetypes = set
    }

    func salienceBoost(for archetype: PatternArchetype) -> Double {
        affirmedArchetypes.contains(archetype.rawValue) ? 0.2 : 0.0
    }
}
