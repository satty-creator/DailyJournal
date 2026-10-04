//
//  OnboardingView.swift
//  DailyJournal
//
//  Onboarding shown to new users after sign-in (Spilr Redesign 2b — a short
//  personal intake before the paywall, not a 3-tap skim):
//
//    0. Welcome       — a 3-card tour: write/talk, Spilr asks, it remembers.
//    1. Goals         — "What brings you here, really?": multi-select.
//    2. Struggle      — "What's hard right now?": a chip + optional free text.
//    3. People        — "Who's in your life?": optional, skippable chips.
//    4. Baseline      — "How heavy do things feel lately?": 0–10, logged to
//                        `MoodLogService` as the first point on the Mirror
//                        tab's heaviness chart.
//    5. Tone          — "When Spilr speaks back…", pre-selected from goals.
//    6. Consent       — AI consent, asked plainly, as an equal choice.
//    7. First entry   — a fixed opening line (see `openingQuestion` below —
//                        deliberately NOT AI-written; see its doc comment),
//                        opening `TemplateRunnerView` on a guided thought
//                        record with a 0–10 rating before and after.
//
//  Completing the guided entry (weaving + saving) shows `SecondLookView` —
//  the payoff: the before/after delta (when it eased) and Spilr's
//  reflection on what was just written — before onboarding actually
//  finishes. Only a completed entry triggers the onboarding paywall; "I'll
//  do this later" (on step 7, or backing out of the guided entry) goes
//  straight to Home instead — see `finishOnboarding`.
//
//  Theme picking is deliberately NOT asked here — it's changeable any time
//  from Profile → Appearance (default `.bloom`).
//
//  The intake answers are persisted via `OnboardingIntent` and read by
//  `SpilrVoice.intentContext()` on every AI prompt thereafter, and (for the
//  struggle + people steps) folded into `LifeContext` by
//  `OnboardingLifeContextSeed` right after consent — see those files' doc
//  comments for how each reaches the model with no second call site to keep
//  in sync.
//
//  Completion is tracked in UserDefaults under "spilr.onboardingCompleted".
//  RootView routes here when the user is authenticated but has not completed
//  onboarding yet. After completion it falls through to MainTabView.
//
//  See onboardingprd.md.
//

import SwiftUI
// For `ListenerRegistration` — `EntryInsightsObserver` (own file) holds a
// live snapshot listener on the just-written entry.
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

    /// True once the user has seen the calendar connect step. Whether they
    /// connected is tracked separately by `CalendarService.isConnected`; this
    /// just prevents re-asking. (The returning-user retro-prompt sheet that set
    /// this was removed while Google Calendar OAuth remains unverified.)
    static let calendarConsentAskedKey = "spilr.calendarConsentAsked"
    var calendarConsentAsked: Bool {
        get { bool(forKey: Self.calendarConsentAskedKey) }
        set { set(newValue, forKey: Self.calendarConsentAskedKey) }
    }
}

// MARK: - Onboarding container

struct OnboardingView: View {

    /// Called once onboarding is done — either a completed guided first
    /// entry (having passed through `SecondLookView`) or "I'll do this
    /// later". RootView switches to MainTabView. (@AppStorage reacting to
    /// `onboardingCompleted` does the actual switch — see `finishOnboarding`.)
    let onComplete: () -> Void

    private enum Step: Int {
        case welcome, goals, struggle, people, baseline, tone, consent, firstEntryIntro
    }

    /// The guided first entry's opening line — deliberately fixed, not
    /// AI-written. This used to be generated per-user from the goals/struggle/
    /// people/baseline intake answers (`AIService.onboardingOpeningQuestion`,
    /// now removed), but a brand-new user has no way to tell "Spilr wrote
    /// this specifically for me" apart from "Spilr always asks something a
    /// little different," so the variance just read as unpredictable rather
    /// than personal — see the chat around 2026-10-04. Same wording for
    /// everyone now; still resolved once and handed down as a constant
    /// rather than typed inline everywhere, so a future change only happens
    /// in one place.
    private static let openingQuestion =
        "What's on your mind right now? Tell me what you're working through: a worry, a task you're stuck on, a decision or just a brain dump. I'll follow your lead."

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var step: Step = .welcome
    @State private var selectedGoals: Set<JournalGoal> = OnboardingIntent.selectedGoals
    @State private var struggle: String? = OnboardingIntent.struggle
    @State private var struggleDetail: String = OnboardingIntent.struggleDetail ?? ""
    @State private var people: [OnboardingPerson] = OnboardingIntent.people
    @State private var baseline: Int? = OnboardingIntent.baseline
    @State private var selectedTone: SpilrTone = OnboardingIntent.tone
    @State private var userPickedTone = false
    @State private var startedAt = Date()

    @State private var showingGuidedEntry = false
    @State private var guidedEntryTemplate: JournalTemplate?
    /// Set by the guided entry's `onSaved` the instant it saves; consumed
    /// once `showingGuidedEntry` actually finishes dismissing (see the
    /// `.onChange` below) so the payoff's own `fullScreenCover` never tries
    /// to present while the guided entry's is still animating out.
    @State private var pendingSecondLookEntry: JournalEntry?
    @State private var showingSecondLook = false
    @State private var secondLookEntry: JournalEntry?

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            Group {
                switch step {
                case .welcome:
                    WelcomeStepView(onNext: { advance(to: .goals) })
                case .goals:
                    GoalsStepView(selectedGoals: $selectedGoals, onNext: advanceFromGoals)
                case .struggle:
                    StruggleStepView(
                        goals: selectedGoals,
                        struggle: $struggle,
                        struggleDetail: $struggleDetail,
                        onBack: { advance(to: .goals) },
                        onNext: advanceFromStruggle
                    )
                case .people:
                    PeopleStepView(
                        people: $people,
                        onBack: { advance(to: .struggle) },
                        onNext: advanceFromPeople
                    )
                case .baseline:
                    BaselineStepView(
                        baseline: $baseline,
                        onBack: { advance(to: .people) },
                        onNext: advanceFromBaseline
                    )
                case .tone:
                    ToneStepView(
                        goals: selectedGoals,
                        selectedTone: $selectedTone,
                        userPickedTone: $userPickedTone,
                        onBack: { advance(to: .baseline) },
                        onNext: advanceFromTone
                    )
                case .consent:
                    ConsentStepView(
                        onBack: { advance(to: .tone) },
                        onDecided: { _ in handleConsentDecided() }
                    )
                case .firstEntryIntro:
                    FirstEntryIntroStepView(
                        forLine: forLine,
                        openingQuestion: Self.openingQuestion,
                        onBack: { advance(to: .consent) },
                        onBegin: beginGuidedEntry,
                        onLater: { finishOnboarding(wroteEntry: false) }
                    )
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
        .onChange(of: step) { _, newStep in
            AnalyticsManager.shared.trackOnboardingStepViewed(String(describing: newStep))
        }
        .trackScreen(.onboarding)
        .fullScreenCover(isPresented: $showingGuidedEntry) {
            if let guidedEntryTemplate {
                TemplateRunnerView(
                    userId: authViewModel.currentUser?.id ?? "",
                    template: guidedEntryTemplate,
                    onSave: {},
                    onExitWithoutSaving: {},
                    onSaved: { entry in
                        logMoodDelta(for: entry)
                        pendingSecondLookEntry = entry
                    }
                )
            }
        }
        // The guided entry's own fullScreenCover must actually finish
        // dismissing before the payoff's is triggered — presenting two
        // full-screen covers back-to-back on the same view in one run loop
        // turn is undefined in UIKit. See `pendingSecondLookEntry`'s doc
        // comment above.
        .onChange(of: showingGuidedEntry) { _, isShowing in
            guard !isShowing, let entry = pendingSecondLookEntry else { return }
            pendingSecondLookEntry = nil
            secondLookEntry = entry
            showingSecondLook = true
        }
        .fullScreenCover(isPresented: $showingSecondLook) {
            if let secondLookEntry {
                SecondLookView(entry: secondLookEntry, onContinue: {
                    finishOnboarding(wroteEntry: true)
                })
            }
        }
    }

    // MARK: - Step transitions

    private func advance(to next: Step) {
        withAnimation { step = next }
    }

    private func advanceFromGoals() {
        OnboardingIntent.selectedGoals = selectedGoals
        advance(to: .struggle)
    }

    private func advanceFromStruggle() {
        OnboardingIntent.struggle = struggle
        let trimmedDetail = struggleDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        OnboardingIntent.struggleDetail = trimmedDetail.isEmpty ? nil : trimmedDetail
        if let struggle {
            AnalyticsManager.shared.trackOnboardingStruggleSelected(option: struggle, hasDetail: !trimmedDetail.isEmpty)
        }
        advance(to: .people)
    }

    private func advanceFromPeople() {
        OnboardingIntent.people = people
        AnalyticsManager.shared.trackOnboardingPeopleCount(people.count)
        advance(to: .baseline)
    }

    private func advanceFromBaseline() {
        OnboardingIntent.baseline = baseline
        if let baseline {
            AnalyticsManager.shared.trackOnboardingBaselineSet(baseline)
            if let uid = authViewModel.currentUser?.id, !uid.isEmpty {
                MoodLogService.shared.log(value: baseline, source: .baseline, userId: uid)
            }
        }
        advance(to: .tone)
    }

    private func advanceFromTone() {
        OnboardingIntent.tone = selectedTone
        advance(to: .consent)
    }

    private func handleConsentDecided() {
        let uid = authViewModel.currentUser?.id ?? ""
        if !uid.isEmpty {
            Task { await OnboardingLifeContextSeed.run(userId: uid) }
        }
        advance(to: .firstEntryIntro)
    }

    // MARK: - Opening question

    private func beginGuidedEntry() {
        guidedEntryTemplate = JournalTemplate.onboardingFirstEntry(openingQuestion: Self.openingQuestion)
        showingGuidedEntry = true
    }

    private func logMoodDelta(for entry: JournalEntry) {
        AnalyticsManager.shared.trackOnboardingFirstEntryDelta(
            before: entry.templateScaleBefore, after: entry.templateScaleAfter
        )
        guard let uid = authViewModel.currentUser?.id, !uid.isEmpty else { return }
        if let before = entry.templateScaleBefore {
            MoodLogService.shared.log(value: before, source: .entryBefore, userId: uid, at: entry.createdAt)
        }
        if let after = entry.templateScaleAfter {
            MoodLogService.shared.log(value: after, source: .entryAfter, userId: uid, at: entry.createdAt)
        }
    }

    /// "QUIET MY HEAD AT NIGHT · CURIOUS" — every selected goal (there's
    /// always at least one; the goals step won't let the user past with
    /// none), the chosen tone.
    private var forLine: String {
        let goalPart = selectedGoals.map(\.rawValue).sorted().joined(separator: " · ")
        return "\(goalPart) · \(selectedTone.title)".uppercased()
    }

    // MARK: - Finish

    /// Only a completed guided first entry queues the Spilr Pro paywall —
    /// "the app earns the paywall first". Skipping (here, or by backing out
    /// of the guided entry without saving) goes straight to Home; the AI-limit
    /// and Profile paywall triggers are unaffected.
    private func finishOnboarding(wroteEntry: Bool) {
        if wroteEntry {
            PaywallPresenter.hasPendingOnboardingPaywall = true
        }
        UserDefaults.standard.onboardingCompleted = true
        AnalyticsManager.shared.trackOnboardingCompleted(
            totalSteps: 8,
            duration: Date().timeIntervalSince(startedAt),
            wroteFirstEntry: wroteEntry
        )
        onComplete()
    }
}

// MARK: - First entry congratulations sheet
//
// Shown as a sheet when the user saves their FIRST ever entry, from
// anywhere in the app — not only onboarding's own guided entry (which shows
// `SecondLookView` instead, and sets `spilr.firstEntryCelebrationShown` so
// this never doubles up on the same entry). Surfaces a congratulations
// message and the AI insight, via the same `EntryInsightsObserver` and
// shared `SpilrHeardCard`/`SpilrHeardPlaceholder` views `SecondLookView` uses.

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
                    reflectionSection

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
    private var reflectionSection: some View {
        if insights.isWaiting {
            SpilrHeardPlaceholder()
        } else if !insights.bullets.isEmpty {
            SpilrHeardCard(bullets: insights.bullets, question: insights.question)
                .animation(.easeOut(duration: 0.35), value: insights.bullets)
        }
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
}
