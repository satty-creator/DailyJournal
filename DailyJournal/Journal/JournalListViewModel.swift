//
//  JournalListViewModel.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import Foundation

@MainActor
final class JournalListViewModel: ObservableObject {

    @Published var entries: [JournalEntry] = []
    /// Starts TRUE. With `false`, the very first body evaluation ran before
    /// `loadEntries()` had set the flag, so `isLoading && entries.isEmpty` was false
    /// and the view fell straight through to "Your journal is empty." — shown to
    /// users with dozens of entries, right before the spinner.
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var searchText = "" {
        didSet {
            // Debounced so typing doesn't spam an event per keystroke — only log
            // once the query has held still for a beat. Length only, never the
            // text itself — see `AnalyticsManager.trackJournalSearched`.
            searchLogTask?.cancel()
            let query = searchText
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            searchLogTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled, self?.searchText == query else { return }
                AnalyticsManager.shared.trackJournalSearched(queryLength: query.count)
            }
        }
    }
    /// Active tag filter chip. nil == "All".
    @Published var tagFilter: String? {
        didSet {
            if tagFilter != nil {
                AnalyticsManager.shared.trackJournalFiltered()
            }
        }
    }

    private let service = JournalService()
    private let userId: String
    private var photoObserver: NSObjectProtocol?
    private var searchLogTask: Task<Void, Never>?

    init(userId: String) {
        self.userId = userId
        // Patches a row's `photoURL` in place once a detached upload (started by
        // the editor, which has usually already dismissed by the time it
        // finishes) completes — see `JournalService.updateEntryPhotoURL`. Without
        // this, a freshly-attached photo doesn't appear until the next full
        // `loadEntries()`, and a cache-first fetch can serve a pre-upload
        // snapshot even then.
        photoObserver = NotificationCenter.default.addObserver(
            forName: .journalEntryPhotoUploaded, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let info = note.userInfo,
                info["userId"] as? String == self.userId,
                let entryId = info["entryId"] as? String,
                let photoURL = info["photoURL"] as? String,
                let index = self.entries.firstIndex(where: { $0.id == entryId })
            else { return }
            self.entries[index].photoURL = photoURL
        }
    }

    deinit {
        if let photoObserver { NotificationCenter.default.removeObserver(photoObserver) }
    }

    // MARK: - Computed

    var filteredEntries: [JournalEntry] {
        var result = entries
        if let tagFilter {
            result = result.filter { $0.tags.contains(tagFilter) }
        }
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query) ||
            $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    /// Total entries (unfiltered) — for the header subtitle.
    var entryCount: Int { entries.count }

    var earliestEntryDate: Date? { entries.map(\.createdAt).min() }

    /// Which tags actually appear in the user's entries (most-used first) — drives
    /// the filter chips so they always reflect the real tags in the journal.
    var availableTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    var groupedEntries: [(month: String, entries: [JournalEntry])] {
        // Group by calendar year+month (not by the localized label string, which
        // sorts alphabetically — "June" < "May" — and put months out of order).
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.dateComponents([.year, .month], from: entry.createdAt)
        }
        return grouped
            .map { (components, entries) -> (month: String, entries: [JournalEntry], sortKey: Date) in
                // Newest entry first within each month.
                let sortedEntries = entries.sorted { $0.createdAt > $1.createdAt }
                let label = sortedEntries.first?.createdAt.formatted(.dateTime.month(.wide).year()) ?? ""
                let key = Calendar.current.date(from: components) ?? .distantPast
                return (label, sortedEntries, key)
            }
            // Newest month first.
            .sorted { $0.sortKey > $1.sortKey }
            .map { (month: $0.month, entries: $0.entries) }
    }

    // MARK: - Actions

    func loadEntries() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await service.fetchEntries(for: userId)
        } catch {
            errorMessage = "Couldn't load entries. Pull to refresh."
        }
        isLoading = false
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        service.deleteEntry(entry)
    }

    /// Insert (or replace) an entry locally so a freshly-saved entry shows in the
    /// list immediately, without waiting on a re-fetch / cache round-trip. The
    /// subsequent loadEntries() reconciles against the source of truth.
    func upsert(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort { $0.createdAt > $1.createdAt }
    }
}