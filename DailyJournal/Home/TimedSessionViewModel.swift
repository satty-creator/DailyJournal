//
//  TimedSessionViewModel.swift
//  DailyJournal
//
//  The save engine behind SpillWriteView. Originally paired with a 90-second
//  countdown View (TimedSessionView) that was removed to cut unreachable UI —
//  this view model survived because SpillWriteView reuses it purely for
//  content state + saveEntry (persists the entry, kicks off Gemini enrichment
//  + Echo extraction + Mirror analysis in the background).
//

import Foundation
import SwiftUI

@MainActor
final class TimedSessionViewModel: ObservableObject {

    @Published var content: String = ""
    /// The entry `saveEntry` just persisted — lets a caller (e.g. SpillWriteView's
    /// "send to future self" action) hand it straight to FutureSelfSheet without a
    /// re-fetch, the same way JournalEditorViewModel.savedEntry works.
    @Published var savedEntry: JournalEntry?

    let userId: String
    /// The pebbles chosen for this session — attached to traces / blank drops.
    /// Mutable so inline pebble selection on the writing screen updates what gets
    /// saved (the picker is no longer a separate gating step).
    var pebbles: [String]

    private let service = JournalService()

    // Local autosave for free spills (no pebbles — this is how SpillWriteView
    // uses this view model) so dismissing the sheet, or a crash, never loses
    // what someone wrote. Mirrors JournalEditorViewModel's draft mechanism.
    private static let draftKey = "spill_draft"
    private var isDraftEligible: Bool { pebbles.isEmpty }

    /// True when `content` was restored from a saved draft on init (lets the
    /// view show a subtle "Draft restored" note).
    @Published var didRestoreDraft = false
    /// Logged once per session, the first time typing actually produces a draft
    /// worth saving — not on every keystroke.
    private var hasLoggedDraft = false

    init(userId: String, pebbles: [String] = []) {
        self.userId = userId
        self.pebbles = pebbles
        if pebbles.isEmpty,
           let draft = UserDefaults.standard.string(forKey: Self.draftKey),
           !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.content = draft
            self.didRestoreDraft = true
        }
    }

    /// Persist (or clear) the in-progress draft. Called as the user types.
    func persistDraft() {
        guard isDraftEligible else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftKey)
        } else {
            UserDefaults.standard.set(content, forKey: Self.draftKey)
            if !hasLoggedDraft {
                hasLoggedDraft = true
                AnalyticsManager.shared.logEvent(.entryDrafted)
            }
        }
    }

    func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }

    func saveEntry(photo: UIImage? = nil, mood: Mood? = nil) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Step 1 – save immediately (no await). Sentiment and tags are derived
        // data and stay local; reflection is AI-only and is left unset until
        // step 2 patches it in. See CLAUDE.md, "No local text in Spilr's voice".
        let sentiment  = LocalAI.detectSentiment(from: trimmed)

        if let mood {
            AnalyticsManager.shared.trackMoodLogged(mood: mood.rawValue)
        }

        // Enrich the chosen pebbles with a few content-derived topical tags so
        // entries aren't limited to a mood word. Pebbles come first.
        var mergedTags = pebbles
        for topic in LocalAI.extractTopics(from: trimmed) where !mergedTags.contains(topic) && mergedTags.count < 5 {
            mergedTags.append(topic)
        }

        let entry = JournalEntry(
            userId: userId,
            content: trimmed,
            mood: mood,
            tags: mergedTags,
            sessionType: .timed,
            sentimentLabel: sentiment
        )
        savedEntry = entry
        service.createEntry(entry)
        clearDraft()

        // Step 2 – Gemini insights, Echo extraction, Mirror analysis and an
        // optional photo upload — all detached, silent on failure. Shared
        // with every other composer via `EntryEnrichment`.
        EntryEnrichment.run(
            entryId: entry.id,
            userId: userId,
            entryCreatedAt: entry.createdAt,
            text: trimmed,
            photo: photo,
            service: service,
            sessionType: .timed,
            mood: mood
        )
    }
}
