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
                content
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Search entries…")
            .toolbar { addEntryButton }
            .sheet(isPresented: $showingEditor) {
                JournalEditorView(userId: authViewModel.currentUser?.id ?? "") {
                    Task { await viewModel.loadEntries() }
                }
            }
            .task { await viewModel.loadEntries() }
            .onAppear { Task { await viewModel.loadEntries() } }
            .refreshable { await viewModel.loadEntries() }
        }
    }

    // MARK: - Content states
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            VStack(spacing: 16) {
                ProgressView().tint(AppTheme.terracotta)
                Text("Loading your journal…")
                    .font(AppTheme.mono(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredEntries.isEmpty && !viewModel.searchText.isEmpty {
            VStack(spacing: 12) {
                Text("Nothing found for \"\(viewModel.searchText)\"")
                    .font(AppTheme.editorialDisplay(size: 20))
                    .foregroundStyle(AppTheme.ink)
                Text("Try a different word or tag.")
                    .font(AppTheme.editorialBody())
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.entries.isEmpty {
            emptyState
        } else {
            entryList
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                    ForEach(group.entries) { entry in
                        NavigationLink {
                            JournalEditorView(
                                userId: authViewModel.currentUser?.id ?? "",
                                existingEntry: entry
                            ) {
                                Task { await viewModel.loadEntries() }
                            }
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
                Spacer(minLength: 100)
            }
        }
    }

    // MARK: - Toolbar
    private var addEntryButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showingEditor = true } label: {
                Image(systemName: "square.and.pencil")
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.terracotta)
            }
        }
    }
}
