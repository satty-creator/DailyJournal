//
//  ThemeCompilationView.swift
//  DailyJournal
//
//  Shown when the user taps a recurring-theme echo's "read them together" button.
//  Fetches all journal entries containing the theme keyword and lays them out
//  chronologically — no chart, no analysis, just the user's own words.
//
//  The keyword is highlighted (terracotta foreground) inline wherever it
//  appears in each entry's snippet.
//

import SwiftUI

struct ThemeCompilationView: View {

    let echo: Echo
    let userId: String
    // No onDismiss callback — the parent sheet's onDismiss handles
    // vm.answerEcho() so this view just calls dismiss() directly.

    @State private var entries: [JournalEntry] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private let service = JournalService()

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerBlock
                            .padding(.bottom, 24)

                        if isLoading {
                            loadingView
                        } else if entries.isEmpty {
                            emptyStateView
                        } else {
                            entryCards
                            insightBlock
                                .padding(.top, 12)
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
            }
            .navigationBarHidden(true)
            .task { await loadMatchingEntries() }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Back / close — parent sheet onDismiss handles the echo state update
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                    Text("Back")
                        .font(.system(size: 14))
                }
                .foregroundStyle(AppTheme.terracotta)
            }
            .padding(.bottom, 16)

            // Count label
            Text("A pattern, \(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(2)
                .textCase(.uppercase)

            // Headline with italic keyword
            Group {
                if let keyword = echo.themeKeyword {
                    Text(keyword)
                        .italic()
                        .foregroundStyle(AppTheme.terracotta)
                    + Text(" has come up.")
                        .foregroundStyle(AppTheme.ink)
                } else {
                    Text("This theme has come up.")
                        .foregroundStyle(AppTheme.ink)
                }
            }
            .font(AppTheme.editorialDisplay(size: 30))
            .lineSpacing(3)
        }
    }

    // MARK: - Entry cards

    private var entryCards: some View {
        VStack(spacing: 10) {
            ForEach(entries) { entry in
                entryCard(for: entry)
            }
        }
    }

    private func entryCard(for entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date stamp
            Text(
                entry.createdAt.formatted(
                    .dateTime.weekday(.wide).day().month(.wide)
                )
            )
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1)
            .textCase(.uppercase)

            // Snippet with keyword highlighted
            snippetText(content: entry.content, keyword: echo.themeKeyword)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.inkSoft.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Keyword highlighting

    /// Returns a `Text` view with the first occurrence of `keyword` rendered in
    /// terracotta. Uses `+` concatenation so no `AnyView` wrapping is needed.
    private func snippetText(content: String, keyword: String?) -> Text {
        let maxLen  = 220
        let snippet = content.count > maxLen
            ? String(content.prefix(maxLen)) + "…"
            : content

        guard
            let kw    = keyword, !kw.isEmpty,
            let range = snippet.range(of: kw, options: .caseInsensitive)
        else {
            // No keyword or not found — render plain italic
            return Text(snippet)
                .italic()
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
        }

        let before  = String(snippet[snippet.startIndex..<range.lowerBound])
        let matched = String(snippet[range])
        let after   = String(snippet[range.upperBound...])

        let textBefore = Text(before)
            .italic()
            .font(AppTheme.editorialBody(size: 14))
            .foregroundStyle(AppTheme.inkSoft)

        let textKeyword = Text(matched)
            .italic()
            .font(AppTheme.editorialBody(size: 14))
            .foregroundStyle(AppTheme.terracotta)

        let textAfter = Text(after)
            .italic()
            .font(AppTheme.editorialBody(size: 14))
            .foregroundStyle(AppTheme.inkSoft)

        return textBefore + textKeyword + textAfter
    }

    // MARK: - Insight block

    private var insightBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ninety noticed")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1.5)
                .textCase(.uppercase)

            Text("The thread is loud right now. No advice from us — but you might want to sit with all of these together.")
                .font(AppTheme.editorialBody(size: 13))
                .italic()
                .foregroundStyle(AppTheme.cream)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        ProgressView()
            .tint(AppTheme.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private var emptyStateView: some View {
        Text("Couldn't find entries mentioning this theme.")
            .font(AppTheme.editorialBody())
            .italic()
            .foregroundStyle(AppTheme.inkSoft)
            .padding(.top, 40)
    }

    // MARK: - Data

    private func loadMatchingEntries() async {
        isLoading = true

        guard let keyword = echo.themeKeyword, !keyword.isEmpty else {
            isLoading = false
            return
        }

        let all = (try? await service.fetchAllEntries(for: userId)) ?? []
        entries = all.filter { $0.content.localizedCaseInsensitiveContains(keyword) }
        isLoading = false
    }
}
