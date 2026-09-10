//
//  OnboardingIntent.swift
//  DailyJournal
//
//  What the person said brought them here, and how they want Spilr to sound
//  back — collected once, in onboarding's goals/tone step (Spilr Redesign
//  2a), and read by `SpilrVoice.intentContext()` on every AI prompt
//  thereafter (folded into `MemoryProfileService.cachedPromptContext()`, so
//  it reaches every prompt that already includes memory context with no
//  second call site to keep in sync — see that function's doc comment).
//
//  Persisted, not derived — unlike `MemoryProfile` (Memory/MemoryProfile.swift),
//  which is intentionally cached/derived and never hand-edited, this is the
//  user's own direct statement and is never overwritten by the AI layer.
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

enum OnboardingIntent {
    private static let goalsKey = "spilr.onboardingGoals"
    private static let toneKey  = "spilr.spilrTone"

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
}
