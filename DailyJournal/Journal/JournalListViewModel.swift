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
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    /// Active mood filter chip. nil == "All".
    @Published var moodFilter: Mood?

    private let service = JournalService()
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Computed

    var filteredEntries: [JournalEntry] {
        var result = entries
        if let moodFilter {
            result = result.filter { $0.mood == moodFilter }
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

    /// The longest run of consecutive calendar days with at least one entry.
    var bestStreakDays: Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.createdAt) }).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for i in 1..<max(days.count, 1) {
            if let diff = cal.dateComponents([.day], from: days[i - 1], to: days[i]).day, diff == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    /// Which moods actually appear in the user's entries — drives which filter
    /// chips we show (no point offering a mood they've never logged).
    var availableMoods: [Mood] {
        let present = Set(entries.compactMap { $0.mood })
        return Mood.allCases.filter { present.contains($0) }
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