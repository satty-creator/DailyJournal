//
//  ProofSheetView.swift
//  DailyJournal
//
//  "more…" — mirror-v3-prd-2026-09-10.md §5.2.
//
//  The numbers behind the line, the user's own words with dates, the exception
//  if there is one, and two ways to push back. Deliberately austere: every
//  string on this screen is a count, a date, or something the person wrote. If
//  the proof sheet needed a paragraph to explain itself, the line above it was
//  not grounded enough to ship.
//

import SwiftUI

struct ProofSheetView: View {

    let line: String
    let proof: ReadingProof
    let userStatus: String
    var onFeedback: ((ReadingFeedback, ReadingMissReason?) -> Void)?
    var onAsk: (() -> Void)?
    var onTeach: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var showMissReasons = false
    @State private var recorded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(line)
                        .font(AppTheme.editorialDisplay(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    switch proof.type {
                    case "callback": callbackBlock
                    case "delta":    deltaBlock
                    default:         comparisonBlock
                    }

                    if !proof.quotes.isEmpty { quotesBlock }
                    exceptionRow
                    actionsBlock
                    if !recorded { feedbackBlock } else { savedRow }
                    countRow
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("The numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss?() }
                }
            }
        }
    }

    // MARK: - Comparison (co-occurrence / exception)

    /// The two-row comparison §5.2 asks for: the rate on the days the subject
    /// appeared, against the rate on every other day. Side by side, because a
    /// single ratio means nothing without its contrast — that is the whole
    /// argument of R1.
    private var comparisonBlock: some View {
        HStack(spacing: 12) {
            statTile(
                big: "\(proof.k) of \(proof.n)",
                small: subjectCaption
            )
            statTile(
                big: "\(proof.j) of \(proof.m)",
                small: "other days"
            )
        }
    }

    private var subjectCaption: String {
        switch proof.type {
        case "timeband": return "written \(MirrorText.bandPhrase(proof.band ?? ""))"
        default:         return "days it showed up"
        }
    }

    private var callbackBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let then = proof.thenQuote {
                thenNowRow(label: MirrorText.shortDate(then.date ?? "") ?? "then", quote: then.text)
            }
            if let now = proof.nowQuote {
                thenNowRow(label: "today", quote: now.text)
            }
            if let days = proof.daysApart {
                Text("\(days) days apart")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func thenNowRow(label: String, quote: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .textCase(.uppercase)
                .tracking(1)
            Text("“\(quote)”")
                .font(AppTheme.editorialBody(size: 15).italic())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deltaBlock: some View {
        HStack(spacing: 12) {
            statTile(big: "\(proof.j)", small: "before")
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
            statTile(big: "\(proof.k)", small: "after")
            if let run = proof.runLength, run > 1 {
                statTile(big: "\(run)", small: "in a row")
            }
        }
    }

    private func statTile(big: String, small: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(big)
                .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
            Text(small)
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Quotes

    private var quotesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("your words")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
                .textCase(.uppercase)
            ForEach(proof.quotes) { quote in
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(AppTheme.terracotta.opacity(0.3))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("“\(quote.text)”")
                            .font(AppTheme.editorialBody(size: 14).italic())
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date = quote.date, let short = MirrorText.shortDate(date) {
                            Text(short)
                                .font(AppTheme.mono(size: 10))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Exception

    @ViewBuilder
    private var exceptionRow: some View {
        if let day = proof.exceptionDays.first, let short = MirrorText.shortDate(day) {
            Text("Exception: \(short)")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.terracotta)
        } else if proof.hasComparison {
            // Saying "none yet" is not padding — it tells the user the app
            // LOOKED for the day this didn't hold and didn't find one, which
            // is a different and more trustworthy statement than silence.
            Text("Exception: none yet")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    // MARK: - Actions

    private var actionsBlock: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppTheme.inkSoft.opacity(0.15))
            actionRow("Ask Spilr about this", icon: "arrow.up.right") { onAsk?() }
            Divider().overlay(AppTheme.inkSoft.opacity(0.15))
            actionRow("Teach Spilr", icon: "pencil.line") { onTeach?() }
            Divider().overlay(AppTheme.inkSoft.opacity(0.15))
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feedback

    private var feedbackBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showMissReasons {
                Text("what missed?")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    ForEach(ReadingMissReason.allCases) { reason in
                        Button {
                            recorded = true
                            onFeedback?(.almost, reason)
                        } label: {
                            Text(reason.label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().stroke(AppTheme.inkSoft.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        recorded = true
                        onFeedback?(.thisIsMe, nil)
                    } label: {
                        Text("That's me")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.cream)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(AppTheme.terracotta))
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { showMissReasons = true } } label: {
                        Text("Not quite")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().stroke(AppTheme.inkSoft.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }

    private var savedRow: some View {
        Text("Saved. Spilr will weigh this.")
            .font(AppTheme.editorialBody(size: 13))
            .foregroundStyle(AppTheme.inkSoft)
    }

    /// The honesty line from the PRD's own mock: "2 numbers · 3 quotes · 0
    /// labels · 0 model text". Kept because it is a standing, visible promise
    /// about what this screen is allowed to contain.
    private var countRow: some View {
        Text("\(proof.hasComparison ? 2 : 0) numbers · \(proof.quotes.count) quotes · 0 labels")
            .font(AppTheme.mono(size: 10))
            .foregroundStyle(AppTheme.inkSoft.opacity(0.7))
    }
}

// MARK: - Person Model reading detail (mirror-v3.1)

/// "more…" for a Mirror v3.1 line — one built on a signature, a because, a
/// say/do gap, or an exception rather than a v3.0 observation, so there is no
/// numeric `ReadingProof` to show. The receipt and `wouldBeFalseIf` ARE the
/// proof here: what the line is grounded in, and what would have made it
/// false — collaborative empiricism means showing the test, not just the
/// claim.
struct PersonModelReadingDetailView: View {

    let reading: Reading
    var onFeedback: ((ReadingFeedback, ReadingMissReason?) -> Void)?
    var onAsk: (() -> Void)?
    var onTeach: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var showMissReasons = false
    @State private var recorded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(reading.line)
                        .font(AppTheme.editorialDisplay(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let shape = reading.shape {
                        Text(shape.lowercased())
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(1)
                            .textCase(.uppercase)
                    }

                    if let receipt = reading.receipt {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("“\(receipt.quote)”")
                                .font(AppTheme.editorialBody(size: 15).italic())
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let label = receipt.relativeLabel {
                                Text(label)
                                    .font(AppTheme.mono(size: 10))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                    }

                    if let wbf = reading.wouldBeFalseIf, !wbf.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("would be false if")
                                .font(AppTheme.mono(size: 10))
                                .foregroundStyle(AppTheme.inkSoft)
                                .tracking(1)
                                .textCase(.uppercase)
                            Text(wbf)
                                .font(AppTheme.editorialBody(size: 14))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 0) {
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                        actionRow("Ask Spilr about this", icon: "arrow.up.right") { onAsk?() }
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                        actionRow("Teach Spilr", icon: "pencil.line") { onTeach?() }
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                    }

                    if recorded {
                        Text("Saved. Spilr will weigh this.")
                            .font(AppTheme.editorialBody(size: 13))
                            .foregroundStyle(AppTheme.inkSoft)
                    } else if showMissReasons {
                        missReasonsRow
                    } else {
                        feedbackRow
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("The numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss?() }
                }
            }
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var feedbackRow: some View {
        HStack(spacing: 10) {
            Button {
                recorded = true
                onFeedback?(.thisIsMe, nil)
            } label: {
                Text("That's me")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(AppTheme.terracotta))
            }
            .buttonStyle(.plain)
            Button {
                recorded = true
                onFeedback?(.huh, nil)
            } label: {
                Text("Huh")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().stroke(AppTheme.inkSoft.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { withAnimation { showMissReasons = true } } label: {
                Text("Not quite")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().stroke(AppTheme.inkSoft.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var missReasonsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("what missed?")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(ReadingMissReason.allCases) { reason in
                    Button {
                        recorded = true
                        onFeedback?(.almost, reason)
                    } label: {
                        Text(reason.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().stroke(AppTheme.inkSoft.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
