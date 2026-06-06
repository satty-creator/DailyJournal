//
//  LocalPatternDetector.swift
//  DailyJournal
//
//  A modest, on-device fallback for Pattern detection when no Gemini key is set.
//  It only attempts the two archetypes that are reliable without an LLM:
//    • entity_repetition — a capitalised name recurring across ≥ 3 entries.
//    • emotion_repetition — the same saved sentiment label recurring ≥ 4 times.
//
//  It deliberately does NOT attempt contradiction / avoidance / cycle /
//  resolution — those need real language understanding, and a wrong guess there
//  is worse than silence. Output is shaped exactly like the LLM path so the rest
//  of the pipeline is identical.
//
//  This never sees crisis content untreated: PatternDetectionService runs the
//  PatternSafety corpus gate BEFORE calling this, and re-checks every quote.
//

import Foundation

enum LocalPatternDetector {

    static func detect(in entries: [JournalEntry]) -> PatternDetectionRaw {
        var callbacks: [RawPatternCallback] = []

        if let entity = detectEntityRepetition(entries) { callbacks.append(entity) }
        if let emotion = detectEmotionRepetition(entries) { callbacks.append(emotion) }

        return PatternDetectionRaw(safetyFlag: false, callbacks: callbacks)
    }

    // MARK: - Entity repetition

    private static let nameStopwords: Set<String> = [
        "the", "and", "but", "for", "with", "this", "that", "today",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
        "i", "i'm", "i'll", "i've", "im", "it", "its", "im", "ok", "okay"
    ]

    private static func detectEntityRepetition(_ entries: [JournalEntry]) -> RawPatternCallback? {
        // Map candidate name → the indices of entries it appears in.
        var hits: [String: Set<Int>] = [:]

        for (idx, entry) in entries.enumerated() {
            for token in candidateNames(in: entry.content) {
                hits[token, default: []].insert(idx)
            }
        }

        // Pick the name appearing in the most distinct entries (≥ 3).
        let ranked = hits
            .filter { $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
        guard let top = ranked.first else { return nil }

        let name = top.key
        let entryIdxs = top.value.sorted().prefix(4)

        let evidence: [(index: Int, quote: String)] = entryIdxs.compactMap { i in
            guard let q = quoteContaining(name, in: entries[i].content) else { return nil }
            return (i, q)
        }
        guard evidence.count >= 2 else { return nil }

        let display = name.prefix(1).uppercased() + String(name.dropFirst())
        let line = "\(display) has come up across \(top.value.count) of your recent entries."

        return RawPatternCallback(
            archetype:    .entityRepetition,
            callbackLine: line,
            entity:       display,
            evidence:     evidence,
            confidence:   0.55
        )
    }

    /// Capitalised, alphabetic tokens mid-sentence that look like names.
    private static func candidateNames(in text: String) -> Set<String> {
        var result: Set<String> = []
        let words = text.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        for (i, word) in words.enumerated() {
            guard i > 0 else { continue }                 // skip sentence-initial caps
            let w = String(word)
            guard w.count >= 3, let f = w.first, f.isUppercase else { continue }
            let lower = w.lowercased()
            guard !nameStopwords.contains(lower) else { continue }
            // Reject ALL-CAPS shouting and words with internal capitals.
            guard w != w.uppercased() else { continue }
            result.insert(lower)
        }
        return result
    }

    /// A short verbatim window around the first occurrence of `name`.
    /// Searches `text` directly (case-insensitive) so the indices are valid for
    /// `text` — never mix indices across two different String instances.
    private static func quoteContaining(_ name: String, in text: String) -> String? {
        guard let range = text.range(of: name, options: .caseInsensitive) else { return nil }
        let start = text.index(range.lowerBound,
                               offsetBy: -30,
                               limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound,
                             offsetBy: 30,
                             limitedBy: text.endIndex) ?? text.endIndex
        let slice = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return slice.isEmpty ? nil : slice
    }

    // MARK: - Emotion repetition (via saved sentiment labels)

    private static func detectEmotionRepetition(_ entries: [JournalEntry]) -> RawPatternCallback? {
        var byLabel: [String: [Int]] = [:]
        for (idx, entry) in entries.enumerated() {
            guard let label = entry.sentimentLabel, !label.isEmpty else { continue }
            byLabel[label, default: []].append(idx)
        }

        let ranked = byLabel
            .filter { $0.value.count >= 4 }
            .sorted { $0.value.count > $1.value.count }
        guard let top = ranked.first else { return nil }

        let label = top.key
        let idxs = top.value.suffix(4)
        let evidence: [(index: Int, quote: String)] = idxs.compactMap { i in
            let snippet = String(entries[i].content.prefix(60))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return snippet.isEmpty ? nil : (i, snippet)
        }
        guard evidence.count >= 2 else { return nil }

        let line = "\(label) keeps surfacing — \(top.value.count) entries carried it lately."
        return RawPatternCallback(
            archetype:    .emotionRepetition,
            callbackLine: line,
            entity:       label,
            evidence:     evidence,
            confidence:   0.5
        )
    }
}
