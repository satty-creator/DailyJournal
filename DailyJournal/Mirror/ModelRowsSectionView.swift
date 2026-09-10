//
//  ModelRowsSectionView.swift
//  DailyJournal
//
//  "WHAT SPILR THINKS IT KNOWS" — mirror-v3.1-person-model-2026-09-10.md §9.
//  3-5 rows max, the model's own signatures. No type label, no lifecycle
//  chip, no maturity ring, no four-button row — just the claim, one
//  confidence word, and the contrast that makes it checkable. Confidence
//  appears once per row because collaborative empiricism requires the user
//  to see how sure the app is, but it is one word, once — never a caption
//  explaining its own uncertainty.
//
//  Replaces ThreadsSectionView (v3.0) on the Mirror tab; the dot-strip idea
//  doesn't carry over because a signature's evidence is a set of ENTRIES,
//  not a daily on/off — the count and the contrast do that job instead.
//

import SwiftUI

struct ModelRowsSectionView: View {

    let items: [PersonModelItem]
    var onSelect: ((PersonModelItem) -> Void)?

    /// §9: "3-5 rows max." Signatures first (the CAPS unit the section is
    /// named for), then anything else already surfaceable, newest first —
    /// `items` arrives pre-sorted by DerivedService.
    private var rows: [PersonModelItem] {
        let signatures = items.filter { $0.kind == "signature" }
        let rest = items.filter { $0.kind != "signature" }
        return Array((signatures + rest).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("what spilr thinks it knows")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.2)
                .textCase(.uppercase)

            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(AppTheme.inkSoft.opacity(0.12)) }
                        row(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22, padding: 18)
    }

    private func row(_ item: PersonModelItem) -> some View {
        Button { onSelect?(item) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayTitle)
                        .font(AppTheme.editorialDisplay(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(item.metaLine)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize()
                }
                if let contrast = item.contrastLine {
                    Text(contrast)
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Honest, not apologetic — most accounts have zero signatures for a long
    /// while, and the Person Model needs n>=3 entries with a contrast before
    /// one is allowed to exist at all.
    private var emptyState: some View {
        Text("Nothing confirmed yet — Spilr needs the same thing to happen on three different days before it calls it a signature.")
            .font(AppTheme.editorialBody(size: 14))
            .foregroundStyle(AppTheme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
