//
//  HomeView.swift
//  DailyJournal
//

import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recentEntries: [JournalEntry] = []
    @Published var arrivedLetters: [JournalEntry] = []
    @Published var isLoading = false
    @Published var showingNinetySecond = false
    @Published var showingFreeWrite = false
    @Published var selectedLetter: JournalEntry?

    // ── Echoes ─────────────────────────────────────────────────────────
    /// The single pending echo to surface this session. Nil when none is
    /// available or after the user dismisses / answers it.
    @Published var pendingEcho: Echo?

    // ── Daily mood log ─────────────────────────────────────────────────
    /// Today's logged mood, if the user has checked in. Drives the mood widget's
    /// "already logged" state.
    @Published var todayMood: Mood?

    // ── Pattern callbacks ──────────────────────────────────────────────
    /// The single pattern callback to surface this session (nil = none / cleared).
    /// Separate system from Echoes — rarer, weightier, stitched from many entries.
    @Published var pendingCallback: PatternCallback?
    /// When true, a crisis signal was detected in the window: we show the soft
    /// opt-in resource card INSTEAD of any callback (non-negotiable safety flow).
    @Published var showResourceCard = false

    private let service          = JournalService()
    private let echoService      = EchoService()
    private let moodService      = MoodLogService()
    private let callbackService  = PatternCallbackService()
    private let detection        = PatternDetectionService.shared
    let userId: String

    private var settings: PatternSettings { PatternSettings(userId: userId) }

    init(userId: String) { self.userId = userId }

    func load() async {
        isLoading = true

        // Fan out all reads concurrently
        async let recent  = (try? await service.fetchRecentEntries(for: userId, limit: 5)) ?? []
        async let letters = (try? await service.fetchArrivedLetters(for: userId)) ?? []
        async let echo    = try? await echoService.fetchTopPendingEcho(for: userId)
        async let mood    = try? await moodService.fetchToday(for: userId)

        recentEntries  = await recent
        arrivedLetters = await letters
        todayMood      = (await mood)?.mood

        // Only set pendingEcho on the first load of a session — prevents the
        // card re-appearing on pull-to-refresh after the user has dismissed it.
        if pendingEcho == nil {
            pendingEcho = await echo
        }

        isLoading = false

        // Surface any callback already waiting, then kick off detection in the
        // background (throttled to ~once/20h inside the service).
        await refreshCallback()
        Task { [weak self] in await self?.runDetection() }
    }

    // MARK: - Pattern callbacks

    /// Surfaces the top eligible callback (if the frequency / quiet-hours / mute
    /// gates allow) and marks it shown. No-op once a card is already on screen.
    private func refreshCallback() async {
        guard pendingCallback == nil, !showResourceCard else { return }
        let all = (try? await callbackService.fetchAll(for: userId)) ?? []
        guard let callback = callbackService.surfaceableCallback(from: all, settings: settings)
        else { return }
        callbackService.markShown(callback)
        withAnimation(.easeOut(duration: 0.4)) { pendingCallback = callback }
    }

    /// Runs detection and reacts to the outcome. Crisis signals route to the soft
    /// resource card and never produce a callback.
    private func runDetection() async {
        switch await detection.detectIfNeeded(for: userId) {
        case .safetyRouted:
            let s = settings
            guard s.shouldShowResourceCard, pendingCallback == nil else { return }
            s.lastResourceCardShown = Date()
            withAnimation(.easeOut(duration: 0.4)) { showResourceCard = true }
        case .created:
            await refreshCallback()
        case .noPattern, .skipped:
            break
        }
    }

    /// "not now" — soft dismiss; the 4-day suppression window does the rest.
    func dismissCallback() {
        guard let callback = pendingCallback else { return }
        callbackService.markDismissed(callback)
        withAnimation(.easeOut(duration: 0.25)) { pendingCallback = nil }
    }

    /// "stop watching [entity]" — mutes the entity locally and in Firestore.
    func muteCallback() {
        guard let callback = pendingCallback else { return }
        if let entity = callback.entity { settings.mute(entity) }
        callbackService.markMuted(callback)
        withAnimation(.easeOut(duration: 0.25)) { pendingCallback = nil }
    }

    /// "I needed that" — strong positive signal; nudges this archetype's salience.
    func affirmCallback() {
        guard let callback = pendingCallback else { return }
        settings.recordAffirmation(callback.archetype)
        callbackService.markAnswered(callback)
        withAnimation(.easeOut(duration: 0.25)) { pendingCallback = nil }
    }

    /// Writing about a callback (from the stitched view) counts as engaging.
    func engageCallback(_ callback: PatternCallback) {
        settings.recordAffirmation(callback.archetype)
        callbackService.markAnswered(callback)
        withAnimation(.easeOut(duration: 0.25)) {
            if pendingCallback?.id == callback.id { pendingCallback = nil }
        }
    }

    /// Dismiss the soft resource card.
    func dismissResourceCard() {
        withAnimation(.easeOut(duration: 0.25)) { showResourceCard = false }
    }

    /// Logs (or updates) today's mood from the Home widget. Fire-and-forget
    /// write; we update local state immediately so the UI reflects it at once.
    func logMood(_ mood: Mood) {
        moodService.logMood(userId: userId, mood: mood)
        withAnimation(.easeInOut(duration: 0.2)) { todayMood = mood }
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
        withAnimation(.easeOut(duration: 0.25)) { pendingEcho = nil }
    }

    /// User confirmed the echo ("done ✓", "it happened", "noted").
    /// Called after the EchoAnsweredView sheet is closed.
    func answerEcho() {
        guard let echo = pendingEcho else { return }
        echoService.markAnswered(id: echo.id, userId: userId)
        withAnimation(.easeOut(duration: 0.25)) { pendingEcho = nil }
    }
}

// MARK: - HomeView
struct HomeView: View {
    @StateObject private var vm: HomeViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showingNinetySecond  = false
    @State private var showingFreeWrite     = false
    @State private var openedLetter: JournalEntry?
    // Echo sheets — capture the echo at tap time so the sheet content stays
    // stable even after vm.pendingEcho is cleared during the dismissal animation.
    @State private var activeEchoForAnswer: Echo?
    @State private var activeEchoForTheme:  Echo?
    // Pattern callback: the stitched tap-through sheet. Captured at tap time so
    // the sheet content stays stable even after vm.pendingCallback is cleared.
    @State private var activeCallbackForStitch: PatternCallback?

    init(userId: String) {
        _vm = StateObject(wrappedValue: HomeViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerSection
                        patternSection       // ← rare, weighty cross-entry callback (or safety card)
                        if !vm.arrivedLetters.isEmpty { lettersSection }
                        echoSection   // ← echo card sits above the prompt card
                        promptCard           // ← primary action: today's prompt + write CTAs
                        moodCheckInSection   // ← secondary: quick daily mood log (collapses once logged)
                        recentSection
                    }
                }
                .refreshable { await vm.load() }
            }
            .navigationBarHidden(true)
            .task { await vm.load() }
            .sheet(isPresented: $showingNinetySecond, onDismiss: { Task { await vm.load() } }) {
                NinetySecondSessionView(userId: vm.userId, onSave: {})
            }
            .sheet(isPresented: $showingFreeWrite, onDismiss: { Task { await vm.load() } }) {
                JournalEditorView(userId: vm.userId)
            }
            .sheet(item: $openedLetter) { letter in
                LetterReadView(entry: letter)
            }
            // Echo: answered / closing sheet.
            // onDismiss fires after the animation completes — at that point
            // activeEchoForAnswer is already nil, so answerEcho() is safe.
            .sheet(item: $activeEchoForAnswer, onDismiss: { vm.answerEcho() }) { echo in
                EchoAnsweredView(echo: echo)
            }
            // Echo: theme compilation sheet.
            // Viewing the compilation counts as engaging with the echo, so we
            // mark it answered (not just skipped) on dismiss.
            .sheet(item: $activeEchoForTheme, onDismiss: { vm.answerEcho() }) { echo in
                ThemeCompilationView(echo: echo, userId: vm.userId)
            }
            // Pattern callback: stitched tap-through. Writing about it marks the
            // callback answered (handled inside via onEngaged).
            .sheet(item: $activeCallbackForStitch) { callback in
                PatternStitchedView(
                    callback: callback,
                    userId:   vm.userId,
                    onEngaged: { vm.engageCallback(callback) }
                )
            }
        }
    }

    // MARK: - Pattern callback section
    //
    // Shows at most one thing: the soft safety resource card (if a crisis signal
    // was detected) OR a single pattern callback. Never both, never a list.
    @ViewBuilder
    private var patternSection: some View {
        if vm.showResourceCard {
            VStack(alignment: .leading, spacing: 0) {
                PatternResourceCardView(onDismiss: { vm.dismissResourceCard() })
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let callback = vm.pendingCallback {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("ninety noticed", count: nil)
                    .padding(.horizontal, 24)

                PatternCallbackCardView(
                    callback: callback,
                    onTap:    { activeCallbackForStitch = callback },
                    onNotNow: { vm.dismissCallback() },
                    onMute:   { vm.muteCallback() },
                    onAffirm: { vm.affirmCallback() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
                        .textCase(.uppercase)
                        .tracking(2)

                    Text(firstName)
                        .font(AppTheme.editorialDisplay(size: 38))
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer()
                Text(todayFormatted)
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 32)
    }

    // MARK: - Daily mood check-in
    //
    // A partial-screen, journal-free way to log how today feels. Tapping the
    // CTA writes a MoodLog and never opens the editor.
    private var moodCheckInSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(vm.todayMood == nil ? "How's today?" : "Today's mood", count: nil)
                .padding(.horizontal, 24)

            MoodBlobView(existingMood: vm.todayMood) { mood in
                vm.logMood(mood)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Letters section
    private var lettersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Letters from past you", count: vm.arrivedLetters.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.arrivedLetters) { letter in
                        LetterCardView(entry: letter) {
                            openedLetter = letter
                            vm.openLetter(letter)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: - Echo section
    //
    // Lives above the prompt card. Only renders when there's a surfaceable echo.
    // The card animates in/out with a combined slide+fade.
    @ViewBuilder
    private var echoSection: some View {
        if let echo = vm.pendingEcho {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("an echo", count: nil)
                    .padding(.horizontal, 24)

                EchoCardView(
                    echo: echo,
                    onSkip:     { vm.skipEcho() },
                    onNotYet:   { vm.skipEcho() },
                    // Capture the echo at tap time — the sheet(item:) binding
                    // holds its own stable reference so content never flickers
                    // if vm.pendingEcho is cleared during the dismiss animation.
                    onAnswer:   { activeEchoForAnswer = echo },
                    onThemeTap: { activeEchoForTheme  = echo }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Today's prompt card
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Today's prompt", count: nil)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 20) {
                // Prompt text
                Text(LocalAI.todayPrompt())
                    .font(AppTheme.editorialDisplay(size: 28))
                    .foregroundStyle(AppTheme.cream)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    // Primary CTA — just start writing.
                    Button {
                        showingFreeWrite = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Start writing")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.terracotta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.cream)
                        .clipShape(Capsule())
                    }

                    // Secondary — the 90-second mode, quieter.
                    Button {
                        showingNinetySecond = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.system(size: 12, weight: .medium))
                            Text("Try a 90-second session")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.cream.opacity(0.85))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Recent entries
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Recent entries", count: nil)
                .padding(.horizontal, 24)

            if vm.isLoading && vm.recentEntries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if vm.recentEntries.isEmpty {
                FriendlyEmptyState(
                    title: "No entries yet.",
                    subtitle: "Your first 90 seconds is waiting."
                )
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.recentEntries) { entry in
                        NavigationLink {
                            JournalEditorView(
                                userId: vm.userId,
                                existingEntry: entry
                            ) { Task { await vm.load() } }
                        } label: {
                            JournalCardView(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Helpers
    private func sectionLabel(_ text: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.5)
            if let count {
                Text("\(count)")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.terracotta)
                    .clipShape(Capsule())
            }
            Rectangle()
                .fill(AppTheme.inkSoft.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.bottom, 4)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Late night"
        }
    }

    private var firstName: String {
        let name = authViewModel.currentUser?.displayName ?? authViewModel.currentUser?.email ?? "there"
        return name.components(separatedBy: " ").first ?? name
    }

    private var todayFormatted: String {
        Date().formatted(.dateTime.weekday(.wide)) + "\n" +
        Date().formatted(.dateTime.month().day().year())
    }
}

// MARK: - Letter Card View (horizontal scroll)
struct LetterCardView: View {
    let entry: JournalEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("✉")
                        .font(.title2)
                    Spacer()
                    Text("tap to open")
                        .font(AppTheme.mono(size: 9))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(1)
                }
                Text("From you,")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                Text(entry.createdAt.formatted(.dateTime.month(.wide).day().year()))
                    .font(AppTheme.editorialDisplay(size: 15))
                    .foregroundStyle(AppTheme.ink)

                Text(String(entry.content.prefix(80)) + (entry.content.count > 80 ? "…" : ""))
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(3)
                    .lineSpacing(2)
            }
            .padding(16)
            .frame(width: 220)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.terracotta.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Letter Read View
struct LetterReadView: View {
    let entry: JournalEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Envelope header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FROM: YOU")
                                .font(AppTheme.mono(size: 10))
                                .foregroundStyle(AppTheme.inkSoft)
                                .tracking(2)
                            Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                .font(AppTheme.editorialDisplay(size: 22))
                                .foregroundStyle(AppTheme.ink)
                            if let deliveryDate = entry.futureSelfDeliveryDate {
                                Text("Delivered \(deliveryDate.formatted(.dateTime.month(.wide).day().year()))")
                                    .font(AppTheme.mono(size: 10))
                                    .foregroundStyle(AppTheme.terracotta)
                                    .tracking(1)
                            }
                        }
                        .padding(.top, 8)

                        Divider()
                            .overlay(AppTheme.inkSoft.opacity(0.2))

                        // The entry content
                        Text(entry.content)
                            .font(AppTheme.editorialBody(size: 17))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(6)

                        // AI summary if present
                        if !entry.aiSummaryBullets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("WHAT YOU FELT THEN")
                                    .font(AppTheme.mono(size: 10))
                                    .foregroundStyle(AppTheme.terracotta)
                                    .tracking(2)
                                ForEach(Array(entry.aiSummaryBullets.enumerated()), id: \.offset) { _, bullet in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("—").foregroundStyle(AppTheme.terracotta)
                                        Text(bullet).foregroundStyle(AppTheme.inkSoft)
                                    }
                                    .font(AppTheme.editorialBody(size: 14))
                                }
                            }
                            .padding(16)
                            .background(AppTheme.paperWarm)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Letter from past you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.terracotta)
                }
            }
        }
    }
}
