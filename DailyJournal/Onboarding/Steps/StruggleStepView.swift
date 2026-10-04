//
//  StruggleStepView.swift
//  DailyJournal
//
//  Onboarding step 2 — "What's hard right now?": one tap from a goal-shaped
//  chip list, plus optional free text. Feeds `lifeContext.primaryFocus` (see
//  `OnboardingLifeContextSeed`) and every AI prompt via
//  `SpilrVoice.intentContext()`.
//
//  The free-text field runs through the same deterministic crisis gate
//  Patterns uses (`PatternSafety.corpusHasCrisisSignal`) as the person types.
//  A trip shows the existing resource card inline, right here — not a
//  blocking alert, and it never prevents continuing. It's also what decides
//  whether the guided first entry's opening question is written by the model
//  or falls back to a static one (see `OnboardingView`).
//

import SwiftUI

struct StruggleStepView: View {
    let goals: Set<JournalGoal>
    @Binding var struggle: String?
    @Binding var struggleDetail: String
    let onBack: () -> Void
    let onNext: () -> Void

    /// The card's own "dismiss" button has nothing to toggle on its own —
    /// this view decides whether it's still shown, keyed to the text that
    /// tripped it so the card comes back if the person keeps typing after
    /// dismissing it, rather than being silenced for the rest of the step.
    @State private var dismissedFor: String?

    private var options: [String] { OnboardingIntent.struggleOptions(for: goals) }

    /// Scans the free-text field only — the chip itself is always one of a
    /// fixed, safe set of phrases.
    private var tripsCrisisSignal: Bool {
        !struggleDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && PatternSafety.corpusHasCrisisSignal([struggleDetail])
    }

    private var showsResourceCard: Bool {
        tripsCrisisSignal && dismissedFor != struggleDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 2, total: 8)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What\u{2019}s hard\nright now?")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("One that fits best. You can say more below, or leave it at that.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            chip(option)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("IN YOUR WORDS \u{00b7} OPTIONAL")
                            .font(AppTheme.mono(size: 10))
                            .tracking(1.4)
                            .foregroundStyle(AppTheme.inkSoft)
                        TextField("Say a bit more, if you want to\u{2026}", text: $struggleDetail, axis: .vertical)
                            .font(AppTheme.editorialBody(size: 16))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(3...6)
                            .padding(14)
                            .background(AppTheme.cream.opacity(0.74))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
                            )
                    }

                    if showsResourceCard {
                        PatternResourceCardView(onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) { dismissedFor = struggleDetail }
                        })
                        .transition(.opacity)
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }
            .animation(.easeOut(duration: 0.2), value: showsResourceCard)

            OnboardingStickyNext(title: "Continue", disabled: struggle == nil) {
                onNext()
            }
        }
        .accessibilityIdentifier("onboarding.struggle")
    }

    private func chip(_ option: String) -> some View {
        let isSelected = option == struggle
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) { struggle = option }
        } label: {
            Text(option)
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
        .accessibilityIdentifier("onboarding.struggle.\(option)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
