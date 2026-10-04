//
//  MirrorView.swift
//  DailyJournal
//
//  The Mirror tab. The living self-model profile (SelfModelView) is the tab:
//  the Ask pill, the weekly-letter banner, and the self-model sections. The
//  7-entry First Sketch ceremony (FirstSketchView) is presented once as a
//  full-screen cover from here — see `maybeShowFirstSketch()`.
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

// MARK: - ViewModel

@MainActor
final class MirrorViewModel: ObservableObject {
    @Published var selfModel: SelfModel = SelfModel.empty(userId: "")
    @Published var hypotheses: [PatternHypothesis] = []
    /// 0–10 ratings for `MoodTrendCard` — onboarding's baseline plus every
    /// guided entry's before/after. See `MoodLogService`.
    @Published var moodPoints: [MoodLogPoint] = []
    @Published var totalEntries: Int = 0
    /// Starts TRUE. `hypotheses == []` and `totalEntries == 0` both read as "this
    /// user has nothing yet", so rendering before the load meant "nothing here yet"
    /// placeholders, then a full swap once the data landed.
    ///
    /// It only covers the Firestore fan-out, which is fast and cache-first.
    @Published var isLoading = true
    // `showFirstSketch` / `showSelfModel` are gone with the daily Mirror screen:
    // the first-sketch sheet had no trigger left, and the profile is no longer
    // pushed — it IS the tab.
    @Published var weeklyLetter: MirrorLetter? = nil

    // MARK: - Mirror v3 / v3.1 derived layer
    /// Tier 0 facts — arithmetic, never wrong, available from the first entry.
    /// No longer rendered as its own strip (v3.1 §11 removes "This week, in
    /// your words" as a surface), but still backs the maturity/unlock gates.
    @Published var facts: MirrorFacts = .empty(userId: "")
    /// Today's one thing. `nil` means the nightly job has not written one yet
    /// (a brand-new account), which is distinct from `reading.silence == true`
    /// — a deliberate quiet day.
    @Published var reading: Reading? = nil
    /// Mirror v3.1 — active Person Model items ("what Spilr thinks it knows").
    @Published var personModelItems: [PersonModelItem] = []
    /// Mirror v3.1 — needs, open hypotheses, tonight's question.
    @Published var personModel: PersonModelAggregate = .empty
    /// The 7-entry "First Sketch" ceremony card — `users/{uid}/derived/firstSeven`,
    /// written by the nightly job when the user crosses 7 entries. Drives the
    /// FirstSketchView ceremony (see MirrorView's `firstSketch` cover); nil
    /// falls back to a SelfModel-derived sketch inside that view.
    @Published var firstSevenCard: FirstSevenCard? = nil
    /// True when the derived layer's last read couldn't reach the server or a
    /// warm cache at all — distinct from `!facts.isFresh`, which means the
    /// docs genuinely don't exist yet. Mirrors `DerivedService.loadFailed`;
    /// drives which empty-state copy the screen shows.
    @Published var derivedLoadFailed = false

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

    /// Reassigns the uid this VM operates on and resets its load-freshness
    /// state. MainTabView constructs this VM with `userId: ""` before
    /// authentication resolves and used to patch `mirrorVM.userId = uid`
    /// directly — which left `hasLoaded`/`lastLoadCompletedAt` from the
    /// placeholder VM in place, so a subsequent `loadIfStale()` could treat a
    /// load that ran against the EMPTY uid as still "fresh" and skip
    /// reloading against the real one. `MirrorView` used to keep its own
    /// shadow `userId` to route writes around this; this method removes the
    /// need for that by making the switch itself safe to observe through
    /// `vm.userId` alone (mirror-v3-prd-2026-09-10.md, Week 1).
    func setUserId(_ newUserId: String) {
        guard newUserId != userId else { return }
        userId = newUserId
        hasLoaded = false
        lastLoadCompletedAt = nil
    }

    // MARK: - Maturity (based on real entry count, as per PRD)

    var maturity: MirrorMaturity {
        MirrorMaturity.current(totalEntries: totalEntries)
    }

    /// Used by HomeView's "Spilr noticed" bridge card, which previews a
    /// pattern on Home before the user opens the Mirror tab.
    ///
    /// Deliberately answers in the SAME order and from the SAME two sources
    /// Mirror's own Today section renders from (`reading`, then the first
    /// thread) — never from `hypotheses` alone. This used to fall back to
    /// `hypotheses.first(where: { $0.isSurfaceable })`, with no maturity gate
    /// and no `timesSeen >= 3` floor, reading a collection
    /// (`patternHypotheses`) that Mirror v3 no longer has any screen for —
    /// `PatternListView` was deleted. The result was structural: Home could
    /// promise an insight that opening Mirror could never show, on a
    /// perfectly healthy network, for any account whose derived layer just
    /// hadn't produced a thread yet. If this returns non-nil, tapping through
    /// to Mirror is now guaranteed to show that same line.
    var bridgeInsightTitle: String? {
        if let reading, !reading.silence { return reading.line }
        return personModelItems.first(where: { $0.kind == "signature" })?.displayTitle
    }

    /// Hypotheses seen on at least 3 distinct entries, sorted by MirrorScore —
    /// the flat "Your patterns" list. Mirror v3 (mirror-v3-prd-2026-09-10.md
    /// §11.1) draws the line between "an observation" and "a pattern" at n≥3;
    /// below that, `PatternListView` would otherwise be a wall of one-off
    /// hypotheses shown with the same chrome as a real recurrence. This will
    /// read as empty for most accounts until the identity/dedup work (§4) and
    /// the dedicated Threads surface (§5.4) land — that emptiness is correct,
    /// not a bug, until then.
    var surfaceablePatterns: [PatternHypothesis] {
        hypotheses
            .filter { $0.isSurfaceable && $0.timesSeen >= 3 }
            .sorted { MirrorScore.score(for: $0) > MirrorScore.score(for: $1) }
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
        // corpus at all; Ask is server-side now (Prompt ASK, mirror-v3.1) and
        // makes its own request when the user actually opens it.
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
        async let moodPointsLoad = MoodLogService.shared.fetch(userId: userId)
        // Mirror v3's derived layer: facts + threads + firstSeven, then
        // today's reading (in that order internally — the reading's date key
        // depends on `facts.timezone`, so DerivedService.load fetches facts
        // first rather than computing the key up front). Server-written
        // nightly — see DerivedService.load's doc comment for the read
        // strategy.
        async let derivedLoad: Void = DerivedService.shared.load(for: userId)

        totalEntries = await rollupStats.entryCount
        _ = await selfModelLoad
        _ = await hypothesesLoad
        _ = await stylePrefsLoad
        _ = await letterLoad
        _ = await derivedLoad
        moodPoints = await moodPointsLoad
        selfModel   = SelfModelService.shared.selfModel
        hypotheses  = MirrorGraphService.shared.hypotheses
        weeklyLetter = MirrorLetterService.shared.latest
        facts       = DerivedService.shared.facts
        reading     = DerivedService.shared.reading
        personModelItems = DerivedService.shared.personModelItems
        personModel = DerivedService.shared.personModel
        firstSevenCard = DerivedService.shared.firstSeven
        derivedLoadFailed = DerivedService.shared.loadFailed

        AIService.cacheLifeContext(await lifeCtx)

        // Deterministic Self Model assembly — if no server-side model exists,
        // populate from hypotheses. Cheap and synchronous (no AI call), so it's
        // still worth finishing before the screen paints.
        if !selfModel.isSurfaceable && hypotheses.count >= 3 {
            SelfModelService.shared.assembleFromHypotheses(hypotheses, userId: userId)
            selfModel = SelfModelService.shared.selfModel
        }

        // Everything the SCREEN needs to render is resolved now — clear the
        // spinner HERE. The steps below make no LLM call (`bootstrapMirror` is
        // a rare, fire-and-forget server trigger for a brand-new user;
        // `refreshDerivedIfNeeded` is pure arithmetic), but they're still
        // sequenced after `isLoading` clears on principle: this screen must
        // never again gate first paint on anything that used to be a
        // 25s-timeout Gemini call.
        isLoading = false
        hasLoaded = true

        // Reconcile entries that were saved without a persisted analysis (AI
        // was unavailable or failed at save time). The mine's maturity gate
        // counts `entryAnalyses` docs, not raw entries, so without this a user
        // can sit at 3+ entries with < 3 analyses and never unlock. Runs before
        // the mine so the 3rd analysis exists when `runMiningIfNeeded`'s floor
        // is evaluated. Post-paint, like the mine itself.
        await EntryAnalysisBackfillService.shared.run(for: userId)

        // One-time bootstrap for a brand-new user the server hasn't mined yet.
        await runMiningIfNeeded()

        // The derived layer (facts/threads/readings) is written nightly at
        // 04:00 UTC. `bootstrapMirror` above only ever fires once per
        // account — it refuses outright once `lastMineRunAt` is set, which is
        // every RETURNING user, including one who reinstalled and lost
        // nothing server-side. Without this, such an account has no path to
        // ever seeing the derived layer except waiting for the next nightly
        // run. `refreshDerived` is pure arithmetic (no model call, no cost
        // ceiling to worry about) and safe to call as often as its own
        // server-side cooldown allows, so it's the right thing to call for
        // "this account has never been computed" specifically, not just
        // "never mined".
        if !facts.isFresh {
            await refreshDerivedIfNeeded()
        }
    }

    /// Fallback for an account whose derived layer (facts/threads/readings)
    /// has never been computed — most commonly a returning user on a fresh
    /// install, where `derived/facts` may simply not exist yet server-side
    /// and the client has no cache to fall back to either. Local cooldown
    /// only; the server enforces its own ~6h cooldown independently
    /// (`refreshDerived`'s per-user rate limit) so this is just here to avoid
    /// a pointless round trip on every Mirror open for an account that is
    /// genuinely still un-computed for some other reason (e.g. below the
    /// mining maturity gate).
    private func refreshDerivedIfNeeded() async {
        // No `isAIAvailable` gate here on purpose: unlike `bootstrapMirror`,
        // `refreshDerived` never touches Gemini (it's the same pure-arithmetic
        // worker the nightly cron runs), so it isn't something AI consent
        // should gate — only sign-in matters, and `AIService.refreshDerived`
        // already no-ops if there's no token to send.
        let cooldownKey = "mirrorDerivedRefreshAttempt_\(userId)"
        let lastAttempt = UserDefaults.standard.object(forKey: cooldownKey) as? Date
        guard lastAttempt == nil || Date().timeIntervalSince(lastAttempt!) > 6 * 3600 else { return }
        UserDefaults.standard.set(Date(), forKey: cooldownKey)

        await AIService.shared.refreshDerived(userId: userId)

        await DerivedService.shared.load(for: userId)
        facts       = DerivedService.shared.facts
        reading     = DerivedService.shared.reading
        personModelItems = DerivedService.shared.personModelItems
        personModel = DerivedService.shared.personModel
        firstSevenCard = DerivedService.shared.firstSeven
        derivedLoadFailed = DerivedService.shared.loadFailed
    }

    // MARK: - Mirror v3 derived helpers

    /// The authoritative unlock hint. Prefers the SERVER's, which can see band
    /// coverage and can therefore say "one entry at a different time of day"
    /// rather than a bare count; falls back to the local ladder for an account
    /// the nightly job has not reached yet.
    var unlockHint: String? {
        facts.unlock.hint ?? UnlockLadder.hint(totalEntries: totalEntries)
    }

    /// True once the server has written the 7-entry unlock card.
    var firstSevenAvailable: Bool { DerivedService.shared.firstSeven != nil }

    func onReadingFeedback(_ feedback: ReadingFeedback,
                           reason: ReadingMissReason?,
                           reading: Reading) {
        DerivedService.shared.recordReadingFeedback(
            feedback, reason: reason, reading: reading, userId: userId)
        self.reading = DerivedService.shared.reading
        if feedback == .almost {
            AnalyticsManager.shared.trackPatternDismissed()
        }
        // §10's metrics: the Huh rate and the Not-quite -> Wrong rate by
        // shape both come from this one event.
        AnalyticsManager.shared.trackMirrorReadingFeedback(
            feedback: feedback.rawValue, reason: reason?.rawValue, shape: reading.shape)
    }

    /// Records that today's line was actually displayed, for the 14-day
    /// novelty gate the server's ObservationScore reads.
    func markReadingShown(_ reading: Reading) {
        DerivedService.shared.markReadingShown(reading, userId: userId)
    }

    /// "Teach Spilr" — routed by the same classifier the evidence drawer uses,
    /// so a note about TONE ("too blunt") becomes a style preference while a
    /// note about CONTENT ("that's not why") becomes a hard exclusion the
    /// miner reads before it writes.
    func submitCorrection(_ text: String, hypothesisId: String?, observationId: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if MirrorCorrectionClassifier.isStyleCorrection(trimmed) {
            StylePreferencesService.shared.addNote(trimmed, userId: userId)
            return
        }
        let correction = ProfileCorrection(
            userId: userId,
            feedbackType: .notMe,
            patternId: observationId,
            hypothesisId: hypothesisId,
            userCorrection: trimmed
        )
        SelfModelService.shared.submitCorrection(correction, userId: userId)
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

        // Maturity floor. The mine needs ≥ 3 entry analyses; below 3 entries it
        // can only ever return `immature`. Attempting anyway was the root of the
        // "sometimes it unlocks, sometimes not" bug: a user who opened Mirror at
        // 1–2 entries spent the cooldown below on a guaranteed-immature attempt,
        // and reaching 3 within the cooldown window then found the retry blocked
        // — so they waited for the nightly cron while a user who happened NOT to
        // open Mirror early got the immediate bootstrap. With this floor the
        // cooldown can only ever be spent at/after 3 entries, when a mine can
        // actually succeed. (Entry count, not analysis count: the backfill in
        // `performLoad` runs first to close the gap between the two.)
        guard totalEntries >= 3 else { return }

        // Local cooldown guards a failed/immature attempt from retrying on every
        // app open — NOT the source of truth for "has this user ever been
        // mined", which is the server-side check below. Deliberately short: the
        // real cost ceiling is server-side (`claimMirrorBootstrap`'s one-shot
        // `lastMineRunAt` plus its 5-minute in-flight claim), so this only needs
        // to prevent a tight per-session retry loop. It is short on purpose so
        // that if a just-run backfill's analysis writes haven't propagated to
        // the server yet — making this bootstrap see < 3 analyses and skip as
        // immature — the next Mirror open retries within minutes rather than
        // locking the unlock out for a day.
        let cooldownKey = "mirrorFirstMineAttempt_\(userId)"
        let lastAttempt = UserDefaults.standard.object(forKey: cooldownKey) as? Date
        guard lastAttempt == nil || Date().timeIntervalSince(lastAttempt!) > 15 * 60 else { return }

        guard await !serverHasMinedBefore() else { return }

        UserDefaults.standard.set(Date(), forKey: cooldownKey)

        await AIService.shared.bootstrapMirror(userId: userId)

        // Reload so the view immediately reflects whatever the server just wrote
        // (if anything — a genuinely immature user leaves this untouched, and
        // the next Mirror load will still see `hypotheses.isEmpty`, same as now).
        await MirrorGraphService.shared.loadHypotheses(for: userId)
        hypotheses = MirrorGraphService.shared.hypotheses

        // …and re-assemble the Self Model from them, exactly as `performLoad`
        // does. This step used to be missing: mining ran AFTER `isLoading`
        // cleared, refreshed `hypotheses`, and left `selfModel` at whatever it
        // was when the screen painted. That was survivable while the profile sat
        // two taps down a "Go deeper" row — you'd see it populated next visit.
        // Now the profile IS the Mirror tab, so a first-time user whose very
        // first mine just succeeded would otherwise stare at "Still learning"
        // until the 60s staleness window let `loadIfStale` run again.
        if !selfModel.isSurfaceable && hypotheses.count >= 3 {
            SelfModelService.shared.assembleFromHypotheses(hypotheses, userId: userId)
            selfModel = SelfModelService.shared.selfModel
        }
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

}

// MARK: - MirrorView
//
// The Mirror tab is the living profile. It was previously a daily-digest screen
// — Today's reading, "what Spilr thinks it knows", "what it doesn't know yet",
// the first-sketch banner — with the profile buried behind a dashed "Your living
// profile" row in a "Go deeper when you want" section. The profile IS the thing
// worth opening the tab for, so it is now the tab, and the digest is gone as a
// surface.
//
// What this view still owns: the NavigationStack (SelfModelView deliberately has
// none of its own), the cold-load spinner, the compose FAB, and the Ask sheet.
//
// MirrorViewModel is unchanged and still loads the whole derived layer — Home's
// "Spilr noticed" bridge card reads `bridgeInsightTitle`, which is built from
// `reading` and `personModelItems`, and `runMiningIfNeeded()` is what produces
// the profile this screen renders.

struct MirrorView: View {
    // Accepts a pre-warmed VM from MainTabView to avoid cold-load spinner on first tap.
    // Falls back to creating its own when used standalone (previews, deep links).
    @ObservedObject private var vm: MirrorViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var showAsk = false
    @State private var showLetter = false
    /// The 7-entry "First Sketch" ceremony (FirstSketchView). Shown once, the
    /// first time the user reaches the `.unlock` maturity level with something
    /// to sketch. `maybeShowFirstSketch()` sets this; a per-user UserDefaults
    /// flag keeps it once-only.
    @State private var showFirstSketch = false

    init(userId: String, viewModel: MirrorViewModel? = nil) {
        vm = viewModel ?? MirrorViewModel(userId: userId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView("Reading your mirror\u{2026}")
                        .tint(AppTheme.terracotta)
                } else {
                    // `onAsk` nil below the entry threshold — the card simply
                    // isn't rendered, same gate the old screen applied.
                    SelfModelView(
                        userId: vm.userId,
                        selfModel: vm.selfModel,
                        totalEntries: vm.totalEntries,
                        onAsk: vm.totalEntries >= 5 ? {
                            showAsk = true
                            AnalyticsManager.shared.trackMirrorAskUsed()
                        } : nil,
                        weeklyLetter: vm.weeklyLetter,
                        onOpenLetter: { openLetter(source: "banner") },
                        moodPoints: vm.moodPoints
                    )
                    .refreshable { await vm.load() }
                }
            }
            .composeFAB(userId: vm.userId) { Task { await vm.load() } }
            .navigationTitle("Mirror")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await vm.loadIfStale()
                AnalyticsManager.shared.logEvent(.mirrorGraphViewed)
                maybeShowFirstSketch()
                await consumePendingLetterOpen()
            }
            // Push tapped while the app is already running and on this tab (or
            // any tab — `openWeeklyLetter()` also switches to Mirror, which
            // re-triggers this view's body but not necessarily a fresh `.task`).
            .onChange(of: router.pendingWeeklyLetterOpen) { _, pending in
                guard pending else { return }
                Task { await consumePendingLetterOpen() }
            }
            // Cold launch from a push: MainTabView sets the real uid a beat
            // after this view first appears with `userId: ""` — the pending
            // flag can arrive before there's a uid to serve it with.
            .onChange(of: vm.userId) { _, _ in
                Task { await consumePendingLetterOpen() }
            }
            .sheet(isPresented: $showAsk) {
                AskView(userId: vm.userId)
            }
            .sheet(isPresented: $showLetter) {
                if let letter = vm.weeklyLetter {
                    WeeklyLetterView(letter: letter, onDismiss: { showLetter = false })
                }
            }
            .fullScreenCover(isPresented: $showFirstSketch, onDismiss: {
                UserDefaults.standard.set(true, forKey: firstSketchShownKey)
            }) {
                FirstSketchView(
                    selfModel: vm.selfModel,
                    serverCard: vm.firstSevenCard,
                    onDismiss: { showFirstSketch = false }
                )
            }
        }
        .trackScreen(.mirror)
    }

    /// Per-user key so a shared device doesn't suppress the ceremony for a
    /// second account. Mirrors the `_\(userId)` convention the mining cooldowns
    /// already use.
    private var firstSketchShownKey: String { "mirrorFirstSketchShown_\(vm.userId)" }

    /// Shows the First Sketch ceremony exactly once, the first time the user is
    /// both at the `.unlock` maturity level (7 entries) AND has something to
    /// sketch — either the server's counted `firstSeven` card or a surfaceable
    /// self-model. Gating on real content avoids an empty ceremony (just a
    /// title and ring) when the nightly derived job hasn't landed yet; the flag
    /// stays unset in that case, so a later visit still gets the moment.
    private func maybeShowFirstSketch() {
        guard !UserDefaults.standard.bool(forKey: firstSketchShownKey),
              vm.maturity.canShowFirstSketch,
              vm.firstSevenCard != nil || vm.selfModel.isSurfaceable,
              !showFirstSketch
        else { return }
        showFirstSketch = true
    }

    /// Opens the letter reader and marks it read. Marking happens on OPEN, not
    /// dismiss — MIRROR_V3_TEST_CASES.md 7.6 is "Open the weekly letter →
    /// `openedAt` set". `source` separates in-app discovery (the banner) from
    /// push delivery for the open-rate metric (PRD §10).
    private func openLetter(source: String) {
        showLetter = true
        MirrorLetterService.shared.markOpened(userId: vm.userId)
        // `markOpened` mutates `latest.openedAt` locally — re-sync so the
        // banner's `isFreshAndUnread` check sees it and disappears immediately.
        vm.weeklyLetter = MirrorLetterService.shared.latest
        AnalyticsManager.shared.trackWeeklyLetterOpened(source: source)
    }

    /// Consumes a "weekly_letter" push tap. Fetches the letter fresh from the
    /// server (a push means one was just written; the cache-first `loadLatest`
    /// path would still show last week's) and opens it if one exists. No-ops
    /// silently offline, or before a uid is known — the flag stays set for the
    /// next call (see the `.onChange(of: vm.userId)` above).
    private func consumePendingLetterOpen() async {
        guard router.pendingWeeklyLetterOpen, !vm.userId.isEmpty else { return }
        router.pendingWeeklyLetterOpen = false
        await MirrorLetterService.shared.refreshFromServer(for: vm.userId)
        vm.weeklyLetter = MirrorLetterService.shared.latest
        guard vm.weeklyLetter != nil else { return }
        openLetter(source: "push")
    }
}

// MARK: - PatternListView — DELETED (Mirror v3 M7)
//
// The flat "Your patterns" list is gone. It rendered every surfaceable
// hypothesis with a taxonomy label, a trend badge and a "Seen N×" count —
// nineteen rows on the account in the 9 Sept screenshots, eighteen of them
// seen once and six of them the same pattern reworded. v3's Threads section
// replaced it (at most three, each requiring three distinct days, a contrast
// set and a passed audit); v3.1 replaced THAT in turn with the Person
// Model's signatures (ModelRowsSectionView, "what Spilr thinks it knows").

// MARK: - The daily Mirror screen — DELETED
//
// Today's reading card, the model rows, the open-questions section, the
// first-sketch banner, the silence/empty-state card and the "Go deeper when you
// want" disclosure section all lived here and are gone with the tab rewrite
// above. `askCard` moved to AskView.swift as `MirrorAskCard`.
//
// FirstSketchView.swift was in this stranded set but is now wired back in as
// the 7-entry ceremony (see `maybeShowFirstSketch()` above). The rest of the
// stranded component files have been deleted along with the client mirror-card
// pipeline they belonged to: TodayMirrorCardView.swift, TodayReadingCardView.swift,
// ModelRowsSectionView.swift, OpenQuestionsSectionView.swift, ProofSheetView.swift
// and TeachSpilrSheet.swift. The legacy per-hypothesis deck is no longer written
// server-side either (MIRROR_LEGACY_DECK = false; generateMirrorDeck removed).
//
// WeeklyLetterView.swift is the one exception: it and its WeeklyLetterBanner
// were also stranded here, but the letter itself is generated and pushed
// correctly server-side (see functions/index.js's buildUserWeeklyLetter) — it
// was just never rendered. Both are wired back in above and in
// SelfModelView.swift, rather than deleted.
