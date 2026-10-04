//
//  OnboardingComponents.swift
//  DailyJournal
//
//  Shared chrome for every onboarding step screen — the progress dots, the
//  back chevron, and the sticky bottom action button. Extracted so each step
//  gets its own file (`Onboarding/Steps/`) without re-typing this chrome nine
//  times. See `OnboardingView.swift` for the step sequence.
//

import SwiftUI

/// One dot per step, current one widened and tinted. `total` replaces the
/// original hardcoded 3 now that onboarding has nine pages.
struct OnboardingProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AppTheme.terracotta : AppTheme.inkSoft.opacity(0.25))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
    }
}

struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35), action)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// The sticky bottom primary action every step ends on — "Continue", "This
/// one", "Continue anyway", etc.
struct OnboardingStickyNext: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .padding(.top, 12)
        .background(
            AppTheme.paper
                .ignoresSafeArea(edges: .bottom)
                .mask(
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                )
        )
        .accessibilityIdentifier("onboarding.next")
    }
}

/// A secondary, quieter escape hatch under the sticky next button — "I'll do
/// this later", "Skip for now".
struct OnboardingSkipLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .buttonStyle(.plain)
    }
}
