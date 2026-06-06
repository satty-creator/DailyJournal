//
//  MascotView.swift
//  DailyJournal
//
//  "Niney" — a tiny breathing blob with a calm little face. Used to warm up
//  empty states so the app feels friendly rather than barren. Pure SwiftUI
//  shapes; no assets, no Canvas, cheap to render.
//

import SwiftUI

struct MascotView: View {
    var size: CGFloat = 96
    var tint: Color = AppTheme.terracotta

    @State private var breathe = false
    @State private var blink = false

    var body: some View {
        ZStack {
            // Soft body
            Circle()
                .fill(tint.opacity(0.18))
                .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1.5))
                .scaleEffect(breathe ? 1.04 : 0.96)

            // Face
            VStack(spacing: size * 0.10) {
                HStack(spacing: size * 0.18) {
                    eye
                    eye
                }
                // gentle smile
                Capsule()
                    .fill(tint)
                    .frame(width: size * 0.30, height: size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var eye: some View {
        Circle()
            .fill(tint)
            .frame(width: size * 0.10, height: size * 0.10)
            .scaleEffect(y: blink ? 0.2 : 1.0)
    }
}

/// A reusable, friendly empty state with the mascot, a headline, supporting copy
/// and an optional primary action.
struct FriendlyEmptyState: View {
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            MascotView()

            Text(title)
                .font(AppTheme.editorialDisplay(size: 26))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(AppTheme.editorialBody())
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(AppTheme.ink)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}
