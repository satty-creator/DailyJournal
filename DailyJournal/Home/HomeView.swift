//
//  HomeView.swift
//  DailyJournal
//

import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recentEntries: [JournalEntry] = []
    @Published var arrivedLetters: [JournalEntry] = []
    /// Starts TRUE, not false. `[]` and `false` are indistinguishable from "this
    /// user genuinely has nothing", so a view that renders before `load()` has run
    /// confidently states the new-user case and then corrects itself — which is the
    /// flicker. Defaulting to `true` makes "we don't know yet" the initial state.
    @Published var isLoading = true

    /// Whether the entries query has come back yet.
    ///
    /// Separate from `isLoading` on purpose. The header subtitle branches on
    /// `recentEntries.isEmpty`, and `[]` is indistinguishable from "this user
    /// has written nothing". Sharing one flag meant clearing it early made a
    /// returning user read "First drop ready" and then watch it flip once the
    /// entries landed — the exact flicker the opacity gate exists to prevent.
    /// Two independent questions need two flags.
    @Published var entriesLoaded = false

    @Published var selectedLetter: JournalEntry?

    // ── Header stats (Spilr Redesign 3a) ────────────────────────────────
    /// The tiny `rollups/stats` doc — entry count + last-entry date for the
    /// returning-user greeting subtitle. Non-throwing and self-healing (see
    /// `RollupService.fetchStats`), so no error state is needed here.
    @Published var stats: RollupStats?
    /// True once the stats fetch above has resolved (hit or miss) this session.
    @Published var statsLoaded = false

    /// Distinct calendar days with at least one entry, within the current
    /// week (Sunday/Monday per the user's calendar). Drives the week-row dots
    /// on the invitation card. Derived from `recentEntries`, not a separate
    /// query — see `load()`.
    @Published var daysWrittenThisWeek: Int = 0

    // ── "Have I written today?" ────────────────────────────────────────
    /// The most recent entry written today, if there is one.
    ///
    /// Home previously had NO state for this. The only place today-ness was
    /// computed was an inline `Calendar.isDateInToday` inside a view-level
    /// computed string, which meant the single thing that changed after posting
    /// was the header subtitle flipping to "Written today ✓" — the hero card and
    /// its CTA were byte-identical before and after. Real state, derived once in
    /// `load()`, so the view can actually render a different card.
    @Published var todayEntry: JournalEntry?

    /// Whether the user has written at least once today.
    var hasPostedToday: Bool { todayEntry != nil }

    // ── Echoes ─────────────────────────────────────────────────────────
    /// The single pending echo to surface this session. Nil when none is
    /// available or after the user dismisses / answers it.
    @Published var pendingEcho: Echo?

    // ── Crisis safety ─────────────────────────────────────────────────
    /// When true, a crisis signal was detected in the recent corpus: show the
    /// soft opt-in resource card (non-negotiable safety flow).
    @Published var showResourceCard = false

    private let service          = JournalService()
    private let echoService      = EchoService()
    private let detection        = PatternDetectionService.shared
    let userId: String

    private var settings: PatternSettings { PatternSettings(userId: userId) }

    /// True once `load()` has completed at least once for this VM instance.
    private var hasLoadedOnce = false

    init(userId: String) {
        self.userId = userId
    }

    func load() async {
        // Only claim "loading" when there is genuinely nothing on screen yet.
        if !hasLoadedOnce { isLoading = true }

        // Fan out all reads concurrently.
        //
        // Limit bumped from 5 → 20 so `daysWrittenThisWeek` below can see a
        // full week's worth of entries without a second query. `askJournalPill`
        // (>= 5) and the first-entry fallback (== 1) both stay correct: a
        // higher limit only ever grows what they see.
        async let recent  = (try? await service.fetchRecentEntries(for: userId, limit: 20)) ?? []
        async let letters = (try? await service.fetchArrivedLetters(for: userId)) ?? []
        async let echo    = try? await echoService.fetchTopPendingEcho(for: userId)
        async let statsFetch = RollupService.shared.fetchStats(for: userId)

        // Entries first, and release the header as soon as they land. Letters,
        // mood and echo are awaited AFTER, so a slow one of those no longer holds
        // the part of the screen that depends only on entries.
        recentEntries = await recent
        entriesLoaded = true

        // Derive today-ness ONCE, here, rather than re-running the calendar check
        // inside every view body that needs it. `recentEntries` is already sorted
        // newest-first, so `first(where:)` is the latest entry from today.
        todayEntry = recentEntries.first {
            Calendar.current.isDateInToday($0.createdAt)
        }

        // Distinct calendar days written this week, for the invitation card's
        // week-row dots. `dateInterval(of: .weekOfYear, for:)` respects the
        // user's calendar (locale-correct week start).
        let cal = Calendar.current
        if let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start {
            let days = Set(
                recentEntries
                    .filter { $0.createdAt >= weekStart }
                    .map { cal.startOfDay(for: $0.createdAt) }
            )
            daysWrittenThisWeek = days.count
        }

        stats = await statsFetch
        statsLoaded = true

        // Release the loading gate here: after entries, and WITHOUT waiting on
        // letters / mood / echo — nothing on this screen renders their results
        // until they land (see below).
        isLoading = false
        hasLoadedOnce = true

        // The rest is off the critical path — awaited after the entries gate
        // releases so a slow letters/echo fetch never holds the screen.
        arrivedLetters = await letters

        // Only set pendingEcho on the first load of a session — prevents the
        // card re-appearing on pull-to-refresh after the user has dismissed it.
        if pendingEcho == nil {
            pendingEcho = await echo
            if let surfaced = pendingEcho {
                AnalyticsManager.shared.trackEchoSurfaced(
                    type: surfaced.type.rawValue,
                    confidence: surfaced.confidence
                )
            }
        }

        // Kick off the crisis-corpus scan in the background (throttled to
        // ~once/20h inside the service).
        Task { [weak self] in await self?.runDetection() }

        // Prime the durable memory profile (and the AI prompt context it caches)
        // so hints/echoes/insights are personalised even before the user opens
        // the Echoes tab. Fire-and-forget; never blocks the home screen.
        Task.detached(priority: .utility) { [userId] in
            await MemoryProfileService.shared.build(for: userId)
        }

        // One page of the events backfill per session — see
        // EventService.backfillIfNeeded. No-ops instantly once a user's whole
        // history has been walked (or if they have no pre-events analyses at
        // all). Fire-and-forget, same tolerance as the memory-profile prime.
        Task.detached(priority: .utility) { [userId] in
            await EventService.shared.backfillIfNeeded(for: userId)
        }
    }

    // MARK: - Crisis safety

    /// Runs the crisis-corpus scan and reacts to the outcome. This is the only
    /// thing PatternDetectionService still does — the pattern-callback system it
    /// used to gate was cut (see PATTERNS_MERGE_PLAN.md); Mirror's Pattern
    /// Hypothesis engine is the one actually shipping.
    private func runDetection() async {
        switch await detection.detectIfNeeded(for: userId) {
        case .safetyRouted:
            let s = settings
            guard s.shouldShowResourceCard else { return }
            s.lastResourceCardShown = Date()
            withAnimation(.easeOut(duration: 0.4)) { showResourceCard = true }
        case .clear, .skipped:
            break
        }
    }

    /// Dismiss the soft resource card.
    func dismissResourceCard() {
        withAnimation(.easeOut(duration: 0.25)) { showResourceCard = false }
    }

    func openLetter(_ entry: JournalEntry) {
        selectedLetter = entry
        service.markLetterOpened(entryId: entry.id, userId: userId)
        arrivedLetters.removeAll { $0.id == entry.id }
    }

    // MARK: - Echo actions

    /// User tapped "skip" or "not yet". Increments skip count; after 2 skips
    /// EchoService will mark it dismissed so it never resurfaces.
    func skipEcho() {
        guard let echo = pendingEcho else { return }
        echoService.skipEcho(id: echo.id, userId: userId, currentSkipCount: echo.skipCount)
        AnalyticsManager.shared.trackEchoDismissed()
        withAnimation(.easeOut(duration: 0.25)) { pendingEcho = nil }
    }

    /// User confirmed the echo ("done ✓", "it happened", "noted").
    /// Called after the EchoAnsweredView sheet is closed.
    func answerEcho() {
        guard let echo = pendingEcho else { return }
        AnalyticsManager.shared.trackEchoAnswered()
        echoService.markAnswered(id: echo.id, userId: userId)
        withAnimation(.easeOut(duration: 0.25)) { pendingEcho = nil }
    }
}

// MARK: - HomeView
struct HomeView: View {
    @StateObject private var vm: HomeViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    /// Cross-tab navigation, so the done card can send the user to their entry.
    @EnvironmentObject private var router: AppRouter
    @State private var showingTimedSession  = false
    @State private var showingDailyChat     = false
    @State private var showProfile          = false
    @State private var showAsk              = false
    /// First-entry celebration: shown once when the user saves their very first entry.
    @AppStorage("spilr.firstEntryCelebrationShown") private var firstEntryCelebrationShown = false
    @State private var celebrationEntry: JournalEntry?
    /// The echo currently being answered — captured on tap so it survives
    /// `vm.pendingEcho` clearing to nil before the sheet's `onDismiss` runs.
    @State private var answeringEcho: Echo?

    /// The starter prompt passed into the Spill write screen. Empty when
    /// reached via the start sheet's "Blank page" — SpillWriteView already
    /// handles an empty prompt by picking its own starter.
    @State private var spillPrompt = ""

    // ── Start sheet ("How do you want to start?", Spilr Redesign 3b) ────
    @State private var showingStartSheet = false
    /// Empty = the options screen; `[.templates]` = the pushed gallery. Also
    /// what the sheet's own detent (short ↔ `.large`) is keyed off, so the
    /// sheet grows in the same transaction as the push.
    @State private var startPath: [StartRoute] = []
    /// Set by an option row, read by the sheet's `onDismiss` once the sheet
    /// has actually finished dismissing — see the note at the `.sheet` call
    /// site for why a cover can't be presented directly from the row's action.
    @State private var pendingStart: StartChoice?
    /// Set alongside `showingDailyChat` when the start sheet's "Talk it out"
    /// row is chosen, so the chat cover knows to open the mic immediately.
    @State private var startChatWithDictation = false
    /// The template whose guided runner is currently presented. `nil` = no
    /// runner on screen. Set from `handlePendingStart`'s `.template` case;
    /// `JournalTemplate`'s `Identifiable` id lets this drive
    /// `.fullScreenCover(item:)` directly.
    @State private var runningTemplate: JournalTemplate?

    @ObservedObject private var mirrorVM: MirrorViewModel

    init(userId: String, mirrorVM: MirrorViewModel) {
        _vm = StateObject(wrappedValue: HomeViewModel(userId: userId))
        self.mirrorVM = mirrorVM
    }

    /// After any write session, instantly check if this was the user's very first entry.
    /// Runs a tiny Firestore query (limit: 2) in parallel with vm.load() — because the
    /// entry was just written to Firestore's local cache, this returns in milliseconds
    /// rather than waiting for a full fetchAllEntries round-trip.
    private func checkFirstEntryFast() async {
        guard !firstEntryCelebrationShown, celebrationEntry == nil else { return }
        let entries = (try? await JournalService().fetchRecentEntries(for: vm.userId, limit: 2)) ?? []
        guard entries.count == 1, let first = entries.first else { return }
        celebrationEntry = first
    }

    /// Slow fallback — used after vm.load() completes in case the fast check raced
    /// and the entry arrived in recentEntries before checkFirstEntryFast resolved.
    private func checkFirstEntry() {
        guard !firstEntryCelebrationShown,
              vm.recentEntries.count == 1,
              let first = vm.recentEntries.first,
              celebrationEntry == nil
        else { return }
        celebrationEntry = first
    }

    /// Fires the cover the start sheet's chosen row actually wants, once the
    /// sheet has finished dismissing (see `.sheet(isPresented: $showingStartSheet)`).
    private func handlePendingStart() {
        guard let choice = pendingStart else { return }
        pendingStart = nil
        switch choice {
        case .spill:
            spillPrompt = ""
            showingTimedSession = true
        case .chat:
            startChatWithDictation = false
            showingDailyChat = true
        case .talk:
            startChatWithDictation = true
            showingDailyChat = true
        case .template(let template):
            runningTemplate = template
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    // The Today screen, per Spilr Redesign 3a: header → the
                    // quiet Today's Read (or, on day one, the invitation leads
                    // and a "starts tomorrow" teaser takes its place) → the
                    // dark invitation card, always the primary CTA → a week
                    // row for returning users → a message from your past (a
                    // Future Self letter if one arrived, else a pending Echo —
                    // never both, never a list) → bridge to Mirror → ask pill.
                    // Only the crisis-safety card may interrupt.
                    VStack(alignment: .leading, spacing: 0) {
                        headerSection
                        if vm.showResourceCard {
                            PatternResourceCardView(onDismiss: { vm.dismissResourceCard() })
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        heroSection
                        weekRow
                        if let entry = vm.todayEntry {
                            writtenTodayRow(entry: entry)
                                .animation(.easeOut(duration: 0.35), value: vm.hasPostedToday)
                        }
                        pastSlot             // ← an arrived letter, else a pending Echo
                        spilrNoticedCard     // ← bridge to Mirror
                        askJournalPill       // ← "Ask your journal anything"
                    }
                }
                .refreshable { await vm.load() }
            }
            .navigationBarHidden(true)
            .task {
                await vm.load()
                // Push permission is NEVER requested cold. We only ask once the
                // user already has at least one entry — asking a brand-new user
                // before they've written anything tanks the opt-in rate. The
                // very-first-entry case is handled at the celebration-sheet
                // dismiss below (the ideal high-consent moment). iOS shows the
                // system prompt only once regardless of how often this is called.
                if !vm.recentEntries.isEmpty {
                    PushNotificationManager.shared.requestAuthorization()
                }
            }
            .fullScreenCover(isPresented: $showingTimedSession, onDismiss: {
                Task {
                    async let fast: () = checkFirstEntryFast()
                    async let reload: () = vm.load()
                    await (fast, reload)
                    checkFirstEntry()  // fallback if fast check raced
                }
            }) {
                // The Spilr-style write screen ("forget 90" — no countdown).
                SpillWriteView(userId: vm.userId, prompt: spillPrompt) {
                    Task {
                        async let fast: () = checkFirstEntryFast()
                        async let reload: () = vm.load()
                        await (fast, reload)
                        checkFirstEntry()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingDailyChat, onDismiss: {
                Task {
                    async let fast: () = checkFirstEntryFast()
                    async let reload: () = vm.load()
                    await (fast, reload)
                    checkFirstEntry()
                }
            }) {
                // Day One-style interactive journaling — chat, then weave an entry.
                DailyChatView(userId: vm.userId, startWithDictation: startChatWithDictation) {
                    Task {
                        async let fast: () = checkFirstEntryFast()
                        async let reload: () = vm.load()
                        await (fast, reload)
                        checkFirstEntry()
                    }
                }
            }
            .sheet(isPresented: $showingStartSheet, onDismiss: {
                // Reset in onDismiss, not onAppear — otherwise reopening the
                // sheet lands straight back on the gallery instead of the
                // options screen.
                startPath = []
                handlePendingStart()
            }) {
                NavigationStack(path: $startPath) {
                    StartOptionsView(
                        onPick: { choice in
                            // A fullScreenCover can't be presented while this
                            // sheet is still dismissing — stash the choice and
                            // let onDismiss above fire it once the sheet is
                            // actually gone, rather than acting here directly.
                            pendingStart = choice
                            showingStartSheet = false
                        },
                        onOpenTemplates: { startPath = [.templates] }
                    )
                    .navigationDestination(for: StartRoute.self) { _ in
                        TemplateGalleryView(onStart: { template in
                            // Same stash-and-dismiss dance as the other three
                            // choices — the runner is a fullScreenCover, and
                            // one can't present while this sheet is still
                            // dismissing.
                            pendingStart = .template(template)
                            showingStartSheet = false
                        })
                    }
                }
                .presentationDetents(startPath.isEmpty ? [.height(420)] : [.large])
                // `StartOptionsView` draws its own drag-handle capsule, so the
                // system indicator stays hidden here too — otherwise the two
                // overlap on the options screen.
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                // `.clear`, not `AppTheme.paper` — `StartOptionsView` now
                // paints its own rounded-top background (see
                // `sheetCornerRadius` there). A system-drawn background here
                // left a seam along the top edge against dark content behind
                // the sheet (e.g. the "Today with Spilr" card) on the custom
                // `.height(420)` detent.
                .presentationBackground(.clear)
            }
            .fullScreenCover(item: $runningTemplate, onDismiss: {
                Task {
                    async let fast: () = checkFirstEntryFast()
                    async let reload: () = vm.load()
                    await (fast, reload)
                    checkFirstEntry()
                }
            }) { template in
                TemplateRunnerView(userId: vm.userId, template: template) {
                    Task {
                        async let fast: () = checkFirstEntryFast()
                        async let reload: () = vm.load()
                        await (fast, reload)
                        checkFirstEntry()
                    }
                }
            }
            .sheet(item: $celebrationEntry, onDismiss: {
                firstEntryCelebrationShown = true
                // The user just wrote and celebrated their first entry — the
                // highest-consent moment there is. Ask for push permission now,
                // not cold on first launch.
                PushNotificationManager.shared.requestAuthorization()
            }) { entry in
                FirstEntryCelebrationSheet(entry: entry) {
                    firstEntryCelebrationShown = true
                    celebrationEntry = nil
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showAsk) {
                AskView(userId: vm.userId)
            }
            .sheet(item: $vm.selectedLetter) { letter in
                JournalEditorView(userId: vm.userId, existingEntry: letter)
            }
            .sheet(item: $answeringEcho, onDismiss: { vm.answerEcho() }) { echo in
                EchoAnsweredView(echo: echo)
            }
        }
        .trackScreen(.home)
    }

    /// First name for the header greeting. Falls back to "there" rather than
    /// ever rendering a bare email address as a name.
    private var greetingName: String {
        guard
            let displayName = authViewModel.currentUser?.displayName?
                .trimmingCharacters(in: .whitespaces),
            !displayName.isEmpty,
            let first = displayName.split(separator: " ").first
        else { return "there" }
        return String(first)
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    /// Day-one gets a plain welcome; a returning user gets a time-of-day
    /// greeting. Branches on `recentEntries.isEmpty`, same signal the rest of
    /// Home already uses to detect a brand-new account.
    private var headerTitle: String {
        vm.recentEntries.isEmpty
            ? "Hi \(greetingName)."
            : "\(timeOfDayGreeting),\n\(greetingName)"
    }

    /// State-aware subtitle for the Today header.
    ///
    /// Deliberately has NO loading branch — see `headerReady` below, which
    /// holds this (and `headerTitle`) invisible until every value it reads is
    /// actually resolved, so the header commits to its wording once rather
    /// than visibly rewriting itself.
    private var headerSubtitle: String {
        let weekday = Date().formatted(.dateTime.weekday(.wide))

        guard !vm.recentEntries.isEmpty else {
            return "\(weekday) · welcome to your first day"
        }
        guard let stats = vm.stats, stats.entryCount > 0, let last = stats.lastEntryAt else {
            return weekday
        }
        if Calendar.current.isDateInToday(last) {
            return "\(weekday) · you wrote today"
        }
        let lastWeekday = last.formatted(.dateTime.weekday(.wide))
        return "\(weekday) · you last wrote on \(lastWeekday)"
    }

    /// Both header lines depend on data from two independent fetches
    /// (entries, and — for a returning user only — stats). Gating on entries
    /// alone would let the subtitle render without its entry count for a
    /// frame whenever stats resolves slightly later, then silently gain it —
    /// the exact flicker `entriesLoaded` was introduced to prevent. Day-one
    /// never reads `stats`, so it doesn't wait on it.
    private var headerReady: Bool {
        vm.entriesLoaded && (vm.recentEntries.isEmpty || vm.statsLoaded)
    }

    // MARK: - Header (prototype "screen-head")
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(AppTheme.editorialDisplay(size: 30))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(2)
                Text(headerSubtitle)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            // Fade on the READY state, not on the strings. Both lines hold
            // their space (sized off whatever content is current) and arrive
            // together once, already in their final wording.
            .opacity(headerReady ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: headerReady)
            Spacer()
            // Single profile chip showing the user's initial.
            Button { showProfile = true } label: {
                avatarChip(profileInitial, colors: [AppTheme.rose, AppTheme.lav])
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 22)
    }

    /// A circular gradient avatar chip (used in the header stack).
    private func avatarChip(_ text: String, colors: [Color]) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.cream)
            .frame(width: 38, height: 38)
            .background(
                LinearGradient(colors: colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
            .overlay(Circle().stroke(AppTheme.cream, lineWidth: 2))
            .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
    }

    // MARK: - Hero section
    //
    // "Today's Read" (a quiet, AI-generated line above the invitation card)
    // was removed — see git history. `InvitationCardView` now carries the
    // hero alone.

    private var heroSection: some View {
        invitationCard
    }

    /// The dark hero CTA — always present, always the primary way in.
    private var invitationCard: some View {
        InvitationCardView(
            dayOne: vm.entriesLoaded ? vm.recentEntries.isEmpty : nil,
            onPrimary: { showingDailyChat = true },
            onMoreWays: { showingStartSheet = true }
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    /// Five dots, filled for each distinct day written this week (capped at
    /// 5 — a week can have more, the row doesn't grow). Non-judgmental by
    /// design, matching onboarding's "no streaks" promise: no loss language,
    /// nothing about a gap, just what happened.
    @ViewBuilder
    private var weekRow: some View {
        if vm.entriesLoaded && !vm.recentEntries.isEmpty {
            let filled = min(vm.daysWrittenThisWeek, 5)
            HStack(spacing: 9) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i < filled ? AppTheme.terracotta : AppTheme.terracotta.opacity(0.28))
                            .frame(width: 8, height: 8)
                    }
                }
                Text("\(vm.daysWrittenThisWeek) \(vm.daysWrittenThisWeek == 1 ? "day" : "days") this week")
                    .font(AppTheme.editorialBody(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func writtenTodayRow(entry: JournalEntry) -> some View {
        Button {
            router.showInJournal(entryId: entry.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)

                Text("written today")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(2)
                    .textCase(.uppercase)

                Spacer()

                Text("See it in your Journal")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.terracotta)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.terracotta)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.cream.opacity(0.7))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppTheme.terracotta.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - A message from your past
    //
    // A Future Self letter you scheduled, or (failing that) a pending Echo the
    // AI surfaced from one of your own entries. Never both, never a list — the
    // letter wins because you chose to send it and it's date-certain.

    @ViewBuilder
    private var pastSlot: some View {
        if let letter = vm.arrivedLetters.first {
            letterArrivedCard(letter)
        } else if let echo = vm.pendingEcho {
            EchoCardView(
                echo: echo,
                onSkip: { vm.skipEcho() },
                onNotYet: { vm.skipEcho() },
                onAnswer: { answeringEcho = echo },
                onThemeTap: { router.showInJournal(entryId: nil) }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private func letterArrivedCard(_ entry: JournalEntry) -> some View {
        Button { vm.openLetter(entry) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.gold)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text("A LETTER HAS ARRIVED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.gold)
                        .tracking(1.5)

                    Text("From you, \(entry.shortFormattedDate)")
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.ink)

                    Text("Open it \u{2192}")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.gold)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppTheme.gold.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.gold.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Spilr noticed (bridge to Mirror)

    @ViewBuilder
    private var spilrNoticedCard: some View {
        if let title = mirrorVM.bridgeInsightTitle {
            Button { router.showMirror() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.lav)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("SPILR NOTICED")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.lav)
                            .tracking(1.5)

                        Text(title)
                            .font(AppTheme.editorialBody(size: 14))
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)

                        Text("See it in Mirror \u{2192}")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.lav)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(AppTheme.lav.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.lav.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Ask your journal pill

    @ViewBuilder
    private var askJournalPill: some View {
        if vm.recentEntries.count >= 5 {
            Button { showAsk = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    Text("Ask your journal anything\u{2026}")
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
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }


    /// First letter of the user's display name (or email) for the avatar chip.
    private var profileInitial: String {
        let source = authViewModel.currentUser?.displayName?.trimmingCharacters(in: .whitespaces)
            ?? authViewModel.currentUser?.email
            ?? "·"
        return String(source.prefix(1)).uppercased()
    }
}

