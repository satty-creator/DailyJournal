// StylePreferences.swift
// DailyJournal
//
// Learned-preferences pattern (rosebud-teardown-mirror-redesign-2026-09-09.md
// §3.9): feedback that changes HOW Spilr writes, not just what it writes about.
// A second, separate memory from PatternHypothesis/SelfModel — style, not life
// facts. Persisted at users/{uid}/stylePreferences/current, client-owned.

import Foundation
import FirebaseFirestore

struct StylePreferences {
    /// -2...0. Lowered by "Too intense" feedback; never raised automatically
    /// (there's no opposite gesture — silence/positive feedback just doesn't
    /// lower it further).
    var sharpness: Int
    /// patternType (raw value) → muted until. Set after two consecutive soft-
    /// negative feedbacks ("Not quite"/"Not me") on the same type.
    var mutedTypes: [String: Date]
    /// patternType (raw value) → consecutive soft-negative count. Resets to 0
    /// on a positive ("This is me") and on muting.
    var softNegativeStreak: [String: Int]
    /// Free-text notes about Spilr's BEHAVIOUR ("stop asking so many
    /// questions", "be blunter") — see MirrorCorrectionClassifier. Most
    /// recent first, capped at 5. Rendered into the writer's style block
    /// server-side, sanitised through the same banned-term lint as any other
    /// user-facing text before injection.
    var notes: [String]
    var updatedAt: Date

    static let maxNotes = 5

    static let empty = StylePreferences(sharpness: 0, mutedTypes: [:], softNegativeStreak: [:], notes: [], updatedAt: Date())

    /// 14-day mute window — long enough to stop repeating something the user
    /// just told us twice was wrong, short enough that a type isn't retired
    /// forever off two data points.
    static let muteDuration: TimeInterval = 14 * 86400

    func isMuted(_ patternType: String, now: Date = Date()) -> Bool {
        guard let until = mutedTypes[patternType] else { return false }
        return until > now
    }

    init(sharpness: Int, mutedTypes: [String: Date], softNegativeStreak: [String: Int], notes: [String], updatedAt: Date) {
        self.sharpness          = sharpness
        self.mutedTypes         = mutedTypes
        self.softNegativeStreak = softNegativeStreak
        self.notes              = notes
        self.updatedAt           = updatedAt
    }

    init?(from data: [String: Any]) {
        self.sharpness = data["sharpness"] as? Int ?? 0
        self.mutedTypes = ((data["mutedTypes"] as? [String: Timestamp]) ?? [:])
            .mapValues { $0.dateValue() }
        self.softNegativeStreak = data["softNegativeStreak"] as? [String: Int] ?? [:]
        self.notes = data["notes"] as? [String] ?? []
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    func toFirestoreData() -> [String: Any] {
        [
            "sharpness":          sharpness,
            "mutedTypes":         mutedTypes.mapValues { Timestamp(date: $0) },
            "softNegativeStreak": softNegativeStreak,
            "notes":              notes,
            "updatedAt":          Timestamp(date: updatedAt)
        ]
    }
}

// MARK: - MirrorCorrectionClassifier

enum MirrorCorrectionClassifier {
    private static let styleKeywords: Set<String> = [
        "stop", "dont", "too", "less", "more", "shorter", "longer", "blunt",
        "blunter", "gentle", "gentler", "softer", "harsher", "sharper",
        "question", "questions", "advice", "bullet", "bullets", "format",
        "formatting", "tone", "direct", "hedge", "hedging"
    ]

    /// True when free-text feedback addresses SPILR's BEHAVIOUR ("stop
    /// asking so many questions", "be blunter", "no bullet points") rather
    /// than the CONTENT of a specific hypothesis ("this isn't about fear,
    /// it's about control"). Routes to StylePreferences instead of
    /// ProfileCorrection — see EvidenceDrawerView's correction submit.
    /// Short and keyword-bearing reads as a style note; a content correction
    /// is usually a longer reinterpretation with no behavioural keyword.
    static func isStyleCorrection(_ text: String) -> Bool {
        guard text.count <= 80 else { return false }
        let words = Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        return !words.isDisjoint(with: styleKeywords)
    }
}
