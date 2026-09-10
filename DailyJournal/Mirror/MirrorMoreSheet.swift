//
//  MirrorMoreSheet.swift
//  DailyJournal
//
//  The "more…" sheet raised from TodayMirrorCardView (L1 → L2 threshold).
//  Two taps live on the card itself (This is me / Not quite); the rest of
//  the old five-option feedback set — Not me, Too intense, Ask tomorrow —
//  lives here, alongside "Teach Spilr" (the correction flow, EvidenceDrawerView)
//  and the hand-off into Daily Chat. A reaction stays a reaction on the card;
//  a survey is one tap away for anyone who wants to give more.
//

import SwiftUI

struct MirrorMoreSheet: View {
    var onFeedback: (MirrorFeedback) -> Void
    var onTeachSpilr: () -> Void
    var onReadFullMirror: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule()
                .fill(AppTheme.inkSoft.opacity(0.2))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(spacing: 8) {
                row(title: "Not me", systemImage: "xmark.circle") {
                    onFeedback(.notMe)
                }
                row(title: "Too intense", systemImage: "wind") {
                    onFeedback(.tooIntense)
                }
                row(title: "Ask me again tomorrow", systemImage: "clock.arrow.circlepath") {
                    onFeedback(.askTomorrow)
                }

                Divider().padding(.vertical, 4)

                row(title: "Teach Spilr", systemImage: "pencil.line") {
                    onTeachSpilr()
                }
                row(title: "Read the full mirror", systemImage: "arrow.up.right") {
                    onReadFullMirror()
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)
        }
        .background(AppTheme.paper.ignoresSafeArea())
    }

    private func row(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(AppTheme.cream.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
