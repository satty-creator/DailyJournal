//
//  QuestionPanelView.swift
//  DailyJournal
//
//  The in-session question panel. Replaces HintPanelView.
//  Three tabs (gentle / specific / choice) plus a hidden "mine" tab when
//  personalized questions exist. Each tab shows exactly 3 QuestionCards.
//
//  Key behavioral changes from HintPanelView:
//   • Cards show QUESTIONS, not sentence stems or fragments.
//   • Tapping a card sets it as the displayed prompt — it does NOT insert
//     text into the journal entry.
//   • CTA copy is "No words yet? Pick a question" (not "Start with a hint").
//   • "Make it smaller" → "Make it easier" (PRD §16).
//

import SwiftUI

struct QuestionPanelView: View {

    @ObservedObject var engine: QuestionEngine

    /// Called when the user selects a question — sets the displayed prompt.
    let onUseQuestion: (QuestionCard) -> Void
    /// Save a trace (no words needed today).
    let onSaveTrace: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: QuestionTab = .gentle
    @State private var ladderCard: QuestionCard?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabPicker
                laneCards
                ladderRow
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tab.title)
                    .font(AppTheme.editorialDisplay(size: 24))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if engine.bundle.source == "gemini" {
                    Text("for you")
                        .font(AppTheme.mono(size: 9))
                        .tracking(1)
                        .foregroundStyle(AppTheme.terracotta)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.terracotta.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
            Text(tab.subtitle)
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        let visibleTabs = engine.hasMineTab
            ? QuestionTab.allCases
            : QuestionTab.allCases.filter { $0 != .mine }

        return Picker("Question lane", selection: $tab) {
            ForEach(visibleTabs, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Lane cards

    private var laneCards: some View {
        VStack(spacing: 12) {
            ForEach(engine.cards(for: tab)) { card in
                questionCard(card) {
                    engine.useQuestion(card)
                    onUseQuestion(card)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Ladder ("make it easier")

    private var ladderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let card = ladderCard {
                questionCard(card) {
                    if card.rung == .traceOnly || card.rung == .blankDrop {
                        onSaveTrace()
                    } else {
                        engine.useQuestion(card)
                        onUseQuestion(card)
                        dismiss()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    ladderCard = engine.makeEasier()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text(engine.rung.isFloor ? "This is the easiest start" : "Make it easier")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(engine.rung.isFloor ? AppTheme.inkSoft : AppTheme.terracotta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.cream)
                .clipShape(Capsule())
            }
            .disabled(engine.rung.isFloor)
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                engine.quietForToday()
                dismiss()
            } label: {
                Text("no questions today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.cream)
                    .clipShape(Capsule())
            }

            Button {
                onSaveTrace()
            } label: {
                Text("save a trace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.mint)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 4)
    }

    // MARK: - One card

    private func questionCard(_ card: QuestionCard, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.lead.uppercased())
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(card.question)
                    .font(AppTheme.editorialBody(size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(accentColor(card.accent).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                engine.lessLikeThis(card)
            } label: {
                Label("Less like this", systemImage: "hand.thumbsdown")
            }
        }
    }

    private func accentColor(_ accent: QuestionCard.Accent) -> Color {
        switch accent {
        case .soft: return AppTheme.rose2
        case .mint: return AppTheme.mint
        case .lav:  return AppTheme.lav
        case .sun:  return AppTheme.sun
        }
    }
}
