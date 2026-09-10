//
//  ThreadsSectionView.swift
//  DailyJournal
//
//  Threads — mirror-v3-prd-2026-09-10.md §5.4. Maximum three rows.
//
//  Each row: a plain-English title, `n`, a first-seen date, a 30-day dot strip,
//  and — only when one exists — "softened {date}". No type label, no lifecycle
//  chip, no confidence caption, no buttons. Tapping opens the same proof sheet
//  the Today card uses.
//
//  The dot strip is doing the real work here: it is the most information-dense,
//  least interpretive element available, it shows recurrence AND exceptions at
//  a glance, and it is the user's own calendar — which is what makes "n 9"
//  credible instead of a number to be taken on trust.
//

import SwiftUI

// MARK: - Dot strip

struct DotStripView: View {

    let dots: [ThreadDot]
    var dotSize: CGFloat = 5
    var spacing: CGFloat = 2.5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(dots) { dot in
                Circle()
                    .fill(fill(for: dot))
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        // The exception gets a ring rather than a colour swap:
                        // it must be findable at a glance without implying
                        // "bad". An exception is good news (R6).
                        if dot.isException {
                            Circle()
                                .stroke(AppTheme.terracotta, lineWidth: 1)
                                .frame(width: dotSize + 3, height: dotSize + 3)
                        }
                    }
            }
        }
        .frame(height: dotSize + 4)
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    private func fill(for dot: ThreadDot) -> Color {
        if dot.isException { return AppTheme.paper }
        return dot.filled ? AppTheme.ink.opacity(0.72) : AppTheme.inkSoft.opacity(0.18)
    }

    private var accessibilityDescription: String {
        let filled = dots.filter(\.filled).count
        let exception = dots.contains(where: \.isException)
        var text = "Appeared on \(filled) of the last \(dots.count) days"
        if exception { text += ", with one day it did not" }
        return text
    }
}

// MARK: - Threads section

struct ThreadsSectionView: View {

    let threads: MirrorThreads
    let canShow: Bool
    let unlockHint: String?
    var onSelect: ((MirrorThread) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("threads")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1.2)
                    .textCase(.uppercase)
                if !threads.threads.isEmpty {
                    Text("(\(threads.threads.count))")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer()
            }

            if threads.threads.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(threads.threads.enumerated()), id: \.element.id) { index, thread in
                        if index > 0 { Divider().overlay(AppTheme.inkSoft.opacity(0.12)) }
                        threadRow(thread)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22, padding: 18)
    }

    private func threadRow(_ thread: MirrorThread) -> some View {
        Button {
            onSelect?(thread)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.title)
                        .font(AppTheme.editorialDisplay(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(thread.metaLine)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize()
                }

                DotStripView(dots: thread.dots)

                if let softened = thread.softenedLine {
                    Text(softened)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.terracotta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Says what would fill it, rather than implying the user has failed to
    /// produce one. At 7 entries most people have zero threads, and being
    /// straight about that is what earns belief at 30 (§7).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(threads.emptyCopy)
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !canShow, let unlockHint {
                Text(unlockHint)
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
