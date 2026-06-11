//
//  JournalListView.swift
//  DailyJournal
//

import SwiftUI

struct JournalListView: View {

    @StateObject private var viewModel: JournalListViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showingEditor = false

    init(userId: String) {
        _viewModel = StateObject(wrappedValue: JournalListViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                // FAB is an overlay on `content` (which respects the safe area) so
                // it floats just above the tab bar — not pinned to the physical
                // screen bottom behind it.
                content
                    .overlay(alignment: .bottomTrailing) { pencilButton }
            }
            // Custom header is rendered inline (see `header`) with explicit colours,
            // so the large title can never end up the wrong colour.
            .navigationBarHidden(true)
            .sheet(isPresented: $showingEditor) {
                JournalEditorView(
                    userId: authViewModel.currentUser?.id ?? "",
                    onSaveEntry: { viewModel.upsert($0) },
                    onSave: { Task { await viewModel.loadEntries() } }
                )
            }
            .task { await viewModel.loadEntries() }
            .onAppear { Task { await viewModel.loadEntries() } }
        }
    }

    // MARK: - Content states
    //
    // The header (title / search / filter chips) stays FIXED at the top so the
    // search field never loses focus as the list re-renders; only the entries
    // below it scroll.
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoading && viewModel.entries.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView().tint(AppTheme.terracotta)
                    Text("Loading your journal…")
                        .font(AppTheme.mono(size: 12))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(1)
                }
                Spacer()
            } else if viewModel.entries.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else if viewModel.filteredEntries.isEmpty {
                Spacer()
                noResults
                Spacer()
            } else {
                entryList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header (custom — replaces the system large title)
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("Your ").foregroundStyle(AppTheme.ink)
                    + Text("journal").foregroundStyle(AppTheme.ink).bold())
                    .font(AppTheme.editorialDisplay(size: 34, weight: .regular))

                Text(subtitleText)
                    .font(AppTheme.mono(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(0.3)
            }

            searchField
            filterChips
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .padding(.bottom, 8)
    }

    private var subtitleText: String {
        let count = viewModel.entryCount
        let entriesLabel = "\(count) " + (count == 1 ? "entry" : "entries")
        let streak = viewModel.bestStreakDays
        guard streak > 1 else { return entriesLabel }
        return entriesLabel + " · \(streak)-day best streak"
    }

    // MARK: - Search field
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "book")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
            TextField("Search your entries", text: $viewModel.searchText)
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.ink)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.inkSoft.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 4)
    }

    // MARK: - Mood filter chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(label: "All", color: AppTheme.inkSoft, isSelected: viewModel.moodFilter == nil) {
                    viewModel.moodFilter = nil
                }
                // Always show every mood filter (worst → best), like the design —
                // not just moods the user has already logged.
                ForEach([Mood.terrible, .bad, .neutral, .good, .amazing], id: \.self) { mood in
                    filterChip(
                        label: Self.filterLabel(mood),
                        color: AppTheme.moodColor(mood),
                        isSelected: viewModel.moodFilter == mood
                    ) {
                        viewModel.moodFilter = (viewModel.moodFilter == mood) ? nil : mood
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.ink : AppTheme.cream)
            .clipShape(Capsule())
            .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Short, scale-style filter label per mood (matches the chip row design).
    static func filterLabel(_ mood: Mood) -> String {
        switch mood {
        case .amazing:  return "Great"
        case .good:     return "Good"
        case .neutral:  return "Okay"
        case .bad:      return "Low"
        case .terrible: return "Tough"
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        FriendlyEmptyState(
            title: "Your journal is empty.",
            subtitle: "Ninety seconds.\nThat's all it takes to begin.",
            actionTitle: "Write your first entry →",
            action: { showingEditor = true }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry list
    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(AppTheme.mono(size: 12))
                        .foregroundStyle(AppTheme.terracotta)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                ForEach(viewModel.groupedEntries, id: \.month) { group in
                    Text(group.month.uppercased())
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(2)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                    ForEach(group.entries) { entry in
                        NavigationLink {
                            JournalEditorView(
                                userId: authViewModel.currentUser?.id ?? "",
                                existingEntry: entry,
                                onSaveEntry: { viewModel.upsert($0) },
                                onSave: { Task { await viewModel.loadEntries() } }
                            )
                        } label: {
                            JournalCardView(entry: entry)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Spacer(minLength: 120)
            }
            .padding(.top, 4)
        }
        .refreshable { await viewModel.loadEntries() }
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Text(searchOrFilterEmptyTitle)
                .font(AppTheme.editorialDisplay(size: 20))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
            Text("Try a different word, tag, or mood.")
                .font(AppTheme.editorialBody())
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var searchOrFilterEmptyTitle: String {
        if !viewModel.searchText.isEmpty { return "Nothing found for \"\(viewModel.searchText)\"" }
        return "No entries for this mood yet."
    }

    // MARK: - Floating compose button (pencil FAB)
    private var pencilButton: some View {
        Button { showingEditor = true } label: {
            Image(systemName: "pencil")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(width: 60, height: 60)
                .background(AppTheme.terracotta)
                .clipShape(Circle())
                .shadow(color: AppTheme.terracotta.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 24)
        .padding(.bottom, 28)
        .accessibilityLabel("New entry")
    }
}
