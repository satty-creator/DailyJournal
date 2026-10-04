//
//  BaselineStepView.swift
//  DailyJournal
//
//  Onboarding step 4 — "How heavy do things feel lately?": a 0–10 baseline,
//  the first point on the Mirror tab's heaviness chart (`MoodTrendCard`).
//  Logged via `MoodLogService` when this step completes — see `OnboardingView`.
//

import SwiftUI

struct BaselineStepView: View {
    @Binding var baseline: Int?
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 4, total: 8)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How heavy does\nthings feel lately?")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Your own rough read. This is the first point on a chart Spilr will build with you over time.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ZeroToTenScale(
                        values: Array(0...10),
                        selected: $baseline,
                        helperText: "0 = light \u{00b7} 10 = very heavy."
                    )
                    .accessibilityIdentifier("onboarding.baseline.scale")

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            OnboardingStickyNext(title: "Continue", disabled: baseline == nil) {
                onNext()
            }
        }
        .accessibilityIdentifier("onboarding.baseline")
    }
}
