//
//  PeopleStepView.swift
//  DailyJournal
//
//  Onboarding step 3 — "Who's in your life?": optional, skippable. Chips for
//  a fixed set of roles, each with an optional name. Seeds
//  `lifeContext.peopleLikelyToAppear` (`OnboardingLifeContextSeed`), so
//  Mirror and Daily Chat already recognise these people on day one instead
//  of learning them from scratch over several entries.
//

import SwiftUI

struct PeopleStepView: View {
    @Binding var people: [OnboardingPerson]
    let onBack: () -> Void
    let onNext: () -> Void

    private let roles = ["partner", "parent", "boss", "friend", "sibling", "kid"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        OnboardingBackButton(action: onBack)
                        OnboardingProgressDots(current: 3, total: 8)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who\u{2019}s in your\nlife right now?")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Totally optional \u{2014} skip this if you\u{2019}d rather Spilr just learn as you write.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(roles, id: \.self) { role in
                            roleRow(role)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 0) {
                OnboardingStickyNext(title: "Continue") {
                    onNext()
                }
                OnboardingSkipLink(title: "Skip for now") {
                    people = []
                    onNext()
                }
                .accessibilityIdentifier("onboarding.people.skip")
                .padding(.bottom, 20)
            }
        }
        .accessibilityIdentifier("onboarding.people")
    }

    private func isSelected(_ role: String) -> Bool {
        people.contains { $0.role == role }
    }

    private func toggle(_ role: String) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) {
            if let idx = people.firstIndex(where: { $0.role == role }) {
                people.remove(at: idx)
            } else {
                people.append(OnboardingPerson(role: role, name: nil))
            }
        }
    }

    private func nameBinding(for role: String) -> Binding<String> {
        Binding(
            get: { people.first(where: { $0.role == role })?.name ?? "" },
            set: { newValue in
                if let idx = people.firstIndex(where: { $0.role == role }) {
                    people[idx].name = newValue
                }
            }
        )
    }

    private func roleRow(_ role: String) -> some View {
        let selected = isSelected(role)
        return VStack(alignment: .leading, spacing: 10) {
            Button { toggle(role) } label: {
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

                    Text(role.capitalized)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.person.\(role)")
            .accessibilityAddTraits(selected ? .isSelected : [])

            if selected {
                TextField("Name (optional)", text: nameBinding(for: role))
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.cream.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
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
}
