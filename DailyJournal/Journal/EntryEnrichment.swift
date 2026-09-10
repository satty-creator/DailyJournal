//
//  EntryEnrichment.swift
//  DailyJournal
//
//  The post-save enrichment tail every composer runs after `JournalService
//  .createEntry`: Gemini insights, an optional photo upload, Echo extraction,
//  and Mirror analysis. All four are detached, silent on failure, and never
//  block the caller — see CLAUDE.md's "AI never blocks the user".
//
//  This was triplicated near-verbatim across `TimedSessionViewModel.saveEntry`,
//  `JournalEditorViewModel.save`, and `DailyChatView.save`. `TemplateRunnerViewModel`
//  is the first new caller to use this shared version instead of a fourth copy;
//  migrating the three existing call sites onto it is a follow-up, kept separate
//  so it stays a pure, easily-reviewed refactor.
//

import Foundation
import UIKit

enum EntryEnrichment {
    static func run(
        entryId: String,
        userId: String,
        entryCreatedAt: Date,
        text: String,
        photo: UIImage? = nil,
        service: JournalService,
        // Typed passthrough for a guided-template entry (Phase 5 — typed
        // template fields). Nil for every non-template composer, which is
        // every existing caller.
        templateId: String? = nil,
        templateScaleBefore: Int? = nil,
        templateScaleAfter: Int? = nil
    ) {
        Task.detached(priority: .utility) {
            guard let insights = try? await AIService.shared.generateInsights(from: text) else { return }
            service.updateEntryInsights(entryId: entryId, userId: userId, insights: insights)
        }

        // Optional photo — upload to Storage, then patch the entry's photoURL.
        // Best-effort and fully detached: a failed/slow upload never blocks the save.
        if let photo {
            Task.detached(priority: .utility) {
                if let url = await PhotoUploadService.shared.uploadEntryPhoto(photo, userId: userId, entryId: entryId) {
                    service.updateEntryPhotoURL(entryId: entryId, userId: userId, url: url)
                }
            }
        }

        Task.detached(priority: .background) {
            await EchoExtractionService.shared.extractAndStore(
                entryText:      text,
                entryId:        entryId,
                userId:         userId,
                entryCreatedAt: entryCreatedAt
            )
        }

        // Mirror analysis (Prompt A) — structured EntryAnalysis for the Mirror /
        // Self-Model / pattern-mining chain. Self-persisting, never throws.
        Task.detached(priority: .background) {
            _ = await AIService.shared.analyzeEntry(
                entryId: entryId,
                userId:  userId,
                text:    text,
                templateId: templateId,
                templateScaleBefore: templateScaleBefore,
                templateScaleAfter: templateScaleAfter
            )
        }
    }
}
