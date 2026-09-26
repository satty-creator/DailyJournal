//
//  JournalEditorViewModel.swift
//  DailyJournal
//

import Foundation
import UIKit

@MainActor
final class JournalEditorViewModel: ObservableObject {

    @Published var content: String
    @Published var selectedMood: Mood?
    @Published var tags: [String]
    @Published var tagInput: String = ""

    // AI / analysis results
    @Published var sentimentLabel: String?
    @Published var aiSummaryBullets: [String]
    @Published var aiQuestion: String?

    // State
    @Published var errorMessage: String?
    @Published var didSaveSuccessfully = false
    @Published var savedEntry: JournalEntry?

    private let service = JournalService()
    let userId: String
    private let existingEntry: JournalEntry?

    // Local autosave for unsaved free-write drafts so dismissing the editor (or
    // a crash) never loses what someone wrote. Only applies to brand-new entries.
    private static let draftKey = "freewrite_draft"
    private var isDraftEligible: Bool { existingEntry == nil }

    var isEditing: Bool { existingEntry != nil }

    /// The date to show in the editor header — the entry's real creation date when
    /// editing an existing entry, or today for new entries.
    var entryDate: Date { existingEntry?.createdAt ?? Date() }

    /// Download URL of the entry's attached photo (when viewing an existing entry).
    var photoURL: String? { existingEntry?.photoURL }

    /// The existing entry's session type, for analytics — irrelevant for a
    /// brand-new entry (there's nothing to have "viewed" yet).
    var sessionTypeLabel: String? { existingEntry?.sessionType.rawValue }

    /// The entry to render into a shareable card: the freshly-saved one if we
    /// have it, otherwise the entry being edited.
    var shareableEntry: JournalEntry? { savedEntry ?? existingEntry }

    var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var wordCount: Int { content.split(separator: " ").count }

    /// True when the restored text came from a saved draft (lets the view show
    /// a subtle "Draft restored" note).
    @Published var didRestoreDraft = false

    init(userId: String, existingEntry: JournalEntry? = nil, initialMood: Mood? = nil) {
        self.userId        = userId
        self.existingEntry = existingEntry
        // For a brand-new entry, seed the mood from an initial value (e.g. the
        // mood the user just tapped on Home before being redirected here).
        self.selectedMood  = existingEntry?.mood ?? initialMood
        self.tags          = existingEntry?.tags             ?? []
        self.sentimentLabel     = existingEntry?.sentimentLabel
        self.aiSummaryBullets   = existingEntry?.aiSummaryBullets ?? []
        self.aiQuestion         = existingEntry?.aiQuestion

        if let existing = existingEntry {
            self.content = existing.content
        } else if let draft = UserDefaults.standard.string(forKey: Self.draftKey),
                  !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.content = draft
            self.didRestoreDraft = true
        } else {
            self.content = ""
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
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }

    // MARK: - Live sentiment (called as user types)
    func updateSentiment() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else { sentimentLabel = nil; return }
        sentimentLabel = LocalAI.detectSentiment(from: trimmed)
    }

    // MARK: - Save
    // Step 1 (synchronous): write to Firestore local cache immediately with
    //   LocalAI heuristics so the UI can dismiss without waiting.
    // Step 2 (background Task): call Gemini and patch the entry if the API
    //   key is present. Fires-and-forgets — any failure is silently swallowed
    //   so it never blocks the user.
    //
    // `photo` is an optional UIImage to attach (edit mode allows replacing /
    // adding a photo). When non-nil, it is uploaded in the background and the
    // entry's photoURL is patched — same pattern as TimedSessionViewModel.
    func save(photo: UIImage? = nil) {
        guard canSave else { return }
        errorMessage = nil

        let trimmed   = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentiment = sentimentLabel ?? LocalAI.detectSentiment(from: trimmed)
        // Reflection is AI-only — see CLAUDE.md, "No local text in Spilr's voice".
        // On a new entry these are empty and `EntryEnrichment` patches them in when
        // Gemini answers; on an edit they carry whatever the entry already had.
        let bullets   = aiSummaryBullets
        let question  = aiQuestion

        if let selectedMood {
            AnalyticsManager.shared.trackMoodLogged(mood: selectedMood.rawValue)
        }

        let savedId: String
        if var entry = existingEntry {
            entry.content          = trimmed
            entry.mood             = selectedMood
            entry.tags             = tags
            entry.updatedAt        = Date()
            entry.sentimentLabel   = sentiment
            entry.aiSummaryBullets = bullets
            entry.aiQuestion       = question
            service.updateEntry(entry)
            savedEntry = entry
            savedId = entry.id

            AnalyticsManager.shared.logEvent(.entryEdited)
        } else {
            // New entry: enrich the user's own tags with a few content-derived
            // topical tags (work, sleep, people, …) so cards aren't limited to a
            // mood word. User tags always come first and are never dropped.
            var mergedTags = tags
            for topic in LocalAI.extractTopics(from: trimmed) where !mergedTags.contains(topic) && mergedTags.count < 5 {
                mergedTags.append(topic)
            }
            let entry = JournalEntry(
                userId:           userId,
                content:          trimmed,
                mood:             selectedMood,
                tags:             mergedTags,
                sessionType:      .freeWrite,
                aiSummaryBullets: bullets,
                aiQuestion:       question,
                sentimentLabel:   sentiment
            )
            service.createEntry(entry)
            savedEntry = entry
            savedId = entry.id
        }

        // The entry is committed — drop any saved draft so it doesn't resurface.
        clearDraft()

        didSaveSuccessfully = true

        let entryCreatedAt = savedEntry?.createdAt ?? Date()
        // Only a genuinely new entry gets an Echo extraction and counts toward
        // the session's entries-written total — editing an existing entry
        // shouldn't re-extract (the original extraction already ran) or
        // double-count a session that already recorded it once.
        let isNewEntry = existingEntry == nil

        EntryEnrichment.run(
            entryId: savedId,
            userId: userId,
            entryCreatedAt: entryCreatedAt,
            text: trimmed,
            photo: photo,
            service: service,
            extractEcho: isNewEntry,
            sessionType: .freeWrite,
            mood: selectedMood
        )
    }

    // MARK: - Delete
    @Published var didDeleteSuccessfully = false

    func delete() {
        guard let entry = existingEntry else { return }
        service.deleteEntry(entry)
        didDeleteSuccessfully = true
    }

    // MARK: - Tag Management
    func submitTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, !tags.contains(tag), tags.count < 5 else {
            tagInput = ""
            return
        }
        tags.append(tag)
        tagInput = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
