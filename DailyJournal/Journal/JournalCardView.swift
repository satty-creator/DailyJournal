//
//  JournalCardView.swift
//  DailyJournal
//

import SwiftUI

struct JournalCardView: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left accent stripe — mood / sentiment color
            Rectangle()
                .fill(entry.accentColor)
                .frame(width: 4)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            VStack(alignment: .leading, spacing: 10) {

                // Top row: date + 90s badge + mood + letter icon
                HStack(spacing: 6) {
                    Text(entry.formattedDate)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(0.5)

                    if entry.sessionType == .ninetySecond {
                        Text("90s")
                            .font(AppTheme.mono(size: 9))
                            .foregroundStyle(AppTheme.terracotta)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.terracotta.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let mood = entry.mood {
                        Text(mood.faceEmoji).font(.system(size: 15))
                    }

                    if entry.isScheduledLetter {
                        Image(systemName: entry.futureSelfOpened ? "envelope.open" : "envelope.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.inkSoft.opacity(0.6))
                    }
                }

                // Content preview / title
                Text(entry.displayTitle)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .lineSpacing(2)

                // First AI bullet if available
                if let firstBullet = entry.aiSummaryBullets.first {
                    HStack(alignment: .top, spacing: 5) {
                        Text("—")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(entry.accentColor)
                        Text(firstBullet)
                            .font(AppTheme.mono(size: 11))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineLimit(1)
                    }
                }

                // Bottom row
                HStack(spacing: 6) {
                    Text("\(entry.wordCount) words")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.slate)

                    if let sentiment = entry.sentimentLabel {
                        Text("·").foregroundStyle(AppTheme.slate)
                            .font(AppTheme.mono(size: 10))
                        Text(sentiment)
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(entry.accentColor)
                    }

                    Spacer()

                    ForEach(entry.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
        }
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppTheme.ink.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}
