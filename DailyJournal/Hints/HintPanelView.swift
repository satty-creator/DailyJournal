//
//  HintPanelView.swift
//  DailyJournal
//
//  The hint panel: a calm bottom sheet that offers the ladder. Three lanes
//  (tiny / specific / choice), a "make it smaller" descent, and two quiet exits —
//  "less hints today" and "save a trace". Tapping any card hands its usable
//  fragment back to the caller to drop into the entry.
//

import SwiftUI

struct HintPanelView: View {

    @ObservedObject var engine: HintEngine

    /// The fragment to insert into the entry / voice prompt.
    let onUse: (String) -> Void
    /// Save a tap-only trace (no words needed today).
    let onSaveTrace: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: HintTab = .tiny
    /// The current smallest hint surfaced by the ladder, shown above the lanes.
    @State private var ladderCard: HintCard?

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
        Picker("Hint lane", selection: $tab) {
            ForEach(HintTab.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Lane cards
    private var laneCards: some View {
        VStack(spacing: 12) {
            ForEach(engine.cards(for: tab)) { card in
                hintCard(card) { onUse(card.insertable) }
            }
        }
    }

    // MARK: - Ladder ("make it smaller")
    private var ladderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let card = ladderCard {
                hintCard(card) {
                    if card.rung == .tapOnlyTrace || card.rung == .blankDrop {
                        onSaveTrace()
                    } else {
                        onUse(card.insertable)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { ladderCard = engine.makeSmaller() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text(engine.rung.isFloor ? "This is the smallest start" : "Make it smaller")
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
                Text("less hints today")
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
    private func hintCard(_ card: HintCard, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.lead.uppercased())
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(card.text)
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
    }

    private func accentColor(_ accent: HintCard.Accent) -> Color {
        switch accent {
        case .soft: return AppTheme.rose2
        case .mint: return AppTheme.mint
        case .lav:  return AppTheme.lav
        case .sun:  return AppTheme.sun
        }
    }
}
