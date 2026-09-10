//
//  MirrorView.swift
//  DailyJournal
//
//  The Mirror tab. Shows the daily Line (one sentence, one payload, two
//  feedback taps — see TodayMirrorCardView), the self-model sketch banner,
//  a flat list of surfaceable patterns, and a link to the full self-model
//  profile. Redesigned per rosebud-teardown-mirror-redesign-2026-09-09.md:
//  the analysis stays a five-part formula; the display is three layers
//  (Line / Card / Proof), each one tap apart.
//

import SwiftUI
import FirebaseFirestore
import Foundation
import os.signpost

/// Instrument-visible timing for `MirrorViewModel.performLoad`, added alongside the
/// concurrency rewrite so cold-launch vs. second-visit durations can actually be
/// measured (Instruments → os_signpost) rather than inferred from inspection.
private let mirrorLoadLog = OSLog(subsystem: "com.satakshi.DailyJournal", category: "MirrorLoad")

// MARK: - PatternType display label extension

extension PatternType {
    var displayLabel: String {
        switch self {
        case .protectiveLoop:        return "Protective loop"
        case .avoidedSubject:        return "Something avoided"
        case .identityRule:          return "Rule you may carry"
        case .relationshipRole:      return "Relationship role"
        case .bodySignal:            return "Body signal"
        case .valuesConflict:        return "Values in tension"
        case .exception:             return "Exception — what helped"
        case .timeRhythm:            return "Time pattern"
        case .vocabularyFingerprint: return "Tracked phrase"
        case .absence:               return "Stopped showing up"
        }
    }
}

// MARK: - Trend badge (replaces the old dedicated "What's shifting" section)

extension PatternHypothesis {
    /// A short trend tag for a pattern-list row — new / growing / quiet, or
    /// nil. Same three arithmetic conditions the old `ShiftingSignal` used,
    /// now a tag on the item instead of its own navigation branch and its
    /// own counted disclosure row (rosebud-teardown-mirror-redesign-2026-09-09.md §3.6).
    var trendBadge: String? {
        let now = Date()
        let daysSinceFirst = Calendar.current.dateComponents([.day], from: firstSeenAt, to: now).day ?? 0
        let daysSinceShown = shownAt.map { Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0 }

        if daysSinceFirst < 7 && timesSeen >= 2 {
            return "new"
        } else if (daysSinceShown ?? 0) > 14 && timesSeen >= 3 {
            return "quiet"
        } else if timesSeen >= 4 && daysSinceFirst > 7 && daysSinceFirst < 30 {
            return "growing"
        }
        return nil
    }
}

// MARK: - ViewModel

/// Where the daily Mirror card stands relative to `isLoading`.
///
/// The card is generated (or fetched) AFTER `isLoading` clears — see the note on
/// `performLoad` — so the screen needs its own signal for "still coming" vs.
/// "genuinely nothing today", distinct from `mirrorCard == nil` alone.
enum MirrorCardLoadState: Equatable {
    case idle      // maturity doesn't allow a daily card yet
    case working   // fetch/generation in flight
    case ready     // vm.mirrorCard is populated
    /// Resolved, and there is no card to show — the silence state (§3.6).
    /// `reason` drives MirrorSilenceCardView's copy: "no_hypotheses" |
    /// "below_threshold" | "novelty_gate".
    case empty(reason: String)
}

@MainActor
final class MirrorViewModel: ObservableObject {
    @Published var selfModel: SelfModel = SelfModel.empty(userId: "")
    @Published var hypotheses: [PatternHypothesis] = []
    @Published var mirrorCard: MirrorCard? = nil
    @Published var cardLoadState: MirrorCardLoadState = .idle
    @Published var totalEntries: Int = 0
    /// Starts TRUE. `hypotheses == []` and `totalEntries == 0` both read as "this
    /// user has nothing yet", so rendering before the load meant "nothing here yet"
    /// placeholders, then a full swap once the data landed.
    ///
    /// Deliberately does NOT wait on the Mirror card any more — see `performLoad`.
    /// It only covers the Firestore fan-out, which is fast and cache-first; the
    /// card's own state is `cardLoadState`.
    @Published var isLoading = true
    @Published var showFirstSketch = false
    @Published var showSelfModel = false
    @Published var weeklyLetter: MirrorLetter? = nil

    var userId: String  // mutable so MainTabView can set the real uid after pre-warming
    /// Prevents the full-screen spinner from re-appearing when navigating back
    /// from SelfModelView. Only the very first fetch shows the spinner; subsequent
    /// refreshes (pull-to-refresh, FAB callback) silently update in the background.
    private var hasLoaded = false
    /// The in-flight load, if any. MainTabView pre-warms this VM at the same time
    /// the Mirror tab's own `.task` runs, so two `load()` passes used to overlap:
    /// the second would set `isLoading = true`, and the FIRST one's `defer` would
    /// then clear it mid-flight — spinner gone, empty placeholders painted, content
    /// swapped in a beat later. Callers now coalesce onto one pass.
    private var loadTask: Task<Void, Never>?

    /// When the last `load()` pass finished. Backs `loadIfStale()` — see its doc
    /// comment for why plain tab navigation needs a different entry point than
    /// `.task`'s previous direct call to `load()`.
    private var lastLoadCompletedAt: Date?
    private static let staleAfter: TimeInterval = 60

    init(userId: String) {
        self.userId = userId
        selfModel = SelfModel.empty(userId: userId)
    }

    // MARK: - Maturity (based on real entry count, as per PRD)

    var maturity: MirrorMaturity {
        MirrorMaturity.current(totalEntries: totalEntries)
    }

    /// Used by HomeView's "Spilr noticed" bridge card, which previews a
    /// pattern on Home before the user opens the Mirror tab.
    var bridgeInsightTitle: String? {
        hypotheses.first(where: { $0.isSurfaceable })?.userFacingTitle
    }

    /// Every surfaceable hypothesis, sorted by MirrorScore — the flat "Your
    /// patterns" list. The old goDeepSection filtered this same array four
    /// separate ways into four counted rows; the taxonomy is now a tag on
    /// each row (`PatternType.displayLabel`, `trendBadge`), not a navigation
    /// branch.
    var surfaceablePatterns: [PatternHypothesis] {
        hypotheses
            .filter(\.isSurfaceable)
            .sorted { MirrorScore.score(for: $0) > MirrorScore.score(for: $1) }
    }

    // MARK: - Mirror card feedback

    func onMirrorFeedback(_ feedback: MirrorFeedback, card: MirrorCard) {
        guard let patternId = card.sourcePatternIds.first else { return }

        // "This is me" (.thisIsMe) is a soft signal — maps to .shown so it
        // records mild agreement without pinning confidence or triggering
        // user_confirmed lifecycle. Only corrective feedback (.notMe) is
        // load-bearing for hypothesis suppression.
        let status: PatternCallbackStatus
        switch feedback {
        case .thisIsMe:    status = .shown
        case .almost:      status = .shown
        case .notMe:       status = .dismissed
        case .tooIntense:  status = .dismissed
        case .askTomorrow: status = .pending
        }

        if status == .dismissed {
            AnalyticsManager.shared.trackPatternDismissed()
        }

        // Persist feedback on the hypothesis
        MirrorGraphService.shared.recordFeedback(
            hypothesisId: patternId,
            userId: userId,
            status: status
        )
        for i in hypotheses.indices where hypotheses[i].id == patternId {
            hypotheses[i].status = status
        }

        // Route into style learning (§3.9 StylePreferences) — "Too intense"
        // lowers sharpness; two consecutive soft-negatives on the same
        // patternType mute it for 14 days. This is what makes feedback
        // visibly change behaviour instead of just logging a rating.
        if let patternType = hypotheses.first(where: { $0.id == patternId })?.patternType {
            StylePreferencesService.shared.recordFeedback(feedback, patternType: patternType.rawValue, userId: userId)
        }

        // Persist feedback on the mirror card itself. Keyed by hypothesis id,
        // not by date — `mirrorCards/{hypothesisId}`, the server-generated deck
        // (see functions/index.js `generateMirrorDeck`). `patternId` IS the
        // card's document id under the new scheme; using it directly here
        // (rather than `card.id`, which happens to equal it) keeps this write
        // correct even if that coincidence ever stops holding.
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("mirrorCards").document(patternId)
            .updateData(["userFeedback": feedback.rawValue]) { _ in }
    }

    // MARK: - Load

    /// Serialising entry point: loads never run concurrently, but every caller still
    /// gets a real pass.
    ///
    /// Deduping instead (return early if one is in flight) looked tempting and is
    /// wrong: `.refreshable` and the compose-FAB callback both call `load()` precisely
    /// BECAUSE the data just changed, so serving them an in-flight result that
    /// predates their write would silently drop the entry they just saved. Chaining
    /// costs one redundant cache-warm pass on cold start and keeps refresh honest.
    func load(showSpinner: Bool = true) async {
        let previous = loadTask
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await self.performLoad(showSpinner: showSpinner)
        }
        loadTask = task
        await task.value
        // Only clear if we're still the newest task — otherwise we'd strand a
        // successor that has already chained onto us. `==` not `===`: Task is a
        // struct, and its Equatable conformance compares the underlying task
        // pointer, so this is the identity check we want.
        if loadTask == task { loadTask = nil }
        lastLoadCompletedAt = Date()
    }

    /// For plain tab navigation, NOT for a caller that knows data just changed.
    ///
    /// `.task { await vm.load() }` used to be Mirror's `.task` directly, which
    /// fires on every return to the tab (SwiftUI re-runs `.task` on reappearance).
    /// `load()` deliberately chains rather than dedupes — correct for
    /// `.refreshable` and the compose-FAB, which call it precisely because data
    /// just changed — but for `.task` that means switching tabs and back re-ran
    /// the entire ~6-round-trip pipeline every time, with only `hasLoaded`
    /// suppressing the spinner: the screen looked idle while the load happened
    /// again underneath. A load within the last minute is treated as fresh and
    /// skipped; only `.refreshable`, the compose-FAB, and the write/chat
    /// completion callbacks still call `load()` directly.
    func loadIfStale() async {
        if let lastLoadCompletedAt,
           Date().timeIntervalSince(lastLoadCompletedAt) < Self.staleAfter,
           loadTask == nil {
            return
        }
        await load()
    }

    private func performLoad(showSpinner: Bool) async {
        let signpostID = OSSignpostID(log: mirrorLoadLog)
        os_signpost(.begin, log: mirrorLoadLog, name: "performLoad", signpostID: signpostID,
                    "coldLaunch=%{public}d", hasLoaded ? 0 : 1)
        defer {
            os_signpost(.end, log: mirrorLoadLog, name: "performLoad", signpostID: signpostID)
        }

        if showSpinner && !hasLoaded {
            isLoading = true
        }

        // 1-5 fan out concurrently — none of them depend on each other. This used
        // to be a straight-line `await` chain of ~6 independent round-trips, which
        // is why the second (warm-cache) visit was still slow: nothing was reused,
        // and everything paid for the sum of the round-trips instead of the max.
        //
        // Entry count comes from `rollups/stats`, not from fetching (and
        // decrypting) 100 full entry documents just to call `.count` on the
        // array — see RollupStats.swift. Mirror no longer holds a live entries
        // corpus at all; Ask loads its own on demand (`AskViewModel.entriesTask`)
        // when the user actually opens it, off this load's critical path.
        //
        // No `entryAnalyses` fetch here any more, either. It existed only to
        // feed the client-side mine/write prompts — both now run server-side
        // (`functions:mineUserInsights` / `functions:bootstrapMirror`), reading
        // `entryAnalyses` themselves. Nothing on this screen's read path needs it.
        async let rollupStats = RollupService.shared.fetchStats(for: userId)
        async let selfModelLoad: Void = SelfModelService.shared.load(for: userId)
        async let hypothesesLoad: Void = MirrorGraphService.shared.loadHypotheses(for: userId)
        async let lifeCtx = SelfModelService.shared.lifeContext(for: userId)
        async let stylePrefsLoad: Void = StylePreferencesService.shared.load(for: userId)
        async let letterLoad: Void = MirrorLetterService.shared.loadLatest(for: userId)

        totalEntries = await rollupStats.entryCount
        _ = await selfModelLoad
        _ = await hypothesesLoad
        _ = await stylePrefsLoad
        _ = await letterLoad
        selfModel   = SelfModelService.shared.selfModel
        hypotheses  = MirrorGraphService.shared.hypotheses
        weeklyLetter = MirrorLetterService.shared.latest

        AIService.cacheLifeContext(await lifeCtx)

        // Deterministic Self Model assembly — if no server-side model exists,
        // populate from hypotheses. Cheap and synchronous (no AI call), so it's
        // still worth finishing before the screen paints.
        if !selfModel.isSurfaceable && hypotheses.count >= 3 {
            SelfModelService.shared.assembleFromHypotheses(hypotheses, userId: userId)
            selfModel = SelfModelService.shared.selfModel
        }

        // Everything the SCREEN needs to render is resolved now — clear the
        // spinner HERE. Neither step below makes an LLM call any more
        // (`loadOrGenerateMirrorCard` only reads Firestore; `bootstrapMirror`
        // is a rare, fire-and-forget server trigger for a brand-new user), but
        // they're still sequenced after `isLoading` clears on principle: this
        // screen must never again gate first paint on anything that used to be
        // a 25s-timeout Gemini call.
        isLoading = false
        hasLoaded = true

        // One-time bootstrap for a brand-new user the server hasn't mined yet.
        await runMiningIfNeeded()

        // Read today's card off the server-generated deck.
        await loadOrGenerateMirrorCard()
    }

    func onFeedback(hypothesisId: String, status: PatternCallbackStatus) {
        MirrorGraphService.shared.recordFeedback(
            hypothesisId: hypothesisId,
            userId: userId,
            status: status
        )
        for i in hypotheses.indices where hypotheses[i].id == hypothesisId {
            hypotheses[i].status = status
        }
    }

    // MARK: - Private helpers

    /// First-mine-only bridge.
    ///
    /// The server (`functions:mineUserInsights`) mines nightly at 04:00 UTC and is
    /// the sole owner of `patternHypotheses` AND the Mirror card deck — see
    /// ai-cost-audit-2026-09-06.md §3.1 and the Mirror re-architecture that
    /// followed it. Mining and card generation used to also run here, client-side;
    /// that duplicated the nightly job (same corpus, near-identical prompt, two
    /// independent writers into one collection — how duplicate identities and
    /// re-surfaced closed threads happen) and put up to two sequential Gemini
    /// calls behind this tab's loading spinner. Neither happens on-device any
    /// more; this method's only job now is to ask the SERVER to do its one-time
    /// bootstrap early.
    ///
    /// What stays: a user who crosses the 3-analysis maturity gate hours after
    /// the last nightly dispatch would otherwise wait up to a day for the first
    /// server mine to land — the worst possible moment for the first-ever Mirror
    /// payoff to go quiet. So this still fires at most ONCE per user, gated on
    /// the server never having mined for them (`users/{uid}.lastMineRunAt`
    /// unset) — every mine after that belongs to the nightly job.
    ///
    /// No local "does this user have ≥3 analyses yet" check any more — that
    /// would need its own Firestore read now that Mirror no longer fetches
    /// `entryAnalyses` for any other reason. `bootstrapMirror` already re-checks
    /// this server-side (`mineHypothesesForUser`'s own MIN_ANALYSES gate) and
    /// no-ops cheaply — a Firestore read, no Gemini call — so an early call from
    /// a genuinely brand-new user just costs one harmless round trip, at most
    /// once per day per the cooldown below.
    private func runMiningIfNeeded() async {
        guard hypotheses.isEmpty, AIService.shared.isAIAvailable else { return }

        // Local cooldown guards a failed/immature attempt from retrying on every
        // app open — NOT the source of truth for "has this user ever been
        // mined", which is the server-side check below.
        let cooldownKey = "mirrorFirstMineAttempt_\(userId)"
        let lastAttempt = UserDefaults.standard.object(forKey: cooldownKey) as? Date
        guard lastAttempt == nil || Date().timeIntervalSince(lastAttempt!) > 86_400.0 else { return }

        guard await !serverHasMinedBefore() else { return }

        UserDefaults.standard.set(Date(), forKey: cooldownKey)

        await AIService.shared.bootstrapMirror(userId: userId)

        // Reload so the view immediately reflects whatever the server just wrote
        // (if anything — a genuinely immature user leaves this untouched, and
        // the next Mirror load will still see `hypotheses.isEmpty`, same as now).
        await MirrorGraphService.shared.loadHypotheses(for: userId)
        hypotheses = MirrorGraphService.shared.hypotheses
    }

    /// True once `functions:mineUserInsights` has run for this user at least once
    /// (`users/{uid}.lastMineRunAt` present). Cache-first: this is a single small field
    /// read on the user's own doc, already permitted by `firestore.rules`.
    private func serverHasMinedBefore() async -> Bool {
        let ref = Firestore.firestore().collection("users").document(userId)
        if let snap = try? await ref.getDocument(source: .cache),
           snap.exists, snap.get("lastMineRunAt") != nil {
            return true
        }
        if let snap = try? await ref.getDocument(), snap.exists {
            return snap.get("lastMineRunAt") != nil
        }
        return false
    }

    /// Reads today's card off the server-generated deck
    /// (`users/{uid}/mirrorCards/{hypothesisId}`) and walks the ranked
    /// candidates until one clears the client's own novelty gate and has a
    /// card that passed the server's lint.
    ///
    /// This used to stop at the single top-scoring hypothesis and give up if
    /// THAT one had no card — even though the deck holds up to
    /// MIRROR_DECK_SIZE (3) cards. A suppressed or not-yet-generated #1 meant
    /// "no card today" even when #2 or #3 had a perfectly good one. Walking
    /// the ranked list fixes that.
    ///
    /// The server already applied its own novelty gate (evidence-subset,
    /// generateMirrorDeck) before writing the deck; this is the piece only
    /// the client can see — the server writes up to 3 cards, but at most one
    /// is ever actually shown, so only the client's own `mirrorShown` history
    /// knows whether TODAY's candidate line repeats what was already shown.
    ///
    /// No AI call anywhere in this method. Prompts D and E (write, guard) run
    /// once per mine cycle in `functions:mineUserInsights` /
    /// `functions:bootstrapMirror` — see ai-cost-audit-2026-09-06.md cut #1.
    /// This is a pure Firestore read, cache-first, so it can never be the
    /// reason the spinner (or, now, `cardLoadState == .working`) lingers.
    private func loadOrGenerateMirrorCard() async {
        guard maturity.canShowDailyMirror else {
            cardLoadState = .idle
            return
        }
        let ranked = MirrorGraphService.shared.rankedCandidates(limit: 3)
        guard !ranked.isEmpty else {
            cardLoadState = .empty(reason: hypotheses.isEmpty ? "no_hypotheses" : "below_threshold")
            return
        }

        cardLoadState = .working

        let recentlyShown = await MirrorGraphService.shared.recentShownRecords(for: userId, days: 14)

        for candidate in ranked {
            guard let card = await AIService.shared.fetchMirrorCard(hypothesisId: candidate.id, userId: userId),
                  card.lintPassed != false
            else { continue }

            let candidateWords = MirrorText.contentWords(card.displayLine)
            let isRepeat = recentlyShown.contains { record in
                MirrorText.jaccardSimilarity(candidateWords, Set(record.contentWords)) > 0.5
            }
            guard !isRepeat else { continue }

            mirrorCard = card
            MirrorGraphService.shared.markShown(
                candidate.id, userId: userId,
                line: card.displayLine,
                evidenceEntryIds: candidate.evidence.map(\.entryId)
            )
            cardLoadState = .ready
            return
        }

        cardLoadState = .empty(reason: "novelty_gate")
    }
}

// MARK: - MirrorView

struct MirrorView: View {
    // Accepts a pre-warmed VM from MainTabView to avoid cold-load spinner on first tap.
    // Falls back to creating its own when used standalone (previews, deep links).
    @ObservedObject private var vm: MirrorViewModel
    @State private var selectedHypothesis: PatternHypothesis? = nil
    @State private var showEvidenceDrawer = false
    @State private var showAsk = false
    @State private var showExploreChat = false
    @State private var exploreSeed: String? = nil
    @State private var showMoreSheet = false
    @State private var silenceSeedPrompt: String? = nil
    @State private var showWeeklyLetter = false

    /// The real uid, held separately from `vm.userId`. MainTabView constructs the
    /// shared VM with `userId: ""` and only assigns the real one inside its `.task`,
    /// so anything that WRITES must use this value — `vm.userId` can still be empty,
    /// which would send the entry to `users//entries`.
    private let userId: String

    init(userId: String, viewModel: MirrorViewModel? = nil) {
        self.userId = userId
        vm = viewModel ?? MirrorViewModel(userId: userId)
    }

    /// The hypothesis behind today's card, when one is loaded. Looked up by
    /// `card.sourcePatternIds.first` — the daily card's payload (receipts,
    /// the Then/Now pair, the exception's "what was different") leans on the
    /// hypothesis for anything the card doc itself doesn't carry.
    private var cardHypothesis: PatternHypothesis? {
        guard let id = vm.mirrorCard?.sourcePatternIds.first else { return nil }
        return vm.hypotheses.first { $0.id == id }
    }

    /// The question shown on the silence card: the top surfaceable
    /// hypothesis's callback question if one exists, else a MirrorSeed lens
    /// rotated by day-of-year so a quiet stretch doesn't show the same seed
    /// every day.
    private var silenceQuestion: String {
        if let q = vm.surfaceablePatterns.first?.callbackQuestion { return q }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let seed = MirrorSeed.all[dayOfYear % MirrorSeed.all.count]
        return seed.prompt
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pastelBackground.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView("Reading your mirror…")
                        .tint(AppTheme.terracotta)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Ask pinned at top
                            if vm.totalEntries >= 5 { askCard }

                            // Weekly letter banner (§3.10) — above the Line,
                            // not in its slot, so Sunday doesn't collide the
                            // letter with the daily card.
                            if let letter = vm.weeklyLetter, letter.isFreshAndUnread {
                                WeeklyLetterBanner {
                                    showWeeklyLetter = true
                                }
                            }

                            // Today's mirror — the single daily reflection.
                            // `isLoading` no longer covers this: the card resolves
                            // (a Firestore read) AFTER the rest of the screen has
                            // already painted, so `cardLoadState` decides what
                            // shows here.
                            if let card = vm.mirrorCard, vm.maturity.canShowDailyMirror {
                                TodayMirrorCardView(
                                    card: card,
                                    hypothesis: cardHypothesis,
                                    onFeedback: { feedback in
                                        vm.onMirrorFeedback(feedback, card: card)
                                    },
                                    onMore: {
                                        showMoreSheet = true
                                    }
                                )
                            } else if vm.cardLoadState == .working {
                                MirrorCardSkeletonView()
                            } else if case .empty(let reason) = vm.cardLoadState, vm.maturity.canShowDailyMirror {
                                MirrorSilenceCardView(
                                    reason: reason,
                                    question: silenceQuestion,
                                    onTapQuestion: { silenceSeedPrompt = silenceQuestion }
                                )
                            }

                            if vm.maturity.canShowFirstSketch && vm.selfModel.isSurfaceable && !firstSketchSeen {
                                firstSketchBanner
                            }

                            // Progressive disclosure: two uncounted rows.
                            goDeepSection

                            Spacer(minLength: 90)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await vm.load() }
                }
            }
            .composeFAB(userId: userId) { Task { await vm.load() } }
            .navigationTitle("Mirror")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await vm.loadIfStale()
                AnalyticsManager.shared.logEvent(.mirrorGraphViewed)
            }
            .sheet(isPresented: $vm.showFirstSketch) {
                FirstSketchView(selfModel: vm.selfModel) {
                    vm.showFirstSketch = false
                    markFirstSketchSeen()
                }
            }
            .sheet(isPresented: $showAsk) {
                AskView(userId: userId)
            }
            .sheet(isPresented: $showWeeklyLetter, onDismiss: {
                MirrorLetterService.shared.markOpened(userId: userId)
                vm.weeklyLetter = MirrorLetterService.shared.latest
            }) {
                if let letter = vm.weeklyLetter {
                    WeeklyLetterView(letter: letter) { showWeeklyLetter = false }
                }
            }
            .fullScreenCover(isPresented: $showExploreChat) {
                DailyChatView(userId: userId, seedContext: exploreSeed) {
                    Task { await vm.load(showSpinner: false) }
                }
            }
            .fullScreenCover(item: $silenceSeedPrompt.asIdentifiablePrompt) { prompt in
                SpillWriteView(userId: userId, prompt: prompt.value) {
                    Task { await vm.load(showSpinner: false) }
                }
            }
            .sheet(isPresented: $showMoreSheet) {
                if let card = vm.mirrorCard {
                    MirrorMoreSheet(
                        onFeedback: { feedback in
                            vm.onMirrorFeedback(feedback, card: card)
                            showMoreSheet = false
                        },
                        onTeachSpilr: {
                            showMoreSheet = false
                            selectedHypothesis = cardHypothesis
                            showEvidenceDrawer = true
                        },
                        onReadFullMirror: {
                            showMoreSheet = false
                            AnalyticsManager.shared.trackPatternExplored(
                                archetype: card.patternName ?? "unknown"
                            )
                            exploreSeed = card.displayLine
                            showExploreChat = true
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showEvidenceDrawer) {
                if let h = selectedHypothesis {
                    EvidenceDrawerView(
                        hypothesis: h,
                        card: h.id == cardHypothesis?.id ? vm.mirrorCard : nil,
                        onDismiss: {
                            showEvidenceDrawer = false
                            selectedHypothesis = nil
                        },
                        onCorrect: { corrected in
                            for i in vm.hypotheses.indices where vm.hypotheses[i].id == corrected.id {
                                vm.hypotheses[i].status = .dismissed
                            }
                        },
                        onHide: { hypothesisId in
                            vm.onFeedback(hypothesisId: hypothesisId, status: .dismissed)
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $vm.showSelfModel) {
                SelfModelView(userId: userId, selfModel: vm.selfModel)
            }
        }
        .trackScreen(.mirror)
    }

    // MARK: - Background

    private var pastelBackground: some View {
        LinearGradient(
            colors: [AppTheme.paper, AppTheme.rose2.opacity(0.4), AppTheme.blue.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - First sketch: shown until opened once
    //
    // Keyed by uid so switching accounts on one device doesn't inherit
    // another user's "already seen" state.

    private var firstSketchSeenKey: String { "mirrorFirstSketchSeen_\(userId)" }

    private var firstSketchSeen: Bool {
        UserDefaults.standard.bool(forKey: firstSketchSeenKey)
    }

    private func markFirstSketchSeen() {
        UserDefaults.standard.set(true, forKey: firstSketchSeenKey)
    }

    private var firstSketchBanner: some View {
        Button {
            vm.showFirstSketch = true
        } label: {
            HStack(spacing: 16) {
                sketchRing
                VStack(alignment: .leading, spacing: 5) {
                    Text("first sketch unlocked")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.terracottaDeep)
                        .tracking(1.2)
                        .textCase(.uppercase)

                    Text("Not a label. A living profile.")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text("Spilr is learning how you work. Tap to see the first sketch.")
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [AppTheme.rose.opacity(0.25), AppTheme.lav.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.terracotta.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sketchRing: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.paperWarm, lineWidth: 7)
            Circle()
                .trim(from: 0, to: 84.0 / 360.0)
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.terracotta, AppTheme.lav, AppTheme.terracotta],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("✦")
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.terracotta)
        }
        .frame(width: 78, height: 78)
    }

    // MARK: - Ask pill (pinned at top)

    private var askCard: some View {
        Button { showAsk = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                Text("Ask about your entries\u{2026}")
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppTheme.cream.opacity(0.7))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }


    // MARK: - Go deeper (progressive disclosure)
    //
    // Two uncounted rows, replacing the old four counted disclosure rows
    // ("Patterns being watched" / "What you might not be noticing" /
    // "What's shifting" / "When the loop softened"). Counts create an
    // obligation; the taxonomy (PatternType.displayLabel, trendBadge) is now
    // a tag on each row inside a single list, not a navigation branch.

    private var goDeepSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Go deeper when you want")

            if !vm.surfaceablePatterns.isEmpty {
                NavigationLink {
                    PatternListView(
                        hypotheses: vm.surfaceablePatterns,
                        onSelectHypothesis: { h in
                            selectedHypothesis = h
                            showEvidenceDrawer = true
                        }
                    )
                } label: {
                    mirrorDisclosureRow(icon: "eye", title: "Your patterns")
                }
                .buttonStyle(.plain)
            }

            // Living profile row (dashed border)
            Button { vm.showSelfModel = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.lav)
                    Text("Your living profile")
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .padding(14)
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(AppTheme.terracotta.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func mirrorDisclosureRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.terracotta)
            Text(title)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(14)
        .background(AppTheme.cream.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Shared helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1.2)
    }
}

// MARK: - Pattern List (pushed from "Your patterns")

struct PatternListView: View {
    let hypotheses: [PatternHypothesis]
    var onSelectHypothesis: ((PatternHypothesis) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Text("\(hypotheses.count) pattern\(hypotheses.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }

                ForEach(hypotheses) { h in
                    patternRow(h)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func patternRow(_ h: PatternHypothesis) -> some View {
        Button {
            onSelectHypothesis?(h)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(h.patternType.displayLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .textCase(.uppercase)
                    if let badge = h.trendBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.terracotta)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.terracotta.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text("Seen \(h.timesSeen)\u{00D7}")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }

                Text(h.userFacingTitle)
                    .font(AppTheme.editorialDisplay(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(cornerRadius: 20, padding: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ask, AskView, MirrorMoreSheet, MirrorSilenceCardView live in their
// own files (AskView.swift, MirrorMoreSheet.swift, TodayMirrorCardView.swift).

// MARK: - Small helper for presenting a String prompt as a sheet item

private struct IdentifiablePrompt: Identifiable {
    let value: String
    var id: String { value }
}

private extension Binding where Value == String? {
    var asIdentifiablePrompt: Binding<IdentifiablePrompt?> {
        Binding<IdentifiablePrompt?>(
            get: { wrappedValue.map(IdentifiablePrompt.init) },
            set: { wrappedValue = $0?.value }
        )
    }
}
