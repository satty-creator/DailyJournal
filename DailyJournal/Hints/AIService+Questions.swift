//
//  AIService+Questions.swift
//  DailyJournal
//
//  Gemini enrichment for the Question Bank. The local QuestionMixer always
//  produces a complete, shippable bundle instantly; this layer asks Gemini for
//  sharper, more personal questions when there's a signed-in user + network.
//
//  AI personalization trigger (PRD §23):
//   • User has completed at least 5 sessions
//   • User has at least 10 question outcomes
//   • Memory profile has meaningful recurring themes
//   • Or user manually taps "refresh my questions"
//
//  Non-negotiable prompt rules (PRD §26):
//   • Output questions only — no sentence stems, no "write 3 words"
//   • No advice, diagnosis, shame, guilt, or productivity pressure
//   • No private phrase unless personal == .me
//   • Questions must end with a question mark
//   • Questions must be answerable in 90 seconds
//   • No question exceeds 140 chars; talk questions ≤ 90 chars
//

import Foundation

extension AIService {

    // MARK: - Enrich bundle

    /// Asks Gemini to enrich the question bundle for the given context.
    /// Returns `nil` on any failure — the caller keeps the local bundle unchanged.
    func enrichQuestions(for context: QuestionContext) async -> QuestionBundle? {
        guard isAIAvailable else { return nil }

        let prompt = Self.questionPrompt(for: context)
        do {
            let data = try await generate(prompt: prompt, maxTokens: 700, temperature: 0.7)
            return try Self.parseQuestionBundle(data, context: context)
        } catch {
            return nil  // silent fallback
        }
    }

    // MARK: - Prompt

    static func questionPrompt(for context: QuestionContext) -> String {
        let pebbleLine = context.pebbles.isEmpty
            ? "(none chosen — serve the best blank-page question from the universal bank)"
            : context.pebbles.joined(separator: ", ")

        let personalRule: String
        switch context.personal {
        case .safe:
            personalRule = "Stay generic and warm. Do NOT reference private themes, specific names, or user history."
        case .light:
            personalRule = "You may use today's chosen pebbles. Do not invent personal history beyond them."
        case .me:
            personalRule = "The user opted into their own words. You may reference a confirmed user phrase (e.g. \"Sunday dread\") if it appears in the memory profile. Never invent new private themes."
        }

        return """
        \(NinetyVoice.system)

        TASK: Generate a set of QUESTIONS for a journaling app.
        The user may be staring at a blank page. Your job is to ask the kind of question
        that makes their OWN words easier to find — not to extract a confession.

        Chosen pebbles: \(pebbleLine)
        Surface: \(context.mode.rawValue.uppercased())
        Personal level: \(context.personal.rawValue) — \(personalRule)
        \(MemoryProfileService.shared.cachedPromptContext())

        NON-NEGOTIABLE RULES:
        - Output QUESTIONS ONLY. No sentence stems. No "write 3 words." No "finish this."
        - Every question ends with a question mark.
        - No advice, diagnosis, shame, guilt, nagging, or productivity pressure.
        - No fake intimacy. No over-personalization. No private phrase unless personal == "me".
        - No lock-screen-facing personal content.
        - Questions must be answerable in 90 seconds.
        - No question exceeds 140 characters.
        - Talk questions must be 90 characters or less and feel sayable in one breath.
        - Use "why" sparingly — prefer "what made that harder?" over "why did you avoid that?"

        Preferred question shapes:
        "What part of…?" / "Where did…?" / "Which felt more…?" / "What changed…?" /
        "What stayed with you…?" / "What tiny thing…?"

        Return ONLY valid JSON (no markdown, no code fences):
        {
          "starter_write": { "question": "string ≤120 chars", "category": "string", "tags": ["string"] },
          "starter_talk":  { "question": "string ≤90 chars",  "category": "string", "tags": ["string"] },
          "gentle":   [ { "question": "string", "category": "string", "tags": ["string"] }, ... ],
          "specific": [ { "question": "string", "category": "string", "tags": ["string"] }, ... ],
          "choice":   [ { "question": "string", "category": "string", "tags": ["string"] }, ... ],
          "personal_candidates": [
            { "question": "string", "category": "string", "tags": ["string"],
              "personal_level": "safe|light|me", "seed_question_ids": ["string"] }
          ]
        }

        Exactly 3 questions in each of: gentle, specific, choice.
        personal_candidates may have 0–10 entries.
        Reject any question that is demanding, preachy, diagnostic, or longer than a breath.
        """
    }

    // MARK: - Parsing

    static func parseQuestionBundle(_ data: Data, context: QuestionContext) throws -> QuestionBundle {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let content = cands.first?["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String,
            let jData   = text.data(using: .utf8),
            let json    = try? JSONSerialization.jsonObject(with: jData) as? [String: Any]
        else { throw AIError.parseError }

        // Starters
        let starterWrite = parseQuestionCard(from: json["starter_write"], lead: "Start here", source: .gemini, accent: .soft, rung: .specificQuestion)
        let starterTalk  = parseQuestionCard(from: json["starter_talk"],  lead: "Start here", source: .gemini, accent: .soft, rung: .specificQuestion)
        guard let sw = starterWrite, let st = starterTalk,
              !sw.question.isEmpty, !st.question.isEmpty
        else { throw AIError.parseError }

        // Tabs
        let gentle   = parseQuestionCards(from: json["gentle"],   lead: "Gentle question", source: .gemini, accent: .soft, rung: .gentleQuestion)
        let specific = parseQuestionCards(from: json["specific"],  lead: "Ask about today",  source: .gemini, accent: .mint, rung: .specificQuestion)
        let choice   = parseQuestionCards(from: json["choice"],    lead: "Give me a choice", source: .gemini, accent: .lav,  rung: .choiceQuestion)

        guard gentle.count == 3, specific.count == 3, choice.count == 3 else {
            throw AIError.parseError
        }

        // Personal candidates — store for later merge (not used in the bundle directly)
        if let candidateArr = json["personal_candidates"] as? [[String: Any]] {
            let candidates = candidateArr.compactMap { dict -> PersonalQuestionCandidate? in
                guard
                    let q   = dict["question"] as? String, q.hasSuffix("?"), q.count <= 140,
                    let cat = dict["category"] as? String,
                    let plv = dict["personal_level"] as? String
                else { return nil }
                let tags    = dict["tags"] as? [String] ?? []
                let seedIDs = dict["seed_question_ids"] as? [String] ?? []
                let level   = QuestionPersonal(rawValue: plv) ?? .safe
                // Reject if more personal than user allowed
                guard personalLevelAllowed(level, context: context) else { return nil }
                return PersonalQuestionCandidate(
                    question: q, category: cat, tags: tags,
                    personalLevel: level, seedQuestionIDs: seedIDs
                )
            }
            // Hand off to personalization service (fire-and-forget)
            Task.detached(priority: .background) {
                QuestionPersonalizationService.shared.merge(candidates: candidates)
            }
        }

        return QuestionBundle(
            starterWrite: sw,
            starterTalk:  st,
            gentle:       gentle,
            specific:     specific,
            choice:       choice,
            mine:         [],
            source:       "gemini"
        )
    }

    // MARK: - Helpers

    private static func parseQuestionCard(
        from raw: Any?,
        lead: String,
        source: QuestionSource,
        accent: QuestionCard.Accent,
        rung: QuestionRung
    ) -> QuestionCard? {
        guard
            let dict = raw as? [String: Any],
            let q    = (dict["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !q.isEmpty, q.hasSuffix("?"), q.count <= 140
        else { return nil }

        let cat  = QuestionCategory(rawValue: dict["category"] as? String ?? "") ?? .blank
        let tags = dict["tags"] as? [String] ?? []
        return QuestionCard(
            id: UUID().uuidString,
            lead: lead,
            question: q,
            category: cat,
            tags: tags,
            source: source,
            personalLevel: .safe,
            accent: accent,
            answerStyle: .open,
            rung: rung
        )
    }

    private static func parseQuestionCards(
        from raw: Any?,
        lead: String,
        source: QuestionSource,
        accent: QuestionCard.Accent,
        rung: QuestionRung
    ) -> [QuestionCard] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        let accents: [QuestionCard.Accent] = [accent, .mint, .lav]
        return arr.enumerated().compactMap { idx, dict in
            guard
                let q = (dict["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !q.isEmpty, q.hasSuffix("?"), q.count <= 140
            else { return nil }
            let cat  = QuestionCategory(rawValue: dict["category"] as? String ?? "") ?? .blank
            let tags = dict["tags"] as? [String] ?? []
            return QuestionCard(
                id: UUID().uuidString,
                lead: lead,
                question: q,
                category: cat,
                tags: tags,
                source: source,
                personalLevel: .safe,
                accent: accents[idx % accents.count],
                answerStyle: .open,
                rung: rung
            )
        }
    }

    private static func personalLevelAllowed(_ level: QuestionPersonal, context: QuestionContext) -> Bool {
        switch context.personal {
        case .safe:  return level == .safe
        case .light: return level == .safe || level == .light
        case .me:    return true
        }
    }
}

// MARK: - PersonalQuestionCandidate

/// Intermediate model returned by AI before validation and merge.
struct PersonalQuestionCandidate {
    let question: String
    let category: String
    let tags: [String]
    let personalLevel: QuestionPersonal
    let seedQuestionIDs: [String]
}
