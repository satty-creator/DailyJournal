//
//  GoalsStepView.swift
//  DailyJournal
//
//  Onboarding step 1 — "What brings you here, really?": multi-select goals.
//  Unchanged from the original 3-tap flow's step 1, just extracted to its
//  own file and re-numbered in the wider progress bar.
//

import SwiftUI

struct GoalsStepView: View {
    @Binding var selectedGoals: Set<JournalGoal>
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    OnboardingProgressDots(current: 1, total: 8)
                        .padding(.top, 60)

                    BloomMarkView(size: 42)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What brings you\nhere, really?")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Pick as many as feel true. This shapes how Spilr talks to you \u{2014} not a label, and never shared.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(JournalGoal.allCases) { goal in
                            goalRow(goal)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            OnboardingStickyNext(title: "Continue", disabled: selectedGoals.isEmpty) {
                onNext()
            }
        }
        .accessibilityIdentifier("onboarding.goals")
    }

    private func goalRow(_ goal: JournalGoal) -> some View {
        let selected = selectedGoals.contains(goal)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) {
                if selected { selectedGoals.remove(goal) } else { selectedGoals.insert(goal) }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? AppTheme.terracottaDeep : Color.clear)
                        .overlay(
                            Circle().stroke(selected ? Color.clear : AppTheme.inkSoft.opacity(0.3), lineWidth: 1.5)
                        )
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(AppTheme.cream)
                    }
                }
                .frame(width: 22, height: 22)

                Text(goal.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [AppTheme.terracotta.opacity(0.16), AppTheme.cream],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(AppTheme.cream)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? AppTheme.terracottaDeep : AppTheme.inkSoft.opacity(0.14),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
    }
}
