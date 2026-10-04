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
        // What the entry was and what it carried, for the `entry_created`
        // event logged below. Every composer knows all three at the point it
        // calls this; none of them reliably logged the event when each owned
        // its own call. Optional so an existing caller that passes no
        // `sessionType` simply doesn't log — there is no such caller today.
        sessionType: SessionType? = nil,
        mood: Mood? = nil,
        // When composition actually began, for composers that track it. Left
        // nil rather than guessed: the parameter is omitted from the event
        // instead of reporting a zero that looks like a real measurement.
        composedFrom: Date? = nil,
        // Typed passthrough for a guided-template entry (Phase 5 — typed
        // template fields). Nil for every non-template composer.
        templateId: String? = nil,
        templateScaleBefore: Int? = nil,
        templateScaleAfter: Int? = nil
    ) {
        if extractEcho {
            SessionManager.shared.recordEntryWritten()

            // `entry_created` — the activation event, logged on the one code
            // path every composer already takes. It used to be each composer's
            // own responsibility and two of the four never did it:
            // `TimedSessionViewModel` (the spill flow) and `DailyChatView`
            // both saved the entry and logged nothing.
            //
            // `extractEcho` is already this function's "is this a genuinely
            // new entry" signal, so re-saving an edit through the editor
            // doesn't count as a new entry here either — same gate, one
            // meaning.
            if let sessionType {
                AnalyticsManager.shared.trackEntryCreated(
                    sessionType: sessionType.analyticsName,
                    wordCount: text.split(separator: " ").count,
                    hasMood: mood != nil,
                    hasPhoto: photo != nil,
                    aiAvailable: AIService.shared.isAIAvailable,
                    compositionSeconds: composedFrom.map { Int(Date().timeIntervalSince($0)) }
                )
            }
        }

        Task.detached(priority: .utility) {
            guard let insights = try? await AIService.shared.generateInsights(from: text) else { return }
            service.updateEntryInsights(entryId: entryId, userId: userId, insights: insights)
        }

        // Optional photo — cache locally so list/collage can render it before
        // the upload below finishes (see PhotoCacheService), then upload to
        // Storage and patch the entry's photoURL. Upload is best-effort and
        // fully detached: a failed/slow upload never blocks the save.
        if let photo {
            PhotoCacheService.shared.store(photo, forEntryId: entryId)
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
