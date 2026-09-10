//
//  HintLadder.swift
//  DailyJournal
//
//  The Hint Ladder — a just-in-time support layer that gives the user an
//  optional, contextual starter when they feel blank, with a re-roll (gentler /
//  more direct / weirder) rather than one fixed question.
//
//  This file is the deterministic, on-device source of truth for that starter.
//  It runs instantly, works offline. A Gemini enrichment layer used to sharpen
//  the phrasing further when there was a network + signed-in user; it was cut
//  (11% of AI spend for one line of text — see ai-cost-audit-2026-09-06.md
//  §3.2). A fuller ladder also used to exist here — a numbered descent
//  (specific prompt → sentence stem → three words → this-or-that → tap-only
//  trace → blank drop) surfaced through a dedicated hint panel, with separate
//  talk-mode phrasing — but the panel was unreachable UI and was cut along
//  with it, leaving only the one starter the composer actually shows.
//
//  Design rules still baked in here (from the PRD):
//   • Hints are optional and tiny. Never shame, nag, diagnose, or perform.
//   • Personal hints stay in-app; the engine never emits raw personal themes for
//     anything lock-screen facing (see `HintPersonal`).
//

import Foundation

// MARK: - Context

/// The user's chosen direction for the day. Drives the local engine. Kept tiny
/// on purpose — the whole point is "no big question".
struct HintContext: Equatable {
    var pebbles: [String]
    var personal: HintPersonal
    var mode: HintMode

    init(pebbles: [String] = [], personal: HintPersonal = .safe, mode: HintMode = .write) {
        self.pebbles  = Array(pebbles.prefix(HintLadder.maxPebbles))
        self.personal = personal
        self.mode     = mode
    }
}

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

// MARK: - The local engine

/// Deterministic hint generation. Pure functions, no state, no I/O — safe to
/// call from anywhere, instantly. Mirrors the agreed prototype behaviour.
enum HintLadder {

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

    // MARK: Helpers

    /// Pebbles, or a neutral `["today"]` stand-in so every function still
    /// produces a warm, generic hint when nothing is selected.
    private static func effectivePebbles(_ pebbles: [String]) -> [String] {
        pebbles.isEmpty ? ["today"] : pebbles
    }
}
