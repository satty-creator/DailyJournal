//
//  CollageTileView.swift
//  DailyJournal
//
//  A single tile in the journal collage (Spilr Redesign screen 1f — "Journal
//  as a scrapbook"). Tile kind, size, rotation and washi tape are all pure
//  functions of the entry — never randomized per render — so a month's worth
//  of tiles hold their shape and position across every redraw and only
//  change when the entries themselves change.
//

import SwiftUI

enum CollageTileKind {
    case photo
    case quote
    case mood
    case text
    case stone

    static func kind(for entry: JournalEntry) -> CollageTileKind {
        if entry.photoURL != nil || PhotoCacheService.shared.hasImage(forEntryId: entry.id) { return .photo }
        if entry.sessionType == .dailyChat || entry.sessionType == .cbtReframe || entry.sessionType == .template { return .quote }
        if entry.wordCount < 20 { return .stone }
        if entry.wordCount >= 50 && entry.mood != nil { return .mood }
        return .text
    }
}

// MARK: - Deterministic per-entry texture

/// FNV-1a — deliberately NOT Swift's `String.hashValue`, which is reseeded
/// every process launch for hash-flood protection. That's fine for a
/// dictionary, but it would mean every tile's rotation/tape reshuffles on
/// every cold launch. This hash is stable across launches, not just redraws.
private func stableHash(_ s: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return hash
}

private enum TileTexture {
    /// Small alternating rotation, matching the mockup's hand-set feel.
    static func rotation(for entry: JournalEntry) -> Double {
        let h = stableHash(entry.id)
        return (Double(h % 1000) / 1000.0) * 2.8 - 1.4 // -1.4°…+1.4°
    }

    /// Roughly one tile in three wears a strip of washi tape.
    static func hasTape(for entry: JournalEntry) -> Bool {
        stableHash(entry.id) % 3 == 0
    }

    static func tapeColor(for entry: JournalEntry) -> Color {
        (stableHash(entry.id) / 3) % 2 == 0 ? AppTheme.sun.opacity(0.75) : AppTheme.mint.opacity(0.8)
    }

    static func tapeRotation(for entry: JournalEntry) -> Double {
        Double((stableHash(entry.id) / 7) % 9) - 4 // -4°…+4°
    }

    static func tapeOffsetX(for entry: JournalEntry) -> CGFloat {
        CGFloat((stableHash(entry.id) / 11) % 40) + 18
    }

    /// A stone tile alternates a faint blue wash and plain cream, like 1f's
    /// "SAT 8" vs "WED 12" tiles.
    static func stoneIsTinted(for entry: JournalEntry) -> Bool {
        stableHash(entry.id) % 2 == 0
    }
}

// MARK: - Sizing (for the masonry packer — see JournalCollageView)

extension CollageTileView {
    static func headline(for entry: JournalEntry) -> String {
        entry.aiSummaryBullets.first ?? entry.displayTitle
    }

    static func cornerRadius(for entry: JournalEntry) -> CGFloat {
        switch CollageTileKind.kind(for: entry) {
        case .photo, .quote: return 22
        case .mood: return 20
        case .text: return 22
        case .stone: return 18
        }
    }

    /// Deterministic estimated tile height, used only to balance the two
    /// masonry columns — not exact layout, just enough to keep columns close
    /// in length. Must stay a pure function of the entry: the packer calls it
    /// once per layout pass, and a value that drifted between calls would
    /// make tiles jump columns on scroll.
    static func estimatedHeight(for entry: JournalEntry) -> CGFloat {
        let lines = max(1, Int(ceil(Double(headline(for: entry).count) / 26.0)))
        switch CollageTileKind.kind(for: entry) {
        case .photo: return 112 + 46 + CGFloat(lines - 1) * 18
        case .mood:  return 74 + CGFloat(lines) * 21
        case .quote: return 54 + CGFloat(lines) * 23
        case .stone: return 62 + CGFloat(max(0, lines - 1)) * 18
        case .text:  return 58 + CGFloat(lines) * 20 + (entry.tags.isEmpty ? 0 : 28)
        }
    }
}

// MARK: - The tile

struct CollageTileView: View {
    let entry: JournalEntry

    private var kind: CollageTileKind { CollageTileKind.kind(for: entry) }
    private var headline: String { Self.headline(for: entry) }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius(for: entry), style: .continuous))
            .shadow(color: AppTheme.ink.opacity(0.08), radius: 7, x: 0, y: 3)
            .overlay(alignment: .top) {
                if TileTexture.hasTape(for: entry) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TileTexture.tapeColor(for: entry))
                        .frame(width: 52, height: 17)
                        .rotationEffect(.degrees(TileTexture.tapeRotation(for: entry)))
                        .offset(x: TileTexture.tapeOffsetX(for: entry) - 26, y: -9)
                }
            }
            .rotationEffect(.degrees(TileTexture.rotation(for: entry)))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .photo: photoTile
        case .mood:  moodTile
        case .quote: quoteTile
        case .stone: stoneTile
        case .text:  textTile
        }
    }

    // MARK: Photo — a taped snapshot

    private var photoTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let localImage = PhotoCacheService.shared.image(forEntryId: entry.id) {
                    // Local copy — shown instantly, before/without a finished upload.
                    Image(uiImage: localImage).resizable().scaledToFill()
                } else if let urlString = entry.photoURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure:            AppTheme.paperWarm
                        default:                  AppTheme.paperWarm
                        }
                    }
                } else {
                    AppTheme.paperWarm
                }
            }
            .frame(height: 112)
            .frame(maxWidth: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.shortFormattedDate.uppercased())
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                Text(headline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
        }
        .background(AppTheme.cream)
    }

    // MARK: Mood — a big-entry tile, tinted by mood

    private var moodTile: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.mood?.faceEmoji ?? "🙂")
                .font(.system(size: 19))
            Text(headline)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(entry.shortFormattedDate.uppercased()) · \(entry.wordCount) WORDS")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.ink.opacity(0.55))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [entry.accentColor, entry.accentColor.blended(with: AppTheme.cream, amount: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: Quote — a chat-woven entry, as a pull-quote

    private var quoteTile: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\u{201C}\(headline)\u{201D}")
                .font(.system(size: 15, weight: .bold, design: .rounded).italic())
                .foregroundStyle(AppTheme.terracottaDeep)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.shortFormattedDate.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.rose2, AppTheme.cream],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: Stone — a one-liner day

    private var stoneTile: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.shortFormattedDate.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
            Text(headline)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if entry.wordCount > 0 {
                Text("\(entry.wordCount) WORDS")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.8))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TileTexture.stoneIsTinted(for: entry) ? AppTheme.blue.opacity(0.4) : AppTheme.cream)
    }

    // MARK: Text — the plain default

    private var textTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.shortFormattedDate.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
            Text(headline)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let tag = entry.tags.first {
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.lavDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.lav.opacity(0.34))
                    .clipShape(Capsule())
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
    }
}
