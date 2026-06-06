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

    // MARK: - Normalisation

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
