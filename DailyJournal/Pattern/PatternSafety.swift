//
//  PatternSafety.swift
//  DailyJournal
//
//  NON-NEGOTIABLE SAFETY LAYER for Pattern Callbacks.
//
//  Product rule, preserved verbatim from the PRD:
//
//    "A hard content filter for self-harm, suicide, eating disorder, or
//     substance abuse signals. These patterns get *zero* pattern callbacks —
//     instead they trigger a different flow: a soft, opt-in resource card."
//
//  This filter runs as a deterministic local gate BEFORE any callback can be
//  created, in addition to the instructions baked into the LLM detection prompt.
//  Belt and suspenders: if EITHER the model or this scanner sees crisis signals
//  anywhere in the detection window, we suppress ALL callbacks for that run and
//  route to PatternResourceCardView instead.
//
//  This scanner intentionally errs toward over-triggering. A missed callback is
//  costless; a callback layered on top of a crisis signal is not.
//

import Foundation

enum PatternSafety {

    /// Crisis-signal phrases. Lowercased, matched on word/substring boundaries.
    /// Grouped by domain only for readability — all route to the same outcome.
    private static let crisisPhrases: [String] = [
        // self-harm / suicide
        "suicide", "suicidal", "kill myself", "killing myself", "end my life",
        "ending my life", "end it all", "want to die", "wish i was dead",
        "wish i were dead", "better off dead", "no reason to live",
        "self harm", "self-harm", "harm myself", "hurt myself", "cut myself",
        "cutting myself", "overdose",
        // eating
        "starve myself", "starving myself", "make myself throw up",
        "make myself sick", "purge", "purging", "binge and purge",
        "anorexi", "bulimi", "not eating for days", "hate my body so much",
        // substance
        "relapse", "relapsed", "drinking again", "blackout drunk",
        "can't stop drinking", "cant stop drinking", "using again",
        "high again", "need a drink to", "drink to cope", "drink to forget",
        "pills to cope", "getting high to"
    ]

    /// Returns true if the text contains any crisis signal.
    static func containsCrisisSignal(in text: String) -> Bool {
        let haystack = normalise(text)
        return crisisPhrases.contains { haystack.contains($0) }
    }

    /// Scans an entire detection corpus. True if ANY entry trips the filter.
    static func corpusHasCrisisSignal(_ texts: [String]) -> Bool {
        texts.contains { containsCrisisSignal(in: $0) }
    }

    // MARK: - Chat-specific tier
    //
    // `containsCrisisSignal` above is a raw substring scan built for the corpus-level
    // pattern gate, where the header comment's "a missed callback is costless" tradeoff
    // is correct — an over-trigger there just skips one callback. In a live chat turn
    // the same over-trigger ends the conversation and hands the user a 988 card, so an
    // ordinary sentence like "my anxiety was high again today" or "I need to purge my
    // inbox" cannot be allowed to trip it. This does NOT change `containsCrisisSignal`
    // or `corpusHasCrisisSignal` — the pattern engine's behaviour is untouched.

    enum ChatCrisisLevel {
        /// No signal at all.
        case none
        /// A metaphor-prone word ("purge", "relapse", "high again", …) that is far more
        /// often mundane than a crisis signal in live conversation. Does NOT stop the
        /// turn or show the resource card — `SpilrVoice.chatSafetyRules`' own crisis
        /// override is the layer that catches a genuine signal phrased this way.
        case ambiguous
        /// An unambiguous self-harm / suicide / eating-disorder signal. Hard stop,
        /// same as `containsCrisisSignal` today.
        case explicit
    }

    /// Unambiguous — self-harm, suicide, and the eating-disorder phrases that have no
    /// ordinary reading.
    private static let explicitChatPhrases: [String] = [
        "suicide", "suicidal", "kill myself", "killing myself", "end my life",
        "ending my life", "end it all", "want to die", "wish i was dead",
        "wish i were dead", "better off dead", "no reason to live",
        "self harm", "self-harm", "harm myself", "hurt myself", "cut myself",
        "cutting myself", "starve myself", "starving myself",
        "make myself throw up",
    ]

    /// Word-stem prefixes for the unambiguous set — "anorexi[a/c]", "bulimi[a/c]" — where
    /// a trailing `\b` after the stem would miss the actual word forms.
    private static let explicitChatStems: [String] = ["anorexi", "bulimi"]

    /// Ambiguous — mundane in ordinary conversation far more often than not. Real
    /// checking of these against a genuine crisis reading is left to the model's own
    /// safety rules, not this deterministic gate.
    private static let ambiguousChatPhrases: [String] = [
        "purge", "purging", "binge and purge", "make myself sick",
        "relapse", "relapsed", "drinking again", "blackout drunk",
        "can't stop drinking", "cant stop drinking", "using again",
        "high again", "need a drink to", "drink to cope", "drink to forget",
        "pills to cope", "getting high to", "overdose", "hate my body so much",
    ]

    /// Chat's own crisis check — word-boundary matching, three tiers instead of one.
    static func chatCrisisLevel(in text: String) -> ChatCrisisLevel {
        let haystack = normalise(text)
        if explicitChatPhrases.contains(where: { containsWordBoundary($0, in: haystack) })
            || explicitChatStems.contains(where: { haystack.contains($0) }) {
            return .explicit
        }
        if ambiguousChatPhrases.contains(where: { containsWordBoundary($0, in: haystack) }) {
            return .ambiguous
        }
        return .none
    }

    /// Matches `phrase` in `haystack` on word boundaries (both sides), not as a bare
    /// substring — so "purge" doesn't match inside "purger" and, more importantly,
    /// phrases keep their intended reading rather than firing on partial overlaps.
    private static func containsWordBoundary(_ phrase: String, in haystack: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: []) else {
            return haystack.contains(phrase)
        }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    // MARK: - Normalisation

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
