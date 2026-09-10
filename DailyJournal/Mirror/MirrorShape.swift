// MirrorShape.swift
// DailyJournal
//
// The L1 card payload shape (rosebud-teardown-mirror-redesign-2026-09-09.md §3.4).
// Selected DETERMINISTICALLY from the hypothesis — never asked of the model.
// The server (functions/index.js `shapeFor`) computes the authoritative value
// and stamps it on the card as `shape`; this Swift copy is a soft-parity
// fallback for cards written before that field existed, and for deriving a
// shape client-side wherever only the hypothesis is in hand.

import Foundation

enum MirrorShape: String {
    /// One receipt: quote + date, nothing else.
    case notice
    /// One question, no receipt.
    case ask
    /// Two quotes — oldest and newest — with "N weeks apart".
    case thenNow
    /// The exception receipt + what was different.
    case softened

    /// Mirrors `shapeFor(hypothesis)` in functions/index.js. Soft parity only —
    /// `MirrorCard.shape`, when present, is authoritative; this exists to
    /// render legacy cards and to pick the fallback payload before Phase 3
    /// lands the field server-side.
    static func `for`(_ h: PatternHypothesis) -> MirrorShape {
        if h.patternType == .exception {
            return .softened
        }
        if h.patternType == .avoidedSubject || h.timesSeen < 3 {
            // Ask needs a question to ask. Without one there's nothing to
            // show for this shape — demote to Notice.
            return h.callbackQuestion != nil ? .ask : .notice
        }
        let recurring = h.patternType == .vocabularyFingerprint
            || h.patternType == .timeRhythm
            || h.patternType == .absence
            || h.timesSeen >= 5
        if recurring {
            // Then/Now needs two receipts at least a week apart. Without
            // that spread there's nothing to contrast — demote to Notice.
            return hasWeekApartEvidence(h) ? .thenNow : .notice
        }
        return .notice
    }

    private static func hasWeekApartEvidence(_ h: PatternHypothesis) -> Bool {
        guard let oldest = h.evidence.map(\.entryCreatedAt).min(),
              let newest = h.evidence.map(\.entryCreatedAt).max()
        else { return false }
        return newest.timeIntervalSince(oldest) >= 7 * 86_400
    }
}
