//
//  River.swift
//  DailyJournal
//
//  The aggregated river artifact for a window (7 / 14 / 30 days). Built from
//  RiverMarks by RiverService. The narrative text fields can be filled either
//  by the on-device generator (LocalRiver) or enriched by Gemini.
//
//  Rivers are DERIVED. v1 regenerates them on demand from marks rather than
//  persisting them, so deleting an entry can never orphan a stale artifact.
//

import Foundation

// MARK: - Window

enum RiverWindow: Int, CaseIterable, Identifiable {
    case week   = 7
    case biweek = 14
    case month  = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week:   return "7 days"
        case .biweek: return "14 days"
        case .month:  return "30 days"
        }
    }

    /// How many entries are required before this artifact is meaningful.
    /// Deliberately low so consistency is never the price of meaning.
    var unlockThreshold: Int {
        switch self {
        case .week:   return 3
        case .biweek: return 5
        case .month:  return 8
        }
    }

    var label: String {
        switch self {
        case .week:   return "Your First Current"
        case .biweek: return "Your Two-Week Current"
        case .month:  return "Your Month, as a River"
        }
    }
}

// MARK: - Per-day segment (drives the renderer)

struct RiverDaySegment: Identifiable {
    let id = UUID()
    let date: Date
    let hasEntry: Bool
    let marker: AppTheme.RiverMarker
    let waterState: WaterState
    /// 0…5 — drives width / opacity intensity.
    let intensity: Int
    /// Colour derived from valence; nil for quiet (mist) days.
    let valence: Int?
    /// Private, shown on tap. Never leaves the device in share mode.
    let tooltip: String
}

// MARK: - Share copy

enum ShareStyle: String, CaseIterable, Identifiable {
    case minimal, poetic, stats
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - River

struct River {

    let window: RiverWindow
    let startDate: Date
    let endDate: Date

    // Counts
    let entryCount: Int
    let returnCount: Int     // returns after a quiet gap (bridges)
    let quietDays: Int

    // Visual
    let segments: [RiverDaySegment]

    // Narrative (private)
    let privateTitle: String
    let mainCurrentTitle: String
    let mainCurrentBody: String
    let recurringWords: [String]
    let bendFrom: String?
    let bendTo: String?
    let bendDescription: String?
    let returnMark: String?
    let quietStretchNote: String?
    /// The single most resonant exact line from the window. PRIVATE.
    let sentenceOfWeek: String?
    let gentleQuestion: String?
    let privateInterpretation: String

    // Share (privacy-safe — no raw text, no sensitive theme labels)
    let shareTitle: String
    let shareCopy: [ShareStyle: String]

    /// One-line "truth" that often becomes the most shareable part.
    let oneLineTruth: String

    /// True when there weren't enough entries to say much with confidence.
    let isSparse: Bool

    // MARK: - Convenience
    var countLabel: String {
        var parts = ["\(entryCount) \(entryCount == 1 ? "entry" : "entries")"]
        if returnCount > 0 { parts.append("\(returnCount) \(returnCount == 1 ? "return" : "returns")") }
        if quietDays  > 0 { parts.append("\(quietDays) quiet") }
        return parts.joined(separator: " · ")
    }

    func share(_ style: ShareStyle) -> String {
        shareCopy[style] ?? shareTitle
    }
}
