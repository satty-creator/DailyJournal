//
//  PatternTypes.swift
//  DailyJournal
//
//  Shared types for the pattern-recognition system. The Pattern Callback
//  engine that originally defined these (a Co-Star-style observation stitched
//  from multiple entries, surfaced on Home) was cut — superseded by Pattern
//  Hypothesis / Mirror, which does the same job scored and typed and was
//  already the one actually shipping (see PATTERNS_MERGE_PLAN.md). These three
//  types survive because PatternHypothesis and the Mirror stack
//  (SelfModelService, MirrorGraphService, EvidenceDrawerView, MirrorView,
//  AIService+Mirror) still depend on them.
//

import Foundation
import FirebaseFirestore

// MARK: - Archetype

/// Ordered by intrinsic salience (most → least) when a hypothesis is one of these.
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
}

// MARK: - Status

enum PatternCallbackStatus: String, Codable {
    case pending   = "pending"    // detected, not yet shown
    case shown     = "shown"      // surfaced at least once
    case answered  = "answered"   // user gave a strong positive signal
    case dismissed = "dismissed"  // user tapped "not now" — soft negative
    case muted     = "muted"      // suppressed (entity or thread muted)

    /// The thread is resolved and must never be raised again. Distinct from
    /// `dismissed` (a soft "not now") and `muted` (suppress the entity). This
    /// is the *forget* affordance, and it is the thing that makes long memory
    /// tolerable rather than persecutory: an app that remembers everything and
    /// lets go of nothing keeps handing the user back a version of themselves
    /// they have already outgrown.
    case closed    = "closed"
}

// MARK: - Evidence

/// One supporting entry behind a hypothesis. Keeps the entry's own id + date so
/// the evidence drawer can render the originals chronologically, plus the exact
/// phrase to highlight (never paraphrased).
struct PatternEvidence: Codable, Identifiable {
    let entryId: String
    let entryCreatedAt: Date
    /// The user's exact words the hypothesis leans on. Never paraphrased.
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
