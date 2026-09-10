//
//  TodayReadingCardView.swift
//  DailyJournal
//
//  Today — mirror-v3-prd-2026-09-10.md §5.2. One card, one line, one receipt,
//  two taps.
//
//  Replaces TodayMirrorCardView's hypothesis-driven card. The difference that
//  matters is not visual: this line always sits on top of a deterministic
//  observation, so the receipt underneath it is not an illustration chosen to
//  match a claim — it is part of the evidence the claim was computed from.
//

import SwiftUI

struct TodayReadingCardView: View {

    let reading: Reading
    var onFeedback: ((ReadingFeedback, ReadingMissReason?) -> Void)?
    var onMore: (() -> Void)?
    var onTapQuestion: ((String) -> Void)?

    @State private var saved = false
    @State private var showMissReasons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reading.line)
                .font(AppTheme.editorialDisplay(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if let receipt = reading.receipt {
                receiptView(receipt)
            }

            if let question = reading.question, !question.isEmpty {
                Button { onTapQuestion?(question) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question)
                            .font(AppTheme.editorialBody(size: 15).italic())
                            .foregroundStyle(AppTheme.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        // §9's [Answer tonight] affordance — the question is
                        // Prompt Q's test for the model's top open hypothesis;
                        // answering it is how the model learns fastest.
                        Text("Answer tonight →")
                            .font(AppTheme.mono(size: 11))
                            .foregroundStyle(AppTheme.terracotta.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
            }

            if saved {
                Text("Saved. Spilr will weigh this.")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .transition(.opacity)
            } else if showMissReasons {
                missReasonRow
            } else {
                feedbackRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 30, padding: 22)
    }

    // MARK: - Receipt

    /// The user's own words, with a relative date. This is the half that makes
    /// the line checkable rather than merely agreeable (R2 — Forer).
    private func receiptView(_ receipt: ReadingReceipt) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(AppTheme.terracotta.opacity(0.35))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(receipt.quote)”")
                    .font(AppTheme.editorialBody(size: 14).italic())
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = receipt.relativeLabel {
                    Text(label)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft.opacity(0.8))
                }
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - Feedback

    /// §9: "That's me" / "Huh" / "Not quite" — three reactions, not two.
    /// "Huh" ("new to me") is the mind-blowing metric (target >= 25% of shown
    /// lines) and is weighted below "That's me" but is not a rejection.
    private var feedbackRow: some View {
        HStack(spacing: 10) {
            feedbackButton("That's me", filled: true) {
                withAnimation { saved = true }
                onFeedback?(.thisIsMe, nil)
            }
            feedbackButton("Huh", filled: false) {
                withAnimation { saved = true }
                onFeedback?(.huh, nil)
            }
            feedbackButton("Not quite", filled: false) {
                withAnimation { showMissReasons = true }
            }
            Spacer()
            Button { onMore?() } label: {
                Text("more…")
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .buttonStyle(.plain)
        }
    }

    /// The follow-up split (§5.2). Only "Too much" changes how Spilr writes —
    /// see DerivedService.recordReadingFeedback.
    private var missReasonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("what missed?")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(ReadingMissReason.allCases) { reason in
                    Button {
                        withAnimation { saved = true; showMissReasons = false }
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

    private func feedbackButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? AppTheme.cream : AppTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if filled {
                        Capsule().fill(AppTheme.terracotta)
                    } else {
                        Capsule().stroke(AppTheme.inkSoft.opacity(0.35), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Silence

/// A quiet day, said plainly. §5.2 step 5 — silence is a valid line, and the
/// unlock hint is what makes it informative rather than an apology.
struct ReadingSilenceCardView: View {

    let reading: Reading
    let seedQuestion: String?
    var onTapQuestion: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reading.silenceHeadline)
                .font(AppTheme.editorialDisplay(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = reading.unlockHint {
                Text(hint)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let seedQuestion {
                Button { onTapQuestion?(seedQuestion) } label: {
                    HStack(spacing: 8) {
                        Text(seedQuestion)
                            .font(AppTheme.editorialBody(size: 15).italic())
                            .foregroundStyle(AppTheme.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 30, padding: 22)
    }
}
