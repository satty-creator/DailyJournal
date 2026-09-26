//
//  OnboardingView.swift
//  DailyJournal
//
//  Onboarding shown to new users after sign-in (Spilr Redesign 2a —
//  "goals-first, 3 taps"):
//    Step 1 — "What brings you here, really?": multi-select goals
//    Step 2 — "When Spilr speaks back…": a tone (Gentle / Curious / Direct)
//    Step 3 — "Then let's start where it's loudest.": a real opening
//              question, answered by typing or talking — landing directly
//              in the first guided session (DailyChatView). Completing that
//              session (weaving + saving an entry) is what finishes
//              onboarding — but it's not the ONLY way to finish it: a quiet
//              "I'll do this later" under the two answer buttons also
//              completes onboarding, with no entry written. Without it, a
//              user who backs out of the chat (or never wants to answer
//              right now) had no way to reach the app at all.
//
//  Theme picking and AI-insights consent are deliberately NOT asked here —
//  both move to after the first entry: theme stays changeable any time from
//  Profile → Appearance (default `.bloom`), and consent is asked by
//  `RetroAIConsentSheet` (see RootView.swift), which already fires the
//  moment `aiConsentGranted` is nil — true for every user the instant they
//  land on MainTabView with no AI Insights decision on file, onboarding
//  having asked for one or not.
//
//  The goals + tone the user picks are persisted via `OnboardingIntent` and
//  read by `SpilrVoice.intentContext()` on every AI prompt thereafter — see
//  that function's doc comment for how it reaches the model without a
//  second call site to keep in sync.
//
//  Completion is tracked in UserDefaults under "spilr.onboardingCompleted".
//  RootView routes here when the user is authenticated but has not completed
//  onboarding yet. After completion it falls through to MainTabView.
//
//  See onboardingprd.md.
//

import SwiftUI
// For `ListenerRegistration` — `EntryInsightsObserver` below holds a live
// snapshot listener on the just-written entry.
import FirebaseFirestore

// MARK: - UserDefaults keys (shared with RootView, AIService)
extension UserDefaults {
    static let onboardingCompletedKey = "spilr.onboardingCompleted"
    var onboardingCompleted: Bool {
        get { bool(forKey: Self.onboardingCompletedKey) }
        set { set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    // Three-state AI consent:
    //   nil (key absent)  → not yet asked  → show consent on next onboarding / launch
    //   true              → user accepted  → AI features enabled
    //   false             → user declined  → local fallbacks only
    static let aiConsentKey = "spilr.aiConsentGranted"
    var aiConsentGranted: Bool? {
        get { object(forKey: Self.aiConsentKey) as? Bool }
        set {
            if let v = newValue { set(v, forKey: Self.aiConsentKey) }
            else { removeObject(forKey: Self.aiConsentKey) }
        }
    }

    /// True once the user has seen the calendar step (new users) or the
    /// retro-prompt sheet (existing users) — see `RetroCalendarConnectSheet`
    /// in RootView.swift. Whether they connected is tracked separately by
    /// `CalendarService.isConnected`; this just prevents re-asking.
    static let calendarConsentAskedKey = "spilr.calendarConsentAsked"
    var calendarConsentAsked: Bool {
        get { bool(forKey: Self.calendarConsentAskedKey) }
        set { set(newValue, forKey: Self.calendarConsentAskedKey) }
    }
}

// MARK: - Onboarding container

struct OnboardingView: View {

    /// Called once the first guided session has been woven and saved;
    /// RootView switches to MainTabView. (@AppStorage reacting to
    /// `onboardingCompleted` does the actual switch — see `finishOnboarding`.)
    let onComplete: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var step = 0
    @State private var selectedGoals: Set<JournalGoal> = OnboardingIntent.selectedGoals
    @State private var selectedTone: SpilrTone = OnboardingIntent.tone
    @State private var startedAt = Date()
    @State private var showingChat = false
    @State private var chatStartsWithDictation = false

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            // Each step fills the screen and transitions horizontally.
            Group {
                switch step {
                case 0: goalsStep
                case 1: toneStep
                // `calendarConnectStep` (case 2) is temporarily out of the flow —
                // Google Calendar connect doesn't work for real users yet (OAuth
                // app is unverified, capped at test users). Kept below, unused,
                // to re-enable once verification clears: restore `case 2:
                // calendarConnectStep`, bump progressDots back to 0..<4, and
                // restore the step transitions this diff reverted.
                default: firstQuestionStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal:   .move(edge: .leading)
            ))
            .id(step)
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .onAppear {
            startedAt = Date()
            AnalyticsManager.shared.trackOnboardingStarted()
        }
        .trackScreen(.onboarding)
        // The first guided session — presented full-screen from step 3.
        // Landing here doesn't finish onboarding by itself; only actually
        // weaving and saving an entry does (`onSave` → `finishOnboarding`),
        // so backing out just returns to "Answer it" rather than skipping
        // the one thing onboarding exists to get the user to.
        //
        // `isOnboarding: true` keeps the lower 2-turn save floor for a first entry
        // and avoids stacking the one-time Thought Journal education sheet over
        // this cover. The opener shown on the step-3 card (`firstQuestion` below)
        // is the same `AIService.chatOpener` this session opens on, so the two
        // stay in sync automatically.
        .fullScreenCover(isPresented: $showingChat) {
            DailyChatView(
                userId: authViewModel.currentUser?.id ?? "",
                startWithDictation: chatStartsWithDictation,
                isOnboarding: true,
                onSave: { finishOnboarding() }
            )
        }
    }

    // MARK: - Step 1: Goals
    private var goalsStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    progressDots(current: 0)
                        .padding(.top, 60)

                    BloomMarkView(size: 42)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What brings you\nhere, really?")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Pick as many as feel true. This shapes how Spilr talks to you \u{2014} not a label, and never shared.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(JournalGoal.allCases) { goal in
                            goalRow(goal)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            stickyNext(title: "Continue", disabled: selectedGoals.isEmpty) {
                OnboardingIntent.selectedGoals = selectedGoals
                withAnimation { step = 1 }
            }
        }
    }

    private func goalRow(_ goal: JournalGoal) -> some View {
        let selected = selectedGoals.contains(goal)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) {
                if selected { selectedGoals.remove(goal) } else { selectedGoals.insert(goal) }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? AppTheme.terracottaDeep : Color.clear)
                        .overlay(
                            Circle().stroke(selected ? Color.clear : AppTheme.inkSoft.opacity(0.3), lineWidth: 1.5)
                        )
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(AppTheme.cream)
                    }
                }
                .frame(width: 22, height: 22)

                Text(goal.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [AppTheme.terracotta.opacity(0.16), AppTheme.cream],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(AppTheme.cream)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? AppTheme.terracottaDeep : AppTheme.inkSoft.opacity(0.14),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
    }

    // MARK: - Step 2: Tone
    private var toneStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        backButton { step = 0 }
                        progressDots(current: 1)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("When Spilr\nspeaks back\u{2026}")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Same words, three temperatures. You can change this any time.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        ForEach(SpilrTone.allCases) { tone in
                            toneCard(tone)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            stickyNext(title: "This one") {
                OnboardingIntent.tone = selectedTone
                // Would normally go to `calendarConnectStep` (step 2) — see the
                // disabled-step note in `body` above. `step = 2` now falls
                // through to `default: firstQuestionStep` while that's off.
                withAnimation { step = 2 }
            }
        }
    }

    // MARK: - Step 3: Connect Google Calendar (optional, skippable) — DISABLED
    //
    // Not currently reachable from `body`'s switch: the Google Calendar OAuth
    // app is unverified, so connecting fails (or shows a scary warning screen)
    // for every real user except the handful added as test users. Kept here,
    // unused, to restore once verification clears — see the note in `body`.
    private var calendarConnectStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        backButton { step = 1 }
                        progressDots(current: 2)
                    }
                    .padding(.top, 60)

                    Image(systemName: "calendar")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.terracotta)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("See your day\nalongside Spilr.")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                        Text("Connect Google Calendar to view your events right inside Spilr. Read-only \u{2014} we never edit or create anything. Totally optional, and you can connect later from Settings.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 0) {
                Button {
                    Task {
                        await CalendarService.shared.connect()
                        UserDefaults.standard.calendarConsentAsked = true
                        withAnimation { step = 3 }
                    }
                } label: {
                    Text("Connect Google Calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                // Connecting is entirely optional — declining here (or in the
                // Google consent screen itself) never blocks onboarding, same
                // shape as the "I'll do this later" escape hatch on step 4.
                Button {
                    UserDefaults.standard.calendarConsentAsked = true
                    withAnimation { step = 3 }
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(
                AppTheme.paper
                    .ignoresSafeArea(edges: .bottom)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            )
        }
    }

    private func toneCard(_ tone: SpilrTone) -> some View {
        let selected = selectedTone == tone
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) { selectedTone = tone }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(tone.emoji).font(.system(size: 16))
                    Text(tone.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    // Always Curious — matches the pre-selected default
                    // (`OnboardingIntent.tone`'s own fallback), not adaptive
                    // to the goals picked on the previous step.
                    if tone == .curious {
                        Text("SUGGESTED")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.lavDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.lav.opacity(0.32))
                            .clipShape(Capsule())
                    }
                }
                Text("\u{201C}\(tone.sampleLine)\u{201D}")
                    .font(AppTheme.editorialBody(size: 14).italic())
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [AppTheme.lav.opacity(0.22), AppTheme.cream],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(AppTheme.cream)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? AppTheme.lavDeep : AppTheme.inkSoft.opacity(0.14), lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: First question
    private var firstQuestionStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        backButton { step = 1 }
                        progressDots(current: 2)
                    }
                    .padding(.top, 60)

                    Text("FOR: \(forLine)")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.lavDeep)
                        .tracking(1.4)

                    Text("Then let\u{2019}s start\nwhere it\u{2019}s loudest.")
                        .font(AppTheme.editorialDisplay(size: 30))
                        .foregroundStyle(AppTheme.ink)
                        .lineSpacing(2)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("SPILR ASKS")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.terracotta)
                            .tracking(2)
                        Text(firstQuestion)
                            .font(AppTheme.editorialDisplay(size: 22, weight: .heavy))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Type a few words or hold to talk. There\u{2019}s no wrong answer, and you can stop whenever.")
                            .font(AppTheme.editorialBody(size: 13.5))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .background(AppTheme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 8)

                    Text("You\u{2019}re one sentence in already. That\u{2019}s the whole habit.")
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Button {
                        chatStartsWithDictation = false
                        showingChat = true
                    } label: {
                        Text("Answer it")
                            .accessibilityIdentifier("onboarding.answer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
                    }
                    .buttonStyle(.plain)

                    Button {
                        chatStartsWithDictation = true
                        showingChat = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.cream)
                            .frame(width: 54, height: 54)
                            .background(AppTheme.ink)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Answer by talking")
                }
                .padding(.horizontal, 24)

                // The escape hatch. Onboarding used to have no way out short
                // of actually weaving and saving a first entry in
                // DailyChatView — closing that sheet just returns here. A
                // user who doesn't want to write yet (or can't right now)
                // was stuck. This never disables and never gates on
                // anything; it's deliberately the quieter of the two paths
                // so "Answer it" still reads as the intended one.
                Button {
                    finishOnboarding(wroteEntry: false)
                } label: {
                    Text("I'll do this later")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.later")
                .padding(.top, 14)
            }
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(
                AppTheme.paper
                    .ignoresSafeArea(edges: .bottom)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            )
        }
    }

    /// "QUIET MY HEAD AT NIGHT · CURIOUS" — every selected goal (there's
    /// always at least one; step 1 won't let the user past with none), the
    /// chosen tone.
    private var forLine: String {
        let goalPart = selectedGoals.map(\.rawValue).sorted().joined(separator: " · ")
        return "\(goalPart) · \(selectedTone.title)".uppercased()
    }

    /// A real, grounded opener — not onboarding-only copy — so the promise "answer
    /// this and you're already inside your first entry" is actually true: it's the
    /// exact question `DailyChatView` opens on below.
    private var firstQuestion: String { AIService.chatOpener }

    private func finishOnboarding(wroteEntry: Bool = true) {
        // Spilr Pro: the paywall is shown once, right as the user lands in the
        // app — MainTabView consumes this flag (see PaywallPresenter).
        PaywallPresenter.hasPendingOnboardingPaywall = true
        UserDefaults.standard.onboardingCompleted = true
        AnalyticsManager.shared.trackOnboardingCompleted(
            totalSteps: 3,
            duration: Date().timeIntervalSince(startedAt),
            wroteFirstEntry: wroteEntry
        )
        onComplete()
    }

    // MARK: - Progress dots
    private func progressDots(current: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AppTheme.terracotta : AppTheme.inkSoft.opacity(0.25))
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
    }

    // MARK: - Back chevron
    private func backButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35), action)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    // MARK: - Sticky next button
    private func stickyNext(title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .padding(.top, 12)
        .background(
            AppTheme.paper
                .ignoresSafeArea(edges: .bottom)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .accessibilityIdentifier("onboarding.next")
    }
}

// MARK: - Live insights for the celebration sheet
//
// The sheet is opened from a snapshot `HomeView.checkFirstEntryFast` reads out of
// Firestore's local cache milliseconds after the entry is written, while
// `EntryEnrichment`'s Gemini call is still in flight — so `aiSummaryBullets` is
// empty on the copy the sheet receives, and a plain value type would never learn
// otherwise. This watches the entry document and republishes when
// `updateEntryInsights` patches it in.
//
// Deliberately shows nothing rather than a local template: a canned observation
// on the user's very first entry is the one place it is most likely to be read as
// Spilr's real judgement of what they wrote.
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

// MARK: - First entry congratulations sheet
//
// Shown as a sheet when the user saves their FIRST ever entry. Surfaces a
// congratulations message and the AI insight — which almost always arrives after
// the sheet is already on screen, so it fades in via `EntryInsightsObserver`.

struct FirstEntryCelebrationSheet: View {

    let entry: JournalEntry
    let onDone: () -> Void

    @StateObject private var insights = EntryInsightsObserver()
    private let service = JournalService()

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Congratulations header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("✦")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.terracotta)
                            .padding(.top, 8)

                        Text("First entry.\nThat took courage.")
                            .font(AppTheme.editorialDisplay(size: 32))
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(2)
                    }

                    // Reflection — Gemini's bullets, which almost always land
                    // after this sheet is already up (see EntryInsightsObserver).
                    insightCard

                    // 7-day promise
                    sevenDayPromiseCard

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }

            // Sticky done button
            VStack {
                Spacer()
                Button(action: onDone) {
                    Text("Start journaling")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
                .padding(.top, 12)
                .background(
                    AppTheme.paper
                        .ignoresSafeArea(edges: .bottom)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
            }
        }
        .onAppear { insights.start(entry: entry, service: service) }
        .onDisappear { insights.stop() }
    }

    // MARK: - Deep reflection (Gemini only)
    //
    // Three states, in the order a first-time user actually hits them:
    //   waiting  — the enrichment call is still in flight; show the placeholder
    //   bullets  — Gemini answered; fade the real observations in
    //   neither  — the call failed or timed out; render nothing at all
    //
    // There is deliberately no local fallback here. This is the first thing Spilr
    // ever says about something the user wrote, so a canned line is the most
    // expensive place in the app to be caught bluffing.
    @ViewBuilder
    private var insightCard: some View {
        if insights.isWaiting {
            insightPlaceholder
        } else if !insights.bullets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("SPILR HEARD")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta)
                    .tracking(2)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(insights.bullets.enumerated()), id: \.offset) { _, bullet in
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

                if let question = insights.question, !question.isEmpty {
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
            .animation(.easeOut(duration: 0.35), value: insights.bullets)
        }
    }

    /// Honest waiting state — says what is actually happening rather than filling
    /// the space with a guess. Two bars sized like the two bullets that replace them,
    /// so the card doesn't jump when they arrive.
    private var insightPlaceholder: some View {
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

    // MARK: - 7-day promise
    private var sevenDayPromiseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.terracotta)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.terracotta.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("The 7-day promise")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }

            Text("Write 3 times this week and we'll show your first reflection pattern.")
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Spilr gets sharper the more you write — and honest observations like the one above start immediately.")
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppTheme.cream.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func nextCard(icon: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 34, height: 34)
                .background(AppTheme.terracotta.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(body)
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppTheme.cream.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
