//
//  JournalCardView.swift
//  DailyJournal
//
//  The journal list row — Spilr Redesign screen 1e ("mood-tinted, safe"): the
//  card is tinted by its own mood/sentiment colour instead of wearing a plain
//  4px accent stripe, the AI summary reads as a real pull-quote, and tags
//  become soft chips. Same underlying JournalEntry, no new data.
//

import SwiftUI

struct JournalCardView: View {
    let entry: JournalEntry

    private var summaryHeadline: String {
        entry.aiSummaryBullets.first ?? entry.displayTitle
    }

    private var metaLine: String {
        "\(entry.shortFormattedDate.uppercased()) · \(entry.wordCount) WORDS"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                if let mood = entry.mood {
                    Text(mood.faceEmoji)
                        .font(.system(size: 15))
                }
                Text(metaLine)
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.inkSoft)
            }

            Text(summaryHeadline)
                .font(AppTheme.editorialDisplay(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Attached photo (if any) — not drawn in the 1e mockup, but silently
            // dropping a real photo would lose data the user attached. Prefers
            // the local cache (instant, warm as soon as save() runs) over the
            // remote URL, which only exists once the background upload finishes.
            if let localImage = PhotoCacheService.shared.image(forEntryId: entry.id) {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let urlString = entry.photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.clear
                    default:
                        AppTheme.paperWarm
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !entry.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags.prefix(4), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(entry.accentColor.blended(with: AppTheme.ink, amount: 0.35))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(entry.accentColor.opacity(0.32))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AppTheme.cream
                LinearGradient(
                    colors: [entry.accentColor.opacity(0.30), AppTheme.cream.opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // A soft glow off the top-trailing corner, echoing 1e's blurred
                // circle — clipped by the card's own corner radius below.
                GeometryReader { geo in
                    Circle()
                        .fill(entry.accentColor.opacity(0.24))
                        .frame(width: 86, height: 86)
                        .position(x: geo.size.width, y: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 3)
    }
}
