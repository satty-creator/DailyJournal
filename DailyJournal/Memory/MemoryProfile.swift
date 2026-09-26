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
        /// How many ENTRIES mention this word — not how many times it was typed.
        /// A lifetime token count read as "work (12)" implies twelve occasions;
        /// twelve mentions in one long entry is a very different fact.
        let count: Int
        var id: String { word }
    }

    /// A phrase inferred from how the person writes, with how often it was seen.
    /// The count travels with the phrase because these are the weakest things in
    /// this struct: without it, one sentence and forty read identically.
    struct Signal: Codable, Equatable, Identifiable {
        let text: String
        let count: Int
        var id: String { text }
    }

    /// Meaningful words the person keeps returning to (most frequent first).
    var recurringThemes: [Theme]
    /// Names / places / subjects that recur (from pattern callbacks + tags).
    var recurringEntities: [String]
    /// The person's own non-standard emotional vocabulary — words like "wired",
    /// "spiralling", "numb", "flat" that they use instead of the standard labels.
    /// These are injected into prompts so the AI mirrors their language back.
    var emotionalVocabulary: [Theme]
    /// Observed coping signals: short phrases like "walks help" / "screens make
    /// it worse" extracted from the person's own entries.
    var copingPatterns: [Signal]
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

    // MARK: - Items (what the person can see and forget)

    enum ItemKind: String, Codable, CaseIterable {
        case theme, entity, vocabulary, coping, moment

        var sectionTitle: String {
            switch self {
            case .theme:      return "Words you keep coming back to"
            case .entity:     return "Names and places"
            case .vocabulary: return "Words you use for how you feel"
            case .coping:     return "What seems to help, or not"
            case .moment:     return "Moments it kept"
            }
        }

        /// Said plainly, because the honest answer differs by kind: two of these
        /// are counts, one is a list the person typed, and two are guesses.
        var provenance: String {
            switch self {
            case .theme:      return "Counted from your entries."
            case .entity:     return "From the tags you added."
            case .vocabulary: return "Words that followed “I feel” in your writing."
            case .coping:     return "Guessed from how a sentence was worded."
            case .moment:     return "Pulled from a single entry."
            }
        }
    }

    struct Item: Identifiable {
        let kind: ItemKind
        let text: String
        /// nil where a count would be meaningless (a tag, a one-off moment).
        let count: Int?
        /// Stable across rebuilds, so forgetting something makes it stay gone.
        var id: String { "\(kind.rawValue):\(text.lowercased())" }
    }

    /// Everything this profile would tell the model, in the order the screen
    /// shows it. The suppression list in `MemoryProfileService` is keyed on
    /// `Item.id`, so this is also the definition of what can be forgotten.
    var items: [Item] {
        recurringThemes.map     { Item(kind: .theme,      text: $0.word, count: $0.count) }
        + recurringEntities.map { Item(kind: .entity,     text: $0,      count: nil) }
        + emotionalVocabulary.map { Item(kind: .vocabulary, text: $0.word, count: $0.count) }
        + copingPatterns.map    { Item(kind: .coping,     text: $0.text, count: $0.count) }
        + notableMoments.map    { Item(kind: .moment,     text: $0,      count: nil) }
    }

    /// Drops whatever the person asked this to forget. Applied after composing
    /// rather than during: `compose` is deterministic over the whole corpus, so
    /// without this every rebuild would quietly resurrect the thing they removed.
    func removing(_ suppressed: Set<String>) -> MemoryProfile {
        guard !suppressed.isEmpty else { return self }
        func keep(_ kind: ItemKind, _ text: String) -> Bool {
            !suppressed.contains(Item(kind: kind, text: text, count: nil).id)
        }
        var copy = self
        copy.recurringThemes     = recurringThemes.filter     { keep(.theme, $0.word) }
        copy.recurringEntities   = recurringEntities.filter   { keep(.entity, $0) }
        copy.emotionalVocabulary = emotionalVocabulary.filter { keep(.vocabulary, $0.word) }
        copy.copingPatterns      = copingPatterns.filter      { keep(.coping, $0.text) }
        copy.notableMoments      = notableMoments.filter      { keep(.moment, $0) }
        return copy
    }

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
                .map { "\($0.word) (in \($0.count) entries)" }
                .joined(separator: ", ")
            lines.append("- Themes they keep returning to: \(themes)")
        }
        if !recurringEntities.isEmpty {
            lines.append("- Tags they have used more than once: \(recurringEntities.prefix(5).joined(separator: ", "))")
        }
        // Emotional vocabulary — their actual words, with how often each appeared.
        if !emotionalVocabulary.isEmpty {
            let vocab = emotionalVocabulary.prefix(6)
                .map { "\($0.word) (\($0.count)×)" }
                .joined(separator: ", ")
            lines.append("- Words they reached for after \"I feel\": \(vocab). Prefer one of"
                + " these over a standard label WHEN IT FITS what they wrote today.")
        }
        // The weakest line in the block, and the only one that reads as a claim
        // about what works for someone — so it says outright that it is a guess.
        if !copingPatterns.isEmpty {
            let coping = copingPatterns.prefix(4)
                .map { "\($0.text) (\($0.count)×)" }
                .joined(separator: "; ")
            lines.append("- Guessed from their wording, NOT established: \(coping)."
                + " Never state one of these back as fact.")
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

        let asOf = generatedAt.formatted(.dateTime.month(.abbreviated).day())

        return """

        WHAT YOU ALREADY KNOW ABOUT THIS PERSON (counted from their own writing,
        as of \(asOf)). Every line below is a TALLY or a GUESS, never a verified
        fact about them, and the counts are there so you can tell a one-off from
        a habit — weight them accordingly. Use this to make ONE line feel
        personally aware; NEVER list these back to them, never say "I notice you
        often…" like a profile readout:
        \(lines.joined(separator: "\n"))
        """
    }
}
