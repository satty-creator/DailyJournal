//
//  PatternCallback.swift
//  DailyJournal
//
//  The Pattern Callback data model. A callback is a Co-Star-style observation
//  stitched from MULTIPLE past entries — "You keep circling back to Marcus."
//
//  This is a separate system from Echoes:
//    • Echo   = one quote from ONE entry, surfaced as a gentle reminder.
//    • Callback = a pattern across MANY entries, surfaced rarely and with weight.
//
//  Callbacks are deliberately scarce (see PatternCallbackService frequency
//  rules) and ALWAYS pass through the crisis-content safety filter before they
//  can be created (see PatternSafety). One card at a time. Always dismissable.
//

import Foundation
import FirebaseFirestore

// MARK: - Archetype

/// The six callback archetypes, ordered by intrinsic salience (most → least).
enum PatternArchetype: String, Codable, CaseIterable {
    case contradiction     = "contradiction"      // says X, then the opposite
    case avoidance         = "avoidance"          // circles a topic without naming it
    case emotionRepetition = "emotion_repetition" // same feeling, many days
    case entityRepetition  = "entity_repetition"  // same person / place recurs
    case cycle             = "cycle"              // a repeating loop over time
    case resolution        = "resolution"         // a long thread that finally eased

    /// Lowercased tag shown on the card ("a contradiction", "a pattern", …).
    var displayLabel: String {
        switch self {
        case .contradiction:     return "a contradiction"
        case .avoidance:         return "something unsaid"
        case .emotionRepetition: return "a recurring feeling"
        case .entityRepetition:  return "a recurring name"
        case .cycle:             return "a cycle"
        case .resolution:        return "a thread that eased"
        }
    }

    /// Intrinsic weight used for salience ranking. Contradiction is the most
    /// arresting; resolution is the gentlest.
    var baseSalience: Double {
        switch self {
        case .contradiction:     return 1.0
        case .avoidance:         return 0.9
        case .emotionRepetition: return 0.7
        case .entityRepetition:  return 0.6
        case .cycle:             return 0.5
        case .resolution:        return 0.4
        }
    }

    /// Which user-facing scope toggle this archetype belongs to. Used to honour
    /// the Settings "scope" preference (Names / Emotions / Cycles / Everything).
    var scope: PatternScope {
        switch self {
        case .entityRepetition:                       return .names
        case .emotionRepetition, .contradiction,
             .avoidance:                              return .emotions
        case .cycle, .resolution:                     return .cycles
        }
    }
}

// MARK: - Status

enum PatternCallbackStatus: String, Codable {
    case pending   = "pending"    // detected, not yet shown
    case shown     = "shown"      // surfaced on Home at least once
    case answered  = "answered"   // user tapped "I needed that" — strong positive signal
    case dismissed = "dismissed"  // user tapped "not now" — soft negative
    case muted     = "muted"      // user tapped "stop watching" — entity suppressed
}

// MARK: - Evidence

/// One supporting entry behind a callback. We keep the entry's own id + date so
/// the stitched view can render the originals chronologically, plus the exact
/// phrase to highlight (never paraphrased).
struct PatternEvidence: Codable, Identifiable {
    let entryId: String
    let entryCreatedAt: Date
    /// The user's exact words that the callback leans on. Highlighted in the
    /// stitched view. Never paraphrased.
    let quote: String

    var id: String { entryId }

    init(entryId: String, entryCreatedAt: Date, quote: String) {
        self.entryId        = entryId
        self.entryCreatedAt = entryCreatedAt
        self.quote          = quote
    }

    init?(from data: [String: Any]) {
        guard
            let entryId = data["entryId"] as? String,
            let created = (data["entryCreatedAt"] as? Timestamp)?.dateValue(),
            let quote   = data["quote"] as? String
        else { return nil }
        self.entryId        = entryId
        self.entryCreatedAt = created
        self.quote          = quote
    }

    func toFirestoreData() -> [String: Any] {
        [
            "entryId":        entryId,
            "entryCreatedAt": Timestamp(date: entryCreatedAt),
            "quote":          quote
        ]
    }
}

// MARK: - PatternCallback

struct PatternCallback: Identifiable, Codable {

    let id: String
    let userId: String
    let archetype: PatternArchetype
    /// The single Co-Star-style observation line shown large on the card.
    /// Reflective, never prescriptive, never diagnostic. e.g. "Marcus has come
    /// up nine times this month — always after a quiet weekend."
    let callbackLine: String
    /// The thing being watched, when there is one (a name, a place, an emotion).
    /// Drives the "stop watching [entity]" action. Nil for archetypes with no
    /// single subject.
    let entity: String?
    /// The entries this callback is stitched from (≥ 2). Chronological order is
    /// applied at render time.
    let evidence: [PatternEvidence]
    /// Computed at detection time: baseSalience × recency × feedback. Higher
    /// wins when several callbacks are pending.
    let salienceScore: Double
    var status: PatternCallbackStatus
    let createdAt: Date
    var shownAt: Date?
    var respondedAt: Date?

    // MARK: Computed

    /// Phrases to highlight inside the stitched view (the evidence quotes).
    var highlightPhrases: [String] { evidence.map(\.quote) }

    /// True when this callback is eligible to be surfaced.
    var isSurfaceable: Bool { status == .pending }

    /// A prompt seed for the "Write about it?" hand-off into a 90-second session.
    var writePrompt: String {
        if let entity { return "What's really going on with \(entity)?" }
        return callbackLine
    }

    // MARK: New-callback init

    init(
        userId: String,
        archetype: PatternArchetype,
        callbackLine: String,
        entity: String?,
        evidence: [PatternEvidence],
        salienceScore: Double
    ) {
        self.id            = UUID().uuidString
        self.userId        = userId
        self.archetype     = archetype
        self.callbackLine  = callbackLine
        self.entity        = entity
        self.evidence      = evidence
        self.salienceScore = salienceScore
        self.status        = .pending
        self.createdAt     = Date()
        self.shownAt       = nil
        self.respondedAt   = nil
    }

    // MARK: Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id            = data["id"]            as? String,
            let userId        = data["userId"]        as? String,
            let archetypeRaw  = data["archetype"]     as? String,
            let archetype     = PatternArchetype(rawValue: archetypeRaw),
            let callbackLine  = data["callbackLine"]  as? String,
            let salienceScore = data["salienceScore"] as? Double,
            let statusRaw     = data["status"]        as? String,
            let status        = PatternCallbackStatus(rawValue: statusRaw),
            let createdAt     = (data["createdAt"]    as? Timestamp)?.dateValue()
        else { return nil }

        let rawEvidence = data["evidence"] as? [[String: Any]] ?? []

        self.id            = id
        self.userId        = userId
        self.archetype     = archetype
        self.callbackLine  = callbackLine
        self.entity        = data["entity"] as? String
        self.evidence      = rawEvidence.compactMap { PatternEvidence(from: $0) }
        self.salienceScore = salienceScore
        self.status        = status
        self.createdAt     = createdAt
        self.shownAt       = (data["shownAt"]     as? Timestamp)?.dateValue()
        self.respondedAt   = (data["respondedAt"] as? Timestamp)?.dateValue()
    }

    // MARK: Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":            id,
            "userId":        userId,
            "archetype":     archetype.rawValue,
            "callbackLine":  callbackLine,
            "evidence":      evidence.map { $0.toFirestoreData() },
            "salienceScore": salienceScore,
            "status":        status.rawValue,
            "createdAt":     Timestamp(date: createdAt)
        ]
        if let entity      { data["entity"]      = entity }
        if let shownAt     { data["shownAt"]     = Timestamp(date: shownAt) }
        if let respondedAt { data["respondedAt"] = Timestamp(date: respondedAt) }
        return data
    }
}
