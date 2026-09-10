//
//  TemplateRunnerView.swift
//  DailyJournal
//
//  The guided-template step runner: one question per screen, a thin progress
//  bar, text/choice/scale controls, and a sticky Continue/Skip footer. On the
//  last step it weaves the answers (`TemplateRunnerViewModel.buildReview`)
//  and presents `TemplateReviewView`.
//
//  Presented as a `fullScreenCover` from `HomeView`, alongside Spill and
//  Daily Chat — see `StartChoice.template` and `HomeView.handlePendingStart`.
//

import SwiftUI

struct TemplateRunnerView: View {

    let userId: String
    let template: JournalTemplate
    let onSave: () -> Void
    /// Called (before `dismiss()`) on every way out of the runner that is
    /// NOT a completed save — the X button with no answers yet, "Save for
    /// later", "Discard answers", and the review screen's "Discard". The
    /// gallery this template was picked from (`TemplateGalleryView`, pushed
    /// on the start sheet's own `NavigationStack`) is already gone by the
    /// time this view is on screen — see `HomeView.handlePendingStart` — so
    /// without this callback every exit lands on Home instead of back where
    /// the user was browsing. A completed save still goes to Home, same as
    /// every other composer.
    let onExitWithoutSaving: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TemplateRunnerViewModel
    @FocusState private var isFocused: Bool
    @State private var showExitConfirm = false
    /// Transient "Draft restored" note — mirrors `SpillWriteView`'s
    /// `showDraftRestored`, shown once when `vm.didRestoreDraft` is true.
    @State private var showDraftRestored = false

    init(
        userId: String,
        template: JournalTemplate,
        onSave: @escaping () -> Void,
        onExitWithoutSaving: @escaping () -> Void
    ) {
        self.userId = userId
        self.template = template
        self.onSave = onSave
        self.onExitWithoutSaving = onExitWithoutSaving
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
        .sheet(isPresented: $vm.showReview) {
            TemplateReviewView(
                template: template,
                vm: vm,
                onSave: {
                    onSave()
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
        case .scale:
            scaleControl
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
        }
        .background(AppTheme.cream.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
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

    // MARK: - Scale control

    private var scaleControl: some View {
        let step = vm.currentStep
        let selected: Int? = vm.answer(for: step)?.scaleValue
        let values = [0, 2, 4, 6, 8, 10]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { v in
                    let isSelected = selected == v
                    // Maps 0…10 onto the app's canonical -3…+3 valence gradient.
                    let tint = AppTheme.valenceColor(v / 2 - 3)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.setAnswer(.scale(v), for: step) }
                    } label: {
                        Text("\(v)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? tint.opacity(0.85) : AppTheme.cream.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? tint : AppTheme.inkSoft.opacity(0.15), lineWidth: 1.5)
                            )
                            .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(v) out of 10")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text("Use an approximate number. The point is comparison, not precision.")
                .font(AppTheme.editorialBody(size: 12))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    // MARK: - "Why ask this?" (only on steps that supply their own rationale —
    // see `TemplateStep.whyThis`. Deliberately NOT the template-level evidence
    // blurb on every step; that repeated one paragraph verbatim across a
    // 7-step template and duplicated the review screen's Framework card.)

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
