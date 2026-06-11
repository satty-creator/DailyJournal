//
//  LocalRiver.swift
//  DailyJournal
//
//  Deterministic, on-device river generation. Used as the immediate result
//  (so a river paints instantly) and as the full fallback when there's no
//  Gemini key. Mirrors the LocalAI philosophy already used for entry insights.
//

import Foundation

enum LocalRiver {

    // MARK: - Per-entry signals (heuristic)

    static func markSignals(from text: String) -> RiverMarkSignals {
        let lower = text.lowercased()
        let sentiment = LocalAI.detectSentiment(from: lower)

        // Valence from sentiment bucket.
        let valence: Int
        switch sentiment {
        case "Excited", "Happy":      valence = 2
        case "Hopeful", "Calm":       valence = 1
        case "Reflective", "Uncertain": valence = 0
        case "Frustrated", "Sad":     valence = -2
        case "Anxious":               valence = -1
        default:                      valence = 0
        }

        // Pressure / activation from demand + urgency language.
        let pressureWords  = ["behind","deadline","late","too much","everyone","need to","have to",
                              "should","busy","overwhelm","pressure","rushing","no time","stuck"]
        let calmWords      = ["quiet","slow","rest","breathe","calm","still","space","peace","enough"]
        let pressureHits   = pressureWords.filter { lower.contains($0) }.count
        let calmHits       = calmWords.filter { lower.contains($0) }.count
        let pressure       = max(0, min(5, pressureHits - (calmHits / 2)))
        let activation     = (sentiment == "Anxious" || sentiment == "Excited") ? min(5, 2 + pressureHits) : min(5, pressureHits)

        // Clarity: lower when uncertainty words present.
        let uncertain = ["don't know","not sure","confused","unclear","lost","maybe","unsure"]
        let clarity   = uncertain.contains(where: lower.contains) ? 1 : 3

        // Self-compassion: harsh vs gentle inner voice.
        let harsh  = ["i should","i'm so","i hate myself","stupid","failure","pathetic","what's wrong with me","not good enough"]
        let gentle = ["it's okay","i tried","i did my best","be kind","gentle","allowed to","proud of"]
        let selfComp = gentle.contains(where: lower.contains) ? 4 : (harsh.contains(where: lower.contains) ? 1 : 2)

        // Motifs = a few frequent non-stop words.
        let motifs = frequentWords(in: lower, limit: 4)

        // Water state + marker.
        let water: WaterState = pressure >= 4 ? .rapid : (valence <= -2 ? .deepPool : (activation >= 3 ? .choppy : .smooth))
        let marker: AppTheme.RiverMarker = {
            if selfComp >= 4 { return .glimmer }
            if pressure >= 4 { return .rapid }
            if valence <= -2 { return .pool }
            return .water
        }()

        // First emotionally-weighted sentence as the quote anchor.
        let quote = LocalAI.generateBullets(from: text).first

        return RiverMarkSignals(
            valence: valence, activation: activation, clarity: clarity,
            pressure: pressure, selfCompassion: selfComp,
            dominantEmotions: [sentiment.lowercased()],
            motifs: motifs, themes: [],
            quoteAnchor: quote,
            waterState: water, marker: marker,
            safetyLevel: PatternSafety.containsCrisisSignal(in: text) ? "high_distress" : "none"
        )
    }

    // MARK: - Window aggregation (deterministic)

    /// Builds a complete River from the marks that fall inside the window.
    /// `narrative` (optional, from Gemini) overrides text fields where present.
    static func build(
        window: RiverWindow,
        marks: [RiverMark],
        narrative: RiverNarrative? = nil
    ) -> River {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(window.rawValue - 1), to: end)!

        // Index marks by day.
        let byDay = Dictionary(grouping: marks) { cal.startOfDay(for: $0.localDate) }
        let windowMarks = marks.filter { $0.localDate >= start && $0.localDate <= end }

        // Build day segments + count returns/quiet.
        var segments: [RiverDaySegment] = []
        var quietRun = 0
        var returnCount = 0
        var quietDays = 0

        for offset in 0..<window.rawValue {
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            if let mark = byDay[day]?.first {
                let isBridge = quietRun > 0
                if isBridge { returnCount += 1 }
                let marker: AppTheme.RiverMarker = isBridge ? .bridge : mark.marker
                segments.append(RiverDaySegment(
                    date: day, hasEntry: true,
                    marker: marker, waterState: mark.waterState,
                    intensity: max(mark.pressure, abs(mark.valence) + 1),
                    valence: mark.valence,
                    tooltip: tooltip(for: mark, isBridge: isBridge)
                ))
                quietRun = 0
            } else {
                quietDays += 1
                quietRun += 1
                segments.append(RiverDaySegment(
                    date: day, hasEntry: false,
                    marker: .mist, waterState: .still,
                    intensity: 0, valence: nil,
                    tooltip: "A quiet day. The river keeps it without turning it into a failure."
                ))
            }
        }

        // Recurring words across the window.
        var wordCounts: [String: Int] = [:]
        for m in windowMarks { for w in m.motifs { wordCounts[w, default: 0] += 1 } }
        let recurring = narrative?.recurringWords ??
            wordCounts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(6).map { $0.key }

        // The bend: first-half vs second-half valence.
        let sorted = windowMarks.sorted { $0.localDate < $1.localDate }
        let mid = sorted.count / 2
        let firstHalf = sorted.prefix(mid)
        let secondHalf = sorted.suffix(sorted.count - mid)
        let v1 = avg(firstHalf.map { $0.valence })
        let v2 = avg(secondHalf.map { $0.valence })
        let bendDesc: String?
        if abs(v2 - v1) >= 0.8 {
            bendDesc = v2 > v1
                ? "The river moved from heavier water toward something a little lighter."
                : "The week deepened — the water grew heavier toward the end."
        } else {
            bendDesc = sorted.count >= 3 ? "The water held a steady course this time." : nil
        }

        // Sentence of the week: highest-pressure mark's quote.
        let sentence = sorted.max(by: { $0.pressure < $1.pressure })?.quoteAnchor

        // Sparse?
        let sparse = windowMarks.count < window.unlockThreshold

        // Titles + copy (deterministic fallbacks).
        let title = narrative?.privateTitle ?? localTitle(recurring: Array(recurring), valence: v2)
        let mainTitle = narrative?.mainCurrentTitle ?? "What kept returning"
        let mainBody = narrative?.mainCurrentBody ?? localMainCurrent(recurring: Array(recurring))
        let returnMark = narrative?.returnMark ?? (returnCount > 0
            ? "You came back \(returnCount) time\(returnCount == 1 ? "" : "s") after a quiet stretch. That return is part of the rhythm."
            : nil)
        let question = narrative?.gentleQuestion ?? localQuestion(recurring: Array(recurring))
        let interpretation = narrative?.privateInterpretation ?? (sparse
            ? "Only a few entries so far — enough for a first shape, not a full pattern. The river will say more as it fills."
            : "This wasn't a perfect window, but it had a visible rhythm: \(recurring.prefix(3).joined(separator: ", ")). \(returnCount > 0 ? "You returned after quiet days." : "You kept a steady course.")")
        let truth = narrative?.oneLineTruth ?? (returnCount > 0
            ? "The habit wasn't perfect attendance. It was return."
            : "Here is the shape your words made.")

        let shareTitle = narrative?.shareMinimal ?? "my \(window == .month ? "month" : "first") current"
        let shareCopy: [ShareStyle: String] = [
            .minimal: narrative?.shareMinimal ?? "\(shareTitle) · made with ninety",
            .poetic:  narrative?.sharePoetic  ?? localPoetic(returnCount: returnCount, hadRapids: windowMarks.contains { $0.pressure >= 4 }),
            .stats:   narrative?.shareStats   ?? "\(windowMarks.count) entries · \(quietDays) quiet · \(returnCount) returns · made with ninety"
        ]

        return River(
            window: window,
            startDate: start, endDate: end,
            entryCount: windowMarks.count,
            returnCount: returnCount,
            quietDays: quietDays,
            segments: segments,
            privateTitle: title,
            mainCurrentTitle: mainTitle,
            mainCurrentBody: mainBody,
            recurringWords: Array(recurring),
            bendFrom: narrative?.bendFrom,
            bendTo: narrative?.bendTo,
            bendDescription: narrative?.bendDescription ?? bendDesc,
            returnMark: returnMark,
            quietStretchNote: quietDays > 0 ? "\(quietDays) quiet day\(quietDays == 1 ? "" : "s"), kept as mist — not as failure." : nil,
            sentenceOfWeek: sentence,
            gentleQuestion: question,
            privateInterpretation: interpretation,
            shareTitle: shareTitle,
            shareCopy: shareCopy,
            oneLineTruth: truth,
            isSparse: sparse
        )
    }

    /// A compact text summary of marks for the aggregation prompt.
    static func marksSummary(_ marks: [RiverMark]) -> String {
        marks.sorted { $0.localDate < $1.localDate }.map { m in
            let d = m.localDate.formatted(.dateTime.month(.abbreviated).day())
            return "[\(d)] valence \(m.valence), pressure \(m.pressure), clarity \(m.clarity), self-compassion \(m.selfCompassion); motifs: \(m.motifs.joined(separator: "/")); marker: \(m.marker.rawValue)"
        }.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func tooltip(for mark: RiverMark, isBridge: Bool) -> String {
        if isBridge { return "A bridge: you came back after a quiet day. Coming back is the habit." }
        switch mark.marker {
        case .rapid:   return "Rapid: high pressure that day\(mark.motifs.isEmpty ? "." : " — \(mark.motifs.prefix(2).joined(separator: ", ")).")"
        case .glimmer: return "Glimmer: the tone softened here."
        case .pool:    return "Deep pool: a heavier entry. Open only when ready."
        case .stone:   return "Stone: a recurring theme surfaced."
        default:       return "A steady current.\(mark.motifs.isEmpty ? "" : " " + mark.motifs.prefix(2).joined(separator: ", ") + ".")"
        }
    }

    private static func localTitle(recurring: [String], valence: Double) -> String {
        if let w = recurring.first { return "The Week of \(w.capitalized)" }
        return valence < 0 ? "The Week That Asked a Lot" : "The Week You Kept Showing Up"
    }

    private static func localMainCurrent(recurring: [String]) -> String {
        guard !recurring.isEmpty else { return "A few honest minutes, returned to across the window." }
        return "This window kept circling: \(recurring.prefix(3).joined(separator: ", "))."
    }

    private static func localQuestion(recurring: [String]) -> String {
        if let w = recurring.first {
            return "What would help \"\(w)\" feel a little less heavy next time it shows up?"
        }
        return "What is one small thing next week could start with?"
    }

    private static func localPoetic(returnCount: Int, hadRapids: Bool) -> String {
        if hadRapids && returnCount > 0 { return "this week had rapids, but I came back \(returnCount == 1 ? "once" : "\(returnCount) times")" }
        if returnCount > 0 { return "there was a gap, then a bridge" }
        return "the shape my words made this week"
    }

    private static func avg(_ xs: [Int]) -> Double {
        xs.isEmpty ? 0 : Double(xs.reduce(0, +)) / Double(xs.count)
    }

    private static let stop: Set<String> = ["the","a","an","and","or","but","in","on","at","to","for","of",
        "with","i","is","it","my","me","was","be","have","had","that","this","are","not","do","did","so",
        "as","we","he","she","they","you","just","can","will","would","could","should","what","when","how",
        "why","been","from","all","by","if","about","up","out","like","im","dont","cant","feel","really",
        "very","too","even","then","there","here","more","some","into","over"]

    private static func frequentWords(in lower: String, limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for w in lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        where w.count > 3 && !stop.contains(w) {
            counts[w, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }
}
