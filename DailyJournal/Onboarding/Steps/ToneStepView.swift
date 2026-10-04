//
//  ToneStepView.swift
//  DailyJournal
//
//  Onboarding step 5 — "When Spilr speaks back…": Gentle / Curious / Direct.
//  Pre-selected from the goals step (`OnboardingIntent.suggestedTone(for:)`)
//  rather than always defaulting to Curious, but still freely changeable —
//  the "SUGGESTED" badge now follows whichever tone the goals actually point
//  to instead of always sitting on Curious.
//

import SwiftUI

struct ToneStepView: View {
    let goals: Set<JournalGoal>
    @Binding var selectedTone: SpilrTone
    /// True once the person has actually tapped a tone card — distinguishes
    /// "still showing the suggested default" from "chose Curious on purpose".
    @Binding var userPickedTone: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    private var suggested: SpilrTone { OnboardingIntent.suggestedTone(for: goals) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 5, total: 8)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("When Spilr\nspeaks back\u{2026}")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Same words, three temperatures. You can change this any time.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        ForEach(SpilrTone.allCases) { tone in
                            toneCard(tone)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            OnboardingStickyNext(title: "This one") {
                onNext()
            }
        }
        .onAppear {
            // Only apply the suggestion the first time this step is reached —
            // a later revisit (after Back) must never overwrite a choice the
            // person already made on purpose.
            if !userPickedTone { selectedTone = suggested }
        }
        .accessibilityIdentifier("onboarding.tone")
    }

    private func toneCard(_ tone: SpilrTone) -> some View {
        let selected = selectedTone == tone
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTone = tone
                userPickedTone = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(tone.emoji).font(.system(size: 16))
                    Text(tone.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    if tone == suggested {
                        Text("SUGGESTED")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.lavDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.lav.opacity(0.32))
                            .clipShape(Capsule())
                    }
                }
                Text("\u{201C}\(tone.sampleLine)\u{201D}")
                    .font(AppTheme.editorialBody(size: 14).italic())
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [AppTheme.lav.opacity(0.22), AppTheme.cream],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(AppTheme.cream)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? AppTheme.lavDeep : AppTheme.inkSoft.opacity(0.14), lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.tone.\(tone.rawValue)")
    }
}
