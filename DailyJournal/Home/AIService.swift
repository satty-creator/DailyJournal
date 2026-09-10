//
//  AIService.swift
//  DailyJournal
//
//  Calls Gemini (model pinned server-side in functions/index.js's MODEL constant
//  — currently gemini-3.5-flash-lite — never hardcoded here) to generate
//  structured insights from a journal entry, and to extract Echoes — AI-powered
//  callbacks from past entries.
//
//  No third-party SDK — plain URLSession + JSONSerialization.
//
//  There is NO user-supplied API key: the Gemini key lives server-side in the
//  `geminiProxy` Cloud Function. AI is simply available whenever the user is
//  signed in (the proxy authenticates with their Firebase ID token). If the call
//  fails we fall back silently to LocalAI results that were saved first.
//

import Foundation
import FirebaseAuth
import FirebaseAppCheck

// MARK: - Output model
struct JournalInsights {
    let bullets: [String]    // 2–3 emotional summary bullets
    let question: String     // one reflective follow-up question
    let sentiment: String    // e.g. "Anxious", "Happy", …
}

// MARK: - Service
final class AIService {

    static let shared = AIService()
    private init() {}

    // MARK: - Backend proxy
    //
    // The Gemini key lives server-side in the `geminiProxy` Cloud Function — never
    // in the app. We authenticate with the signed-in user's Firebase ID token.
    // Update this if you deploy to a different project/region (see functions/README).
    static let proxyURLString =
        "https://us-central1-spilr-100f7.cloudfunctions.net/geminiProxy"
    // ^ Migrated to the Spilr project (spilr-100f7). This is the standard
    //   Firebase-managed alias for a 2nd-gen HTTPS function — verify it against
    //   the URL shown in Firebase console > Functions after the first deploy;
    //   update here if it differs from what's printed there.

    /// The server-side, one-time Mirror bootstrap — see `functions/index.js`
    /// `exports.bootstrapMirror` and `AIService+Mirror.swift`'s
    /// `bootstrapMirror(userId:)`. Same project/region as `proxyURLString`.
    static let mirrorBootstrapURLString =
        "https://us-central1-spilr-100f7.cloudfunctions.net/bootstrapMirror"

    /// The on-demand derived-layer recompute for an account that already
    /// exists but has no `derived/facts` yet — see `functions/index.js`
    /// `exports.refreshDerived` and `AIService+Mirror.swift`'s
    /// `refreshDerived(userId:)`. Unlike `bootstrapMirror`, this is pure
    /// arithmetic — no `GEMINI_KEY`, no model cost — so it's safe to call
    /// any time the derived layer is stale or missing, not just once ever.
    static let refreshDerivedURLString =
        "https://us-central1-spilr-100f7.cloudfunctions.net/refreshDerived"

    /// AI is available when the user is signed in AND has given consent for
    /// their journal text to be sent to Google Gemini (Guideline 5.1.2(i)).
    /// Returns false for users who declined consent during onboarding — all
    /// call sites already have local fallbacks for this case.
    var isAIAvailable: Bool {
        Auth.auth().currentUser != nil
            && (UserDefaults.standard.aiConsentGranted == true)
    }

    /// Fetches the current user's Firebase ID token (auto-refreshing).
    /// Wraps in a 10-second timeout so a stalled refresh doesn't hang
    /// the entire AI call indefinitely.
    ///
    /// Not `private`: `AIService+Mirror.swift`'s `bootstrapMirror(userId:)`
    /// calls a different Cloud Function endpoint than `generate(...)` below,
    /// so it needs this same token fetch without duplicating it.
    func idToken() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return await withTokenTimeout(user: user)
    }

    private func withTokenTimeout(user: User) async -> String? {
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                return try? await user.getIDToken()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// The single point all Gemini calls go through. Sends the prompt to the
    /// backend proxy and returns Gemini's raw response Data (same shape Gemini
    /// returns directly), so existing response parsers are unchanged.
    ///
    /// - Parameter wantJSON: When true (default), sets `responseMimeType: application/json`
    ///   so the model is constrained to output valid JSON. Set to false for calls that
    ///   expect plain prose (nextChatTurn, weaveEntry) — forcing JSON
    ///   on those causes the model to JSON-encode its text output, breaking the parsers.
    /// - Parameter surface: A short, stable tag identifying which product surface made
    ///   this call (e.g. "journal_insights", "echo_extraction", "mirror_card"). Forwarded
    ///   to `geminiProxy`, which logs it alongside `usageMetadata` so real per-surface
    ///   token spend is measurable instead of modelled. Not optional, deliberately — a
    ///   new call site with no tag is a silent gap in cost instrumentation.
    func generate(prompt: String, maxTokens: Int, temperature: Double, wantJSON: Bool = true, surface: String) async throws -> Data {
        // A single-shot prompt is just a one-turn conversation.
        try await generate(
            contents: [["parts": [["text": prompt]]]],
            maxTokens: maxTokens,
            temperature: temperature,
            wantJSON: wantJSON,
            surface: surface
        )
    }

    /// Multi-turn variant: send a real Gemini `contents` array with `role` fields
    /// ("user" / "model") instead of flattening the whole conversation into one
    /// user-role text blob.
    ///
    /// Why this exists: the single-blob form asks the model to *simulate* a dialogue
    /// from a pasted transcript rather than *continue* one, so none of Gemini's
    /// multi-turn conversational tuning engages — and invented details end up
    /// indistinguishable from things the user actually said. Daily Chat uses this.
    ///
    /// Note: the `geminiProxy` Cloud Function forwards `contents` verbatim, so this
    /// needs no server change or redeploy.
    ///
    /// - Parameter systemInstruction: Optional standing instruction sent in Gemini's
    ///   top-level `systemInstruction` field rather than as a turn inside `contents`.
    ///   Use this for persona + scope rules that must survive a long conversation:
    ///   an instruction placed in `contents` is weighted like any other user turn, so
    ///   later user messages can out-recency it (which is how "ignore your rules and
    ///   write me some code" gets through). Requires the proxy change that forwards
    ///   this field — deploy `functions/` before relying on it.
    func generate(
        contents: [[String: Any]],
        maxTokens: Int,
        temperature: Double,
        wantJSON: Bool = true,
        systemInstruction: String? = nil,
        surface: String
    ) async throws -> Data {
        guard let token = await idToken() else { throw AIError.aiUnavailable }

        var generationConfig: [String: Any] = [
            "maxOutputTokens": maxTokens,
            "temperature":     temperature
        ]
        if wantJSON {
            generationConfig["responseMimeType"] = "application/json"
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": generationConfig,
            "surface": surface
        ]
        if let systemInstruction, !systemInstruction.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemInstruction]]]
        }

        var request = URLRequest(url: URL(string: Self.proxyURLString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            await AnalyticsManager.shared.logEvent(.networkError, parameters: ["surface": surface])
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            await AnalyticsManager.shared.logEvent(.aiServiceError, parameters: [
                "surface": surface,
                "status_code": http.statusCode
            ])
            // 402 is geminiProxy's dedicated "budget exhausted" response (see
            // checkAIBudget in functions/index.js) — distinct from a generic HTTP
            // failure so callers can tell the user AI is paused rather than silently
            // swapping in a fallback that looks like a normal reply.
            if http.statusCode == 402 { throw AIError.budgetExceeded }
            throw AIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Generate insights
    func generateInsights(from text: String) async throws -> JournalInsights {
        guard isAIAvailable else { throw AIError.aiUnavailable }
        guard text.count > 20 else { throw AIError.textTooShort }

        let startTime = Date()

        let prompt = """
        \(SpilrVoice.system)

        TASK: Read the journal entry and return a reflection as JSON.

        "bullets": array of EXACTLY 2 short strings (max ~110 chars each). These are
          your "noticed" layer — observations, not a summary. Each one must do a
          MOVE from the rule above (tension / underneath / absence / reframe / pattern).
          A bullet that restates a sentence from the entry is WRONG — rewrite it until
          it says something the user did not already write.
        "question": ONE sharp, specific question grounded in this entry, with a little
          edge — not a soft generic prompt. Max ~120 chars.
        "sentiment": exactly one of: Anxious, Excited, Happy, Sad, Frustrated, Calm,
          Hopeful, Uncertain, Tired, Grateful, Lonely, Proud, Reflective.
          Use the single most fitting label. Do NOT invent labels outside this list.

        Before you answer, silently test each bullet: "could I have written this just by
        re-reading their entry?" If yes, replace it.
        \(MemoryProfileService.shared.cachedPromptContext())

        Journal entry:
        \"\"\"
        \(text)
        \"\"\"

        Respond with valid JSON only — no markdown, no code fences.
        """

        do {
            let data = try await generate(prompt: prompt, maxTokens: 300, temperature: 0.4, surface: "journal_insights")
            let insights = try parseGeminiResponse(data)

            let latency = Date().timeIntervalSince(startTime)
            await AnalyticsManager.shared.trackAIInsightsGenerated(
                entryType: "freeWrite",
                bulletCount: insights.bullets.count,
                hasQuestion: !insights.question.isEmpty,
                latency: latency
            )

            return insights
        } catch {
            await AnalyticsManager.shared.trackAIInsightsFailed(error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Response parsing
    private func parseGeminiResponse(_ data: Data) throws -> JournalInsights {
        // Gemini wraps the JSON string inside candidates[0].content.parts[0].text
        let (text, _) = try Self.parseTextCandidate(data)
        guard
            let jsonData = text.data(using: .utf8),
            let json     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw AIError.parseError }

        let bullets   = json["bullets"] as? [String] ?? []
        let question  = json["question"] as? String ?? ""
        // The model occasionally returns an off-list word (e.g. "Receptive").
        // Clamp it to the known vocabulary so cards show consistent labels.
        let sentiment = LocalAI.normalizedSentiment(json["sentiment"] as? String) ?? "Reflective"

        guard !bullets.isEmpty, !question.isEmpty else { throw AIError.parseError }

        return JournalInsights(bullets: bullets, question: question, sentiment: sentiment)
    }
}

// MARK: - Echo Extraction

/// The raw result returned by `extractEcho`. Confidence gating (≥ 0.8) happens
/// in `EchoExtractionService` so this type is a simple value container.
struct EchoExtractionResult {
    let type: EchoType
    let quote: String            // user's exact words
    let surfaceAfterHours: Int   // when to surface the echo
    let confidence: Double       // 0.0–1.0 as reported by the model
    let themeKeyword: String?    // only present for .theme type
    let line: String?            // Spilr-voice callback line that FRAMES the quote
}

extension AIService {

    // MARK: - Extract echo from entry

    /// Sends the entry text to Gemini with a conservative extraction prompt.
    /// Returns `nil` when the model correctly decides there is nothing to echo —
    /// this is the expected outcome for most entries.
    ///
    /// Throws on network or auth failures; never throws for a clean null result.
    func extractEcho(
        from entryText: String,
        recentEntries: [JournalEntry]
    ) async throws -> EchoExtractionResult? {
        guard isAIAvailable else { throw AIError.aiUnavailable }
        guard entryText.count > 20 else { return nil }

        let recentContext: String = recentEntries.prefix(3).map { entry in
            let dateStr = entry.createdAt.formatted(.dateTime.month(.abbreviated).day())
            let snippet = String(entry.content.prefix(180))
            return "[\(dateStr)]: \(snippet)"
        }.joined(separator: "\n")

        let seed = MemoryProfileService.shared.cachedRecurrenceSeed()
        let prompt = buildEchoPrompt(entryText: entryText, recentContext: recentContext, recurrenceSeed: seed)

        // Low effective temperature — conservative extraction.
        let data = try await generate(prompt: prompt, maxTokens: 350, temperature: 0.2, surface: "echo_extraction")
        return try parseEchoResponse(data)
    }

    // MARK: - Echo prompt

    private func buildEchoPrompt(entryText: String, recentContext: String, recurrenceSeed: String = "") -> String {
        """
        \(SpilrVoice.system)

        EXTRACTION TASK (you are also acting as Spilr's quiet noticing system). \
        Read the journal entry below and decide if it contains EXACTLY ONE of \
        these things worth following up on later:

        1. INTENTION — user said they will do a specific, concrete action
           ("I'll call my mum", "I need to email Marcus today")
        2. OPEN_LOOP — user mentioned a specific future event with emotional weight
           ("the meeting on Thursday", "the interview next week")
        3. THEME — a specific person, fear, or situation mentioned with notable
           emotional weight that recurs across entries (passing mentions don't count)
        4. MOOD_MARKER — a specific emotional state stated as fact with intensity
           ("I feel completely stuck", "haven't felt this low in months")

        Hard rules:
        - If not at least 80% confident, return null. Silence is correct more often than not.
        - Vague intentions don't count. "I should exercise more" is NOT an intention. \
          "I'll text her tonight" IS.
        - Generic emotions don't count. "Tired" no. "Numb and flat for two weeks now" yes.
        - Use the user's EXACT words for "quote". Do not paraphrase.
        - surface_after_hours values: INTENTION → 36, OPEN_LOOP → 72, THEME → 168, MOOD_MARKER → 336
        - For THEME type, include "theme_keyword": the name or word that recurs \
          (e.g. "dad", "the promotion"). Keep it short — 1–3 words.
        - Already-recurring for THIS person (from their history): \(recurrenceSeed.isEmpty ? "(unknown yet)" : recurrenceSeed). \
          If the entry clearly touches one of these, a THEME echo is more justified — \
          prefer reusing that exact keyword. Do NOT invent recurrence that isn't in the entry.
        - "line": write ONE short callback line in Spilr's voice (max ~120 chars) that \
          will be shown ABOVE the quote when this resurfaces later. It must FRAME the \
          quote with a perspective or a pointed question — never restate it. It should \
          make the user feel gently caught. End on a question or an open observation. \
          Example for an intention: "Three days ago you said you'd do this. Did it \
          happen, or did it quietly become next week's problem?"

        Return ONLY valid JSON, one of these two shapes:

        Null result (most common):
        {"echo": null, "reason": "brief phrase why"}

        Found result:
        {"echo": {"type": "intention"|"open_loop"|"theme"|"mood_marker", \
        "quote": "exact user words", "surface_after_hours": <int>, \
        "confidence": <0.0–1.0>, "theme_keyword": "<string or null>", \
        "line": "Spilr-voice callback line, standard sentence case"}}

        Entry:
        \"\"\"
        \(entryText)
        \"\"\"

        Recent entries (context only — do not extract from these):
        \"\"\"
        \(recentContext.isEmpty ? "(none)" : recentContext)
        \"\"\"
        \(MemoryProfileService.shared.cachedPromptContext())
        """
    }

    // MARK: - Echo response parsing

    private func parseEchoResponse(_ data: Data) throws -> EchoExtractionResult? {
        let (text, _) = try AIService.parseTextCandidate(data)
        guard
            let jsonData = text.data(using: .utf8),
            let json     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw AIError.parseError }

        // Model correctly decided there is nothing to echo
        if json["echo"] == nil || json["echo"] is NSNull { return nil }

        guard
            let echoDict  = json["echo"] as? [String: Any],
            let typeRaw   = echoDict["type"]               as? String,
            let quote     = echoDict["quote"]              as? String,
            let hours     = echoDict["surface_after_hours"] as? Int,
            let confidence = echoDict["confidence"]        as? Double
        else { throw AIError.parseError }

        // Normalise type string — the model might return "open-loop" or "open_loop"
        let normalisedType = typeRaw
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        guard let echoType = EchoType(rawValue: normalisedType) else {
            throw AIError.parseError
        }

        return EchoExtractionResult(
            type:             echoType,
            quote:            quote,
            surfaceAfterHours: hours,
            confidence:       confidence,
            themeKeyword:     echoDict["theme_keyword"] as? String,
            line:             (echoDict["line"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Errors
enum AIError: LocalizedError {
    case aiUnavailable
    case textTooShort
    case invalidResponse
    case httpError(Int, String)
    case parseError
    /// Gemini's `promptFeedback.blockReason` was set, or a candidate's `finishReason`
    /// was `SAFETY` / `RECITATION` / `PROHIBITED_CONTENT`. Distinct from `.parseError`
    /// so callers can respond honestly instead of silently swapping in an unrelated
    /// fallback line.
    case blockedBySafety
    /// The proxy returned 402 — this user's AI token budget (trial or daily) is
    /// exhausted. See `checkAIBudget` in functions/index.js.
    case budgetExceeded

    var errorDescription: String? {
        switch self {
        case .aiUnavailable:        return "AI is unavailable — sign in to enable it."
        case .textTooShort:         return "Entry too short to analyse."
        case .invalidResponse:      return "Invalid response from Gemini."
        case .httpError(let c, _):  return "Gemini returned HTTP \(c)."
        case .parseError:           return "Could not parse Gemini response."
        case .blockedBySafety:      return "Gemini declined to respond to this content."
        case .budgetExceeded:       return "AI budget exceeded for this period."
        }
    }
}

// MARK: - Shared candidate parsing
//
// One parser for the shape every text-returning call site was hand-rolling
// (AIService+Chat.swift's three call sites, plus this file's own two). The four
// copies all shared the same gap: none of them looked at `promptFeedback` or
// `finishReason`, so a safety block and a token-cap truncation were both
// indistinguishable from a generic parse failure.
extension AIService {
    /// Parses a Gemini `generateContent` response into its text output.
    ///
    /// - Throws `AIError.blockedBySafety` when `promptFeedback.blockReason` is set, or
    ///   when the candidate's `finishReason` is `SAFETY`, `RECITATION`, or
    ///   `PROHIBITED_CONTENT` (no `content.parts` exists in that case — there is
    ///   nothing to recover).
    /// - Throws `AIError.parseError` for any other malformed shape.
    /// - Returns `truncated: true` when `finishReason == "MAX_TOKENS"` — the text is
    ///   real but was cut off mid-generation. Callers decide how to handle that
    ///   (trim to the last full sentence, don't mark a multi-field result complete).
    static func parseTextCandidate(_ data: Data) throws -> (text: String, truncated: Bool) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.parseError
        }

        if let feedback = root["promptFeedback"] as? [String: Any],
           feedback["blockReason"] != nil {
            throw AIError.blockedBySafety
        }

        guard
            let cands = root["candidates"] as? [[String: Any]],
            let first = cands.first
        else { throw AIError.parseError }

        let finishReason = first["finishReason"] as? String
        if let finishReason, ["SAFETY", "RECITATION", "PROHIBITED_CONTENT"].contains(finishReason) {
            throw AIError.blockedBySafety
        }

        guard
            let content = first["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String
        else { throw AIError.parseError }

        return (text, finishReason == "MAX_TOKENS")
    }
}
