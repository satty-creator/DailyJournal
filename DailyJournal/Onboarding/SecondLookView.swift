//
//  SecondLookView.swift
//  DailyJournal
//
//  Onboarding's payoff — step 9 of the new flow (OnboardingView.swift): the
//  screen right after the guided first entry saves, before the paywall.
//  Shows the before → after heaviness delta (when it eased) and Spilr's
//  reflection on what was just written, via the same live-observer pattern
//  `FirstEntryCelebrationSheet` uses.
//
//  With AI declined, or if the call fails or times out, the reflection
//  section simply doesn't render — same rule as everywhere else ("No local
//  text in Spilr's voice", CLAUDE.md). The delta line and a short excerpt of
//  the user's own words still show either way: both are data, not voice, the
//  same fallback `InsightShareCard` already uses for its own excerpt.
//
//  Sets `spilr.firstEntryCelebrationShown` on appear so Home's
//  `FirstEntryCelebrationSheet` — which also fires on a user's first-ever
//  entry — doesn't show a second congratulations screen for the same entry
//  a moment later.
//

import SwiftUI

struct SecondLookView: View {
    let entry: JournalEntry
    let onContinue: () -> Void

    @StateObject private var insights = EntryInsightsObserver()
    private let service = JournalService()

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("✦")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.terracotta)
                            .padding(.top, 8)
                        Text("One more look\nbefore you go.")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                    }

                    if let deltaLine {
                        deltaCard(deltaLine)
                    }

                    reflectionSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }

            VStack {
                Spacer()
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.secondLook.continue")
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
                .padding(.top, 12)
                .background(
                    AppTheme.paper
                        .ignoresSafeArea(edges: .bottom)
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                )
            }
        }
        .onAppear {
            insights.start(entry: entry, service: service)
            UserDefaults.standard.set(true, forKey: "spilr.firstEntryCelebrationShown")
        }
        .onDisappear { insights.stop() }
    }

    // MARK: - Delta

    private var deltaLine: (before: Int, after: Int)? {
        Self.deltaToShow(before: entry.templateScaleBefore, after: entry.templateScaleAfter)
    }

    /// Only returns a pair when things eased (`after < before`) — a rise or a
    /// flat read isn't the moment to hand the user a number, per the product
    /// call on this screen. A free function of its inputs so the rule is
    /// unit-testable without a `JournalEntry`.
    static func deltaToShow(before: Int?, after: Int?) -> (before: Int, after: Int)? {
        guard let before, let after, after < before else { return nil }
        return (before, after)
    }

    private func deltaCard(_ delta: (before: Int, after: Int)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW HEAVY THIS FELT")
                .font(AppTheme.mono(size: 9))
                .tracking(1.4)
                .foregroundStyle(AppTheme.inkSoft)
            Text("You came in at \(delta.before), you're leaving at \(delta.after).")
                .font(AppTheme.editorialDisplay(size: 19, weight: .heavy))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppTheme.mint.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Reflection (Gemini, or the user's own words as a quiet fallback)

    @ViewBuilder
    private var reflectionSection: some View {
        if insights.isWaiting {
            SpilrHeardPlaceholder()
        } else if !insights.bullets.isEmpty {
            SpilrHeardCard(bullets: insights.bullets, question: insights.question)
        } else {
            whatYouWroteCard
        }
    }

    /// The honest fallback when there's no AI reflection to show — local-only
    /// consent, a failed call, or a timeout. A short excerpt of the user's own
    /// words, same pattern `InsightShareCard` already uses when it has no
    /// bullets to fall back on.
    private var whatYouWroteCard: some View {
        let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(trimmed.prefix(200)) + (trimmed.count > 200 ? "…" : "")
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU WROTE")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
            Text(excerpt)
                .font(AppTheme.editorialBody(size: 15).italic())
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(3)
        }
        .padding(14)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
