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
}
