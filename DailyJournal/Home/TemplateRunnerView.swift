//
//  TemplateRunnerView.swift
//  DailyJournal
//
//  The guided-template step runner: one question per screen, a thin progress
//  bar, text/choice/scale controls, and a sticky Continue/Skip footer. On the
//  last step it weaves the answers (`TemplateRunnerViewModel.buildReview`)
//  and presents `TemplateReviewView`.
//
//  Text steps can be dictated as well as typed — the same `SpeechManager` the
//  Spill and Journal composers use. See `micButton`.
//
//  Presented as a `fullScreenCover` from `HomeView`, alongside Spill and
//  Daily Chat — see `HomeView`'s templates gallery sheet.
//

import SwiftUI
import UIKit

struct TemplateRunnerView: View {

    let userId: String
    let template: JournalTemplate
    let onSave: () -> Void
    /// Called (before `dismiss()`) on every way out of the runner that is
    /// NOT a completed save — the X button with no answers yet, "Save for
    /// later", "Discard answers", and the review screen's "Discard". The
    /// gallery this template was picked from (`TemplateGalleryView`, a sheet
    /// off the invitation card) is already dismissed by the time this view is
    /// on screen — so without this callback every exit lands on Home instead
    /// of back where the user was browsing. A completed save still goes to
    /// Home, same as every other composer.
    let onExitWithoutSaving: () -> Void
    /// Optional: fires alongside `onSave()`, with the entry that was just
    /// written. `vm.savedEntry` is already set synchronously by the time
    /// `TemplateReviewView` calls `onSave()` (see `TemplateRunnerViewModel.save`),
    /// so this never races. Used by onboarding's guided first entry to hand the
    /// saved entry to the payoff screen — every other caller leaves this nil
    /// and just goes to Home, same as before.
    var onSaved: ((JournalEntry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TemplateRunnerViewModel
    @FocusState private var isFocused: Bool
    @State private var showExitConfirm = false
    /// Voice dictation for `.text` steps. A `.choice` or `.scale` step has
    /// nothing to dictate into, so the mic is only rendered on text steps and
    /// the transcript mirror below bails on any other kind.
    @StateObject private var speech = SpeechManager()
    @State private var micError: String?
    /// Transient "Draft restored" note — mirrors `SpillWriteView`'s
    /// `showDraftRestored`, shown once when `vm.didRestoreDraft` is true.
    @State private var showDraftRestored = false

    init(
        userId: String,
        template: JournalTemplate,
        onSave: @escaping () -> Void,
        onExitWithoutSaving: @escaping () -> Void,
        onSaved: ((JournalEntry) -> Void)? = nil
    ) {
        self.userId = userId
        self.template = template
        self.onSave = onSave
        self.onExitWithoutSaving = onExitWithoutSaving
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: TemplateRunnerViewModel(userId: userId, template: template))
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                progressBar
                if showDraftRestored {
                    draftRestoredBanner
                }

                ScrollView {
                    questionArea
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 150)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            stickyFooter
        }
        .onAppear {
            if vm.didRestoreDraft {
                showDraftRestored = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { showDraftRestored = false }
                }
            }
        }
        // Mirror the live transcript into the current step's answer as the
        // person speaks. Guard on isRecording so a stale `liveText` from a
        // finished session can't overwrite text typed after the mic stopped —
        // the same guard `SpillWriteView` uses.
        .onChange(of: speech.liveText) { _, live in
            guard speech.isRecording else { return }
            guard case .text = vm.currentStep.kind else { return }
            textBinding().wrappedValue = live
        }
        .onChange(of: speech.errorMessage) { _, message in micError = message }
        .onDisappear { speech.stop() }
        .sheet(isPresented: $vm.showReview) {
            TemplateReviewView(
                template: template,
                vm: vm,
                onSave: {
                    onSave()
                    if let onSaved, let saved = vm.savedEntry { onSaved(saved) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                },
                onDiscard: {
                    onExitWithoutSaving()
                    dismiss()
                },
                onBack: { vm.showReview = false }
            )
            // The only ways out are the sheet's own Keep going / Save /
            // Discard — a swipe-to-dismiss would otherwise drop the user's
            // edits to the woven prose with no confirmation (see A1).
            .interactiveDismissDisabled()
        }
        .alert("Leave this exercise?", isPresented: $showExitConfirm) {
            Button("Save for later") {
                // The draft autosaves on every answer, so there's nothing
                // extra to persist here — just leave it in place.
                onExitWithoutSaving()
                dismiss()
            }
            Button("Discard answers", role: .destructive) {
                vm.discard()
                onExitWithoutSaving()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Pick up where you left off later, or clear your answers now.")
        }
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

    private var draftRestoredBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10))
            Text("Draft restored")
                .font(AppTheme.mono(size: 10))
                .tracking(1)
        }
        .foregroundStyle(AppTheme.terracotta)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                speech.stop()
                isFocused = false
                if vm.hasAnyAnswer {
                    showExitConfirm = true
                } else {
                    onExitWithoutSaving()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit exercise")

            Spacer()

            Text(template.title)
                .font(AppTheme.mono(size: 10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.inkSoft)
                .lineLimit(1)

            Spacer()

            // Balances the leading close button so the title stays centered.
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.inkSoft.opacity(0.18))
                Capsule()
                    .fill(template.accentColor)
                    .frame(width: geo.size.width * vm.progress)
                    .animation(.easeInOut(duration: 0.25), value: vm.progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    // MARK: - Question

    private var questionArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STEP \(vm.stepIndex + 1) OF \(template.steps.count)")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)

            Text(vm.currentStep.question)
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !vm.currentStep.helper.isEmpty {
                Text(vm.currentStep.helper)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !vm.currentStep.examples.isEmpty {
                examplesHint(vm.currentStep.examples)
            }

            stepControl
                .padding(.top, 4)

            if let whyThis = vm.currentStep.whyThis {
                whyAskThisCard(whyThis)
            }
        }
        .id(vm.stepIndex) // fresh identity per step keeps focus/animation clean
        .onAppear {
            // Autofocus text steps only — a chip/scale step has nothing to type
            // into, and stealing focus there would just pop the keyboard away.
            if case .text = vm.currentStep.kind {
                isFocused = true
            }
        }
    }

    @ViewBuilder
    private var stepControl: some View {
        switch vm.currentStep.kind {
        case .text(let placeholder):
            textControl(placeholder: placeholder)
        case .choice(let options):
            choiceControl(options: options)
        case .multiChoice(let options, let allowsOther):
            multiChoiceControl(options: options, allowsOther: allowsOther)
        case .scale(_, let values):
            scaleControl(values: values)
        case .breathing(let cycles):
            breathingControl(cycles: cycles)
        }
    }

    // MARK: - Text control

    private func textBinding() -> Binding<String> {
        let step = vm.currentStep
        return Binding(
            get: {
                if case .text(let s)? = vm.answer(for: step) { return s }
                return ""
            },
            set: { vm.setAnswer(.text($0), for: step) }
        )
    }

    private func textControl(placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            let binding = textBinding()
            if binding.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.slate.opacity(0.7))
                    .italic()
                    .padding(.top, 18)
                    .padding(.leading, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: binding)
                .font(AppTheme.editorialBody(size: 17))
                .foregroundStyle(AppTheme.ink)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)
                .lineSpacing(5)
                .frame(minHeight: 150)
                .padding(12)
                .accessibilityIdentifier("templateRunner.textField")
        }
        .background(AppTheme.cream.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            micButton.padding(10)
        }
    }

    /// Voice → live transcription into the current text step. Sized down from
    /// `SpillWriteView`'s floating-bar mic (46/58) because this one sits inside
    /// the editor card rather than on a bar of its own, and mustn't compete
    /// with the sticky footer's primary action.
    private var micButton: some View {
        Button {
            // Snapshot BEFORE dismissing the keyboard — `isFocused = false` can
            // trigger a pending autocorrect commit that would race the async
            // task and corrupt the existingText snapshot (see SpillWriteView).
            let snapshot = textBinding().wrappedValue
            isFocused = false
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
        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Answer by talking")
    }

    // MARK: - Choice control

    private func choiceControl(options: [String]) -> some View {
        let step = vm.currentStep
        let selected: String? = {
            if case .choice(let s)? = vm.answer(for: step) { return s }
            return nil
        }()
        return FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { vm.setAnswer(.choice(option), for: step) }
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.inkSoft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(isSelected ? AppTheme.ink : AppTheme.cream)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(AppTheme.inkSoft.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - Multi-choice control (emotions, thinking traps — any number on at once)

    private func multiChoiceControl(options: [String], allowsOther: Bool) -> some View {
        let step = vm.currentStep
        return MultiChoiceStepControl(
            options: options,
            allowsOther: allowsOther,
            chipHelp: step.chipHelp,
            selected: Binding(
                get: { vm.answer(for: step)?.choiceValues ?? [] },
                set: { vm.setAnswer(.choices($0), for: step) }
            )
        )
    }

    // MARK: - Scale control

    private func scaleControl(values: [Int]) -> some View {
        let step = vm.currentStep
        return ZeroToTenScale(
            values: values,
            selected: Binding(
                get: { vm.answer(for: step)?.scaleValue },
                set: { if let v = $0 { vm.setAnswer(.scale(v), for: step) } }
            )
        )
    }

    // MARK: - Breathing control

    /// `.breathing` steps store no real content — `onComplete`/`onSkip` just
    /// mark the step answered (so the footer's "Skip" label flips to
    /// "Continue") and log which way it went. See `BoxBreathingView`.
    private func breathingControl(cycles: Int) -> some View {
        let step = vm.currentStep
        return BoxBreathingView(
            cycles: cycles,
            onComplete: {
                vm.setAnswer(.choice("done"), for: step)
                AnalyticsManager.shared.logEvent(.templateBreathingCompleted, parameters: ["template_id": template.id])
            },
            onSkip: {
                vm.setAnswer(.choice("skipped"), for: step)
                AnalyticsManager.shared.logEvent(.templateBreathingSkipped, parameters: ["template_id": template.id])
            }
        )
        // The breathing view sizes to its ~180pt content and doesn't stretch;
        // the question stack is `.leading`, so without this it hugs the left
        // edge. Fill the width and center it — every other control already
        // expands to full width on its own.
        .frame(maxWidth: .infinity)
    }

    // MARK: - "Why ask this?" (only on steps that supply their own rationale —
    // see `TemplateStep.whyThis`. Deliberately NOT the template-level evidence
    // blurb on every step; that repeated one paragraph verbatim across a
    // 7-step template and duplicated the review screen's Framework card.)

    // MARK: - Examples hint
    //
    // A quiet "FOR EXAMPLE" block under a text step's helper (see
    // `TemplateStep.examples`). Shows what a real answer looks like without
    // writing one for the user — deliberately not a card and not in the entry's
    // voice, so it reads as a prompt, not as content. Left-aligned with the
    // question in the `.leading` question stack.

    private func examplesHint(_ examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FOR EXAMPLE")
                .font(AppTheme.mono(size: 9))
                .tracking(1.5)
                .foregroundStyle(AppTheme.inkSoft)
            ForEach(examples, id: \.self) { example in
                Text(example)
                    .font(AppTheme.editorialBody(size: 13))
                    .italic()
                    .foregroundStyle(AppTheme.slate)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func whyAskThisCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WHY ASK THIS?")
                .font(AppTheme.mono(size: 9))
                .tracking(1.5)
                .foregroundStyle(AppTheme.inkSoft)
            Text(text)
                .font(AppTheme.editorialBody(size: 12.5))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
        }
        .softCard(cornerRadius: 16, padding: 14)
    }

    // MARK: - Sticky footer

    private var nextLabel: String {
        if vm.isWeaving { return "Weaving\u{2026}" }
        if vm.isLastStep { return "Build entry" }
        return vm.currentIsAnswered ? "Continue" : "Skip"
    }

    private var stickyFooter: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                if vm.stepIndex > 0 {
                    Button {
                        // The step's `.id(vm.stepIndex)` swaps the text field out
                        // from under a live session — end it before moving.
                        speech.stop()
                        isFocused = false
                        vm.back()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.inkSoft)
                            .padding(.vertical, 15)
                            .padding(.horizontal, 22)
                            .background(AppTheme.cream.opacity(0.8))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    // Also covers the last step, where advance() opens the
                    // review sheet: its own SpeechManager can't share the audio
                    // session with one that's still running here.
                    speech.stop()
                    isFocused = false
                    vm.advance()
                } label: {
                    HStack(spacing: 8) {
                        if vm.isWeaving {
                            ProgressView().tint(AppTheme.cream)
                        }
                        Text(nextLabel)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(.plain)
                .disabled(vm.isWeaving)
                .accessibilityIdentifier("templateRunner.next")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(
                AppTheme.paper
                    .ignoresSafeArea(edges: .bottom)
                    .mask(
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    )
            )
        }
    }
}

// MARK: - Multi-choice step control

/// Chip grid for `.multiChoice` steps — any number of `options` can be on at
/// once, plus an optional free-text "Other" chip. A dedicated struct (rather
/// than inline state on `TemplateRunnerView`, like every other control here)
/// because it needs its own `otherText`/`showOtherField` state that must NOT
/// bleed from one step to the next; `questionArea`'s `.id(vm.stepIndex)` on
/// the parent gives this view a fresh identity — and fresh `@State` — every
/// time the step changes, the same guarantee `textControl`'s focus reset
/// relies on.
private struct MultiChoiceStepControl: View {
    let options: [String]
    let allowsOther: Bool
    /// One-line definition per option, shown under the chip once it's on —
    /// see `TemplateStep.chipHelp`.
    let chipHelp: [String: String]
    @Binding var selected: [String]

    @State private var standardSelected: [String]
    @State private var otherText: String
    @State private var showOtherField: Bool

    init(options: [String], allowsOther: Bool, chipHelp: [String: String], selected: Binding<[String]>) {
        self.options = options
        self.allowsOther = allowsOther
        self.chipHelp = chipHelp
        self._selected = selected
        let current = selected.wrappedValue
        let other = current.first { !options.contains($0) } ?? ""
        self._standardSelected = State(initialValue: current.filter { options.contains($0) })
        self._otherText = State(initialValue: other)
        self._showOtherField = State(initialValue: !other.isEmpty)
    }

    private func commit() {
        var result = standardSelected
        let trimmedOther = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOther.isEmpty { result.append(trimmedOther) }
        selected = result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
                if allowsOther {
                    otherChip
                }
            }

            if showOtherField {
                TextField("Something else\u{2026}", text: $otherText)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
                    )
                    .onChange(of: otherText) { _, _ in commit() }
            }

            ForEach(standardSelected.filter { chipHelp[$0] != nil }, id: \.self) { option in
                if let help = chipHelp[option] {
                    HStack(alignment: .top, spacing: 6) {
                        Text(option + ":")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text(help)
                            .font(AppTheme.editorialBody(size: 11.5))
                    }
                    .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
    }

    private func chip(_ option: String) -> some View {
        let isSelected = standardSelected.contains(option)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    standardSelected.removeAll { $0 == option }
                } else {
                    standardSelected.append(option)
                }
                commit()
            }
        } label: {
            chipLabel(option, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var otherChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                showOtherField.toggle()
                if !showOtherField {
                    otherText = ""
                    commit()
                }
            }
        } label: {
            chipLabel("Other", isSelected: showOtherField)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showOtherField ? .isSelected : [])
    }

    private func chipLabel(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.inkSoft)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(isSelected ? AppTheme.ink : AppTheme.cream)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppTheme.inkSoft.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
            )
    }
}
