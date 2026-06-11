//
//  HintEngine.swift
//  DailyJournal
//
//  The observable owner of one session's hint state. It is local-first: it hands
//  the UI a complete bundle synchronously at init, then quietly swaps in a richer
//  Gemini bundle if one comes back. It also owns the ladder position ("make it
//  smaller") and the day-scoped "less hints today" preference.
//
//  Everything here is non-blocking and failure-tolerant — a hint never stalls the
//  writing surface.
//

import Foundation
import SwiftUI

@MainActor
final class HintEngine: ObservableObject {

    // MARK: - Published state

    /// The bundle the UI renders. Starts local, may upgrade to Gemini.
    @Published private(set) var bundle: HintBundle

    /// The current ladder position. Descends one rung each "make it smaller" tap.
    @Published private(set) var rung: HintRung = .specificPrompt

    /// User asked for fewer hints today. Suppresses the auto blank-rescue prompt
    /// (the manual hint button always stays available — help, never nagging).
    @Published private(set) var hintsQuietedToday: Bool

    let context: HintContext

    // MARK: - Init

    init(context: HintContext) {
        self.context = context
        self.bundle  = context.localBundle
        self.hintsQuietedToday = Self.isQuieted(on: MoodLog.dayKey())

        // Fire-and-forget enrichment. Local bundle is already on screen.
        Task { [weak self] in await self?.enrich() }
    }

    // MARK: - Starters

    /// The starter prompt for the active surface.
    func starter(for mode: HintMode) -> String {
        mode == .talk ? bundle.starterTalk : bundle.starterWrite
    }

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

    func restyledVoice(_ kind: HintLadder.VoiceKind) -> String {
        HintLadder.voicePrompt(pebbles: context.pebbles, kind: kind)
    }

    // MARK: - Panel cards

    func cards(for tab: HintTab) -> [HintCard] {
        // Gemini bundle already has mode-correct phrasing; the local fallback is
        // generated for `.write`, so re-derive talk cards locally when needed.
        if bundle.source == "gemini" { return bundle.cards(for: tab) }
        return HintLadder.cards(for: tab, pebbles: context.pebbles, personal: context.personal, mode: context.mode)
    }

    // MARK: - Ladder

    /// Descend one rung and return the smaller hint. Always succeeds — the floor
    /// is a blank drop, so the user is never told to try harder.
    @discardableResult
    func makeSmaller() -> HintCard {
        rung = rung.smaller
        return HintLadder.rungHint(rung, pebbles: context.pebbles, personal: context.personal, mode: context.mode)
    }

    /// The hint for the current rung without advancing (used to seed the panel).
    func currentRungHint() -> HintCard {
        HintLadder.rungHint(rung, pebbles: context.pebbles, personal: context.personal, mode: context.mode)
    }

    // MARK: - Quiet for today

    func quietForToday() {
        hintsQuietedToday = true
        Self.setQuieted(on: MoodLog.dayKey())
    }

    // MARK: - Enrichment

    private func enrich() async {
        guard let upgraded = await AIService.shared.enrichHints(for: context) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { bundle = upgraded }
    }

    // MARK: - Day-scoped persistence

    private static func key(_ day: String) -> String { "hintsQuieted-\(day)" }

    private static func isQuieted(on day: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(day))
    }

    private static func setQuieted(on day: String) {
        UserDefaults.standard.set(true, forKey: key(day))
    }
}
