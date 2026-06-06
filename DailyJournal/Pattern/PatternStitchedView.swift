//
//  PatternStitchedView.swift
//  DailyJournal
//
//  The tap-through for a Pattern Callback. The observation sits large at the
//  top; beneath it the triggering entries are stitched together in chronological
//  order with the relevant phrases highlighted — the "show your work" view that
//  makes a callback feel earned rather than magical.
//
//  "Write about it?" hands off into a 90-second session, seeded with the
//  callback as its prompt, and marks the callback as engaged.
//

import SwiftUI

struct PatternStitchedView: View {

    let callback: PatternCallback
    let userId: String
    /// Called when the user engages (writes about it) — used to mark answered.
    let onEngaged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entriesById: [String: JournalEntry] = [:]
    @State private var showingWrite = false

    private let service = JournalService()

    /// Evidence in chronological order (oldest first), as the spec requires.
    private var orderedEvidence: [PatternEvidence] {
        callback.evidence.sorted { $0.entryCreatedAt < $1.entryCreatedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        headerBlock
                        Divider().overlay(AppTheme.inkSoft.opacity(0.2))
                        ForEach(orderedEvidence) { evidence in
                            evidenceBlock(evidence)
                        }
                        writeButton
                            .padding(.top, 8)
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("What ninety noticed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.terracotta)
                }
            }
            .task { await loadEntries() }
            .sheet(isPresented: $showingWrite, onDismiss: { dismiss() }) {
                NinetySecondSessionView(
                    userId: userId,
                    prompt: callback.writePrompt,
                    onSave: { onEngaged() }
                )
            }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(callback.archetype.displayLabel.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(2)
            Text(callback.callbackLine)
                .font(AppTheme.editorialDisplay(size: 28))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - Evidence block

    @ViewBuilder
    private func evidenceBlock(_ evidence: PatternEvidence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(evidence.entryCreatedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)

            if let entry = entriesById[evidence.entryId] {
                highlighted(entry.content, quote: evidence.quote)
                    .font(AppTheme.editorialBody(size: 16))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(5)
            } else {
                // Fallback before the full entry loads (or if it was deleted):
                // show just the cited phrase.
                Text("\u{201C}\(evidence.quote)\u{201D}")
                    .font(AppTheme.editorialBody(size: 16))
                    .italic()
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(5)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Write CTA

    private var writeButton: some View {
        Button {
            showingWrite = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                Text("Write about it?")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlight helper

    /// Builds a Text where every (case-insensitive) occurrence of `quote` inside
    /// `content` is emphasised. Falls back to plain content if the phrase isn't
    /// found verbatim.
    private func highlighted(_ content: String, quote: String) -> Text {
        guard !quote.isEmpty,
              let range = content.range(of: quote, options: .caseInsensitive)
        else { return Text(content) }

        let before = String(content[content.startIndex..<range.lowerBound])
        let match  = String(content[range])
        let after  = String(content[range.upperBound..<content.endIndex])

        return Text(before)
            + Text(match)
                .foregroundColor(AppTheme.terracottaDeep)
                .fontWeight(.semibold)
            + Text(after)
    }

    // MARK: - Load

    private func loadEntries() async {
        let all = (try? await service.fetchAllEntries(for: userId)) ?? []
        let ids = Set(callback.evidence.map(\.entryId))
        var map: [String: JournalEntry] = [:]
        for entry in all where ids.contains(entry.id) { map[entry.id] = entry }
        entriesById = map
    }
}
