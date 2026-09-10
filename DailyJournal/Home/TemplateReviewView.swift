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
//  output — see `TemplateRunnerViewModel.save(finalText:)`.
//

import SwiftUI

struct TemplateReviewView: View {

    let template: JournalTemplate
    @ObservedObject var vm: TemplateRunnerViewModel
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onBack: () -> Void

    @State private var text: String
    @State private var showDiscardConfirm = false

    init(
        template: JournalTemplate,
        vm: TemplateRunnerViewModel,
        onSave: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.template = template
        self.vm = vm
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onBack = onBack
        _text = State(initialValue: vm.wovenPreview)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

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
                vm.discard()
                onDiscard()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This entry won't be saved.")
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How stuck this felt")
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
        TextEditor(text: $text)
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
    }

    // MARK: - Your answers

    private var answersSection: some View {
        let answered = template.steps.compactMap { step -> (TemplateStep, TemplateAnswer)? in
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
            Text(template.evidence.blurb)
                .font(AppTheme.editorialBody(size: 12.5))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
            if !template.evidence.sources.isEmpty {
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
                .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
    }
}
