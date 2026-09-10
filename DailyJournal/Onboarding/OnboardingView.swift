//
//  OnboardingView.swift
//  DailyJournal
//
//  Three-tap onboarding shown to new users after sign-in (Spilr Redesign 2a
//  — "goals-first, 3 taps"):
//    Step 1 — "What brings you here, really?": multi-select goals
//    Step 2 — "When Spilr speaks back…": a tone (Gentle / Curious / Direct)
//    Step 3 — "Then let's start where it's loudest.": a real opening
//              question, answered by typing or talking — landing directly
//              in the first guided session (DailyChatView). Completing that
//              session (weaving + saving an entry) is what finishes
//              onboarding; there is no separate "done" tap.
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
        .fullScreenCover(isPresented: $showingChat) {
            DailyChatView(
                userId: authViewModel.currentUser?.id ?? "",
                startWithDictation: chatStartsWithDictation,
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
                withAnimation { step = 2 }
            }
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

            HStack(spacing: 11) {
                Button {
                    chatStartsWithDictation = false
                    showingChat = true
                } label: {
                    Text("Answer it")
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
            .padding(.bottom, 48)
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

    /// A real, grounded opener — the same one `HomeView`'s "Begin" and the
    /// chat's own cold-open use (`AIService.chatOpener`), not onboarding-only
    /// copy, so the promise "answer this and you're already inside your
    /// first entry" is actually true: it's the exact question `DailyChatView`
    /// opens on below.
    private var firstQuestion: String { AIService.chatOpener(for: .normal) }

    private func finishOnboarding() {
        UserDefaults.standard.onboardingCompleted = true
        AnalyticsManager.shared.trackOnboardingCompleted(
            totalSteps: 3,
            duration: Date().timeIntervalSince(startedAt)
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
    }
}

// MARK: - First entry congratulations sheet
//
// Shown as a sheet when the user saves their FIRST ever entry. Surfaces a
// congratulations message and displays the AI insight inline if already available
// — otherwise a local fallback observation while Gemini runs in the background.

struct FirstEntryCelebrationSheet: View {

    let entry: JournalEntry
    let onDone: () -> Void

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

                    // Instant topical insight — one plain sentence about what
                    // this entry is about, available immediately (no AI wait).
                    topicInsightCard

                    // Deep reflection card — uses AI bullets if ready, else local fallback
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
    }

    // MARK: - Instant topical insight
    // Builds a plain "This entry seems related to…" sentence from the entry's
    // tags + detected sentiment. Always available immediately — no API wait.
    private var topicInsightCard: some View {
        let topics = topicSentence
        return VStack(alignment: .leading, spacing: 10) {
            Text("SPILR NOTICED")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(2)

            Text(topics)
                .font(AppTheme.editorialDisplay(size: 20))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppTheme.rose2.opacity(0.6), AppTheme.lav.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Constructs the topical sentence from tags and/or sentiment.
    private var topicSentence: String {
        let sentiment = entry.sentimentLabel ?? LocalAI.detectSentiment(from: entry.content)
        let tags = entry.tags.prefix(3)

        if tags.isEmpty {
            // Warm, encouraging fallback for a first entry — tags arrive with
            // AI enrichment, so this is very common on entry #1.
            return "Something real is in here. Patterns start surfacing as you keep writing."
        }

        let tagList: String
        switch tags.count {
        case 1:
            tagList = tags[0]
        case 2:
            tagList = "\(tags[0]) and \(tags[1])"
        default:
            let all = Array(tags)
            tagList = "\(all.dropLast().joined(separator: ", ")), and \(all.last!)"
        }

        return "This entry seems related to \(tagList)."
    }

    // MARK: - Deep reflection (AI bullets or local fallback)
    private var insightCard: some View {
        let sentiment = entry.sentimentLabel ?? LocalAI.detectSentiment(from: entry.content)
        let bullets = entry.aiSummaryBullets.isEmpty
            ? SpilrVoice.localReflection(from: entry.content, sentiment: sentiment).observations
            : entry.aiSummaryBullets

        return VStack(alignment: .leading, spacing: 12) {
            // Only render the "SPILR HEARD" section when there's something to show.
            // Both AI bullets and local fallback can return empty (very short entry,
            // or a first-run race between save and enrichment).
            if !bullets.isEmpty {
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

                if let question = entry.aiQuestion {
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
