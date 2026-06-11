//
//  QuestionEngine.swift
//  DailyJournal
//
//  Session-level question state. @MainActor ObservableObject that lives inside
//  NinetySecondSessionView. Replaces HintEngine.
//
//  On init it synchronously builds a local QuestionBundle and immediately
//  exposes a starter question. It then fires off AI enrichment in the background.
//  If AI succeeds, the bundle is swapped in with animation. If it fails, the
//  local bundle stays — the user never knows.
//
//  The ladder descends by making the question *easier to answer*, not by
//  making the user produce less. The floor is a blank drop, which still counts.
//

import Foundation
import SwiftUI

@MainActor
final class QuestionEngine: ObservableObject {

    // MARK: - Published state

    /// The full bundle for this session. Starts local, may upgrade to Gemini.
    @Published private(set) var bundle: QuestionBundle

    /// The currently displayed starter question.
    @Published private(set) var currentQuestion: QuestionCard

    /// Current rung of the "make it easier" ladder.
    @Published private(set) var rung: QuestionRung = .specificQuestion

    /// User asked for no questions today — suppresses the blank-rescue banner.
    @Published private(set) var questionsQuietedToday: Bool

    let context: QuestionContext

    /// Questions shown in this session (used to exclude from reroll).
    private var shownIDs: [String] = []

    // MARK: - Init

    init(context: QuestionContext) {
        self.context = context
        self.questionsQuietedToday = Self.isQuieted(on: MoodLog.dayKey())

        // Build local bundle synchronously — UI is never blank.
        let localBundle = QuestionMixer.localBundle(for: context)
        self.bundle = localBundle

        // Starter: use explicit question if the session was launched with one.
        if let explicit = context.explicitQuestion {
            self.currentQuestion = QuestionCard(
                id: "explicit",
                lead: "Your question",
                question: explicit,
                category: .blank,
                tags: [],
                source: context.source,
                personalLevel: context.personal,
                accent: .soft,
                answerStyle: .open,
                rung: .specificQuestion
            )
        } else {
            self.currentQuestion = context.mode == .talk ? localBundle.starterTalk : localBundle.starterWrite
        }

        // Record that we've shown this question.
        shownIDs.append(currentQuestion.id)

        // Fire-and-forget AI enrichment.
        Task { [weak self] in await self?.enrich() }
    }

    // MARK: - Using a question

    /// Mark the question as used — records the outcome signal.
    func useQuestion(_ card: QuestionCard) {
        var outcome = makeOutcome(for: card)
        outcome.selected = true
        QuestionMixer.recordOutcome(outcome)

        withAnimation(.easeInOut(duration: 0.2)) {
            currentQuestion = card
        }
        shownIDs.append(card.id)
    }

    func dismissQuestion(_ card: QuestionCard) {
        var outcome = makeOutcome(for: card)
        outcome.dismissed = true
        QuestionMixer.recordOutcome(outcome)
    }

    func lessLikeThis(_ card: QuestionCard) {
        var outcome = makeOutcome(for: card)
        outcome.lessLikeThis = true
        QuestionMixer.recordOutcome(outcome)
    }

    // MARK: - Reroll

    /// Instantly swap in a different question using local bank.
    func reroll(style: QuestionRerollStyle) {
        // Reroll is hidden when session was launched with an explicit question.
        guard context.explicitQuestion == nil else { return }

        let next = QuestionMixer.reroll(
            style: style,
            current: currentQuestion,
            pebbles: context.pebbles,
            mode: context.mode,
            excluding: shownIDs
        )
        withAnimation(.easeInOut(duration: 0.2)) { currentQuestion = next }
        shownIDs.append(next.id)
    }

    // MARK: - Make it easier (ladder descent)

    /// Descend one rung and return the easier question.
    @discardableResult
    func makeEasier() -> QuestionCard {
        rung = rung.smaller
        let card = QuestionMixer.rungQuestion(rung, pebbles: context.pebbles, mode: context.mode)
        withAnimation(.easeInOut(duration: 0.2)) { currentQuestion = card }
        shownIDs.append(card.id)
        return card
    }

    // MARK: - Tab cards

    func cards(for tab: QuestionTab) -> [QuestionCard] {
        bundle.cards(for: tab)
    }

    var hasMineTab: Bool { !bundle.mine.isEmpty }

    // MARK: - Session outcome

    /// Call when the session is saved. Updates startedness score.
    func recordSessionSaved(wordCount: Int) {
        var outcome = makeOutcome(for: currentQuestion)
        outcome.sessionSaved = true
        outcome.selected = true
        outcome.wordCount = wordCount
        QuestionMixer.recordOutcome(outcome)
    }

    func recordBlankDrop() {
        var outcome = makeOutcome(for: currentQuestion)
        outcome.blankDropSaved = true
        QuestionMixer.recordOutcome(outcome)
    }

    func recordFirstInput(timeInterval: TimeInterval) {
        var outcome = makeOutcome(for: currentQuestion)
        outcome.timeToFirstInput = timeInterval
        outcome.selected = true
        QuestionMixer.recordOutcome(outcome)
    }

    // MARK: - Quiet for today

    func quietForToday() {
        questionsQuietedToday = true
        Self.setQuieted(on: MoodLog.dayKey())
    }

    // MARK: - Enrichment

    private func enrich() async {
        guard let upgraded = await AIService.shared.enrichQuestions(for: context) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            bundle = upgraded
            // Only update the starter if we haven't already used a question.
            if shownIDs.count <= 1 {
                currentQuestion = context.mode == .talk ? upgraded.starterTalk : upgraded.starterWrite
                shownIDs = [currentQuestion.id]
            }
        }
    }

    // MARK: - Helpers

    private func makeOutcome(for card: QuestionCard) -> QuestionOutcome {
        QuestionOutcome(
            questionID: card.id,
            source: card.source,
            mode: context.mode,
            pebbles: context.pebbles,
            shownAt: Date()
        )
    }

    // MARK: - Day-scoped quiet persistence

    private static func key(_ day: String) -> String { "questionsQuieted-\(day)" }

    private static func isQuieted(on day: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(day))
    }

    private static func setQuieted(on day: String) {
        UserDefaults.standard.set(true, forKey: key(day))
    }
}

// MARK: - QuestionPersonalizationService stub

/// Placeholder for the personalization merge service (PRD §27).
/// Stores AI-generated personal question candidates. Full implementation in
/// QuestionPersonalizationService.swift.
final class QuestionPersonalizationService {
    static let shared = QuestionPersonalizationService()
    private init() {}

    func merge(candidates: [PersonalQuestionCandidate]) {
        // TODO: implement full merge logic per PRD §27
        // 1. Validate schema
        // 2. Remove duplicates
        // 3. Remove too-similar to universal bank
        // 4. Reject personal-level violations
        // 5. Assign initial successScore
        // 6. Insert into active personal bank (Firestore + local cache)
        // 7. Archive lowest-performing if bank exceeds 50
    }

    func activeQuestions(for context: QuestionContext) -> [QuestionCard] {
        // TODO: return stored personal questions for this context
        return []
    }

    func resetPersonalBank() {
        // TODO: clear Firestore personal question collection + local cache
    }
}
