//
//  AIService+Hints.swift
//  DailyJournal
//
//  Gemini enrichment for the Hint Ladder. The local `HintLadder` engine always
//  produces a complete, shippable bundle instantly; this layer asks Gemini for
//  sharper, more personal phrasing when there's a signed-in user + network.
//
//  Everything here degrades silently: any missing key, network failure, parse
//  error, or safety trip returns the local bundle unchanged. A hint is never
//  worth blocking the user over.
//
//  Hard guarantees enforced in the prompt:
//   • Hints never shame, nag, diagnose, or give advice.
//   • Talk hints are "say one sentence" sized — never "talk for 90 seconds".
//   • The ladder only gets SMALLER, never more demanding.
//   • No personal theme is emitted unless the user opted into "my words", and
//     even then it stays in-app (the bundle is never used lock-screen facing).
//

import Foundation

// MARK: - Context

/// The user's chosen direction for the day. Drives both the local engine and the
/// Gemini prompt. Kept tiny on purpose — the whole point is "no big question".
struct HintContext: Equatable {
    var pebbles: [String]
    var personal: HintPersonal
    var mode: HintMode

    init(pebbles: [String] = [], personal: HintPersonal = .safe, mode: HintMode = .write) {
        self.pebbles  = Array(pebbles.prefix(HintLadder.maxPebbles))
        self.personal = personal
        self.mode     = mode
    }

    /// The local bundle for this context — the always-available baseline.
    var localBundle: HintBundle {
        HintLadder.localBundle(pebbles: pebbles, personal: personal)
    }
}

extension AIService {

    // MARK: - Enrich

    /// Asks Gemini to rewrite the hint bundle in ninety's voice, grounded in the
    /// chosen pebbles. Returns `nil` (not an error) whenever we should just keep
    /// the local bundle — the caller treats nil as "no change".
    func enrichHints(for context: HintContext) async -> HintBundle? {
        guard isAIAvailable else { return nil }

        let prompt = Self.hintPrompt(for: context)
        do {
            // A touch more warmth/variety than a pure scaffold — we want starters
            // that feel specific and a little probing, not template-y. Still bounded
            // by the hard safety rules in the prompt.
            let data = try await generate(prompt: prompt, maxTokens: 600, temperature: 0.7)
            return try Self.parseHintBundle(data)
        } catch {
            return nil   // silent fallback to local
        }
    }

    // MARK: - Prompt

    static func hintPrompt(for context: HintContext) -> String {
        let pebbleLine = context.pebbles.isEmpty
            ? "(none chosen — this is the open blank page. Do NOT play it safe with a vague \"how are you?\". Pick ONE concrete, slightly probing angle into today and commit to it.)"
            : context.pebbles.joined(separator: ", ")

        // Only let the model reach for confirmed personal phrasing at the "me" level.
        let personalRule: String
        switch context.personal {
        case .safe:
            personalRule = "Stay generic but warm. Do NOT reference anything that sounds like a private, specific theme."
        case .light:
            personalRule = "You may lean on today's pebbles. Do not invent personal history beyond them."
        case .me:
            personalRule = "The user opted into their own words; you may use a chosen pebble phrase verbatim (e.g. \"Sunday dread\"). Never invent new private themes."
        }

        return """
        \(NinetyVoice.system)

        TASK: write a HINT LADDER for a journaling app. The user feels blank and chose
        a tiny bit of context. Your job is to make the FIRST THREE SECONDS easier — never
        to extract a confession. These are optional scaffolds, not prompts to "go deep".

        Chosen pebbles (the direction of their day): \(pebbleLine)
        Surface they're on: \(context.mode.rawValue.uppercased())   // "write" or "talk"
        Personal level: \(context.personal.rawValue) — \(personalRule)
        \(MemoryProfileService.shared.cachedPromptContext())

        VOICE: specific and a little probing beats safe and generic. Name the ACTUAL tension
        a person with these pebbles might be sitting in. A direct, slightly uncomfortable
        question ("What did you let slide today that you'll pay for tomorrow?") is far better
        than a soft, forgettable one ("How are you feeling?"). Concrete nouns, real friction,
        a pointed angle. Earn the user's honesty — don't beg for it.

        NON-NEGOTIABLE RULES (these override the voice above if they ever conflict):
        - Directness is welcome; cruelty is not. Never shame, nag, guilt, diagnose, label
          ("you're anxious"), or give advice ("you should…"). Probe, don't prescribe.
        - Hints only ever get SMALLER, never more demanding. "Make it smaller", never "try harder".
        - TALK hints must be sentence-sized: "Say one sentence", "Start with: Today was mostly…".
          NEVER ask the user to "talk for 90 seconds" or record a full entry. A single sentence counts.
        - Keep every hint short and answerable in one breath. A stem ("The part I keep dodging is…")
          or 3 words beats a paragraph. Sharp and short, not long and heavy.
        - This output is shown IN-APP only, but write it as if it must never embarrass anyone.

        Produce, as JSON:
        {
          "starter_write": string,   // ONE specific, probing starter question grounded in the pebbles. Concrete, a little pointed, not generic (max ~120 chars)
          "starter_talk":  string,   // ONE say-able starter, sentence-sized (max ~90 chars)
          "tiny":     [ {"lead": string, "text": string}, ... ],  // EXACTLY 3, the gentlest rung: 3 words / a stem / one word
          "specific": [ {"lead": string, "text": string}, ... ],  // EXACTLY 3, leaning on the pebbles, slightly sharper
          "choice":   [ {"lead": string, "text": string}, ... ]   // EXACTLY 3, tap-not-compose: this-or-that, say-it-badly, trace-only
        }

        "lead" is a tiny label (e.g. "Write 3 words", "Finish this", "This or that").
        "text" is the usable fragment the user taps to drop into their entry.
        For TALK mode, phrase leads as "Say …" not "Write …".

        Before returning, silently delete any hint that is demanding, preachy, diagnostic,
        or longer than a breath. Return ONLY valid JSON — no markdown, no code fences.
        """
    }

    // MARK: - Parsing

    private static func parseHintBundle(_ data: Data) throws -> HintBundle {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let content = cands.first?["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String,
            let jData   = text.data(using: .utf8),
            let json    = try? JSONSerialization.jsonObject(with: jData) as? [String: Any]
        else { throw AIError.parseError }

        let starterWrite = (json["starter_write"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let starterTalk  = (json["starter_talk"]  as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let tiny     = cards(from: json["tiny"],     defaultRung: .threeWords)
        let specific = cards(from: json["specific"], defaultRung: .specificPrompt)
        let choice   = cards(from: json["choice"],   defaultRung: .thisOrThat)

        // Reject a thin / malformed response — caller falls back to local.
        guard !starterWrite.isEmpty, !starterTalk.isEmpty,
              tiny.count == 3, specific.count == 3, choice.count == 3 else {
            throw AIError.parseError
        }

        return HintBundle(
            starterWrite: starterWrite,
            starterTalk:  starterTalk,
            tiny:         tiny,
            specific:     specific,
            choice:       choice,
            source:       "gemini"
        )
    }

    /// Maps Gemini's `[{lead, text}]` array into HintCards, cycling a small accent
    /// palette so the panel stays visually varied.
    private static func cards(from raw: Any?, defaultRung: HintRung) -> [HintCard] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        let accents: [HintCard.Accent] = [.soft, .mint, .lav, .sun]
        return arr.enumerated().compactMap { idx, dict in
            guard
                let lead = (dict["lead"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let text = (dict["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !lead.isEmpty, !text.isEmpty
            else { return nil }
            return HintCard(lead: lead, text: text, accent: accents[idx % accents.count], rung: defaultRung)
        }
    }
}
