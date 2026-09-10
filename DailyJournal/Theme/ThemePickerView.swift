//
//  ThemePickerView.swift
//  DailyJournal
//
//  The "Choose vibe" screen — a grid of selectable themes modelled on the
//  Spilr prototype's theme picker. Tapping a tile switches the whole app
//  instantly via ThemeManager.
//
//  See themesprd.md.
//

import SwiftUI

struct ThemePickerView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Intro copy (mirrors the prototype's identity-safe framing).
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your vibe")
                            .font(AppTheme.editorialDisplay(size: 30))
                            .foregroundStyle(AppTheme.ink)
                        Text("Make spilr feel like yours — soft, calm, grounded, data-first, or warm. Change it anytime.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    // Live preview of the currently selected theme.
                    ThemePreviewCard()

                    // The theme grid.
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(ThemeID.allCases) { theme in
                            ThemeTile(
                                theme: theme,
                                isSelected: themeManager.themeID == theme
                            ) {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                #endif
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    themeManager.select(theme)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme tile

private struct ThemeTile: View {
    let theme: ThemeID
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SwatchView(colors: theme.swatch)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.terracotta : AppTheme.inkSoft.opacity(0.4))
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(AppTheme.editorialDisplay(size: 18))
                        .foregroundStyle(AppTheme.ink)
                    Text(theme.subtitle)
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(16)
            .background(AppTheme.cream.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? AppTheme.terracotta : Color.clear, lineWidth: 2)
            )
            .shadow(color: AppTheme.cardShadow,
                    radius: isSelected ? 20 : 10,
                    x: 0, y: isSelected ? 12 : 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Swatch

private struct SwatchView: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                c
            }
        }
        .frame(width: 54, height: 30)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - Live preview card

private struct ThemePreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.terracotta)
                    .frame(width: 9, height: 9)
                Text("TODAY'S READ")
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.inkSoft)
            }

            Text("You keep circling back to rest, but calling it laziness.")
                .font(AppTheme.editorialDisplay(size: 20))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("A gentle mirror from your own words — no diagnosis, just a reflection.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Start today's spill")
                    .font(AppTheme.editorialBody(size: 14).weight(.semibold))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )

                // A few mood dots, so the preview shows the accent vocabulary.
                HStack(spacing: 6) {
                    ForEach([AppTheme.mint, AppTheme.sun, AppTheme.dusk, AppTheme.blue], id: \.self) { c in
                        Circle().fill(c).frame(width: 12, height: 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.cream.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.terracotta.opacity(0.16), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 18, x: 0, y: 12)
    }
}
