//
//  ReadShareCard.swift
//  DailyJournal
//
//  The share surface for "Today's Read" — a high-contrast, minimalist typographic
//  card built for Instagram Stories / TikTok. This is the feature's viral loop.
//
//  PRIVACY: it renders ONLY `read.shareSafeText` — never the receipt chips, source
//  entries, mood, dates, or any other private context. The share-safe line is a
//  clean, de-contextualised restatement produced by the engine/generator exactly
//  for this purpose.
//
//  `ReadShareCard` is the visual; `ShareReadButton` renders it to a UIImage via
//  ImageRenderer and hands it to a SwiftUI ShareLink — same approach as
//  ShareableInsightCard.
//

import SwiftUI

// MARK: - The rendered card

struct ReadShareCard: View {

    let read: DailyRead

    /// Story-friendly 9:16-ish canvas. Dark, so it reads as "ninety" at a glance.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text("today's read")
                .font(AppTheme.mono(size: 13))
                .foregroundStyle(AppTheme.cream.opacity(0.55))
                .tracking(3)
                .textCase(.lowercase)

            Spacer(minLength: 40)

            // The share-safe line — the only user-derived text on the card.
            Text(read.shareSafeText)
                .font(AppTheme.editorialDisplay(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 40)

            HStack(spacing: 8) {
                Text("\u{2726}")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.sun)
                Text("made with ninety")
                    .font(AppTheme.mono(size: 12))
                    .foregroundStyle(AppTheme.cream.opacity(0.7))
                    .tracking(1)
                Spacer()
                Text("get your read")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.ink)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.sun)
                    .clipShape(Capsule())
            }
        }
        .padding(40)
        .frame(width: 405, height: 720)   // 9:16
        .background(
            LinearGradient(
                colors: [AppTheme.ink, Color(hex: "1C1730")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Share button

struct ShareReadButton: View {

    let read: DailyRead

    @State private var shareImage: Image?

    var body: some View {
        Group {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("today's read", image: shareImage)
                ) { label }
            } else {
                // Falls back to a plain button while the image renders; tapping
                // re-renders in case the first pass hadn't completed.
                Button { render() } label: { label }
            }
        }
        .onAppear { render() }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 11, weight: .semibold))
            Text("share")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppTheme.cream.opacity(0.8))
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: ReadShareCard(read: read))
        renderer.scale = UIScreen.main.scale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}
