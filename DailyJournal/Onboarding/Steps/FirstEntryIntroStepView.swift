//
//  FirstEntryIntroStepView.swift
//  DailyJournal
//
//  Onboarding step 7 — the card right before the guided first entry opens.
//  Shows the fixed opening line (`OnboardingView.openingQuestion` — see its
//  doc comment for why this is no longer AI-written) and launches
//  `TemplateRunnerView` running `JournalTemplate.onboardingFirstEntry`.
//

import SwiftUI

struct FirstEntryIntroStepView: View {
    let forLine: String
    let openingQuestion: String
    let onBack: () -> Void
    let onBegin: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 7, total: 8)
                    }
                    .padding(.top, 60)

                    Text("FOR: \(forLine)")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.lavDeep)
                        .tracking(1.4)

                    Text("Then let\u{2019}s start\nwhere it\u{2019}s loudest.")
                        .font(AppTheme.editorialDisplay(size: 30))
                        .foregroundStyle(AppTheme.ink)
                        .lineSpacing(2)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("SPILR ASKS")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.terracotta)
                            .tracking(2)

                        Text(openingQuestion)
                            .font(AppTheme.editorialDisplay(size: 22, weight: .heavy))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("A few short steps. There\u{2019}s no wrong answer, and you can stop whenever.")
                            .font(AppTheme.editorialBody(size: 13.5))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .background(AppTheme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 8)

                    Text("You\u{2019}re one sentence in already. That\u{2019}s the whole habit.")
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 0) {
                Button(action: onBegin) {
                    Text("Answer it")
                        .accessibilityIdentifier("onboarding.answer")
                        .font(.system(size: 17, weight: .semibold))
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
                .padding(.horizontal, 24)

                OnboardingSkipLink(title: "I'll do this later", action: onLater)
                    .accessibilityIdentifier("onboarding.later")
                    .padding(.top, 14)
            }
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(
                AppTheme.paper
                    .ignoresSafeArea(edges: .bottom)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            )
        }
        .accessibilityIdentifier("onboarding.firstEntryIntro")
    }
}
