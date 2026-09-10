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
}
