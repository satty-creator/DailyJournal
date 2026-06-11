//
//  AIService+River.swift
//  DailyJournal
//
//  Gemini prompts for the River system. Two passes:
//
//   1. extractRiverMarkSignals  — per entry: structured emotional signals.
//   2. generateRiverNarrative   — per window: the human, specific summary text.
//
//  Both prompts are intentionally strict: non-clinical, evidence-grounded,
//  no advice, missed days treated neutrally. A specificity gate lives inside
//  the aggregation prompt so the model rejects its own generic output.
//
//  If the API key is missing or any call fails, callers fall back to LocalRiver.
//

import Foundation

// MARK: - Parsed signal payloads

/// Raw signals for one entry. RiverService wraps this into a RiverMark by
/// attaching the entry id + date.
struct RiverMarkSignals {
    let valence: Int
    let activation: Int
    let clarity: Int
    let pressure: Int
    let selfCompassion: Int
    let dominantEmotions: [String]
    let motifs: [String]
    let themes: [String]
    let quoteAnchor: String?
    let waterState: WaterState
    let marker: AppTheme.RiverMarker
    let safetyLevel: String
}

/// AI-written narrative for a window. All optional so the service can fall
/// back to LocalRiver field-by-field.
struct RiverNarrative {
    var privateTitle: String?
    var mainCurrentTitle: String?
    var mainCurrentBody: String?
    var recurringWords: [String]?
    var bendFrom: String?
    var bendTo: String?
    var bendDescription: String?
    var returnMark: String?
    var gentleQuestion: String?
    var privateInterpretation: String?
    var oneLineTruth: String?
    var shareMinimal: String?
    var sharePoetic: String?
    var shareStats: String?
}

extension AIService {

    // MARK: - 1. Per-entry mark extraction

    func extractRiverMarkSignals(from entryText: String) async throws -> RiverMarkSignals {
        guard isAIAvailable else { throw AIError.aiUnavailable }
        guard entryText.count > 20 else { throw AIError.textTooShort }

        let prompt = Self.riverMarkPrompt(entryText: entryText)
        // Conservative — these are measurements, not prose.
        let data = try await generate(prompt: prompt, maxTokens: 400, temperature: 0.2)
        return try Self.parseRiverMark(data)
    }

    // MARK: - 2. Window aggregation narrative

    func generateRiverNarrative(
        window: RiverWindow,
        marksSummary: String,
        recurringWords: [String]
    ) async throws -> RiverNarrative {
        guard isAIAvailable else { throw AIError.aiUnavailable }

        let prompt = Self.riverNarrativePrompt(
            window: window,
            marksSummary: marksSummary,
            recurringWords: recurringWords
        )
        // A little warmth for the prose.
        let data = try await generate(prompt: prompt, maxTokens: 700, temperature: 0.6)
        return try Self.parseRiverNarrative(data)
    }

    // MARK: - Prompts

    static func riverMarkPrompt(entryText: String) -> String {
        """
        You are the river-mark extraction engine for ninety, a private journaling app.
        You convert ONE journal entry into grounded, non-clinical emotional signals.
        These signals later render as a flowing "river" the user reads back.

        Hard rules:
        - You are NOT a therapist. Do not diagnose, label disorders, or use clinical
          terms unless the user used them first.
        - Be specific to THIS entry. Use the user's own words for motifs and the quote.
        - Do not give advice. Do not moralise. Do not exaggerate certainty.
        - If the entry is very short, keep signals modest — do not invent depth.
        - If the entry contains possible self-harm, suicide, eating-disorder, or
          substance-abuse content, set safety_level accordingly and STOP analysing tone.
        - Return ONLY valid JSON. No markdown, no code fences.

        Scoring scales:
        - valence:         -3 (very negative) … +3 (very positive)
        - activation:       0 (very calm) … 5 (highly activated / racing)
        - clarity:          0 (confused) … 5 (very clear)
        - pressure:         0 (no pressure) … 5 (intense demand / heaviness)
        - self_compassion:  0 (harsh self-talk) … 5 (warm / gentle to self)

        water_state: one of "still" | "smooth" | "choppy" | "rapid" | "deep_pool"
          (deep_pool = emotionally heavy/dense, rapid = high pressure/urgency)
        marker: one of "water" | "mist" | "bridge" | "glimmer" | "stone" | "rapid" | "pool" | "fork"
          (glimmer = a moment of softness/relief/hope; fork = ambivalence/competing wants;
           pick the single most fitting one for this entry)
        safety_level: "none" | "mild_distress" | "high_distress" | "possible_self_harm" | "imminent_danger"

        Schema:
        {
          "valence": int, "activation": int, "clarity": int,
          "pressure": int, "self_compassion": int,
          "dominant_emotions": [string],   // 1-3, plain words
          "motifs": [string],              // 1-4 recurring words/images, the user's language
          "themes": [string],              // 0-3 short theme labels e.g. "wanting quiet"
          "quote_anchor": string,          // ONE short exact phrase from the entry
          "water_state": string,
          "marker": string,
          "safety_level": string
        }

        Entry:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    static func riverNarrativePrompt(
        window: RiverWindow,
        marksSummary: String,
        recurringWords: [String]
    ) -> String {
        """
        \(NinetyVoice.system)

        TASK: write the river narrative for a \(window.rawValue)-day window, built from
        signals already extracted from the user's own entries.

        The north star: the user should read this and think "that is weirdly me,"
        NOT "this app made a nice wellness graphic."

        INTERPRET, DON'T DESCRIBE. A description lists what happened ("you wrote about
        work three times"). An interpretation says what it MEANS ("work only showed up
        on the days you also mentioned not sleeping — it reads less like ambition and
        more like a place the worry goes to land"). Reach for the higher-value moves:
          • AVOIDANCE   — a theme that was loud early and then went silent. Name it.
          • CONTRADICTION — a topic whose mood is consistently heavier than the words admit.
          • THE BEND     — don't just state from→to; say what the movement reveals.
        Only claim a pattern you can ground in the signals below.

        Hard rules:
        - Do not diagnose. Do not claim causation ("because"). Use "appeared with",
          "tended to", "showed up alongside", "seems".
        - Do not give advice or wellness clichés. BANNED words/phrases unless the user
          used them: "self-care", "growth journey", "embrace", "resilience",
          "unlock your potential", "practice gratitude", "mindfulness".
        - Anchor every claim in the recurring words / motifs / movement provided below.
        - Missed / quiet days are described neutrally or warmly, NEVER as failure.
        - Returns after a gap are a positive part of the rhythm, not a broken streak.
        - share_* fields are PUBLIC: no raw quotes, no names, no sensitive theme labels.
        - private_* fields may use a short exact quote.
        - If the data is thin, say so plainly and keep claims tentative.
        - Return ONLY valid JSON. No markdown.

        SPECIFICITY GATE — before returning, silently check your own output and rewrite
        anything that (a) could apply to almost anyone, (b) gives advice, (c) diagnoses,
        or (d) is not grounded in the provided evidence. Only return output that passes.

        Titles must come from the user's actual language. Good: "The Week You Wanted
        Quiet". Bad: "A Reflective Week", "Your Emotional Journey".

        Recurring words across the window: \(recurringWords.isEmpty ? "(none strong enough)" : recurringWords.joined(separator: ", "))

        Per-day signal summary (oldest → newest):
        \(marksSummary)

        Schema:
        {
          "private_title": string,
          "main_current_title": string,
          "main_current_body": string,         // 1-2 sentences, specific
          "recurring_words": [string],         // 3-6, the user's words
          "bend_from": string,                 // short phrase, e.g. "I'm behind"
          "bend_to": string,                   // short phrase, e.g. "I need quiet"
          "bend_description": string,          // 1 sentence on the emotional movement
          "return_mark": string,               // warm note about returning after gaps, or ""
          "gentle_question": string,           // ONE question grounded in their words
          "private_interpretation": string,    // 2-3 sentences, may include a short quote
          "one_line_truth": string,            // a single resonant line about the window
          "share_minimal": string,             // e.g. "my first current"
          "share_poetic": string,              // e.g. "this week had rapids, but I came back twice"
          "share_stats": string                // e.g. "4 entries · 3 quiet days · 2 returns"
        }
        """
    }

    // MARK: - Parsing

    private static func unwrap(_ data: Data) -> [String: Any]? {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let content = cands.first?["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String,
            let jData   = text.data(using: .utf8),
            let json    = try? JSONSerialization.jsonObject(with: jData) as? [String: Any]
        else { return nil }
        return json
    }

    private static func parseRiverMark(_ data: Data) throws -> RiverMarkSignals {
        guard let j = unwrap(data) else { throw AIError.parseError }
        return RiverMarkSignals(
            valence:          j["valence"]         as? Int ?? 0,
            activation:       j["activation"]      as? Int ?? 0,
            clarity:          j["clarity"]         as? Int ?? 2,
            pressure:         j["pressure"]        as? Int ?? 0,
            selfCompassion:   j["self_compassion"] as? Int ?? 2,
            dominantEmotions: j["dominant_emotions"] as? [String] ?? [],
            motifs:           j["motifs"]          as? [String] ?? [],
            themes:           j["themes"]          as? [String] ?? [],
            quoteAnchor:      j["quote_anchor"]    as? String,
            waterState:       WaterState(rawValue: (j["water_state"] as? String) ?? "") ?? .smooth,
            marker:           AppTheme.RiverMarker(rawValue: (j["marker"] as? String) ?? "") ?? .water,
            safetyLevel:      j["safety_level"]    as? String ?? "none"
        )
    }

    private static func parseRiverNarrative(_ data: Data) throws -> RiverNarrative {
        guard let j = unwrap(data) else { throw AIError.parseError }
        return RiverNarrative(
            privateTitle:          j["private_title"]          as? String,
            mainCurrentTitle:      j["main_current_title"]     as? String,
            mainCurrentBody:       j["main_current_body"]      as? String,
            recurringWords:        j["recurring_words"]        as? [String],
            bendFrom:              j["bend_from"]              as? String,
            bendTo:                j["bend_to"]                as? String,
            bendDescription:       j["bend_description"]       as? String,
            returnMark:            j["return_mark"]            as? String,
            gentleQuestion:        j["gentle_question"]        as? String,
            privateInterpretation: j["private_interpretation"] as? String,
            oneLineTruth:          j["one_line_truth"]         as? String,
            shareMinimal:          j["share_minimal"]          as? String,
            sharePoetic:           j["share_poetic"]           as? String,
            shareStats:            j["share_stats"]            as? String
        )
    }
}
