//
//  JournalCollageView.swift
//  DailyJournal
//
//  The collage/scrapbook layout for the Journal tab (Spilr Redesign screen
//  1f). SwiftUI has no masonry primitive, so this packs each month's entries
//  into two `LazyVStack` columns — greedily appending each entry (newest
//  first) to whichever column is currently shorter, using
//  `CollageTileView.estimatedHeight` as the height estimate. Packing runs per
//  month group so `JournalListViewModel.groupedEntries` still drives section
//  headers, matching list mode.
//
//  Meant to be embedded directly inside the same ScrollView/ScrollViewReader
//  that list mode uses in `JournalListView`, so cross-tab scroll-to-entry and
//  the arrival ring keep working in both modes.
//

import SwiftUI

struct JournalCollageView: View {
    let groupedEntries: [(month: String, entries: [JournalEntry])]
    let userId: String
    let highlightedId: String?
    let onSaveEntry: (JournalEntry) -> Void
    let onSave: () -> Void
    let onDelete: (JournalEntry) -> Void

    var body: some View {
        ForEach(groupedEntries, id: \.month) { group in
            Text(group.month.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 10)

            let packed = Self.pack(group.entries)
            HStack(alignment: .top, spacing: 11) {
                column(packed.left)
                column(packed.right)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private func column(_ entries: [JournalEntry]) -> some View {
        VStack(spacing: 11) {
            ForEach(entries) { entry in
                NavigationLink {
                    JournalEditorView(
                        userId: userId,
                        existingEntry: entry,
                        onSaveEntry: onSaveEntry,
                        onSave: onSave
                    )
                } label: {
                    CollageTileView(entry: entry)
                        .overlay(
                            RoundedRectangle(cornerRadius: CollageTileView.cornerRadius(for: entry), style: .continuous)
                                .stroke(AppTheme.terracotta, lineWidth: highlightedId == entry.id ? 2 : 0)
                                .opacity(highlightedId == entry.id ? 1 : 0)
                        )
                        .scaleEffect(highlightedId == entry.id ? 1.03 : 1)
                        .animation(.easeOut(duration: 0.35), value: highlightedId)
                }
                .buttonStyle(.plain)
                .id(entry.id)
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Greedy two-column packing, newest entry first — same order as list
    /// mode. Deterministic given a fixed entry list, so tiles don't reshuffle
    /// columns between redraws of the same data.
    static func pack(_ entries: [JournalEntry]) -> (left: [JournalEntry], right: [JournalEntry]) {
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 20 // the right column starts padded down, matching 1f
        var left: [JournalEntry] = []
        var right: [JournalEntry] = []
        for entry in entries {
            let height = CollageTileView.estimatedHeight(for: entry)
            if leftHeight <= rightHeight {
                left.append(entry)
                leftHeight += height + 11
            } else {
                right.append(entry)
                rightHeight += height + 11
            }
        }
        return (left, right)
    }
}
