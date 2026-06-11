//
//  QuestionBank.swift
//  DailyJournal
//
//  Core models, enums, and pebble bank constants for the Question Bank feature.
//  This replaces the HintLadder direction. The product promise is now:
//  "Ask me something I can actually answer."
//
//  Design rules:
//   • Questions, not commands. Never sentence stems.
//   • Personal only when the user has allowed personalization.
//   • The ladder descends by making the question easier to answer — not smaller.
//   • A blank drop is not failure. It means the user showed up.
//

import Foundation
import SwiftUI

// MARK: - QuestionMode

/// Whether the user is starting in the writing or talking surface.
enum QuestionMode: String, Codable, CaseIterable {
    case write
    case talk

    var label: String {
        switch self {
        case .write: return "Write"
        case .talk:  return "Talk"
        }
    }

    var blurb: String {
        switch self {
        case .write: return "A tiny sentence, messy notes, or one true thing."
        case .talk:  return "Say one sentence, pause, or save a trace."
        }
    }
}

// MARK: - QuestionPersonal

/// How close to the user's own words a question may get.
/// Higher levels are in-app only — never lock-screen, notification, or widget facing.
enum QuestionPersonal: String, Codable, CaseIterable {
    /// Universal, warm, non-private questions. Safe to show anywhere.
    case safe
    /// May use today's pebbles and broad behavioral patterns. In-app only.
    case light
    /// May use confirmed personal phrases and recurring themes. In-app only.
    case me

    var label: String {
        switch self {
        case .safe:  return "safe"
        case .light: return "light"
        case .me:    return "my words"
        }
    }

    var blurb: String {
        switch self {
        case .safe:  return "Generic but warm."
        case .light: return "Uses today's pebbles."
        case .me:    return "Only your confirmed phrases."
        }
    }

    /// Only `.safe` questions may appear outside the app shell.
    var isLockScreenSafe: Bool { self == .safe }
}

// MARK: - QuestionSource

enum QuestionSource: String, Codable {
    case universal      // from the fixed 50-question bank
    case localContext   // selected locally using pebble scoring
    case personal       // from the user's personalized question bank
    case gemini         // AI-enriched bundle
}

// MARK: - QuestionCategory

enum QuestionCategory: String, Codable, CaseIterable {
    case blank          // blank-page friendly
    case body           // body, energy, and mood
    case people         // people and messages
    case work           // work, pressure, and avoidance
    case home           // home, world, and tiny details
    case personal       // personal / confirmed-phrase questions
}

// MARK: - QuestionAnswerStyle

enum QuestionAnswerStyle: String, Codable {
    case open           // user answers freely in their own words
    case choice         // either/or question
    case tapOnly        // user taps a word from a list
    case trace          // save chosen pebbles or feeling words
}

// MARK: - QuestionRung

/// The ladder, from most specific (top) to the floor (blank drop).
/// Each "make it easier" tap descends one rung.
/// The user is never punished for descending.
enum QuestionRung: Int, CaseIterable, Comparable {
    case specificQuestion   = 0   // sharp, contextual question
    case gentleQuestion     = 1   // softer question, less emotional demand
    case choiceQuestion     = 2   // either/or question
    case tapOnlyQuestion    = 3   // user answers with one tap
    case traceOnly          = 4   // save chosen pebbles or feeling words
    case blankDrop          = 5   // show up with nothing; river still gets a mark

    static func < (lhs: QuestionRung, rhs: QuestionRung) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var smaller: QuestionRung { QuestionRung(rawValue: rawValue + 1) ?? .blankDrop }
    var isFloor: Bool { self == .blankDrop }
}

// MARK: - QuestionTab

/// The three visible tabs in the question panel.
/// A fourth tab (.mine) is hidden until sufficient personalization history exists.
enum QuestionTab: String, CaseIterable {
    case gentle
    case specific
    case choice
    case mine

    var title: String {
        switch self {
        case .gentle:   return "Ask me gently"
        case .specific: return "Ask about today"
        case .choice:   return "Give me a choice"
        case .mine:     return "Mine"
        }
    }

    var subtitle: String {
        switch self {
        case .gentle:   return "Low pressure. Easy to answer badly."
        case .specific: return "Based on today's pebbles."
        case .choice:   return "Pick one. No composing required."
        case .mine:     return "Questions learned from your patterns."
        }
    }
}

// MARK: - QuestionRerollStyle

/// The reroll pill the user taps inside the session.
enum QuestionRerollStyle: String {
    // write mode
    case gentler
    case moreSpecific
    case giveChoice
    case surpriseMe
    // talk mode
    case shorter
    case easier
}

// MARK: - QuestionCard

/// A single question card shown in the panel or as the session starter.
/// `question` is displayed as the prompt. It should not be auto-inserted into the journal body.
struct QuestionCard: Identifiable, Equatable {
    let id: String          // stable question ID e.g. "UQ001" or UUID for AI cards
    let lead: String        // small label e.g. "Start here", "Gentle question"
    let question: String    // the actual question shown to the user
    let category: QuestionCategory
    let tags: [String]
    let source: QuestionSource
    let personalLevel: QuestionPersonal
    let accent: Accent
    let answerStyle: QuestionAnswerStyle
    let rung: QuestionRung

    enum Accent: String { case soft, mint, lav, sun }

    static func == (lhs: QuestionCard, rhs: QuestionCard) -> Bool { lhs.id == rhs.id }
}

// MARK: - QuestionBundle

/// The full set of questions for one session context.
/// Local bundle is always built synchronously; AI enrichment is optional.
struct QuestionBundle: Equatable {
    var starterWrite: QuestionCard
    var starterTalk: QuestionCard
    var gentle: [QuestionCard]    // 3 soft questions
    var specific: [QuestionCard]  // 3 contextual, pebble-aware questions
    var choice: [QuestionCard]    // 3 either/or questions
    var mine: [QuestionCard]      // 3 personalized (empty until history exists)
    var source: String            // "local", "gemini", or "personal"

    func cards(for tab: QuestionTab) -> [QuestionCard] {
        switch tab {
        case .gentle:   return gentle
        case .specific: return specific
        case .choice:   return choice
        case .mine:     return mine
        }
    }
}

// MARK: - QuestionContext

/// Passed from QuestionPickerView → NinetySecondSessionView → QuestionEngine.
struct QuestionContext: Equatable {
    var pebbles: [String]
    var personal: QuestionPersonal
    var mode: QuestionMode
    /// Set when the user explicitly selects a specific question before entering the session.
    var explicitQuestion: String?
    var source: QuestionSource

    init(
        pebbles: [String] = [],
        personal: QuestionPersonal = .safe,
        mode: QuestionMode = .write,
        explicitQuestion: String? = nil,
        source: QuestionSource = .universal
    ) {
        self.pebbles = Array(pebbles.prefix(QuestionBank.maxPebbles))
        self.personal = personal
        self.mode = mode
        self.explicitQuestion = explicitQuestion
        self.source = source
    }
}

// HintContext drives .fullScreenCover(item:), which needs Identifiable.
extension QuestionContext: Identifiable {
    var id: String {
        "\(mode.rawValue)|\(personal.rawValue)|\(pebbles.joined(separator: ","))|\(explicitQuestion ?? "")"
    }
}

// MARK: - QuestionOutcome

/// Lightweight outcome recorded every time a question is shown.
/// Drives the startedness score without reading the user's content.
struct QuestionOutcome: Codable {
    let questionID: String
    let source: QuestionSource
    let mode: QuestionMode
    let pebbles: [String]
    let shownAt: Date

    var selected: Bool = false
    var dismissed: Bool = false
    var lessLikeThis: Bool = false
    var timeToFirstInput: TimeInterval? = nil
    var sessionSaved: Bool = false
    var blankDropSaved: Bool = false
    var wordCount: Int = 0
    var audioDuration: TimeInterval? = nil
}

// MARK: - QuestionBank constants

/// Static constants — pebble bank, personal pebble set, tap-only feeling words.
enum QuestionBank {

    static let maxPebbles = 3

    static let pebbleBank: [String] = [
        "work", "food", "moved", "sleep", "people", "messages",
        "home", "money", "screen", "outside", "avoided", "tiny win",
        "nothing happened", "I don't know", "Sunday dread", "after gym"
    ]

    /// Personal pebbles may only influence questions when QuestionPersonal == .me.
    /// They should never appear in lock-screen, notification, or widget contexts.
    static let personalPebbles: Set<String> = ["Sunday dread", "after gym"]

    /// Feeling words used for tap-only trace answers.
    static let feelingWords: [String] = [
        "flat", "loud", "soft", "sharp", "heavy", "fizzy", "quiet", "stuck"
    ]

    /// Pebble → category tag mapping used by QuestionMixer for scoring.
    static let pebbleTagMap: [String: [String]] = [
        "work":             ["work"],
        "food":             ["body"],
        "moved":            ["body"],
        "sleep":            ["body"],
        "people":           ["people"],
        "messages":         ["people"],
        "home":             ["home"],
        "money":            ["home"],
        "screen":           ["home"],
        "outside":          ["home"],
        "avoided":          ["work"],
        "tiny win":         ["work"],
        "nothing happened": ["blank"],
        "I don't know":     ["blank"],
        "Sunday dread":     ["blank", "personal"],
        "after gym":        ["body", "personal"]
    ]
}
