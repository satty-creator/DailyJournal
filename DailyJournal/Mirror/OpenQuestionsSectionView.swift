//
//  OpenQuestionsSectionView.swift
//  DailyJournal
//
//  "WHAT IT DOESN'T KNOW YET" — mirror-v3.1-person-model-2026-09-10.md §9.
//  1-2 open hypotheses, tappable. Tapping one opens Daily Chat seeded with
//  the test question that would confirm or reject it — data collection and
//  therapy are the same act (§6).
//

import SwiftUI

struct OpenQuestionsSectionView: View {

    let openHypotheses: [OpenHypothesis]
    var onSelect: ((OpenHypothesis) -> Void)?

    private var rows: [OpenHypothesis] {
        Array(openHypotheses.prefix(2))
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("what it doesn't know yet")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1.2)
                    .textCase(.uppercase)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, hyp in
                        if index > 0 { Divider().overlay(AppTheme.inkSoft.opacity(0.12)) }
                        row(hyp)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(cornerRadius: 22, padding: 18)
        }
    }

    private func row(_ hyp: OpenHypothesis) -> some View {
        Button { onSelect?(hyp) } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(hyp.hypothesis)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
