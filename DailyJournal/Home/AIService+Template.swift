//
//  AIService+Template.swift
//  DailyJournal
//
//  Weaves a finished guided-template run into one first-person journal entry.
//  Mirrors `AIService+Chat.weaveEntry`'s prompt shape (same six rules), but
//  can't reuse it directly:
//
//  1. `weaveEntry` takes `[ChatMessage]`, not labeled step answers.
//  2. It guards on `userText.split(separator: " ").count >= 12` — a template
//     run with a couple of short answers or a skipped step can land under
//     that easily, which would silently fall back to local for a completed,
//     legitimate run. Templates get no minimum.
//  3. A chip or scale answer ("Anxious", "8") is meaningless prose on its
//     own, and the model must never narrate a scale change (e.g. 8 → 3) as
//     improvement or a result — that's an interpretation the safety rules
//     forbid. Rule 8 below says so explicitly.
//
//  This is a REFLECTION surface (like Echo/Mirror/Reads), not live
//  conversation, so it's built on `SpilrVoice.system` (which already embeds
//  `safetyRules`) — not `chatSafetyRules`.
//

import Foundation

extension AIService {

    /// AI weave: sends the labeled answers to Gemini and returns flowing prose.
    /// Throws (never crashes) on any failure — callers must fall back to
    /// `localWeaveTemplateEntry`, which is the *permanent* path for anyone who
    /// hasn't granted AI consent (`isAIAvailable` gates on both sign-in and
    /// consent), not just an offline edge case.
    func weaveTemplateEntry(
        template: JournalTemplate,
        answers: [String: TemplateAnswer]
    ) async throws -> String {
        guard isAIAvailable else { throw AIError.aiUnavailable }

        let answered = template.steps.compactMap { step -> (TemplateStep, TemplateAnswer)? in
            guard let answer = answers[step.id], answer.isAnswered else { return nil }
            return (step, answer)
        }
        guard !answered.isEmpty else { throw AIError.textTooShort }

        let labeled = answered
            .map { step, answer in "\(step.label): \(answer.displayValue)" }
            .joined(separator: "\n")

        let prompt = """
        \(SpilrVoice.system)

        WEAVING TASK — guided exercise answers → first-person journal entry.

        Below are answers from a short guided writing exercise called
        "\(template.title)" (\(template.evidence.pill)). Turn them into a journal
        entry written in the person's first-person voice ("I…").

        Rules:
        1. PRESERVE the person's own words, phrases and images wherever possible. You
           are stitching their answers into flowing prose, not rewriting or "improving"
           them.
        2. Use ONLY what they actually wrote. Do not invent events, feelings, or
           details that aren't in their answers.
        3. MATCH LENGTH TO DEPTH. If they gave a couple of short answers, write a
           couple of sentences — nothing more. NEVER pad thin answers into a longer
           entry; that invents emotional weight that isn't there.
        4. First person throughout. No second-person address, no "you".
        5. ABSOLUTELY NO bullet points, dashes, numbered lists, or any list formatting.
           Every sentence must live inside a paragraph.
        6. Output ONLY the entry body — no title, no heading, no quotes, no AI
           commentary, observations, or questions.
        7. The labels below (e.g. "Situation:", "What supports it:") are scaffolding
           from the exercise, not the person's words. Drop them entirely — never echo
           a label as a heading or a phrase in the entry.
        8. Some answers are a bare number on a 0–10 scale — the person's own rough
           self-rating, not a measurement. You may mention that they rated something a
           certain way. You may NOT describe a change between two numbers as
           improvement, progress, or any kind of result, and you may NOT diagnose or
           interpret what the number means. That reads as a clinical judgment this
           app never makes.
        9. If a step was left blank, just write around it — never invent what they
           would have said.

        \(MemoryProfileService.shared.cachedPromptContext())

        Answers:
        \"\"\"
        \(labeled)
        \"\"\"

        Respond with flowing prose only — no JSON, no markdown, no labels, no lists.
        """

        let data = try await generate(prompt: prompt, maxTokens: 700, temperature: 0.3, wantJSON: false, surface: "template_weave_entry")

        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let first   = cands.first,
            let content = first["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let text    = parts.first?["text"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AIError.parseError }

        return AIService.stripListFormatting(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Plain on-device stitch — the permanent path for AI-off users, so this
    /// needs to read as genuinely usable prose, not a placeholder. Answers are
    /// already ordered by the framework, so joining them as sentences in
    /// sequence is close to correct on its own. Chip/scale answers become a
    /// short lead-in clause rather than a bare word or number.
    func localWeaveTemplateEntry(
        template: JournalTemplate,
        answers: [String: TemplateAnswer]
    ) -> String {
        let sentences: [String] = template.steps.compactMap { step in
            guard let answer = answers[step.id], answer.isAnswered else { return nil }
            switch answer {
            case .text(let s):
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let capitalized = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                let terminated = capitalized.hasSuffix(".") || capitalized.hasSuffix("!") || capitalized.hasSuffix("?")
                    ? capitalized : capitalized + "."
                return terminated
            case .choice(let s):
                return "I'd have called it \(s.lowercased())."
            case .scale(let n):
                return "On a scale of 0 to 10, I'd have put it at \(n)."
            }
        }

        guard !sentences.isEmpty else { return "" }

        // Group into small runs so this reads as 2-3 short paragraphs rather
        // than one blob, matching `localWeaveEntry`'s chunking.
        let chunkSize = max(2, Int(ceil(Double(sentences.count) / 3.0)))
        let chunks = stride(from: 0, to: sentences.count, by: chunkSize).map {
            Array(sentences[$0 ..< min($0 + chunkSize, sentences.count)])
        }
        return chunks.map { $0.joined(separator: " ") }.joined(separator: "\n\n")
    }
}
