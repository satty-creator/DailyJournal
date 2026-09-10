//
//  TemplateRunnerViewModel.swift
//  DailyJournal
//
//  Drives a single guided-template run: step navigation, answers, the
//  weave → preview → commit save. Its own view model rather than a bent
//  `TimedSessionViewModel` — that class's whole state surface is a single
//  `content: String` plus a single-slot draft key, and this needs a step
//  cursor, per-step typed answers, and weave/preview state instead.
//
//  Mirrors `DailyChatView`'s weave() / save(entryText:) shape (see
//  `DailyChatView.swift`), including the shared `EntryEnrichment` tail
//  instead of a fourth near-verbatim copy of it.
//

import Foundation
import SwiftUI

@MainActor
final class TemplateRunnerViewModel: ObservableObject {

    let template: JournalTemplate
    let userId: String

    @Published var stepIndex: Int = 0
    @Published private(set) var answers: [String: TemplateAnswer] = [:]

    @Published var isWeaving = false
    @Published var showReview = false
    /// The woven entry text shown (and editable) on the review screen.
    @Published var wovenPreview: String = ""
    /// Whether the preview came from Gemini or the local fallback — surfaced
    /// so `trackEntryCreated(hasAI:)` reflects what actually happened, not
    /// just whether AI was available.
    @Published private(set) var usedAI = false

    @Published private(set) var savedEntry: JournalEntry?

    /// True when `stepIndex`/`answers` were restored from a saved draft on
    /// init (lets the view show a transient "Draft restored" note, mirroring
    /// `TimedSessionViewModel.didRestoreDraft`).
    @Published private(set) var didRestoreDraft = false

    private let service = JournalService()
    private let startedAt = Date()

    // MARK: - Draft

    /// Multi-step, multi-typed answers don't fit `TimedSessionViewModel`'s
    /// single-`String` draft, so this stores the step cursor alongside the
    /// typed answers. Keyed per template (not one shared key) so an abandoned
    /// run of one exercise never resurfaces inside a different one.
    private struct Draft: Codable {
        var stepIndex: Int
        var answers: [String: TemplateAnswer]
    }
    private var draftKey: String { "template_draft.\(template.id)" }
    /// Logged once per run, the first time an answer actually makes the draft
    /// worth saving — not on every keystroke.
    private var hasLoggedDraft = false

    init(userId: String, template: JournalTemplate) {
        self.userId = userId
        self.template = template
        if let data = UserDefaults.standard.data(forKey: draftKey),
           let draft = try? JSONDecoder().decode(Draft.self, from: data),
           draft.answers.values.contains(where: { $0.isAnswered }) {
            stepIndex = min(draft.stepIndex, template.steps.count - 1)
            answers = draft.answers
            didRestoreDraft = true
        }
        AnalyticsManager.shared.trackEntryCompositionStarted(sessionType: "template")
    }

    private func persistDraft() {
        guard hasAnyAnswer else {
            clearDraft()
            return
        }
        let draft = Draft(stepIndex: stepIndex, answers: answers)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: draftKey)
        if !hasLoggedDraft {
            hasLoggedDraft = true
            AnalyticsManager.shared.logEvent(.entryDrafted)
        }
    }

    func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    // MARK: - Step navigation

    var currentStep: TemplateStep { template.steps[stepIndex] }
    var progress: Double { Double(stepIndex + 1) / Double(template.steps.count) }
    var isLastStep: Bool { stepIndex == template.steps.count - 1 }

    var hasAnyAnswer: Bool { answers.values.contains { $0.isAnswered } }
    var currentIsAnswered: Bool { answers[currentStep.id]?.isAnswered ?? false }

    func answer(for step: TemplateStep) -> TemplateAnswer? { answers[step.id] }

    func setAnswer(_ answer: TemplateAnswer, for step: TemplateStep) {
        answers[step.id] = answer
        persistDraft()
    }

    func back() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        persistDraft()
    }

    /// Advances past the current step, or — on the last step — starts the
    /// weave. Never gated on the current step being answered: the gallery
    /// promises "you can leave any question blank" (`TemplateGalleryView`),
    /// so a blank step is a valid step to move past, not a dead end.
    func advance() {
        if isLastStep {
            buildReview()
        } else {
            stepIndex += 1
            persistDraft()
        }
    }

    // MARK: - Delta (only for templates with a before/after scale pair)

    var scaleDelta: (before: Int, after: Int)? {
        guard
            let beforeStep = template.beforeScaleStep,
            let afterStep = template.afterScaleStep,
            let before = answers[beforeStep.id]?.scaleValue,
            let after = answers[afterStep.id]?.scaleValue
        else { return nil }
        return (before, after)
    }

    // MARK: - Weave

    /// The answers the current `wovenPreview` was actually built from. Lets
    /// `buildReview()` tell "user tapped Continue past an unchanged answer set"
    /// (e.g. went Back from the review to re-read a question, then forward again)
    /// apart from "an answer actually changed" — only the latter should re-weave.
    /// Without this, returning to the review after any edit to the prose itself
    /// would also silently discard that edit and fire a second Gemini call.
    private var lastWovenAnswers: [String: TemplateAnswer]?

    func buildReview() {
        guard !isWeaving else { return }
        if let lastWovenAnswers, lastWovenAnswers == answers {
            // Nothing about the answers changed since the last weave — show the
            // existing (possibly user-edited) preview instead of re-weaving over it.
            showReview = true
            return
        }
        isWeaving = true
        let template = self.template
        let currentAnswers = self.answers
        Task { [weak self] in
            guard let self else { return }
            let woven: String
            let succeeded: Bool
            if let ai = try? await AIService.shared.weaveTemplateEntry(template: template, answers: currentAnswers) {
                woven = ai
                succeeded = true
            } else {
                woven = AIService.shared.localWeaveTemplateEntry(template: template, answers: currentAnswers)
                succeeded = false
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.wovenPreview = woven
                self.usedAI = succeeded
                self.lastWovenAnswers = currentAnswers
                self.showReview = true
                self.isWeaving = false
            }
        }
    }

    // MARK: - Save / discard

    /// Mirrors `TimedSessionViewModel.saveEntry` / `DailyChatView.save`: save
    /// instantly with local heuristics, then enrich in detached background
    /// tasks via `EntryEnrichment`.
    func save(finalText: String) {
        // Re-entry guard: the review screen's Save button stays live during the
        // dismiss delay in `TemplateRunnerView`, so a second tap must be a no-op
        // rather than minting a duplicate entry.
        guard savedEntry == nil else { return }
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sentiment  = LocalAI.detectSentiment(from: trimmed)
        let reflection = SpilrVoice.localReflection(from: trimmed, sentiment: sentiment)

        // Seeded from the template's real topic tags ("clarity", "calm", …) —
        // NOT `template.id`, which is a kebab-case slug that would otherwise
        // render as a raw hashtag like "#after-a-hard-conversation" on the
        // journal card (see `JournalCardView`).
        var mergedTags = template.tags
        for topic in LocalAI.extractTopics(from: trimmed) where !mergedTags.contains(topic) && mergedTags.count < 5 {
            mergedTags.append(topic)
        }

        let delta = scaleDelta
        let entry = JournalEntry(
            userId: userId,
            title: template.title,
            content: trimmed,
            tags: mergedTags,
            sessionType: .template,
            aiSummaryBullets: reflection.observations,
            aiQuestion: reflection.question,
            sentimentLabel: sentiment,
            templateId: template.id,
            templateScaleBefore: delta?.before,
            templateScaleAfter: delta?.after
        )
        savedEntry = entry
        service.createEntry(entry)
        clearDraft()

        EntryEnrichment.run(
            entryId: entry.id,
            userId: userId,
            entryCreatedAt: entry.createdAt,
            text: trimmed,
            service: service,
            templateId: entry.templateId,
            templateScaleBefore: entry.templateScaleBefore,
            templateScaleAfter: entry.templateScaleAfter
        )

        AnalyticsManager.shared.trackEntryCreated(
            sessionType: "template",
            wordCount: entry.wordCount,
            hasMood: false,
            hasPhoto: false,
            hasAI: usedAI,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    /// Called when the user explicitly discards mid-flow (as opposed to
    /// exiting with "Save for later", which leaves the autosaved draft in
    /// place). No entry is written, and the draft is cleared so a future
    /// run of this template starts blank.
    func discard() {
        let wordCount = answers.values
            .map(\.displayValue)
            .joined(separator: " ")
            .split(separator: " ")
            .count
        clearDraft()
        AnalyticsManager.shared.trackEntryDiscarded(sessionType: "template", wordCount: wordCount)
    }
}
