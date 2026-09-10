//
//  JournalListView.swift
//  DailyJournal
//

import SwiftUI

struct JournalListView: View {

    @StateObject private var viewModel: JournalListViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    /// Cross-tab navigation — carries "scroll to this entry" from the Today tab.
    @EnvironmentObject private var router: AppRouter
    @State private var showingEditor = false
    /// The entry currently wearing the arrival highlight. Transient; cleared after
    /// ~1.4s so the ring reads as an arrival cue, not a selection state.
    @State private var highlightedId: String?
    /// List ↔ collage (Spilr Redesign 1e/1f). Seeded from the last choice so it
    /// survives both a relaunch and the `.id(themeManager.themeID)` re-identify
    /// a theme switch triggers on the whole tab tree.
    @State private var viewMode: JournalViewMode = JournalViewMode.lastUsed

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
            .fullScreenCover(isPresented: $showingEditor, onDismiss: { Task { await viewModel.loadEntries() } }) {
                // The pencil now opens the Spill write screen (same UI as the Home
                // write actions), which opens with a starter "question."
                SpillWriteView(userId: authViewModel.currentUser?.id ?? "") {
                    Task { await viewModel.loadEntries() }
                }
            }
            .task { await viewModel.loadEntries() }
        }
        .trackScreen(.journal)
    }

    // MARK: - Content states
    //
    // The header (title / toggle / search / filter chips) stays FIXED at the
    // top so the search field never loses focus as the list re-renders; only
    // the entries below it scroll.
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
    //
    // Shared by both view modes (Spilr Redesign 1f's shape, since that's where
    // the toggle lives): a big month title + entry/photo count (+ a month
    // mood-dot strip in list mode only, per 1e) with the list/collage pills
    // trailing, then the existing search field and tag chips underneath —
    // unchanged, so nothing that works today is lost.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(headerMonthTitle)
                        .font(AppTheme.editorialDisplay(size: 32, weight: .heavy))
                        .foregroundStyle(AppTheme.ink)

                    // Renders outside the loading branch, so this used to paint
                    // "0 entries" before jumping to the real count. Hidden (but
                    // space-reserving) until the count is real.
                    HStack(spacing: 8) {
                        Text(headerStatLine)
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(1.4)
                        if viewMode == .list {
                            moodDotStrip
                        }
                    }
                    .opacity(viewModel.isLoading && viewModel.entries.isEmpty ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
                }

                Spacer(minLength: 8)

                viewModeToggle
            }

            searchField
            filterChips
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .padding(.bottom, 8)
    }

    private var headerMonthTitle: String {
        viewModel.groupedEntries.first?.month ?? "Your journal"
    }

    private var headerStatLine: String {
        let count = viewModel.entryCount
        var parts = ["\(count) " + (count == 1 ? "ENTRY" : "ENTRIES")]
        let photoCount = viewModel.entries.lazy.filter { $0.photoURL != nil }.count
        if photoCount > 0 {
            parts.append("\(photoCount) " + (photoCount == 1 ? "PHOTO" : "PHOTOS"))
        }
        return parts.joined(separator: " · ")
    }

    /// One dot per entry in the newest month, filled by mood — a rhythm strip
    /// to flip past, per 1e.
    @ViewBuilder
    private var moodDotStrip: some View {
        let entries = viewModel.groupedEntries.first?.entries ?? []
        if !entries.isEmpty {
            HStack(spacing: 3) {
                ForEach(entries.prefix(24)) { entry in
                    Circle()
                        .fill(entry.mood != nil ? AppTheme.moodColor(entry.mood) : AppTheme.paperWarm)
                        .frame(width: 9, height: 9)
                }
            }
        }
    }

    // MARK: - List / collage toggle
    private var viewModeToggle: some View {
        HStack(spacing: 6) {
            modeChip(.list, label: "list")
            modeChip(.collage, label: "collage")
        }
    }

    private func modeChip(_ mode: JournalViewMode, label: String) -> some View {
        let isSelected = viewMode == mode
        return Button {
            guard viewMode != mode else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            withAnimation(.easeOut(duration: 0.15)) { viewMode = mode }
            JournalViewMode.lastUsed = mode
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(isSelected ? AppTheme.ink : AppTheme.cream)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppTheme.inkSoft.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
                )
                .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
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

    // MARK: - Tag filter chips
    //
    // Driven by the tags that actually appear in the user's entries
    // (`availableTags`, most-used first), so the filters always reflect the
    // journal — not a fixed list.
    @ViewBuilder
    private var filterChips: some View {
        if !viewModel.availableTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterChip(label: "All", isSelected: viewModel.tagFilter == nil) {
                        viewModel.tagFilter = nil
                    }
                    ForEach(viewModel.availableTags, id: \.self) { tag in
                        filterChip(label: "#\(tag)", isSelected: viewModel.tagFilter == tag) {
                            viewModel.tagFilter = (viewModel.tagFilter == tag) ? nil : tag
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? AppTheme.ink : AppTheme.cream)
                .clipShape(Capsule())
                .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        FriendlyEmptyState(
            title: "Your journal is empty.",
            subtitle: "One quiet minute.\nThat's all it takes to begin.",
            actionTitle: "Write your first entry →",
            action: { showingEditor = true }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry list
    private var entryList: some View {
        // ScrollViewReader so the Today "done" card's "See it in your Journal" can
        // land on the entry the user just wrote instead of the top of the list.
        // Without this the jump is technically correct and useless — a fresh entry
        // is visually indistinguishable from the twenty above it. Shared by both
        // view modes so the scroll-to-entry / arrival ring behaviour is identical.
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(AppTheme.mono(size: 12))
                        .foregroundStyle(AppTheme.terracotta)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                switch viewMode {
                case .list:
                    listRows
                case .collage:
                    JournalCollageView(
                        groupedEntries: viewModel.groupedEntries,
                        userId: authViewModel.currentUser?.id ?? "",
                        highlightedId: highlightedId,
                        onSaveEntry: { viewModel.upsert($0) },
                        onSave: { Task { await viewModel.loadEntries() } },
                        onDelete: { viewModel.delete($0) }
                    )
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 4)
        }
        .refreshable { await viewModel.loadEntries() }
        // Consume the router's pointer: scroll to the entry, ring it, then clear.
        // Keyed on the router value so it fires whether the tab was already loaded
        // or is appearing for the first time.
        .task(id: router.highlightedEntryId) {
            guard let target = router.highlightedEntryId else { return }
            // Let the list finish laying out before asking to scroll to a row that
            // may not be realised yet (LazyVStack).
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(target, anchor: .center)
            }
            highlightedId = target
            // Hold the ring long enough to be seen, then release it. The router
            // pointer is cleared too, so returning to this tab later is quiet.
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeOut(duration: 0.4)) { highlightedId = nil }
            router.clearHighlight()
        }
        } // ScrollViewReader
    }

    // MARK: - List mode rows (Spilr Redesign 1e)
    @ViewBuilder
    private var listRows: some View {
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
                        // Brief ring on the entry we were sent here to show.
                        // Fades itself out; see the .task below.
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(AppTheme.terracotta,
                                        lineWidth: highlightedId == entry.id ? 2 : 0)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 5)
                                .opacity(highlightedId == entry.id ? 1 : 0)
                        )
                        .scaleEffect(highlightedId == entry.id ? 1.015 : 1)
                        .animation(.easeOut(duration: 0.35), value: highlightedId)
                }
                .buttonStyle(.plain)
                .id(entry.id)
                // `.swipeActions` is a `List`-only modifier — a silent no-op inside
                // this `LazyVStack`, so delete had no working affordance. A context
                // menu works in any container.
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
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
        if let tag = viewModel.tagFilter { return "No entries tagged #\(tag) yet." }
        return "Nothing matches yet."
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
        .padding(.bottom, 90)
        .accessibilityLabel("New entry")
    }
}
