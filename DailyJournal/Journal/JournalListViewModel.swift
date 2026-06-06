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

    private let service = JournalService()
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Computed

    var filteredEntries: [JournalEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query) ||
            $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var groupedEntries: [(month: String, entries: [JournalEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            entry.createdAt.formatted(.dateTime.month(.wide).year())
        }
        return grouped
            .map { (month: $0.key, entries: $0.value) }
            .sorted { $0.month > $1.month }
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
}