//
//  ConsentStepView.swift
//  DailyJournal
//
//  Onboarding step 6 — AI consent, asked plainly and as an equal choice
//  rather than a lazy sheet right before the first chat turn (the original
//  flow's `beginFirstChat`/`RetroAIConsentSheet` detour). Same copy as
//  `RetroAIConsentSheet` (RootView.swift) so returning users who see that
//  sheet later never read something different from what onboarding told
//  them — but the two buttons are equal weight here ("Use AI reflections" /
//  "Keep it local only"), not a primary action and a quiet decline.
//
//  Writes `spilr.aiConsentGranted` directly, same key `RetroAIConsentSheet`
//  and `isAIAvailable` read — nothing downstream needs to know which screen
//  set it.
//

import SwiftUI

struct ConsentStepView: View {
    let onBack: () -> Void
    /// `localOnly` tells the caller which button was tapped, so it can skip
    /// starting the AI opening-question call for a user who just declined.
    let onDecided: (_ localOnly: Bool) -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 6, total: 8)
                    }
                    .padding(.top, 60)

                    Text("One more thing\nbefore you write.")
                        .font(AppTheme.editorialDisplay(size: 30))
                        .foregroundStyle(AppTheme.ink)
                        .lineSpacing(2)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Spilr uses AI to notice patterns in what you write and turn them into reflections. To do that, your entry text is sent securely for processing.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showDetails.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("What gets used, and how")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.terracotta)
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.terracotta)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDetails {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow(label: "What's sent",       value: "The text of your entries")
                                detailRow(label: "What for",          value: "Reflections, patterns, emotional summaries")
                                detailRow(label: "Kept after?",       value: "No \u{2014} only the results come back")
                                detailRow(label: "Used to train AI?", value: "No")
                                detailRow(label: "Full details",      value: "In the Privacy Policy")
                            }
                            .padding(14)
                            .background(AppTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(18)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("You can change this at any time in Profile \u{2192} AI & Privacy.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)

                    // Equal weight, deliberately — both are capsules of the
                    // same size, distinguished by fill rather than by one
                    // being visually "the answer".
                    VStack(spacing: 12) {
                        choiceButton(
                            title: "Use AI reflections",
                            style: .filled
                        ) {
                            UserDefaults.standard.aiConsentGranted = true
                            AnalyticsManager.shared.trackAIConsentGranted()
                            onDecided(false)
                        }
                        .accessibilityIdentifier("onboarding.consent.useAI")

                        choiceButton(
                            title: "Keep it local only",
                            style: .outlined
                        ) {
                            UserDefaults.standard.aiConsentGranted = false
                            AnalyticsManager.shared.trackAIConsentDenied()
                            onDecided(true)
                        }
                        .accessibilityIdentifier("onboarding.consent.localOnly")
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .accessibilityIdentifier("onboarding.consent")
    }

    private enum ChoiceStyle { case filled, outlined }

    private func choiceButton(title: String, style: ChoiceStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(style == .filled ? AppTheme.cream : AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(style == .filled ? AppTheme.ink : AppTheme.cream)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppTheme.inkSoft.opacity(style == .filled ? 0 : 0.25), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.5)
            Text(value)
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.ink)
        }
    }
}
