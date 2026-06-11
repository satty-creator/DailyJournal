//
//  HintLadder.swift
//  DailyJournal
//
//  The Hint Ladder — a just-in-time support layer that gives the user optional,
//  contextual, progressively SMALLER starts when they feel blank. The product
//  never says "try harder." It says "make it smaller."
//
//  This file is the deterministic, on-device source of truth. It runs instantly,
//  works offline, and produces every hint the UI can show. AIService+Hints layers
//  sharper, more personal phrasing on top when there's a network + signed-in user,
//  but the local engine is always a complete, shippable fallback.
//
//  Design rules baked in here (from the PRD):
//   • Hints are optional and tiny. Never shame, nag, diagnose, or perform.
//   • The ladder goes DOWN: specific prompt → sentence stem → three words →
//     this-or-that → tap-only trace → blank drop.
//   • Talk mode is phrased as "say one sentence", never "talk for 90 seconds".
//   • Personal hints stay in-app; the engine never emits raw personal themes for
//     anything lock-screen facing (see `HintPersonal`).
//

import Foundation

// MARK: - Mode

/// Whether the user is starting in the writing surface or the talking surface.
/// Distinct from `SessionType` because both write and talk can produce a
/// 90-second entry — this only changes how a hint is phrased.
enum HintMode: String, Codable, CaseIterable {
    case write
    case talk
}

// MARK: - How personal

/// How close to the user's own words a hint is allowed to get. Higher levels
/// only ever surface *in-app* — never on the lock screen or in share copy.
enum HintPersonal: String, Codable, CaseIterable {
    /// Generic but warm. Safe to show anywhere.
    case safe
    /// Uses today's chosen pebbles. In-app only.
    case light
    /// User-confirmed phrases only (e.g. a saved "Sunday dread"). In-app only.
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

    /// Personal levels above `safe` are never allowed outside the app shell.
    var isLockScreenSafe: Bool { self == .safe }
}

// MARK: - Ladder rungs

/// The ladder, top (most effortful) to bottom (least effortful). Each "make it
/// smaller" tap descends exactly one rung. There is always a floor: a blank drop
/// still counts, so a user who cannot write or talk can still save a trace.
enum HintRung: Int, CaseIterable, Comparable {
    case specificPrompt = 0   // a sharp, contextual question
    case sentenceStem         // "Today felt…"
    case threeWords           // body / room / thought
    case thisOrThat           // was it more X or Y?
    case tapOnlyTrace         // save the pebbles, no words
    case blankDrop            // show up with nothing at all

    static func < (lhs: HintRung, rhs: HintRung) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The next rung down. The blank drop is the floor — it returns itself.
    var smaller: HintRung { HintRung(rawValue: rawValue + 1) ?? .blankDrop }

    var isFloor: Bool { self == .blankDrop }
}

// MARK: - Hint tabs (the panel's three lanes)

/// The three lanes shown in the hint panel. They are alternate doors into the
/// ladder, not a strict sequence — "tiny" is the gentlest, "choice" removes
/// composition entirely, "specific" leans on the chosen pebbles.
enum HintTab: String, CaseIterable {
    case tiny
    case specific
    case choice

    var title: String {
        switch self {
        case .tiny:     return "Make it tiny."
        case .specific: return "A more personal hint."
        case .choice:   return "Choose, don't compose."
        }
    }

    var subtitle: String {
        switch self {
        case .tiny:     return "No full sentence required."
        case .specific: return "Based only on today's pebbles."
        case .choice:   return "Tap a sentence and change it if you want."
        }
    }
}

// MARK: - A single hint card

/// A tappable hint. `lead` is the small label ("Write 3 words"); `text` is the
/// thing the user can actually use ("body / room / thought"). `insertable` is
/// the cleaned string that should land in the editor / voice prompt when tapped.
struct HintCard: Identifiable, Equatable {
    let id = UUID()
    let lead: String
    let text: String
    let accent: Accent
    /// The rung this card represents — drives the ladder + analytics.
    let rung: HintRung

    enum Accent: String { case soft, mint, lav, sun }

    /// What to actually drop into the field. For stems like "Finish this" we
    /// strip the instruction so only the usable fragment is inserted.
    var insertable: String {
        text
            .replacingOccurrences(of: "Finish this:", with: "")
            .replacingOccurrences(of: "Write 3 words:", with: "")
            .replacingOccurrences(of: "Say 3 words:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - The bundle the UI renders

/// Everything the hint surfaces need for one context. The local engine fills
/// this synchronously; Gemini can replace it wholesale later (same shape).
struct HintBundle: Equatable {
    var starterWrite: String
    var starterTalk: String
    var tiny: [HintCard]
    var specific: [HintCard]
    var choice: [HintCard]
    /// "local" or "gemini" — lets the UI show provenance and the engine decide
    /// whether an enrichment swap is still worth doing.
    var source: String

    func cards(for tab: HintTab) -> [HintCard] {
        switch tab {
        case .tiny:     return tiny
        case .specific: return specific
        case .choice:   return choice
        }
    }
}

// MARK: - The local engine

/// Deterministic hint generation. Pure functions, no state, no I/O — safe to
/// call from anywhere, instantly. Mirrors the agreed prototype behaviour.
enum HintLadder {

    // MARK: Pebble bank

    /// The starter pebbles. Order matters — calmer/world pebbles first, the more
    /// personal "confirmed phrase" pebbles last and flagged below.
    static let pebbleBank: [String] = [
        "work", "food", "moved", "sleep", "people", "messages",
        "home", "money", "screen", "outside", "avoided", "tiny win",
        "nothing happened", "I don't know", "Sunday dread", "after gym"
    ]

    /// Pebbles that are user-confirmed personal phrases. These only inform hints
    /// when `HintPersonal == .me`, and are never emitted lock-screen facing.
    static let personalPebbles: Set<String> = ["Sunday dread", "after gym"]

    /// The tap-only feeling words used for a trace (no sentence required).
    static let feelingWords: [String] = ["flat", "loud", "soft", "sharp", "heavy", "fizzy", "quiet", "stuck"]

    static let maxPebbles = 3

    // MARK: Starter prompt (write)

    /// The one starter hint shown on the writing screen. `style` lets the user
    /// nudge it gentler / more direct / weirder without leaving the page.
    static func starterPrompt(
        pebbles: [String],
        personal: HintPersonal = .safe,
        style: PromptStyle = .default,
        variant: Int = 0
    ) -> String {
        let p = effectivePebbles(pebbles)
        let has = { (x: String) in p.contains(x) }

        // When the user explicitly taps gentler / more direct / weirder, rotate
        // through a small pool of phrasings so re-tapping the SAME control always
        // produces a NEW question (it used to return one fixed string forever).
        if style != .default {
            let pool = styledPool(style, pebbles: p)
            guard !pool.isEmpty else { return pool.first ?? "" }
            return pool[((variant % pool.count) + pool.count) % pool.count]
        }

        // Combination-aware starters — the specific magic from the prototype.
        if has("work") && has("food") {
            return style == .direct
                ? "Was food a pause, a rush, or an afterthought today?"
                : "Did work change how you ate, or did food change how work felt?"
        }
        if has("work") && has("moved") {
            return "Did movement clear the workday, or did work follow you into your body?"
        }
        if has("messages") && has("avoided") {
            return "Which felt louder: the message, or the thought of replying?"
        }
        if has("sleep") && has("people") {
            return "Did tiredness make people feel heavier today?"
        }
        if has("tiny win") && has("avoided") {
            return "What can be true together: the small win, and the thing still undone?"
        }
        if has("I don't know") {
            return "Start with: I don't know, but…"
        }
        if has("nothing happened") {
            return "If nothing happened, what still had a texture?"
        }
        // Personal pebble — only when the user confirmed "my words".
        if has("Sunday dread") && personal == .me {
            return "Is Sunday dread here today, or only its shadow?"
        }

        // Style fallbacks. Tuned to be specific and a little probing rather than
        // soft and forgettable — the local path should still feel like it's
        // reaching for something true.
        switch style {
        case .weird:   return "If today were a closing door, what's on the other side of it?"
        case .direct:  return "What took the most from you today — and did you let it?"
        case .gentle:  return "What's one small thing today that you haven't let yourself feel yet?"
        case .default: break
        }

        // Generic fallbacks (no matching combo). Still pointed, never bland.
        return p.isEmpty || p == ["today"]
            ? "What's the thing you've been not-thinking-about all day?"
            : "Which of these did you avoid looking at directly today?"
    }

    enum PromptStyle: String { case `default`, gentle, direct, weird }

    /// A rotating pool of phrasings for each restyle. Some weave in the user's
    /// first pebble so the shuffled question still feels specific. The caller
    /// advances `variant` on each tap (see `HintEngine.restyledStarter`).
    private static func styledPool(_ style: PromptStyle, pebbles: [String]) -> [String] {
        let lead = pebbles.first.flatMap { $0 == "today" ? nil : $0 }
        switch style {
        case .gentle:
            return [
                "What's one small thing today that you haven't let yourself feel yet?",
                "If today asked nothing of you, what would you still want to say?",
                lead.map { "What did \($0) leave behind that you haven't named?" }
                    ?? "What softened, even a little, today?",
                "What would you say to a friend who'd had your exact day?"
            ]
        case .direct:
            return [
                "What took the most from you today — and did you let it?",
                "What are you avoiding writing down right now?",
                lead.map { "Be honest: what did \($0) actually cost you today?" }
                    ?? "What's the truth you keep editing before you say it?",
                "What do you already know that you keep pretending you don't?"
            ]
        case .weird:
            return [
                "If today were a closing door, what's on the other side of it?",
                "What colour was today — and why that one?",
                lead.map { "If \($0) were a sound today, what was it?" }
                    ?? "What object best holds how today felt?",
                "If today left you a note, what would its first line be?"
            ]
        case .default:
            return []
        }
    }

    // MARK: Starter prompt (talk)

    /// Talk-mode starter. Phrased as "say one small thing" — never a performance.
    static func voicePrompt(pebbles: [String], kind: VoiceKind = .default) -> String {
        let p = effectivePebbles(pebbles)
        let pair = Array(p.prefix(2)).joined(separator: " or ")

        switch kind {
        case .choice:
            return "Say: it was more \(p.first ?? "heavy") than \(p.dropFirst().first ?? "clear") today."
        case .short:
            return "Say: Today felt…"
        case .default:
            if !p.isEmpty && p != ["today"] {
                return "Start with: today, \(pair) was the thing."
            }
            return "Start with: today was mostly…"
        }
    }

    enum VoiceKind: String { case `default`, short, choice }

    // MARK: The ladder (one rung at a time)

    /// The single hint for a given rung — used by the "make it smaller" descent
    /// and the blank-rescue flow. Talk mode rephrases "write" → "say".
    static func rungHint(
        _ rung: HintRung,
        pebbles: [String],
        personal: HintPersonal = .safe,
        mode: HintMode = .write
    ) -> HintCard {
        let p = effectivePebbles(pebbles)
        let verb = mode == .talk ? "Say" : "Write"

        switch rung {
        case .specificPrompt:
            return HintCard(lead: "A sharper start",
                            text: mode == .talk ? voicePrompt(pebbles: pebbles) : starterPrompt(pebbles: pebbles, personal: personal),
                            accent: .soft, rung: rung)
        case .sentenceStem:
            return HintCard(lead: "Finish this", text: "Today felt…", accent: .soft, rung: rung)
        case .threeWords:
            return HintCard(lead: "\(verb) 3 words", text: "body / room / thought", accent: .mint, rung: rung)
        case .thisOrThat:
            return HintCard(lead: "This or that",
                            text: "Was it more \(p.first ?? "tired") or \(p.dropFirst().first ?? "quiet") today?",
                            accent: .lav, rung: rung)
        case .tapOnlyTrace:
            let trace = p == ["today"] ? "today" : p.joined(separator: " / ")
            return HintCard(lead: "Trace only", text: "Save: \(trace)", accent: .sun, rung: rung)
        case .blankDrop:
            return HintCard(lead: "Blank drop", text: "Show up with nothing. The river still gets a mark.", accent: .lav, rung: rung)
        }
    }

    // MARK: Panel lanes

    /// The cards for a panel tab. Talk mode swaps "Write 3 words" → "Say 3 words".
    static func cards(
        for tab: HintTab,
        pebbles: [String],
        personal: HintPersonal = .safe,
        mode: HintMode = .write
    ) -> [HintCard] {
        let p = effectivePebbles(pebbles)
        let verb = mode == .talk ? "Say" : "Write"

        switch tab {
        case .tiny:
            return [
                HintCard(lead: "\(verb) 3 words", text: "body / room / thought", accent: .mint, rung: .threeWords),
                HintCard(lead: "Finish this", text: "Today felt…", accent: .soft, rung: .sentenceStem),
                HintCard(lead: "One honest word", text: "Choose one: loud, flat, heavy, soft.", accent: .lav, rung: .threeWords)
            ]
        case .choice:
            let trace = p == ["today"] ? "today" : p.joined(separator: " / ")
            return [
                HintCard(lead: "This or that",
                         text: "Was it more \(p.first ?? "tired") or \(p.dropFirst().first ?? "quiet") today?",
                         accent: .soft, rung: .thisOrThat),
                HintCard(lead: "Say it badly", text: "The thing I keep circling is…", accent: .mint, rung: .sentenceStem),
                HintCard(lead: "Trace only", text: "Save: \(trace)", accent: .sun, rung: .tapOnlyTrace)
            ]
        case .specific:
            return [
                HintCard(lead: "Use today's pebbles", text: starterPrompt(pebbles: pebbles, personal: personal, style: .default), accent: .soft, rung: .specificPrompt),
                HintCard(lead: "Make it direct", text: starterPrompt(pebbles: pebbles, personal: personal, style: .direct), accent: .mint, rung: .specificPrompt),
                HintCard(lead: "Make it strange", text: starterPrompt(pebbles: pebbles, personal: personal, style: .weird), accent: .lav, rung: .specificPrompt)
            ]
        }
    }

    // MARK: Full bundle

    /// Build the complete local bundle for a context in one shot.
    static func localBundle(pebbles: [String], personal: HintPersonal = .safe) -> HintBundle {
        HintBundle(
            starterWrite: starterPrompt(pebbles: pebbles, personal: personal),
            starterTalk:  voicePrompt(pebbles: pebbles),
            tiny:         cards(for: .tiny, pebbles: pebbles, personal: personal, mode: .write),
            specific:     cards(for: .specific, pebbles: pebbles, personal: personal, mode: .write),
            choice:       cards(for: .choice, pebbles: pebbles, personal: personal, mode: .write),
            source:       "local"
        )
    }

    // MARK: Helpers

    /// Pebbles, or a neutral `["today"]` stand-in so every function still
    /// produces a warm, generic hint when nothing is selected.
    private static func effectivePebbles(_ pebbles: [String]) -> [String] {
        pebbles.isEmpty ? ["today"] : pebbles
    }
}
