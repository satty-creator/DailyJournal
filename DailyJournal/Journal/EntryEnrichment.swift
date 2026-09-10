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
//  `JournalEditorViewModel.save`, and `DailyChatView.save`. All three now call
//  this shared version instead of keeping their own copy.
//

import Foundation
import UIKit

enum EntryEnrichment {
    /// All four call sites (`TimedSessionViewModel`, `JournalEditorViewModel`,
    /// `DailyChatViewModel`, `TemplateRunnerViewModel`) are themselves
    /// `@MainActor` classes, so this only formalizes what was already true —
    /// and it's required now that `run` touches `SessionManager.shared`
    /// (also `@MainActor`) synchronously rather than inside a detached task.
    @MainActor
    static func run(
        entryId: String,
        userId: String,
        entryCreatedAt: Date,
        text: String,
        photo: UIImage? = nil,
        service: JournalService,
        // False only for `JournalEditorViewModel` editing an existing entry:
        // re-extracting an Echo from re-edited text would duplicate the one
        // already extracted on first save, and it isn't a *new* entry for the
        // session counter either — both are gated on the same "is this
        // actually new" signal rather than two separate flags.
        extractEcho: Bool = true,
        // Typed passthrough for a guided-template entry (Phase 5 — typed
        // template fields). Nil for every non-template composer.
        templateId: String? = nil,
        templateScaleBefore: Int? = nil,
        templateScaleAfter: Int? = nil
    ) {
        if extractEcho {
            SessionManager.shared.recordEntryWritten()
        }

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

        if extractEcho {
            Task.detached(priority: .background) {
                await EchoExtractionService.shared.extractAndStore(
                    entryText:      text,
                    entryId:        entryId,
                    userId:         userId,
                    entryCreatedAt: entryCreatedAt
                )
            }
        }

        // Mirror analysis (Prompt A) — structured EntryAnalysis for the Mirror /
        // Self-Model / pattern-mining chain. Self-persisting, never throws.
        // Runs on every save (new or edited) so re-edited text re-analyses.
        Task.detached(priority: .background) {
            _ = await AIService.shared.analyzeEntry(
                entryId: entryId,
                userId:  userId,
                text:    text,
                entryCreatedAt: entryCreatedAt,
                templateId: templateId,
                templateScaleBefore: templateScaleBefore,
                templateScaleAfter: templateScaleAfter
            )
        }
    }
}
