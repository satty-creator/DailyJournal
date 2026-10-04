//
//  EntryInsightsObserver.swift
//  DailyJournal
//
//  Live insights for a just-saved entry, plus the two shared views that
//  render them — used by both `FirstEntryCelebrationSheet` (Home's
//  first-entry-ever sheet) and `SecondLookView` (onboarding's guided-entry
//  payoff), which would otherwise carry two copies of the same waiting /
//  arrived / never-arrived rendering.
//
//  Enrichment lands *after* a composer dismisses, so anything displaying a
//  just-saved entry holds a stale value type — `aiSummaryBullets` is empty on
//  the copy either sheet receives while `EntryEnrichment`'s Gemini call is
//  still in flight. This watches the entry document and republishes when
//  `updateEntryInsights` patches it in (see `JournalService.observeEntry`).
//
//  Deliberately shows nothing rather than a local template on timeout or
//  failure: a canned observation on the user's very first entry is the one
//  place it is most likely to be read as Spilr's real judgement of what they
//  wrote. See CLAUDE.md, "No local text in Spilr's voice".
//

import SwiftUI
import FirebaseFirestore

@MainActor
final class EntryInsightsObserver: ObservableObject {

    /// Nil until Gemini's insights land. `waiting` drives the placeholder.
    @Published private(set) var bullets: [String] = []
    @Published private(set) var question: String?
    @Published private(set) var isWaiting = true

    private var listener: ListenerRegistration?
    private var timeoutTask: Task<Void, Never>?

    /// How long to keep the placeholder up before giving up. Generous — the call
    /// is a Cloud Function hop plus a Gemini round trip, and a cold start can add
    /// several seconds on top. On timeout the section simply disappears.
    private static let timeout: Duration = .seconds(20)

    func start(entry: JournalEntry, service: JournalService) {
        // Composers no longer seed `aiSummaryBullets` at save time, so a non-empty
        // value means Gemini genuinely answered — either already, or while we watch.
        if !entry.aiSummaryBullets.isEmpty {
            apply(entry)
            return
        }
        guard listener == nil else { return }

        listener = service.observeEntry(entryId: entry.id, userId: entry.userId) { [weak self] updated in
            Task { @MainActor in self?.apply(updated) }
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.isWaiting = false
            self?.stop()
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func apply(_ entry: JournalEntry) {
        // A snapshot listener fires immediately with the cached document, which at
        // this point is still un-enriched — ignore it and keep waiting.
        guard !entry.aiSummaryBullets.isEmpty else { return }
        bullets   = entry.aiSummaryBullets
        question  = entry.aiQuestion
        isWaiting = false
        stop()
    }

    deinit {
        listener?.remove()
        timeoutTask?.cancel()
    }
}

// MARK: - Shared rendering

/// "SPILR HEARD" — Gemini's bullets plus an optional follow-up question.
/// Shared by `FirstEntryCelebrationSheet` and `SecondLookView`.
struct SpilrHeardCard: View {
    let bullets: [String]
    let question: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPILR HEARD")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("—")
                            .font(AppTheme.mono(size: 12))
                            .foregroundStyle(AppTheme.terracotta)
                        Text(bullet)
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.paperWarm)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let question, !question.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(.top, 2)
                    Text(question)
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .italic()
                        .lineSpacing(3)
                }
                .padding(.top, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Honest waiting state — says what is actually happening rather than filling
/// the space with a guess. Two bars sized like the two bullets that replace them,
/// so the card doesn't jump when they arrive.
struct SpilrHeardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SPILR HEARD")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta.opacity(0.6))
                    .tracking(2)
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.terracotta.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Reading what you wrote…")
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.7))
                    .italic()

                ForEach([0.92, 0.64], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.inkSoft.opacity(0.08))
                        .frame(height: 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, y: 1, anchor: .leading)
                }
            }
            .padding(14)
            .background(AppTheme.paperWarm)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .transition(.opacity)
    }
}
