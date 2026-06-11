//
//  RiverMark.swift
//  DailyJournal
//
//  A RiverMark is the *derived* per-entry signal that feeds the river. The raw
//  journal entry stays sacred and untouched; the mark is a separate, versioned
//  object so it can be regenerated or deleted independently.
//
//  Stored at users/{uid}/riverMarks/{entryId}. We key it on the entry id so a
//  mark always 1:1 maps to its entry and re-generation overwrites cleanly.
//

import Foundation
import FirebaseFirestore

// MARK: - Water state (cute-but-semantic visual hint)

enum WaterState: String, Codable {
    case still, smooth, choppy, rapid, deepPool = "deep_pool"
}

// MARK: - RiverMark

struct RiverMark: Identifiable {

    /// Same id as the source entry — one mark per entry.
    let id: String
    let userId: String
    let entryId: String
    /// Local calendar day of the entry (start-of-day) for windowing.
    let localDate: Date

    // ── Derived emotional signals (the river is built from these, not mood alone) ──
    /// -3 very negative … +3 very positive
    let valence: Int
    /// 0 very calm … 5 highly activated
    let activation: Int
    /// 0 unclear/confused … 5 very clear
    let clarity: Int
    /// 0 no pressure … 5 intense pressure
    let pressure: Int
    /// 0 harsh/self-critical … 5 warm/self-compassionate
    let selfCompassion: Int

    // ── Language-derived meaning ─────────────────────────────────────────
    let dominantEmotions: [String]
    let motifs: [String]              // recurring words / images
    let themes: [String]              // short theme labels
    /// A short, exact phrase from the entry. Private — never in share copy.
    let quoteAnchor: String?

    // ── Visual hint + safety ─────────────────────────────────────────────
    let waterState: WaterState
    /// The dominant marker for this day's segment.
    let marker: AppTheme.RiverMarker
    /// "none" unless a safety signal was detected, in which case the river
    /// pipeline backs off and the existing PatternSafety/resource flow takes over.
    let safetyLevel: String

    // ── Provenance ───────────────────────────────────────────────────────
    let source: String                // "gemini" | "local"
    let promptVersion: String
    let createdAt: Date

    // MARK: - New init
    init(
        entryId: String,
        userId: String,
        localDate: Date,
        valence: Int,
        activation: Int,
        clarity: Int,
        pressure: Int,
        selfCompassion: Int,
        dominantEmotions: [String],
        motifs: [String],
        themes: [String],
        quoteAnchor: String?,
        waterState: WaterState,
        marker: AppTheme.RiverMarker,
        safetyLevel: String = "none",
        source: String,
        promptVersion: String = RiverMark.currentPromptVersion
    ) {
        self.id               = entryId
        self.userId           = userId
        self.entryId          = entryId
        self.localDate        = Calendar.current.startOfDay(for: localDate)
        self.valence          = valence.clamped(to: -3...3)
        self.activation       = activation.clamped(to: 0...5)
        self.clarity          = clarity.clamped(to: 0...5)
        self.pressure         = pressure.clamped(to: 0...5)
        self.selfCompassion   = selfCompassion.clamped(to: 0...5)
        self.dominantEmotions = dominantEmotions
        self.motifs           = motifs
        self.themes           = themes
        self.quoteAnchor      = quoteAnchor
        self.waterState       = waterState
        self.marker           = marker
        self.safetyLevel      = safetyLevel
        self.source           = source
        self.promptVersion    = promptVersion
        self.createdAt        = Date()
    }

    static let currentPromptVersion = "river_mark_v1"

    // MARK: - Firestore deserialisation
    init?(from data: [String: Any]) {
        guard
            let id        = data["id"]        as? String,
            let userId    = data["userId"]    as? String,
            let entryId   = data["entryId"]   as? String,
            let localDate = (data["localDate"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id               = id
        self.userId           = userId
        self.entryId          = entryId
        self.localDate        = localDate
        self.valence          = data["valence"]        as? Int ?? 0
        self.activation       = data["activation"]     as? Int ?? 0
        self.clarity          = data["clarity"]        as? Int ?? 2
        self.pressure         = data["pressure"]       as? Int ?? 0
        self.selfCompassion   = data["selfCompassion"] as? Int ?? 2
        self.dominantEmotions = data["dominantEmotions"] as? [String] ?? []
        self.motifs           = data["motifs"]           as? [String] ?? []
        self.themes           = data["themes"]           as? [String] ?? []
        self.quoteAnchor      = data["quoteAnchor"]      as? String
        self.waterState       = WaterState(rawValue: data["waterState"] as? String ?? "") ?? .smooth
        self.marker           = AppTheme.RiverMarker(rawValue: data["marker"] as? String ?? "") ?? .water
        self.safetyLevel      = data["safetyLevel"]    as? String ?? "none"
        self.source           = data["source"]         as? String ?? "local"
        self.promptVersion    = data["promptVersion"]  as? String ?? "unknown"
        self.createdAt        = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    // MARK: - Firestore serialisation
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":               id,
            "userId":           userId,
            "entryId":          entryId,
            "localDate":        Timestamp(date: localDate),
            "valence":          valence,
            "activation":       activation,
            "clarity":          clarity,
            "pressure":         pressure,
            "selfCompassion":   selfCompassion,
            "dominantEmotions": dominantEmotions,
            "motifs":           motifs,
            "themes":           themes,
            "waterState":       waterState.rawValue,
            "marker":           marker.rawValue,
            "safetyLevel":      safetyLevel,
            "source":           source,
            "promptVersion":    promptVersion,
            "createdAt":        Timestamp(date: createdAt)
        ]
        if let q = quoteAnchor { data["quoteAnchor"] = q }
        return data
    }
}

// MARK: - Small numeric helper
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
