// PersonModelChatContext.swift
// DailyJournal
//
// Gives Daily Chat the Person Model (mirror-v3.1-person-model-2026-09-10.md
// §4/§6) — until now the falsifiable hypotheses and the daily discriminating
// question lived only on the Mirror tab, and never reached the conversation
// that could actually test them. This is deliberately POORER than the Mirror
// tab's own rendering of the same rows: no counts, no dates, no confidence
// word. Chat may only ever ask about a hypothesis, never assert one, and the
// user decided chat's references to the past stay undated and hedged
// (`ChatPrompts.md`'s "### MEMORY" rule carries the rest of that boundary).
//
// Pure, no Firestore — takes what DerivedService already has loaded.

import Foundation

enum PersonModelChatContext {

    /// At most this many hypothesis rows reach the prompt — the model block
    /// stays a faint tint, not a readout (decision: undated, hedged references).
    private static let maxRows = 3

    /// Builds the "WHAT SPILR IS STILL WORKING OUT" + "THE ONE THING WORTH
    /// FINDING OUT" block, or "" if there's nothing safe to show.
    ///
    /// `sensitiveTopicsDisabled` is the deterministic code gate the privacy
    /// PRD asks for: a row is dropped here, in Swift, before the string is
    /// ever built — not passed through and merely asked-not-to-use.
    static func block(
        items: [PersonModelItem],
        aggregate: PersonModelAggregate,
        sensitiveTopicsDisabled: [String]
    ) -> String {
        let rows = items
            .filter { $0.isActive && $0.userStatus != "not_me" }
            .filter { !isDisabled($0.displayTitle, sensitiveTopicsDisabled: sensitiveTopicsDisabled) }
            .sorted { a, b in
                let (ra, rb) = (confidenceRank(a), confidenceRank(b))
                return ra != rb ? ra > rb : a.timesSeen > b.timesSeen
            }
            .prefix(maxRows)
            .map { "- \($0.displayTitle)" }

        let question = aggregate.openHypotheses
            .first { !isDisabled($0.testQuestion ?? $0.hypothesis, sensitiveTopicsDisabled: sensitiveTopicsDisabled) }?
            .testQuestion

        guard !rows.isEmpty || (question?.isEmpty == false) else { return "" }

        var sections: [String] = []
        if !rows.isEmpty {
            sections.append("""
            WHAT SPILR IS STILL WORKING OUT ABOUT THIS PERSON (hypotheses, not facts —
            never state one as true, never say how often or when you saw it; a row here
            may only ever become a question):
            \(rows.joined(separator: "\n"))
            """)
        }
        if let question, !question.isEmpty {
            sections.append("""
            THE ONE THING WORTH FINDING OUT (ask it only if the conversation goes near it):
            - \(question)
            """)
        }
        return sections.joined(separator: "\n")
    }

    /// The deterministic privacy code gate (privacy PRD: enforced in Swift,
    /// never merely asked-of-the-model) — true when `text` overlaps a topic
    /// the user disabled. Exposed so a single string (Prompt Q's opener
    /// question, checked before it ever becomes the chat opener) can be
    /// checked the same way a whole block is.
    static func isDisabled(_ text: String?, sensitiveTopicsDisabled: [String]) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let disabled = sensitiveTopicsDisabled
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !disabled.isEmpty else { return false }
        let hay = text.lowercased()
        return disabled.contains { hay.contains($0) }
    }

    /// "likely" > "maybe" > "hunch" — the same three-word band the server
    /// computes (functions/lib/personModel.js#confidenceBandFor); this just
    /// orders rows by it, never displays it (decision 2: no confidence word).
    private static func confidenceRank(_ item: PersonModelItem) -> Int {
        switch item.confidence {
        case "likely": return 2
        case "maybe":  return 1
        default:       return 0
        }
    }
}
