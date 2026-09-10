// MirrorText.swift
// DailyJournal
//
// Deterministic text-overlap helpers for the client-side half of the novelty
// gate (rosebud-teardown-mirror-redesign-2026-09-09.md §3.8). Deliberately a
// SEPARATE, independent implementation from the JS `contentWords`/`jaccard`
// pair in functions/index.js — not a cross-language parity point the way
// MirrorScore/MirrorMaturity are. The server applies its own evidence-subset
// gate against data only it has (recent `mirrorShown` docs + entryAnalyses);
// this runs the client's own 14-day check against the SAME `mirrorShown`
// history but from the angle only the client can see — which of the
// server's up-to-3 cards was actually DISPLAYED.

import Foundation

enum MirrorText {

    /// Small, generic stopword list — not required to match the server's.
    private static let stopwords: Set<String> = [
        "this", "that", "with", "have", "from", "were", "been", "your", "their",
        "there", "about", "into", "just", "like", "really", "would", "could",
        "should", "when", "what", "them", "then", "than", "over", "want", "know",
        "feel", "felt", "think", "thing", "things", "time", "today", "week",
        "going", "getting", "make", "made", "back", "does", "doing"
    ]

    /// Lowercased, diacritic-folded content words ≥4 letters, stopwords dropped.
    static func contentWords(_ text: String) -> Set<String> {
        let folded = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(words.filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    /// 0 when either set is empty (nothing to compare — never a false "repeat").
    static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// "12 Aug" from "2026-08-12". Deliberately not a DateFormatter round-trip:
    /// these keys are already in the USER's local calendar (the server built
    /// them in their timezone), so re-parsing them as instants would shift
    /// them back into the device's timezone and could move the date by a day.
    /// Moved here from MirrorThread.swift (retired with the v3.0 Threads
    /// section) since ProofSheetView needs it independent of that type.
    static func shortDate(_ key: String) -> String? {
        guard key.count >= 10 else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthIndex = Int(key.dropFirst(5).prefix(2)) ?? 0
        let day = Int(key.dropFirst(8).prefix(2)) ?? 0
        guard monthIndex >= 1, monthIndex <= 12, day >= 1 else { return nil }
        return "\(day) \(months[monthIndex - 1])"
    }

    /// Moved here from ThisWeekStripView.swift (retired along with the v3.0
    /// "This week, in your words" strip) since ProofSheetView needs it
    /// independent of that view.
    static func bandPhrase(_ band: String) -> String {
        switch band {
        case "morning":   return "before noon"
        case "afternoon": return "in the afternoon"
        case "evening":   return "in the evening"
        case "late":      return "after 9pm"
        default:          return band
        }
    }
}
