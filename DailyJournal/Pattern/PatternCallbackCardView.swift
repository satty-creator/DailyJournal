//
//  PatternCallbackCardView.swift
//  DailyJournal
//
//  The Home card for a Pattern Callback. Heavier and quieter than an Echo card:
//  the observation line is the hero, the rest recedes. One card, ever. Always
//  dismissable. Tapping the body opens the stitched tap-through view.
//
//  All mutations go through callbacks so HomeViewModel stays the single source
//  of truth (same contract as EchoCardView).
//

import SwiftUI

struct PatternCallbackCardView: View {

    let callback: PatternCallback

    /// Tapped the body — open the stitched view of the source entries.
    let onTap: () -> Void
    /// "not now" — soft dismiss, 4-day cool-down applies.
    let onNotNow: () -> Void
    /// "stop watching [entity]" — only offered when there's an entity.
    let onMute: () -> Void
    /// "I needed that" — strong positive training signal.
    let onAffirm: () -> Void

    @State private var dotOpacity: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 16)

            // Hero: the observation, tappable to open the stitched view.
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(callback.callbackLine)
                        .font(AppTheme.editorialDisplay(size: 23))
                        .foregroundStyle(AppTheme.cream)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    seeEntriesRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)

            actionRow
        }
        .padding(20)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.terracotta.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.terracotta)
                    .frame(width: 6, height: 6)
                    .opacity(dotOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                            dotOpacity = 1.0
                        }
                    }
                Text("ninety noticed · \(callback.archetype.displayLabel)")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.terracotta)
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            Spacer()
            Button(action: onNotNow) {
                Text("not now")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.cream.opacity(0.5))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - "See the entries" affordance

    private var seeEntriesRow: some View {
        HStack(spacing: 6) {
            Text("from \(callback.evidence.count) entries")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.cream.opacity(0.55))
                .tracking(0.5)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.cream.opacity(0.55))
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            if callback.entity != nil {
                Button(action: onMute) {
                    Text("stop watching")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.cream.opacity(0.6))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .overlay(
                            Capsule().stroke(AppTheme.cream.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Button(action: onAffirm) {
                Text("I needed that")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                    .background(AppTheme.cream)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
