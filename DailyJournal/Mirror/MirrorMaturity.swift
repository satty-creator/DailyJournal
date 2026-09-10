//
//  MirrorMaturity.swift
//  DailyJournal
//
//  Gates which Mirror features are available based on how many entries the user has.
//

import Foundation

enum MirrorMaturity: Int, Comparable {
    case seed    = 0
    case first   = 1   // 1–2 entries  → light single-entry mirror
    case soft    = 3   // 3–6 entries  → soft pattern, hedged
    case unlock  = 7   // 7–13 entries → First Sketch ceremony
    case deeper  = 14  // 14–29        → deeper pattern
    case monthly = 30  // 30–89        → monthly mirror
    case rhythm  = 90  // 90+          → identity/rhythm insights

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    static func current(totalEntries: Int) -> MirrorMaturity {
        switch totalEntries {
        case 0:        return .seed
        case 1..<3:    return .first
        case 3..<7:    return .soft
        case 7..<14:   return .unlock
        case 14..<30:  return .deeper
        case 30..<90:  return .monthly
        default:       return .rhythm
        }
    }

    var canShowDailyMirror:    Bool { self >= .first   }
    var canShowFirstSketch:    Bool { self >= .unlock  }

    /// A thread needs the same thing on three different days plus a contrast
    /// set, which is not reachable much before this (§7).
    var canShowThreads:        Bool { self >= .unlock  }
    /// "What follows what" needs a baseline. At 7 entries the arrows are noise
    /// presented as signal — the exact failure in the 9 Sept screenshots.
    var canShowLagObservations: Bool { self >= .deeper }
    var canShowShifting:       Bool { self >= .deeper  }
}

// MARK: - Unlock ladder

/// "Tell the user what would unlock the next thing" (PRD §7, principle 7, R9).
///
/// PARITY: `functions/lib/facts.js` — `LADDER` and `unlockStateFor`. The server
/// computes the authoritative hint nightly into `derived/facts.unlock`; this
/// table is the fallback for a user whose FactsJob has not run yet (a brand-new
/// account, or the window between first entry and first nightly pass). Keep the
/// two in step: a hint that promises a different threshold than the one the
/// server is actually gating on is worse than no hint.
enum UnlockLadder {

    struct Step {
        let atEntries: Int
        let unlocks: String
    }

    static let steps: [Step] = [
        Step(atEntries: 1,  unlocks: "strip"),
        Step(atEntries: 3,  unlocks: "observations"),
        Step(atEntries: 7,  unlocks: "firstSeven"),
        Step(atEntries: 10, unlocks: "threads"),
        Step(atEntries: 14, unlocks: "lag"),
        Step(atEntries: 30, unlocks: "monthly"),
    ]

    /// The local fallback hint. Prefer `facts.unlock.hint` whenever the derived
    /// doc is present — the server can see band coverage and can therefore say
    /// "one entry at a different time of day", which this cannot.
    static func hint(totalEntries: Int) -> String? {
        guard let next = steps.first(where: { $0.atEntries > totalEntries }) else { return nil }
        let need = next.atEntries - totalEntries
        let entries = need == 1 ? "1 more entry" : "\(need) more entries"
        switch next.unlocks {
        case "observations": return "\(entries) and Spilr can compare days."
        case "firstSeven":   return "\(entries) and Spilr can show you your first seven."
        case "threads":      return "\(entries) and a thread can form."
        case "lag":          return "\(entries) and Spilr can look at what follows what."
        case "monthly":      return "\(entries) and Spilr can look at a whole month."
        default:             return "\(entries) to go."
        }
    }
}
