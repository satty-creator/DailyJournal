//
//  OnboardingIntent.swift
//  DailyJournal
//
//  What the person said brought them here, what's hard right now, who's in
//  their life, and how they want Spilr to sound back — collected once,
//  across onboarding's intake steps (Spilr Redesign 2b), and read by
//  `SpilrVoice.intentContext()` on every AI prompt thereafter (folded into
//  `MemoryProfileService.cachedPromptContext()`, so it reaches every prompt
//  that already includes memory context with no second call site to keep in
//  sync — see that function's doc comment).
//
//  Persisted, not derived — unlike `MemoryProfile` (Memory/MemoryProfile.swift),
//  which is intentionally cached/derived and never hand-edited, this is the
//  user's own direct statement and is never overwritten by the AI layer.
//
//  Every key here lives under the "spilr." namespace, so `LocalUserState`'s
//  prefix sweep clears it on account deletion with no list to keep in sync —
//  see that file's header comment.
//

import Foundation

enum JournalGoal: String, CaseIterable, Identifiable {
    // Raw values are the plain-language phrases sent to the model inline
    // (see `SpilrVoice.intentContext()`) — kept lowercase so they read
    // naturally in a sentence, not as a label.
    case quietMyHead        = "quiet my head at night"
    case understandRelation = "understand a relationship"
    case makeADecision      = "make a decision I'm stuck on"
    case buildTheHabit      = "just build the habit"

    var id: String { rawValue }

    /// Sentence-cased for the goal-picker row.
    var title: String {
        switch self {
        case .quietMyHead:        return "Quiet my head at night"
        case .understandRelation: return "Understand a relationship"
        case .makeADecision:      return "Make a decision I'm stuck on"
        case .buildTheHabit:      return "Just build the habit"
        }
    }

    /// Chips shown on the "what's hard right now" step when this goal is
    /// among the ones picked — see `OnboardingIntent.struggleOptions(for:)`,
    /// which unions and dedupes across every selected goal.
    var struggleOptions: [String] {
        switch self {
        case .quietMyHead:
            return ["work", "money", "a decision", "sleep", "the news", "a relationship"]
        case .understandRelation:
            return ["a partner", "a parent", "a friend", "a coworker", "family", "myself"]
        case .makeADecision:
            return ["work", "money", "a relationship", "where to live", "health", "something vague"]
        case .buildTheHabit:
            return ["work", "a relationship", "sleep", "motivation", "health", "something vague"]
        }
    }

    /// The tone this goal alone would suggest — used to pre-select the tone
    /// step. See `OnboardingIntent.suggestedTone(for:)` for how several goals
    /// resolve to one tone.
    var suggestedTone: SpilrTone {
        switch self {
        case .quietMyHead:        return .gentle
        case .understandRelation: return .curious
        case .makeADecision:      return .direct
        case .buildTheHabit:      return .curious
        }
    }
}

enum SpilrTone: String, CaseIterable, Identifiable {
    case gentle, curious, direct

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .gentle:  return "🌿"
        case .curious: return "🔍"
        case .direct:  return "✴️"
        }
    }

    /// The same underlying thought, at this tone's temperature — shown on the
    /// tone-picker card so the choice is concrete rather than a label picked
    /// blind.
    var sampleLine: String {
        switch self {
        case .gentle:  return "It sounds like today asked more of you than you had to give."
        case .curious: return "What would have made today count as enough?"
        case .direct:  return "You planned to rest, then graded the rest."
        }
    }

    /// How this reads inside a system prompt — see `SpilrVoice.intentContext()`.
    var promptDescription: String {
        switch self {
        case .gentle:  return "gentle — validate before anything else, soften the edges"
        case .curious: return "curious — ask more than you assert, stay exploratory"
        case .direct:  return "direct — skip the cushioning, name what you notice plainly"
        }
    }
}

/// One person the user names on the "who's in your life" step — a fixed role
/// chip (partner, parent, boss, friend, sibling, kid) plus an optional name.
/// `role` alone is the identity: the step offers each role once, so there's
/// never a duplicate to disambiguate with a name.
struct OnboardingPerson: Codable, Equatable, Identifiable {
    var id: String { role }
    let role: String
    var name: String?

    /// How this reads inline — the name if one was given, the role otherwise.
    var displayLabel: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return role
    }
}

enum OnboardingIntent {
    private static let goalsKey          = "spilr.onboardingGoals"
    private static let toneKey           = "spilr.spilrTone"
    private static let struggleKey       = "spilr.onboardingStruggle"
    private static let struggleDetailKey = "spilr.onboardingStruggleDetail"
    private static let peopleKey         = "spilr.onboardingPeople"
    private static let baselineKey       = "spilr.onboardingBaseline"

    static var selectedGoals: Set<JournalGoal> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: goalsKey) ?? []
            return Set(raw.compactMap(JournalGoal.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: goalsKey) }
    }

    /// Defaults to `.curious` — same as the onboarding tone card that ships
    /// pre-selected and badged "SUGGESTED" — so a user who somehow reaches an
    /// AI surface before finishing the tone step still gets a sensible voice.
    static var tone: SpilrTone {
        get { SpilrTone(rawValue: UserDefaults.standard.string(forKey: toneKey) ?? "") ?? .curious }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: toneKey) }
    }

    /// One tapped chip from `struggleOptions(for:)` — "work", "a relationship",
    /// "something vague", etc. `nil` until the struggle step is answered.
    static var struggle: String? {
        get { UserDefaults.standard.string(forKey: struggleKey) }
        set { UserDefaults.standard.set(newValue, forKey: struggleKey) }
    }

    /// The optional free-text "in your words" field alongside the struggle chip.
    static var struggleDetail: String? {
        get { UserDefaults.standard.string(forKey: struggleDetailKey) }
        set { UserDefaults.standard.set(newValue, forKey: struggleDetailKey) }
    }

    /// People named on the optional "who's in your life" step. Empty means
    /// the step was skipped, not answered-and-empty — there's no distinction
    /// worth keeping between the two.
    static var people: [OnboardingPerson] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: peopleKey),
                let decoded = try? JSONDecoder().decode([OnboardingPerson].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: peopleKey)
        }
    }

    /// "How heavy do things feel lately?", 0–10. `nil` until the baseline step
    /// is answered — distinct from 0, a real (if unlikely) rating.
    static var baseline: Int? {
        get { UserDefaults.standard.object(forKey: baselineKey) as? Int }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: baselineKey) }
            else { UserDefaults.standard.removeObject(forKey: baselineKey) }
        }
    }

    /// The struggle chips to show: every selected goal's own options, unioned
    /// in `JournalGoal.allCases` order and deduped, capped at 6 so the row
    /// never wraps past two lines. Always ends with a catch-all if there's
    /// room, so no one is stuck picking something that isn't true.
    static func struggleOptions(for goals: Set<JournalGoal>) -> [String] {
        var seen: Set<String> = []
        var options: [String] = []
        outer: for goal in JournalGoal.allCases where goals.contains(goal) {
            for option in goal.struggleOptions where !seen.contains(option) {
                seen.insert(option)
                options.append(option)
                if options.count == 6 { break outer }
            }
        }
        if !seen.contains("something vague"), options.count < 6 {
            options.append("something vague")
        }
        return options
    }

    /// The tone the user's goals suggest — the first match in
    /// `JournalGoal.allCases` order when several goals were picked, so this
    /// is stable regardless of `Set` iteration order. Falls back to
    /// `.curious`, same as `tone`'s own default.
    static func suggestedTone(for goals: Set<JournalGoal>) -> SpilrTone {
        JournalGoal.allCases.first(where: goals.contains)?.suggestedTone ?? .curious
    }
}
