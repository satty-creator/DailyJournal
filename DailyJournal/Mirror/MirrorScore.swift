//
//  MirrorScore.swift
//  DailyJournal
//
//  Deterministic scorer that ranks pattern hypotheses.
//  The LLM proposes; the device disposes.
//

import Foundation

struct MirrorScore {

    /// Score a PatternHypothesis. Higher = more likely to surface as Today's Mirror.
    /// Floor is 0. No ceiling, but typical range is 0–4.
    static func score(for h: PatternHypothesis) -> Double {
        let evidenceStrength = min(1.0, Double(h.evidence.count) / 4.0)
        let seenBonus = min(1.0, Double(h.timesSeen) / 5.0)
        let positive = h.emotionalWeight
                     + h.noveltyScore
                     + h.actionabilityScore
                     + evidenceStrength
                     + seenBonus * 0.5
        let negative = h.shameRisk + h.diagnosticRisk + repetitionFatigue(h)
        return max(0, positive - negative)
    }

    private static func repetitionFatigue(_ h: PatternHypothesis) -> Double {
        guard let shown = h.shownAt else { return 0 }
        let daysSince = Date().timeIntervalSince(shown) / 86400
        if daysSince < 1 { return 1.0 }
        if daysSince < 3 { return 0.5 }
        if daysSince < 7 { return 0.2 }
        return 0
    }
}
