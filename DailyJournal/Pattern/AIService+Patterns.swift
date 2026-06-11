//
//  AIService+Patterns.swift
//  DailyJournal
//
//  Gemini-backed detection of Pattern Callbacks across a 60-day window.
//  Separate file so the core AIService (entry insights + Echo extraction) stays
//  untouched. Same URLSession + JSONSerialization approach, no SDK.
//
//  The prompt is conservative and SAFETY-FIRST: the model is told to refuse to
//  generate callbacks for crisis content and to raise a safety_flag instead.
//  PatternSafety re-checks this locally — the model is never the only guard.
//

import Foundation

// MARK: - Raw detection result (pre-scoring, pre-persistence)

/// One callback as reported by the model, before we map evidence indices to
/// real entries, score salience, or persist anything.
struct RawPatternCallback {
    let archetype: PatternArchetype
    let callbackLine: String
    let entity: String?
    /// Evidence as (entryIndex, exactQuote) pairs referring to the indexed list
    /// we sent the model.
    let evidence: [(index: Int, quote: String)]
    let confidence: Double
}

struct PatternDetectionRaw {
    /// True when the model saw self-harm / suicide / ED / substance signals.
    /// When true, callbacks MUST be ignored and the safety flow used instead.
    let safetyFlag: Bool
    let callbacks: [RawPatternCallback]
}

extension AIService {

    // MARK: - Detect callbacks

    /// Runs pattern detection over an indexed, chronological list of entries.
    /// `indexedEntries[i]` corresponds to evidence index `i` in the result.
    func detectPatterns(indexedEntries: [String]) async throws -> PatternDetectionRaw {
        guard isAIAvailable else { throw AIError.aiUnavailable }
        guard indexedEntries.count >= 6 else {
            return PatternDetectionRaw(safetyFlag: false, callbacks: [])
        }

        let prompt = buildPatternPrompt(indexedEntries: indexedEntries)
        let data = try await generate(prompt: prompt, maxTokens: 700, temperature: 0.3)
        return try parsePatternResponse(data)
    }

    // MARK: - Prompt

    private func buildPatternPrompt(indexedEntries: [String]) -> String {
        let corpus = indexedEntries.enumerated()
            .map { "[\($0.offset)] \($0.element)" }
            .joined(separator: "\n\n")

        return """
        You are a reflective pattern-detection system for a private journaling \
        app called ninety. You are given a person's journal entries from the last \
        60 days, each prefixed with an index like [0], [1], …

        Your job: find AT MOST 2 genuine patterns that span MULTIPLE entries and \
        are worth gently reflecting back. A pattern is only worth surfacing if it \
        would make the person pause and feel *seen* — not surprised by a parlour \
        trick. Most weeks there is nothing. Returning an empty list is the correct \
        and common answer.

        The six archetypes (use the exact string):
        - "entity_repetition": a specific person / place keeps recurring.
        - "emotion_repetition": the same feeling recurs across many days.
        - "avoidance": they circle a subject repeatedly without naming it.
        - "contradiction": they assert something, then later the opposite.
        - "cycle": a repeating loop over time (e.g. crash → recover → crash).
        - "resolution": a long-running difficult thread that has finally eased.

        SAFETY — this overrides everything else:
        If ANY entry contains signals of self-harm, suicidal ideation, eating \
        disorders, or substance abuse, DO NOT generate ANY callbacks. Instead set \
        "safety_flag": true and return an empty "callbacks" array. Never build a \
        pattern on top of crisis content.

        Also DO NOT generate callbacks that:
        - characterise third parties negatively ("your sister is toxic"),
        - use medical or diagnostic language ("this is depression / anxiety"),
        - give prescriptive advice ("you should leave him").

        Style of "callback_line":
        - One sentence. Observational and warm, never clinical.
        - Reflect, don't prescribe. "Marcus has come up six times this month — \
          always on a Sunday." NOT "You should talk to Marcus."
        - Reference the person's OWN words where natural.

        For each callback include 2–4 pieces of evidence. Each evidence item must \
        cite the entry "index" and an EXACT "quote" (verbatim substring, never \
        paraphrased).

        Return ONLY valid JSON of this exact shape:
        {
          "safety_flag": false,
          "callbacks": [
            {
              "archetype": "entity_repetition",
              "callback_line": "…",
              "entity": "Marcus" | null,
              "evidence": [ { "index": 3, "quote": "exact words" } ],
              "confidence": 0.0
            }
          ]
        }

        Entries:
        \"\"\"
        \(corpus)
        \"\"\"
        """
    }

    // MARK: - Parse

    private func parsePatternResponse(_ data: Data) throws -> PatternDetectionRaw {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let first   = cands.first,
            let content = first["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String,
            let json    = text.data(using: .utf8),
            let obj     = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { throw AIError.parseError }

        let safety = obj["safety_flag"] as? Bool ?? false
        if safety {
            return PatternDetectionRaw(safetyFlag: true, callbacks: [])
        }

        let rawList = obj["callbacks"] as? [[String: Any]] ?? []
        let callbacks: [RawPatternCallback] = rawList.compactMap { dict in
            guard
                let typeRaw = (dict["archetype"] as? String)?
                    .replacingOccurrences(of: "-", with: "_").lowercased(),
                let archetype = PatternArchetype(rawValue: typeRaw),
                let line = dict["callback_line"] as? String, !line.isEmpty
            else { return nil }

            let evidence: [(index: Int, quote: String)] =
                (dict["evidence"] as? [[String: Any]] ?? []).compactMap { e in
                    guard let idx = e["index"] as? Int,
                          let q = e["quote"] as? String, !q.isEmpty else { return nil }
                    return (idx, q)
                }
            guard evidence.count >= 2 else { return nil }

            let entityRaw = dict["entity"] as? String
            let entity = (entityRaw?.isEmpty == false) ? entityRaw : nil
            let confidence = dict["confidence"] as? Double ?? 0.5

            return RawPatternCallback(
                archetype:    archetype,
                callbackLine: line,
                entity:       entity,
                evidence:     evidence,
                confidence:   confidence
            )
        }

        return PatternDetectionRaw(safetyFlag: false, callbacks: callbacks)
    }
}
