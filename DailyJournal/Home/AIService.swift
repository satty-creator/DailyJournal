//
//  AIService.swift
//  DailyJournal
//
//  Calls Gemini 2.0 Flash (free tier) to generate structured insights from a
//  journal entry, and to extract Echoes — AI-powered callbacks from past entries.
//
//  No third-party SDK — plain URLSession + JSONSerialization.
//
//  API key is stored in UserDefaults and entered once in Profile → Settings.
//  If the key is absent or the call fails we fall back silently to LocalAI
//  results that were saved first.
//

import Foundation

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

    // MARK: - API key (stored in UserDefaults)
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_api_key") }
    }

    var hasApiKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Generate insights
    func generateInsights(from text: String) async throws -> JournalInsights {
        guard hasApiKey else { throw AIError.noApiKey }
        guard text.count > 20 else { throw AIError.textTooShort }

        let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        )!

        let prompt = """
        You are a compassionate journaling assistant. Analyze this journal entry and respond with a JSON object.

        Rules:
        - "bullets": array of exactly 2-3 short strings (max 80 chars each) capturing the core emotional themes
        - "question": one warm, reflective follow-up question (max 100 chars)
        - "sentiment": exactly one of: Anxious, Excited, Happy, Sad, Frustrated, Calm, Hopeful, Uncertain, Reflective

        Journal entry:
        \(text)

        Respond with valid JSON only — no markdown, no code fences.
        """

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 300,
                "temperature": 0.4
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, body)
        }

        return try parseGeminiResponse(data)
    }

    // MARK: - Response parsing
    private func parseGeminiResponse(_ data: Data) throws -> JournalInsights {
        // Gemini wraps the JSON string inside candidates[0].content.parts[0].text
        guard
            let root     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands    = root["candidates"] as? [[String: Any]],
            let first    = cands.first,
            let content  = first["content"] as? [String: Any],
            let parts    = content["parts"] as? [[String: Any]],
            let text     = parts.first?["text"] as? String,
            let jsonData = text.data(using: .utf8),
            let json     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw AIError.parseError }

        let bullets   = json["bullets"] as? [String] ?? []
        let question  = json["question"] as? String ?? ""
        let sentiment = json["sentiment"] as? String ?? "Reflective"

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
        guard hasApiKey else { throw AIError.noApiKey }
        guard entryText.count > 20 else { return nil }

        let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        )!

        let recentContext: String = recentEntries.prefix(3).map { entry in
            let dateStr = entry.createdAt.formatted(.dateTime.month(.abbreviated).day())
            let snippet = String(entry.content.prefix(180))
            return "[\(dateStr)]: \(snippet)"
        }.joined(separator: "\n")

        let prompt = buildEchoPrompt(entryText: entryText, recentContext: recentContext)

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens":  350,
                "temperature":      0.2   // low temperature — conservative extraction
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, body)
        }

        return try parseEchoResponse(data)
    }

    // MARK: - Echo prompt

    private func buildEchoPrompt(entryText: String, recentContext: String) -> String {
        """
        You are an extraction system for a journaling app called ninety. \
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

        Return ONLY valid JSON, one of these two shapes:

        Null result (most common):
        {"echo": null, "reason": "brief phrase why"}

        Found result:
        {"echo": {"type": "intention"|"open_loop"|"theme"|"mood_marker", \
        "quote": "exact user words", "surface_after_hours": <int>, \
        "confidence": <0.0–1.0>, "theme_keyword": "<string or null>"}}

        Entry:
        \"\"\"
        \(entryText)
        \"\"\"

        Recent entries (context only — do not extract from these):
        \"\"\"
        \(recentContext.isEmpty ? "(none)" : recentContext)
        \"\"\"
        """
    }

    // MARK: - Echo response parsing

    private func parseEchoResponse(_ data: Data) throws -> EchoExtractionResult? {
        guard
            let root     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands    = root["candidates"] as? [[String: Any]],
            let first    = cands.first,
            let content  = first["content"] as? [String: Any],
            let parts    = content["parts"] as? [[String: Any]],
            let text     = parts.first?["text"] as? String,
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
            themeKeyword:     echoDict["theme_keyword"] as? String
        )
    }
}

// MARK: - Errors
enum AIError: LocalizedError {
    case noApiKey
    case textTooShort
    case invalidResponse
    case httpError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noApiKey:             return "No Gemini API key set."
        case .textTooShort:         return "Entry too short to analyse."
        case .invalidResponse:      return "Invalid response from Gemini."
        case .httpError(let c, _):  return "Gemini returned HTTP \(c)."
        case .parseError:           return "Could not parse Gemini response."
        }
    }
}
