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

    private let service = JournalService()
    private let startedAt = Date()

    init(userId: String, template: JournalTemplate) {
        self.userId = userId
        self.template = template
        AnalyticsManager.shared.trackEntryCompositionStarted(sessionType: "template")
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
    }

    func back() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
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

    func buildReview() {
        guard !isWeaving else { return }
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
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sentiment  = LocalAI.detectSentiment(from: trimmed)
        let reflection = SpilrVoice.localReflection(from: trimmed, sentiment: sentiment)

        var mergedTags = [template.id]
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

    /// Called when the user exits mid-flow. No entry is written — the runner
    /// keeps no draft (unlike `TimedSessionViewModel`'s single-slot draft;
    /// a multi-step, multi-typed draft is a deliberate follow-up, not part
    /// of this change).
    func discard() {
        let wordCount = answers.values
            .map(\.displayValue)
            .joined(separator: " ")
            .split(separator: " ")
            .count
        AnalyticsManager.shared.trackEntryDiscarded(sessionType: "template", wordCount: wordCount)
    }
}
