//
//  MemoryProfile.swift
//  DailyJournal
//
//  A lightweight, persistent "what Spilr knows about you" layer.
//
//  Until now every Gemini call was stateless: hints saw only pebbles, insights
//  saw only the current entry, echoes saw 3 recent snippets, patterns saw a
//  60-day window — but nothing carried a durable sense of the person across
//  calls. MemoryProfile is that durable sense: a small, deterministic digest of
//  recurring themes, recurring names/places, mood lately, and cadence.
//
//  It powers two things:
//   1. The Echoes (Memories) feed — "things about you" that are always there.
//   2. A compact `promptContext()` block injected into AI prompts so Spilr's
//      "a friend who's been reading your journal" voice is finally backed by data.
//
//  It is intentionally derived + cached, never hand-edited, and never contains
//  raw entry bodies — only aggregates safe to keep around.
//

import Foundation

struct MemoryProfile: Codable, Equatable {

    struct Theme: Codable, Equatable, Identifiable {
        let word: String
        let count: Int
        var id: String { word }
    }

    /// Meaningful words the person keeps returning to (most frequent first).
    var recurringThemes: [Theme]
    /// Names / places / subjects that recur (from pattern callbacks + tags).
    var recurringEntities: [String]
    /// The person's own non-standard emotional vocabulary — words like "wired",
    /// "spiralling", "numb", "flat" that they use instead of the standard labels.
    /// These are injected into prompts so the AI mirrors their language back.
    var emotionalVocabulary: [String]
    /// Observed coping signals: short phrases like "walks help" / "screens make
    /// it worse" extracted from the person's own entries.
    var copingPatterns: [String]
    /// A couple of the most salient recent `JournalEvent`s, rendered as short
    /// "situation → outcome" lines (see `EventService.fetchRecent` /
    /// `JournalEvent.salience`). This is the one field in this struct that
    /// isn't a frequency count — it's what upgrades `promptContext()` from
    /// "themes: work (12), tired (9)" to a specific, checkable moment, at the
    /// same 10 call sites that already read this block.
    var notableMoments: [String]
    /// Dominant mood over the recent window, as `Mood.rawValue` (nil if unknown).
    var topMoodRaw: String?
    /// Lifetime + recent cadence.
    var totalEntries: Int
    var activeDaysLast30: Int
    var activeDaysThisWeek: Int
    var firstEntryDate: Date?
    var lastEntryDate: Date?
    /// When this digest was last composed.
    var generatedAt: Date

    var hasContent: Bool { totalEntries > 0 }

    static let empty = MemoryProfile(
        recurringThemes: [], recurringEntities: [],
        emotionalVocabulary: [], copingPatterns: [], notableMoments: [],
        topMoodRaw: nil,
        totalEntries: 0, activeDaysLast30: 0, activeDaysThisWeek: 0,
        firstEntryDate: nil, lastEntryDate: nil, generatedAt: .distantPast
    )

    // MARK: - Convenience for the feed

    var topMood: Mood? { topMoodRaw.flatMap { Mood(rawValue: $0) } }

    /// A short "here since…" line for the feed header / bubbles.
    var sinceLabel: String? {
        guard let first = firstEntryDate else { return nil }
        return "here since " + first.formatted(.dateTime.month(.abbreviated).year())
    }

    // MARK: - Prompt context

    /// A compact block describing the person, injected at the END of AI prompts.
    /// Returns "" when there's nothing worth saying yet. Deliberately framed so
    /// the model uses it for awareness, not recitation.
    func promptContext() -> String {
        guard hasContent else { return "" }

        var lines: [String] = []

        if !recurringThemes.isEmpty {
            let themes = recurringThemes.prefix(5)
                .map { "\($0.word) (\($0.count))" }
                .joined(separator: ", ")
            lines.append("- Themes they keep returning to: \(themes)")
        }
        if !recurringEntities.isEmpty {
            lines.append("- Names/places that recur: \(recurringEntities.prefix(5).joined(separator: ", "))")
        }
        // Emotional vocabulary — use their actual words, not ours
        if !emotionalVocabulary.isEmpty {
            lines.append("- Their emotional vocabulary (use these words, not standard labels): "
                + emotionalVocabulary.prefix(6).joined(separator: ", "))
        }
        // Coping patterns — useful context for grounding observations
        if !copingPatterns.isEmpty {
            lines.append("- Observed coping signals: "
                + copingPatterns.prefix(4).joined(separator: "; "))
        }
        // Specific remembered moments — the one line here that's a checkable
        // episode rather than a frequency count. See JournalEvent.swift.
        if !notableMoments.isEmpty {
            lines.append("- Specific moments worth remembering: "
                + notableMoments.prefix(3).joined(separator: "; "))
        }
        if let mood = topMood {
            lines.append("- Mood lately tends toward: \(mood.scaleLabel.lowercased())")
        }

        var cadence = "- Cadence: \(totalEntries) entries"
        cadence += ", journaled \(activeDaysThisWeek) of the last 7 days"
        if let since = sinceLabel { cadence += ", \(since)" }
        cadence += "."
        lines.append(cadence)

        guard !lines.isEmpty else { return "" }

        return """

        WHAT YOU ALREADY KNOW ABOUT THIS PERSON (context only — use it to make ONE
        line feel personally aware; NEVER list these facts back to them, never say
        "I notice you often…" like a profile readout. Use their own words for
        emotions where possible — their vocabulary, not generic labels):
        \(lines.joined(separator: "\n"))
        """
    }
}
