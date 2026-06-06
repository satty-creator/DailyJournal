//
//  EchoCardView.swift
//  DailyJournal
//
//  The card shown above today's prompt on HomeView when an Echo is surfaceable.
//  One card. One soft pulse. Always dismissable. Never a list.
//
//  Callbacks are used instead of direct service calls so HomeViewModel owns
//  all state mutations (single source of truth, easier to test).
//

import SwiftUI

struct EchoCardView: View {

    let echo: Echo

    /// Tapped the "skip" link — one tap, no confirm.
    let onSkip: () -> Void
    /// Tapped "not yet" — treated identically to skip for state purposes.
    let onNotYet: () -> Void
    /// Tapped the primary action ("done ✓", "it happened", "noted").
    let onAnswer: () -> Void
    /// Tapped "read them together" — only fired for .theme type echoes.
    let onThemeTap: () -> Void

    @State private var dotOpacity: Double = 0.35

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 10)

            quoteText
                .padding(.bottom, 6)

            timeAgoLabel
                .padding(.bottom, 14)

            actionRow
        }
        .padding(16)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.inkSoft.opacity(0.2), lineWidth: 1)
        )
        // Subtle hard shadow — matches the spec's "box-shadow: 2px 2px 0"
        .shadow(color: AppTheme.ink.opacity(0.12), radius: 0, x: 2, y: 2)
    }

    // MARK: - Header row (type tag + skip)

    private var headerRow: some View {
        HStack(alignment: .center) {
            typeTag
            Spacer()
            skipButton
        }
    }

    private var typeTag: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AppTheme.terracotta)
                .frame(width: 6, height: 6)
                .opacity(dotOpacity)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 2.4)
                        .repeatForever(autoreverses: true)
                    ) {
                        dotOpacity = 1.0
                    }
                }

            Text("an echo · \(echo.type.displayLabel)")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1.4)
                .textCase(.uppercase)
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("skip")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.4)
                .textCase(.uppercase)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quote

    private var quoteText: some View {
        Text("\u{201C}\(echo.quote)\u{201D}")
            .font(AppTheme.editorialBody(size: 15))
            .italic()
            .foregroundStyle(AppTheme.ink)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Time ago

    private var timeAgoLabel: some View {
        Text(relativeTime(from: echo.sourceEntryCreatedAt))
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(0.4)
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        if echo.type == .theme {
            themeActionButton
        } else {
            standardActionButtons
        }
    }

    private var standardActionButtons: some View {
        HStack(spacing: 8) {
            // "Not yet" — left, secondary
            Button(action: onNotYet) {
                Text("not yet")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .overlay(
                        Capsule().stroke(AppTheme.inkSoft.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Primary action — right, filled
            Button(action: onAnswer) {
                Text(echo.type.actionLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppTheme.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var themeActionButton: some View {
        Button(action: onThemeTap) {
            HStack {
                Text("read them together")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.cream)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.cream.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func relativeTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        let hours   = Int(seconds / 3600)
        let days    = Int(seconds / 86400)
        if days  > 1 { return "From your entry · \(days) days ago" }
        if days == 1 { return "From your entry · yesterday" }
        if hours > 1 { return "From your entry · \(hours) hours ago" }
        if hours == 1 { return "From your entry · an hour ago" }
        return "From your entry · just now"
    }
}
