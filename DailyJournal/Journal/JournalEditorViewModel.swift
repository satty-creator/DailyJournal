//
//  JournalEditorViewModel.swift
//  DailyJournal
//

import Foundation

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

    init(userId: String, existingEntry: JournalEntry? = nil) {
        self.userId        = userId
        self.existingEntry = existingEntry
        self.selectedMood  = existingEntry?.mood
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
    func save() {
        guard canSave else { return }
        errorMessage = nil

        let trimmed   = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentiment = sentimentLabel ?? LocalAI.detectSentiment(from: trimmed)
        let bullets   = aiSummaryBullets.isEmpty ? LocalAI.generateBullets(from: trimmed) : aiSummaryBullets
        let question  = aiQuestion ?? LocalAI.generateQuestion(from: trimmed, sentiment: sentiment)

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
        } else {
            let entry = JournalEntry(
                userId:           userId,
                content:          trimmed,
                mood:             selectedMood,
                tags:             tags,
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

        // Capture locals for detached tasks (avoids capturing self across concurrency boundary)
        let svc            = service
        let uid            = userId
        let entryCreatedAt = savedEntry?.createdAt ?? Date()
        let isNewEntry     = existingEntry == nil  // only extract echoes for new entries

        // Background Gemini enrichment — never blocks save or UI
        Task.detached(priority: .utility) {
            guard let insights = try? await AIService.shared.generateInsights(from: trimmed) else { return }
            svc.updateEntryInsights(entryId: savedId, userId: uid, insights: insights)
        }

        // Echo extraction — only on new entries (editing an existing one shouldn't
        // re-extract; the original extraction already ran when it was first saved)
        if isNewEntry {
            Task.detached(priority: .background) {
                await EchoExtractionService.shared.extractAndStore(
                    entryText:      trimmed,
                    entryId:        savedId,
                    userId:         uid,
                    entryCreatedAt: entryCreatedAt
                )
            }
        }
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
