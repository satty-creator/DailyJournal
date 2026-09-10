//
//  HintEngine.swift
//  DailyJournal
//
//  The observable owner of one session's hint state — just the re-roll
//  (gentler / more direct / weirder) on the composer's starter prompt. Purely
//  local: `HintLadder.starterPrompt` computes each phrasing synchronously and
//  nothing here ever calls the network.
//
//  Used to also own a full `HintBundle` (starter + the Hint Ladder panel's
//  tiny/specific/choice lanes), enrich the starter with a Gemini call fired
//  from init (see ai-cost-audit-2026-09-06.md §3.2), and drive the panel's
//  "make it smaller" descent. All of that was cut — the panel was unreachable
//  UI, and the enrichment cost 11% of AI spend for an upgrade to one line of
//  text — leaving only the re-roll, the one piece the composer actually uses.
//
//  Non-blocking and failure-tolerant — a hint never stalls the writing surface.
//

import Foundation

@MainActor
final class HintEngine: ObservableObject {

    let context: HintContext

    init(context: HintContext) {
        self.context = context
    }

    // MARK: - Starter

    /// Per-style rotation index so tapping the SAME restyle again yields a new
    /// question instead of repeating one fixed string.
    private var styleVariant: [HintLadder.PromptStyle: Int] = [:]

    /// Re-roll the starter locally when the user taps gentler / direct / weirder.
    /// (Stays local — these are instant, no-network nudges.) Advances a per-style
    /// counter so each tap shuffles to a different phrasing.
    func restyledStarter(_ style: HintLadder.PromptStyle) -> String {
        let next = (styleVariant[style] ?? -1) + 1
        styleVariant[style] = next
        return HintLadder.starterPrompt(
            pebbles: context.pebbles,
            personal: context.personal,
            style: style,
            variant: next
        )
    }
}
