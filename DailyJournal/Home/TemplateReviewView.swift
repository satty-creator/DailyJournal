//
//  TemplateReviewView.swift
//  DailyJournal
//
//  The weave → preview → commit review screen for a finished guided template
//  run — the shape `DailyChatView`'s `WovenEntryPreviewSheet` uses, extended
//  with the before→after delta (when the template has one) and the
//  "Framework" evidence box.
//
//  "Your words stay primary" here means literally that: the woven prose is
//  editable, and Save persists whatever's in the box, not the original AI
//  output — see `TemplateRunnerViewModel.save(finalText:)`. It can be dictated
//  as well as typed, same as the runner's text steps.
//

import SwiftUI
import UIKit

struct TemplateReviewView: View {

    let template: JournalTemplate
    @ObservedObject var vm: TemplateRunnerViewModel
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onBack: () -> Void

    @State private var showDiscardConfirm = false
    /// Guards against a double-tap on Save minting a duplicate entry — the
    /// sheet stays visible during `TemplateRunnerView`'s 0.35s dismiss delay,
    /// so the button needs to go inert on the first tap, not just once
    /// `vm.save` returns (see A2).
    @State private var isSaving = false
    /// This sheet has its own lifecycle, so it owns its own `SpeechManager`
    /// rather than borrowing the runner's. `TemplateRunnerView` stops its
    /// recorder in the footer action that opens this sheet, so only one is ever
    /// holding the audio session.
    @StateObject private var speech = SpeechManager()
    @State private var micError: String?

    /// Bound straight to `vm.wovenPreview` (no local `@State` copy) so an
    /// edit survives going back to a question and returning — see A1.
    private var trimmed: String { vm.wovenPreview.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if let delta = vm.scaleDelta {
                            deltaCard(delta)
                        }

                        proseEditor
                        answersSection
                        frameworkCard

                        PhotoAttachCard(image: $vm.attachedPhoto)

                        saveButton

                        Button {
                            showDiscardConfirm = true
                        } label: {
                            Text("Discard")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.inkSoft)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Keep going", action: onBack)
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
        .alert("Discard this entry?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                speech.stop()
                vm.discard()
                onDiscard()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This entry won't be saved.")
        }
        // Guarded on isRecording so a stale liveText can't overwrite an edit
        // made after the mic stopped — same as the runner and SpillWriteView.
        .onChange(of: speech.liveText) { _, live in
            guard speech.isRecording else { return }
            vm.wovenPreview = live
        }
        .onChange(of: speech.errorMessage) { _, message in micError = message }
        .onDisappear { speech.stop() }
        .alert("Microphone unavailable", isPresented: Binding(
            get: { micError != nil },
            set: { if !$0 { micError = nil } }
        )) {
            Button("Open Settings") {
                micError = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { micError = nil }
        } message: {
            Text(micError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENTRY READY")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)
            Text(template.title)
                .font(AppTheme.editorialDisplay(size: 28))
                .foregroundStyle(AppTheme.ink)
            Text("Your words stay primary \u{2014} edit anything before you save.")
                .font(AppTheme.editorialBody(size: 13.5))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
        }
        .padding(.top, 8)
    }

    // MARK: - Delta card

    private func deltaCard(_ delta: (before: Int, after: Int)) -> some View {
        let change = delta.before - delta.after
        let tint: Color = change > 0 ? AppTheme.mint : (change < 0 ? AppTheme.rose : AppTheme.cream)
        let caption: String = change > 0
            ? "Eased by \(change) point\(change == 1 ? "" : "s")."
            : (change < 0 ? "Rose by \(abs(change)) point\(abs(change) == 1 ? "" : "s")." : "No change.")
        // Drawn from the before-step's own label rather than hardcoded, so a
        // future template with a different before/after pair (e.g. "How
        // anxious this felt") gets the right title automatically — see A5.
        let title = template.beforeScaleStep?.label ?? "Feeling intensity"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("BEFORE \u{2192} AFTER")
                        .font(AppTheme.mono(size: 9))
                        .tracking(1)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer()
                Text("\(delta.before) \u{2192} \(delta.after)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
            Text("\(caption) Spilr stores this as a signal to compare over time \u{2014} not a diagnosis.")
                .font(AppTheme.editorialBody(size: 12))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
        }
        .padding(14)
        .background(tint.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Editable prose

    private var proseEditor: some View {
        TextEditor(text: $vm.wovenPreview)
            .font(AppTheme.editorialBody(size: 17))
            .foregroundStyle(AppTheme.ink)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .lineSpacing(5)
            .frame(minHeight: 200)
            .padding(14)
            .background(AppTheme.cream.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.terracotta.opacity(0.25), lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                micButton.padding(10)
            }
    }

    /// Voice → live transcription appended onto the woven prose. Same face and
    /// sizing as `TemplateRunnerView.micButton`.
    private var micButton: some View {
        Button {
            let snapshot = vm.wovenPreview
            Task { await speech.toggle(existingText: snapshot) }
        } label: {
            ZStack {
                if speech.isRecording {
                    Circle()
                        .stroke(AppTheme.terracotta.opacity(0.4), lineWidth: 3)
                        .frame(width: 52, height: 52)
                        .scaleEffect(speech.isRecording ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: speech.isRecording)
                }
                Circle()
                    .fill(speech.isRecording ? AppTheme.terracotta : AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.cream)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Add to this by talking")
    }

    // MARK: - Your answers

    private var answersSection: some View {
        let answered = template.steps.compactMap { step -> (TemplateStep, TemplateAnswer)? in
            // `.breathing` stores "done"/"skipped" purely so the runner's
            // footer can tell answered from unanswered — it's a pause, never
            // a real answer, so it never shows up here (see `AIService+Template`'s
            // weave, which excludes it the same way).
            if case .breathing = step.kind { return nil }
            guard let answer = vm.answer(for: step), answer.isAnswered else { return nil }
            return (step, answer)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("YOUR ANSWERS")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)

            ForEach(answered, id: \.0.id) { step, answer in
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.label.uppercased())
                        .font(AppTheme.mono(size: 9))
                        .tracking(1)
                        .foregroundStyle(AppTheme.inkSoft)
                    Text(answer.displayValue)
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(cornerRadius: 14, padding: 12)
            }
        }
    }

    // MARK: - Framework / evidence

    private var frameworkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRAMEWORK")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)
            Text(template.evidence.pill)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            // Practice templates show the pill only — their blurb is a
            // disclaimer, not a citation, and reads badly right before Save.
            if template.evidence.kind == .clinical {
                Text(template.evidence.blurb)
                    .font(AppTheme.editorialBody(size: 12.5))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(2)
            }
            if template.evidence.kind == .clinical, !template.evidence.sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(template.evidence.sources) { source in
                        Link(source.label, destination: source.url)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 18, padding: 16)
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            guard !isSaving else { return }
            // Stop first: `trimmed` reads `vm.wovenPreview`, and a transcript
            // landing mid-save would be a silent edit to what gets persisted.
            speech.stop()
            isSaving = true
            vm.save(finalText: trimmed)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave()
        } label: {
            Text("Save entry")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .opacity(trimmed.isEmpty || isSaving ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty || isSaving)
        .accessibilityIdentifier("templateReview.save")
    }
}
