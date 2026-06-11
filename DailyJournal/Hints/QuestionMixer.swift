//
//  QuestionMixer.swift
//  DailyJournal
//
//  Local scoring and question selection — runs synchronously, no network, no I/O.
//  Picks the best questions from the universal bank (and optionally the personal bank)
//  using a simple scoring system before AI is involved.
//
//  Scoring philosophy (PRD §18):
//   +  matches selected pebbles
//   +  has helped the user start before (higher successScore)
//   +  fits the selected mode
//   +  has not been shown recently
//   +  adds category variety
//   +  respects the selected personal level
//   –  was dismissed
//   –  was shown recently
//   –  is more personal than the user allowed
//

import Foundation

enum QuestionMixer {

    // MARK: - Build a full local bundle

    /// Returns a complete QuestionBundle synchronously from the universal bank,
    /// scored and filtered for the given context. Safe to call on any session init.
    static func localBundle(for context: QuestionContext) -> QuestionBundle {
        let mode = context.mode
        let pebbles = context.pebbles
        let personal = context.personal
        let recentIDs = recentlyShownIDs()
        let outcomes = loadOutcomes()

        let candidates = UniversalQuestionBank.all
            .filter { $0.isSuitable(for: mode) }

        func score(_ q: UniversalQuestion) -> Double {
            var s: Double = 0
            let tagSet = Set(q.tags)
            let pebbleTags = pebbles.flatMap { QuestionBank.pebbleTagMap[$0] ?? [] }
            let pebbleTagSet = Set(pebbleTags)

            // Pebble match bonus
            if !tagSet.isDisjoint(with: pebbleTagSet) { s += 3 }

            // Category variety — give a slight boost to categories we haven't picked yet
            // (caller assembles tabs so we just score generally here)

            // Recency penalty
            if recentIDs.contains(q.id) { s -= 2 }

            // Prior success bonus
            let outcome = outcomes.filter { $0.questionID == q.id }
            let avgSuccess = outcome.isEmpty ? 0.0 : outcome.map { $0.sessionSaved ? 1.0 : 0.0 }.reduce(0, +) / Double(outcome.count)
            s += avgSuccess * 2

            // Dismissed penalty
            let dismissed = outcome.filter { $0.dismissed }.count
            s -= Double(dismissed) * 1.5

            return s
        }

        let sorted = candidates.sorted { score($0) > score($1) }

        // Starters
        let starterWriteQ = sorted.first ?? UniversalQuestionBank.blankPage[0]
        let talkCandidates = UniversalQuestionBank.all.filter { $0.isSuitable(for: .talk) }
        let sortedTalk = talkCandidates.sorted { score($0) > score($1) }
        let starterTalkQ = sortedTalk.first ?? UniversalQuestionBank.blankPage[0]

        let starterWrite = starterWriteQ.asCard(lead: "Start here", source: .localContext, accent: .soft, rung: .specificQuestion)
        let starterTalk  = starterTalkQ.asCard(lead: "Start here", source: .localContext, accent: .soft, rung: .specificQuestion)

        // Gentle tab: soft universal questions, lowest category demand
        let gentlePool = candidates
            .filter { [.blank, .body].contains($0.category) }
            .sorted { score($0) > score($1) }
        let gentle = pickDistinct(from: gentlePool, count: 3, lead: "Gentle question", source: .universal, accent: .soft, rung: .gentleQuestion)

        // Specific tab: pebble-matched questions
        let specificPool = pebbles.isEmpty
            ? sorted
            : candidates.filter { q in
                let tagSet = Set(q.tags)
                let pebbleTags = Set(pebbles.flatMap { QuestionBank.pebbleTagMap[$0] ?? [] })
                return !tagSet.isDisjoint(with: pebbleTags)
            }.sorted { score($0) > score($1) }
        let specific = pickDistinct(from: specificPool, count: 3, lead: "Ask about today", source: .localContext, accent: .mint, rung: .specificQuestion)

        // Choice tab: questions with a binary/or structure, or gentle open ones as fallback
        let choiceCards = buildChoiceCards(pebbles: pebbles, mode: mode)

        return QuestionBundle(
            starterWrite: starterWrite,
            starterTalk:  starterTalk,
            gentle:       gentle,
            specific:     specific,
            choice:       choiceCards,
            mine:         [],       // populated separately by QuestionEngine when personal bank exists
            source:       "local"
        )
    }

    // MARK: - Pick for a single rung

    /// Best question for a specific rung given the context. Used by QuestionEngine.makeEasier().
    static func rungQuestion(
        _ rung: QuestionRung,
        pebbles: [String],
        mode: QuestionMode
    ) -> QuestionCard {
        let trace = pebbles.isEmpty ? "today" : pebbles.joined(separator: " + ")

        switch rung {
        case .specificQuestion:
            let pebbleTags = Set(pebbles.flatMap { QuestionBank.pebbleTagMap[$0] ?? [] })
            let pool = UniversalQuestionBank.all.filter { q in
                q.isSuitable(for: mode) && !Set(q.tags).isDisjoint(with: pebbleTags)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.blankPage[0]
            return q.asCard(lead: "Ask about today", source: .localContext, accent: .soft, rung: rung)

        case .gentleQuestion:
            let pool = UniversalQuestionBank.all.filter {
                $0.isSuitable(for: mode) && [.blank, .body].contains($0.category)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.blankPage[0]
            return q.asCard(lead: "Gentle question", source: .universal, accent: .soft, rung: rung)

        case .choiceQuestion:
            let choices = buildChoiceCards(pebbles: pebbles, mode: mode)
            return choices.first ?? QuestionCard(
                id: "choice-fallback",
                lead: "Give me a choice",
                question: "Did today feel more rushed or more flat?",
                category: .blank,
                tags: ["blank"],
                source: .universal,
                personalLevel: .safe,
                accent: .lav,
                answerStyle: .choice,
                rung: .choiceQuestion
            )

        case .tapOnlyQuestion:
            let wordList = QuestionBank.feelingWords.joined(separator: ", ")
            return QuestionCard(
                id: "tap-only",
                lead: "Which is closest?",
                question: "Which fits better: \(wordList)?",
                category: .blank,
                tags: ["blank"],
                source: .universal,
                personalLevel: .safe,
                accent: .sun,
                answerStyle: .tapOnly,
                rung: rung
            )

        case .traceOnly:
            return QuestionCard(
                id: "trace-only",
                lead: "Trace only",
                question: "Save: \(trace)",
                category: .blank,
                tags: ["blank"],
                source: .universal,
                personalLevel: .safe,
                accent: .sun,
                answerStyle: .trace,
                rung: rung
            )

        case .blankDrop:
            return QuestionCard(
                id: "blank-drop",
                lead: "Blank drop",
                question: "Show up with nothing. The river still gets a mark.",
                category: .blank,
                tags: ["blank"],
                source: .universal,
                personalLevel: .safe,
                accent: .lav,
                answerStyle: .trace,
                rung: rung
            )
        }
    }

    // MARK: - Reroll

    /// Pick a replacement question for a given reroll style.
    static func reroll(
        style: QuestionRerollStyle,
        current: QuestionCard,
        pebbles: [String],
        mode: QuestionMode,
        excluding: [String] = []
    ) -> QuestionCard {
        let excluded = Set(excluding + [current.id])

        switch style {
        case .gentler:
            let pool = UniversalQuestionBank.all.filter {
                $0.isSuitable(for: mode) &&
                [.blank, .body].contains($0.category) &&
                !excluded.contains($0.id)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.blankPage[0]
            return q.asCard(lead: "Gentler", source: .universal, accent: .soft, rung: .gentleQuestion)

        case .moreSpecific:
            let pebbleTags = Set(pebbles.flatMap { QuestionBank.pebbleTagMap[$0] ?? [] })
            let pool = UniversalQuestionBank.all.filter {
                $0.isSuitable(for: mode) &&
                !Set($0.tags).isDisjoint(with: pebbleTags) &&
                !excluded.contains($0.id)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.work[0]
            return q.asCard(lead: "More specific", source: .localContext, accent: .mint, rung: .specificQuestion)

        case .giveChoice:
            let cards = buildChoiceCards(pebbles: pebbles, mode: mode).filter { !excluded.contains($0.id) }
            return cards.first ?? buildChoiceCards(pebbles: pebbles, mode: mode)[0]

        case .surpriseMe:
            let pool = UniversalQuestionBank.all.filter {
                $0.isSuitable(for: mode) && !excluded.contains($0.id)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.home[5]
            return q.asCard(lead: "Surprise", source: .universal, accent: .lav, rung: .specificQuestion)

        case .shorter, .easier:
            // Talk mode: pick a shorter / gentler question
            let pool = UniversalQuestionBank.all.filter {
                $0.isSuitable(for: .talk) &&
                $0.text.count < 50 &&
                !excluded.contains($0.id)
            }
            let q = pool.randomElement() ?? UniversalQuestionBank.blankPage[0]
            return q.asCard(lead: style == .shorter ? "Shorter" : "Easier", source: .universal, accent: .soft, rung: .gentleQuestion)
        }
    }

    // MARK: - Helpers

    private static func pickDistinct(
        from pool: [UniversalQuestion],
        count: Int,
        lead: String,
        source: QuestionSource,
        accent: QuestionCard.Accent,
        rung: QuestionRung
    ) -> [QuestionCard] {
        let accents: [QuestionCard.Accent] = [accent, .mint, .lav]
        var seen = Set<QuestionCategory>()
        var result: [QuestionCard] = []

        for (i, q) in pool.enumerated() {
            if result.count >= count { break }
            let a = accents[i % accents.count]
            result.append(q.asCard(lead: lead, source: source, accent: a, rung: rung))
            seen.insert(q.category)
        }

        // Pad with anything if pool was thin
        for q in UniversalQuestionBank.blankPage where result.count < count {
            let a = accents[result.count % accents.count]
            result.append(q.asCard(lead: lead, source: source, accent: a, rung: rung))
        }

        return Array(result.prefix(count))
    }

    private static func buildChoiceCards(pebbles: [String], mode: QuestionMode) -> [QuestionCard] {
        let p1 = pebbles.first ?? "heavy"
        let p2 = pebbles.dropFirst().first ?? "flat"

        let q1 = QuestionCard(
            id: "choice-\(p1)-\(p2)",
            lead: "This or that",
            question: "Did today feel more \(p1) or more \(p2)?",
            category: .blank,
            tags: ["blank"],
            source: .localContext,
            personalLevel: .safe,
            accent: .soft,
            answerStyle: .choice,
            rung: .choiceQuestion
        )
        let q2 = QuestionCard(
            id: "choice-UQ008",
            lead: "Which direction?",
            question: "Where did the day slow down for you?",
            category: .blank,
            tags: ["blank"],
            source: .universal,
            personalLevel: .safe,
            accent: .mint,
            answerStyle: .choice,
            rung: .choiceQuestion
        )
        let q3 = QuestionCard(
            id: "choice-taponly",
            lead: "Which is closest?",
            question: "Which fits better: flat, loud, heavy, quiet, fizzy?",
            category: .blank,
            tags: ["blank"],
            source: .universal,
            personalLevel: .safe,
            accent: .lav,
            answerStyle: .tapOnly,
            rung: .tapOnlyQuestion
        )
        return [q1, q2, q3]
    }

    // MARK: - Persistence helpers

    private static let outcomesKey = "questionOutcomes"
    private static let recentKey = "recentlyShownQuestionIDs"

    static func recordOutcome(_ outcome: QuestionOutcome) {
        var outcomes = loadOutcomes()
        // Keep a rolling window of 200 outcomes
        outcomes.append(outcome)
        if outcomes.count > 200 { outcomes = Array(outcomes.suffix(200)) }
        if let data = try? JSONEncoder().encode(outcomes) {
            UserDefaults.standard.set(data, forKey: outcomesKey)
        }

        // Track recently shown for recency penalty
        var recent = recentlyShownIDs()
        recent.insert(outcome.questionID)
        // Keep a window of 10 to avoid complete repetition
        if recent.count > 10 { recent = Set(Array(recent).suffix(10)) }
        UserDefaults.standard.set(Array(recent), forKey: recentKey)
    }

    static func loadOutcomes() -> [QuestionOutcome] {
        guard
            let data = UserDefaults.standard.data(forKey: outcomesKey),
            let outcomes = try? JSONDecoder().decode([QuestionOutcome].self, from: data)
        else { return [] }
        return outcomes
    }

    private static func recentlyShownIDs() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        return Set(arr)
    }
}
