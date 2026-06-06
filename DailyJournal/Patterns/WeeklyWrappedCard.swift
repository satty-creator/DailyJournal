//
//  WeeklyWrappedCard.swift
//  DailyJournal
//
//  A small "this week" recap shown at the top of Patterns: active days, words,
//  the week's dominant mood, and a standout line. Designed to be glanceable and
//  shareable (same ImageRenderer → ShareLink approach as the insight card).
//

import SwiftUI

struct WeeklyWrappedCard: View {
    let activeDays: Int
    let wordCount: Int
    let topMood: Mood?
    let standoutLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("THIS WEEK")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta)
                    .tracking(2)
                Spacer()
                Text("ninety.")
                    .font(AppTheme.editorialDisplay(size: 18))
                    .foregroundStyle(AppTheme.terracotta)
                    .italic()
            }

            HStack(spacing: 24) {
                stat(value: "\(activeDays)", label: activeDays == 1 ? "day" : "days")
                stat(value: "\(wordCount)", label: "words")
                if let topMood {
                    VStack(spacing: 4) {
                        Text(topMood.faceEmoji).font(.system(size: 26))
                        Text("mood")
                            .font(AppTheme.mono(size: 9))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(1)
                    }
                }
            }

            if let standoutLine {
                Text("“\(standoutLine)”")
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft)
                    .italic()
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.terracotta.opacity(0.2), lineWidth: 1)
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTheme.editorialDisplay(size: 30))
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
        }
    }
}

/// Renders the recap into a fixed-size image and offers it via ShareLink.
struct ShareWeeklyButton: View {
    let activeDays: Int
    let wordCount: Int
    let topMood: Mood?
    let standoutLine: String?

    @State private var shareImage: Image?

    private var cardForShare: some View {
        WeeklyWrappedCard(
            activeDays: activeDays,
            wordCount: wordCount,
            topMood: topMood,
            standoutLine: standoutLine
        )
        .frame(width: 360)
        .padding(24)
        .background(AppTheme.paper)
    }

    var body: some View {
        Group {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("My week on ninety", image: shareImage)
                ) { label }
            } else {
                Button { render() } label: { label }
            }
        }
        .onAppear { render() }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
            Text("Share my week")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AppTheme.terracotta)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: cardForShare)
        renderer.scale = UIScreen.main.scale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}
