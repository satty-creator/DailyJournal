//
//  StartSheetView.swift
//  DailyJournal
//
//  "How do you want to start?" — Spilr Redesign 3b's start sheet, reached
//  from the invitation card's "More ways" link. Chat is already the primary
//  door (the invitation card itself); this sheet is every other way in.
//
//  The sheet only *selects* — it hands a `StartChoice` back to `HomeView`,
//  which owns the actual `fullScreenCover`s, or pushes the Templates gallery
//  onto its own `NavigationStack`. See `HomeView`'s `.sheet(isPresented:
//  $showingStartSheet)` for why the choice is stashed and applied in
//  `onDismiss` rather than acted on directly from a row's tap.
//

import SwiftUI

/// Destinations the sheet can push to on its own `NavigationStack`.
enum StartRoute: Hashable {
    case templates
}

/// A choice that closes the sheet and hands control back to `HomeView`.
enum StartChoice {
    case spill
    case chat
    case talk
    /// Picked a card in `TemplateGalleryView` — carries the template so
    /// `HomeView.handlePendingStart` can present `TemplateRunnerView` with it
    /// directly, no id lookup needed.
    case template(JournalTemplate)
}

struct StartOptionsView: View {
    let onPick: (StartChoice) -> Void
    let onOpenTemplates: () -> Void

    // Matches `.presentationCornerRadius(28)` on the sheet in `HomeView`. The
    // corners are baked into this view's own background rather than left to
    // the system sheet's corner-radius compositing — that path was leaving a
    // faint seam (the system's default sheet drop-shadow) along the top edge
    // wherever the backdrop behind it was dark, e.g. the "Today with Spilr"
    // card.
    private let sheetCornerRadius: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(AppTheme.inkSoft.opacity(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("How do you want to start?")
                .font(AppTheme.editorialDisplay(size: 21))
                .foregroundStyle(AppTheme.ink)

            Text("Every door leads to the same place \u{2014} an entry that\u{2019}s yours.")
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.top, 4)

            VStack(spacing: 10) {
                reflectRow
                blankPageRow
                templatesRow
                talkItOutRow
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .bottom)
        .background(
            AppTheme.paper,
            in: UnevenRoundedRectangle(
                topLeadingRadius: sheetCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: sheetCornerRadius,
                style: .continuous
            )
        )
        .navigationBarHidden(true)
    }

    // MARK: - Reflect with Spilr (featured, dark)

    private var reflectRow: some View {
        Button { onPick(.chat) } label: {
            HStack(spacing: 14) {
                BloomMarkView(size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Reflect with Spilr")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.cream)
                        Text("MOST START HERE")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.sun)
                            .clipShape(Capsule())
                    }
                    Text("I ask, you answer. The gentlest way in.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.cream.opacity(0.72))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [AppTheme.ink, AppTheme.inkRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plain rows (Blank page / Templates / Talk it out)

    private var blankPageRow: some View {
        row(
            icon: "square.and.pencil",
            iconTint: AppTheme.terracotta,
            title: "Blank page",
            subtitle: "Just write. No prompt, no timer.",
            action: { onPick(.spill) }
        )
    }

    private var talkItOutRow: some View {
        row(
            icon: "mic.fill",
            iconTint: AppTheme.gold,
            title: "Talk it out",
            subtitle: "Speak instead of type; it becomes an entry.",
            action: { onPick(.talk) }
        )
    }

    private var templatesRow: some View {
        Button(action: onOpenTemplates) {
            HStack(alignment: .top, spacing: 14) {
                iconTile(systemName: "square.grid.2x2.fill", tint: AppTheme.lavDeep)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Templates")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("Structured exercises for a mood or moment.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                    // FlowLayout, not a fixed HStack — real template titles run
                    // longer than the old hardcoded tags ("Gratitude", "Wind
                    // down") did, and this wraps instead of overflowing.
                    FlowLayout(spacing: 6) {
                        // Derived from the real catalog so this can't drift
                        // out of sync with it (it used to be hardcoded and
                        // named a template — "A hard decision" — that didn't
                        // exist under that title).
                        ForEach(JournalTemplate.all.prefix(3).map(\.title), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.lavDeep)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.lav.opacity(0.34))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared row shape

    private func row(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconTile(systemName: icon, tint: iconTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconTile(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
