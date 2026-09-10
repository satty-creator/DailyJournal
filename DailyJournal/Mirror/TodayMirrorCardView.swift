//
//  TodayMirrorCardView.swift
//  DailyJournal
//
//  The Mirror Engine's daily card. Redesigned per
//  rosebud-teardown-mirror-redesign-2026-09-09.md §3.3–3.4: the card renders
//  ONLY the L0 line, one shape-specific L1 payload, and two feedback taps.
//  Everything else — receipts beyond the one shown, the alternative read, the
//  tiny experiment, "Too intense" / "Ask tomorrow" / "Teach Spilr" — lives one
//  tap away behind "more…", in EvidenceDrawerView (L2).
//

import SwiftUI

struct TodayMirrorCardView: View {

    let card: MirrorCard
    /// The hypothesis this card was generated from. Supplies the payload data
    /// the card itself doesn't carry (e.g. the Then/Now pair, the exception
    /// receipt) and the fallback shape for cards written before `card.shape`
    /// existed (pre Phase 3).
    let hypothesis: PatternHypothesis?

    var onFeedback: ((MirrorFeedback) -> Void)? = nil
    var onMore: (() -> Void)? = nil

    @State private var selectedFeedback: MirrorFeedback? = nil
    @State private var feedbackSaved = false
    @State private var loggedSurfaced = false

    private var shape: MirrorShape {
        if let shape = card.shape { return shape }
        if let hypothesis { return MirrorShape.for(hypothesis) }
        return .notice
    }

    var body: some View {
        heroCard
            .onAppear {
                guard !loggedSurfaced else { return }
                loggedSurfaced = true
                selectedFeedback = card.userFeedback
                AnalyticsManager.shared.trackPatternSurfaced(
                    archetype: card.patternName ?? "unknown",
                    evidenceCount: card.receipts.count,
                    noveltyScore: card.confidence
                )
            }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(card.displayLine)
                .font(AppTheme.editorialDisplay(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            payloadView

            feedbackRow

            if feedbackSaved {
                Text("Saved. Spilr will weigh this.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .transition(.opacity)
            }

            Button {
                onMore?()
            } label: {
                Text("more\u{2026}")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 22, x: 0, y: 14)
        .animation(.easeOut(duration: 0.3), value: feedbackSaved)
    }

    // MARK: - Payload (one shape, one thing)

    @ViewBuilder
    private var payloadView: some View {
        switch shape {
        case .notice:
            if let receipt = card.receipts.first {
                receiptLine(quote: receipt.quote, date: receipt.entryDate)
            } else if let evidence = hypothesis?.evidence.first {
                receiptLine(quote: evidence.quote, date: evidence.entryCreatedAt)
            }

        case .ask:
            if let question = card.question ?? card.tomorrowCallbackQuestion ?? hypothesis?.callbackQuestion {
                Text(question)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .thenNow:
            if let hypothesis, let pair = thenNowPair(hypothesis) {
                VStack(alignment: .leading, spacing: 6) {
                    receiptLine(quote: pair.oldest.quote, date: pair.oldest.entryCreatedAt)
                    Text("\(pair.weeksApart) weeks apart")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(1)
                    receiptLine(quote: pair.newest.quote, date: pair.newest.entryCreatedAt)
                }
            } else if let receipt = card.receipts.first {
                receiptLine(quote: receipt.quote, date: receipt.entryDate)
            }

        case .softened:
            if let receipt = card.receipts.first {
                receiptLine(quote: receipt.quote, date: receipt.entryDate)
            } else if let evidence = hypothesis?.evidence.first {
                receiptLine(quote: evidence.quote, date: evidence.entryCreatedAt)
            }
            if let different = hypothesis?.counterEvidence.first {
                Text("What was different: \(different)")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func receiptLine(quote: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\u{201C}\(quote)\u{201D}")
                .font(AppTheme.editorialBody(size: 14).italic())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func thenNowPair(_ h: PatternHypothesis) -> (oldest: PatternEvidence, newest: PatternEvidence, weeksApart: Int)? {
        guard let oldest = h.evidence.min(by: { $0.entryCreatedAt < $1.entryCreatedAt }),
              let newest = h.evidence.max(by: { $0.entryCreatedAt < $1.entryCreatedAt }),
              oldest.entryId != newest.entryId
        else { return nil }
        let weeks = max(1, Int(newest.entryCreatedAt.timeIntervalSince(oldest.entryCreatedAt) / (7 * 86_400)))
        return (oldest, newest, weeks)
    }

    // MARK: - Feedback row
    //
    // Two taps, not five. "This is me" / "Not quite" map to `.thisIsMe` /
    // `.almost` — the same soft-signal mapping as before (MirrorView's
    // onMirrorFeedback), so the SM-1 correction loop keeps its signal. The
    // other three (Not me / Too intense / Ask tomorrow) live in the "more…"
    // sheet, alongside "Teach Spilr" — a reaction stays a reaction; a survey
    // is one tap away for anyone who wants to give more.

    private var feedbackRow: some View {
        HStack(spacing: 8) {
            feedbackButton(label: "This is me", value: .thisIsMe, isPrimary: true)
            feedbackButton(label: "Not quite", value: .almost, isPrimary: false)
        }
    }

    private func feedbackButton(label: String, value: MirrorFeedback, isPrimary: Bool) -> some View {
        let isSelected = selectedFeedback == value
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedFeedback = value
                feedbackSaved = true
            }
            onFeedback?(value)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { feedbackSaved = false }
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(
                    isSelected ? AppTheme.terracotta :
                    isPrimary ? AppTheme.lav : AppTheme.ink
                )
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? AppTheme.rose.opacity(0.15) :
                    isPrimary ? AppTheme.lav.opacity(0.12) : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSelected ? AppTheme.terracotta :
                            isPrimary ? AppTheme.lav.opacity(0.5) : AppTheme.inkSoft.opacity(0.25),
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading placeholder

/// Shown in the mirror card's slot while `MirrorViewModel.cardLoadState == .working`
/// — i.e. the rest of the screen has already painted and the daily card fetch
/// is still resolving in the background. Same silhouette as
/// `TodayMirrorCardView.heroCard` so nothing reflows when the real card swaps in.
struct MirrorCardSkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bar(width: 260, height: 20)
            bar(width: 200, height: 14)
            bar(width: 180, height: 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 22, x: 0, y: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Reading your mirror")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(AppTheme.inkSoft.opacity(shimmer ? 0.10 : 0.18))
            .frame(width: width, height: height)
    }
}

// MARK: - Silence card
//
// §3.6: silence is a feature, not a fallback. Shown when nothing clears the
// score floor, the novelty gate, or the lint. Pairs a plain-spoken "nothing
// new" line with a question — the top surfaceable hypothesis's callback
// question if one exists, else a rotating MirrorSeed lens.

struct MirrorSilenceCardView: View {
    let reason: String
    let question: String?
    var onTapQuestion: (() -> Void)? = nil

    private var headline: String {
        switch reason {
        case "novelty_gate":
            return "Nothing new to show. Your last few entries read like one week."
        case "below_threshold", "no_hypotheses":
            return "Nothing sharp enough yet to show today."
        default:
            return "Nothing to show today."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headline)
                .font(AppTheme.editorialDisplay(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let question {
                Button {
                    onTapQuestion?()
                } label: {
                    Text(question)
                        .font(AppTheme.editorialBody(size: 15))
                        .foregroundStyle(AppTheme.terracotta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 22, x: 0, y: 14)
    }
}
