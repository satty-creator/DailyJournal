//
//  EchoExtractionService.swift
//  DailyJournal
//
//  Orchestrates the full extraction pipeline after an entry is saved:
//    1. Fetch up to 3 recent entries for AI context (silently skips if it fails)
//    2. Call AIService.extractEcho — conservative, low-temperature prompt
//    3. Gate on confidence ≥ 0.8 (as instructed by the prompt AND enforced here)
//    4. Create the Echo in Firestore via EchoService
//
//  This service is always called fire-and-forget from the save path so it
//  MUST NEVER throw or propagate errors that could affect the save UI.
//

import Foundation

final class EchoExtractionService {

    static let shared = EchoExtractionService()
    private init() {}

    private let echoService    = EchoService()
    private let journalService = JournalService()

    // MARK: - Main entry point

    /// Call this after every entry save. Runs the full extraction pipeline
    /// asynchronously. Any failure at any step is silently swallowed.
    ///
    /// - Parameters:
    ///   - entryText:        The plain-text content of the saved entry.
    ///   - entryId:          The Firestore document ID of the saved entry.
    ///   - userId:           The authenticated user's ID.
    ///   - entryCreatedAt:   The entry's `createdAt` timestamp (used to compute
    ///                       "time ago" on the Echo card).
    func extractAndStore(
        entryText: String,
        entryId: String,
        userId: String,
        entryCreatedAt: Date
    ) async {
        // Guard: AI unavailable (not signed in) → skip extraction silently
        guard AIService.shared.isAIAvailable else { return }
        // Guard: entry too short to yield anything meaningful
        guard entryText.count > 30 else { return }

        // 1. Fetch recent entries for context (best-effort — empty is fine)
        let recent: [JournalEntry] = (try? await journalService.fetchRecentEntries(
            for: userId,
            limit: 4          // fetch 4 so we can exclude the just-saved one
        )) ?? []

        // Exclude the entry we just saved so the AI isn't confused by its own source
        let context = recent.filter { $0.id != entryId }

        // 2. Run AI extraction
        guard let result = try? await AIService.shared.extractEcho(
            from: entryText,
            recentEntries: context
        ) else { return }  // nil = AI stayed quiet (correct), or an error — both are fine

        // 3. Confidence gate — belt-and-suspenders on top of the prompt instruction
        guard result.confidence >= 0.8 else { return }

        // 4. Spilr's framing line is the whole point of an Echo (see `Echo.line`) —
        //    without it the card is just the user's own words replayed back at them.
        //    The local template that used to fill this in shipped the same four
        //    canned sentences to everyone, so a missing line now drops the Echo
        //    instead. See CLAUDE.md, "No local text in Spilr's voice".
        guard let line = result.line, !line.isEmpty else { return }
        let echo = Echo(
            userId:               userId,
            sourceEntryId:        entryId,
            sourceEntryCreatedAt: entryCreatedAt,
            type:                 result.type,
            quote:                result.quote,
            surfaceAfterHours:    result.surfaceAfterHours,
            confidence:           result.confidence,
            themeKeyword:         result.themeKeyword,
            line:                 line
        )
        echoService.createEcho(echo)
    }
}
