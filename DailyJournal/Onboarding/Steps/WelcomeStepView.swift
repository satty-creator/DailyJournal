//
//  WelcomeStepView.swift
//  DailyJournal
//
//  Onboarding step 0 — a 3-card product tour before any question is asked:
//  write or talk → Spilr asks good questions → it remembers and spots
//  patterns. Purely explanatory, no state to collect.
//

import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void

    private struct Card: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let body: String
    }

    private let cards: [Card] = [
        Card(id: 0, icon: "square.and.pencil",
             title: "You write or talk",
             body: "A few lines, or a voice note if that's easier. No blank page — Spilr always gives you somewhere to start."),
        Card(id: 1, icon: "bubble.left.and.text.bubble.right",
             title: "Spilr asks good questions",
             body: "Not a generic prompt. A question grounded in what you actually just wrote."),
        Card(id: 2, icon: "sparkles",
             title: "It remembers, and spots patterns",
             body: "The more you write, the sharper Spilr gets at noticing what keeps showing up for you.")
    ]

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressDots(current: 0, total: 8)
                .padding(.top, 60)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("How Spilr works.")
                    .font(AppTheme.editorialDisplay(size: 30))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(cards) { card in
                    welcomeCard(card).tag(card.id)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            OnboardingStickyNext(title: "Get started") {
                onNext()
            }
        }
        .accessibilityIdentifier("onboarding.welcome")
    }

    private func welcomeCard(_ card: Card) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            Image(systemName: card.icon)
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 84, height: 84)
                .background(AppTheme.terracotta.opacity(0.12))
                .clipShape(Circle())

            Text(card.title)
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            Text(card.body)
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 20)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
    }
}
