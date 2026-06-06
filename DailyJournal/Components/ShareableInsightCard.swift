//
//  ShareableInsightCard.swift
//  DailyJournal
//
//  A branded, square-ish image rendered from an entry's reflection so people can
//  share a beautiful artifact (Stories / Messages) rather than a screenshot of
//  text. This is the app's main organic-growth surface.
//
//  `InsightShareCard` is the visual; `ShareInsightButton` renders it to a UIImage
//  via ImageRenderer and hands it to a SwiftUI ShareLink.
//

import SwiftUI

// MARK: - The rendered card

struct InsightShareCard: View {
    let entry: JournalEntry

    /// First AI bullet if present, else a trimmed excerpt of the entry.
    private var headline: String {
        if let first = entry.aiSummaryBullets.first, !first.isEmpty { return first }
        let excerpt = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(excerpt.prefix(160)) + (excerpt.count > 160 ? "…" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ninety.")
                    .font(AppTheme.editorialDisplay(size: 26))
                    .foregroundStyle(AppTheme.terracotta)
                    .italic()
                Spacer()
                if let mood = entry.mood {
                    Text(mood.faceEmoji).font(.system(size: 26))
                }
            }

            Spacer(minLength: 28)

            Text("“\(headline)”")
                .font(AppTheme.editorialDisplay(size: 28))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if let question = entry.aiQuestion, !question.isEmpty {
                Text(question)
                    .font(AppTheme.editorialBody(size: 16))
                    .foregroundStyle(AppTheme.inkSoft)
                    .italic()
                    .lineSpacing(3)
                    .padding(.top, 16)
            }

            Spacer(minLength: 28)

            HStack {
                Text(entry.createdAt.formatted(.dateTime.month(.wide).day().year()))
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                Spacer()
                Text("a space to think")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.slate)
                    .tracking(1)
            }
        }
        .padding(32)
        .frame(width: 360, height: 480)
        .background(AppTheme.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(AppTheme.terracotta.opacity(0.25), lineWidth: 6)
        )
    }
}

// MARK: - Share button

struct ShareInsightButton: View {
    let entry: JournalEntry
    @State private var shareImage: Image?

    var body: some View {
        Group {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("My reflection", image: shareImage)
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
                .font(.system(size: 12, weight: .semibold))
            Text("Share")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AppTheme.terracotta)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: InsightShareCard(entry: entry))
        renderer.scale = UIScreen.main.scale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}
