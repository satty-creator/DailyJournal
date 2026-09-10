//
//  DailyChatView.swift
//  DailyJournal
//
//  Daily Chat — a Day One-style interactive journaling surface. Spilr opens with a
//  question, the person replies in a familiar chat thread, Spilr asks adaptive
//  follow-ups, and at any point the conversation can be "woven" into a first-person
//  journal entry that's saved like any other (Echoes / River / Patterns all pick it
//  up). AI drives the follow-ups and the weaving; both degrade to on-device fallbacks
//  so the flow always works offline and never blocks.
//
//  See dailychatprd.md.
//

import SwiftUI
import UIKit

// MARK: - ViewModel

@MainActor
final class DailyChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    /// True while Spilr is composing its next line (the network round-trip).
    @Published var isThinking = false
    /// True while Spilr's received line is typing itself out on screen.
    @Published var isRevealing = false
    /// True once there's enough material to weave a worthwhile entry.
    @Published var readyToWeave = false
    /// True while the weaving AI pass is running.
    @Published var isWeaving = false
    /// The woven entry awaiting the user's accept/discard in the preview sheet.
    @Published var wovenPreview: String?
    @Published var showPreview = false
    /// Up to two Casual Vent quick-reply chips for the LATEST Spilr line — see
    /// `ChatTurn.suggestions`. Cleared the instant the user sends (or taps a
    /// chip, which fills the draft rather than auto-sending — see
    /// `DailyChatView`), so a stale chip never lingers past the turn it answers.
    @Published var suggestions: [String] = []

    /// The active chat mode (Casual Vent vs Unpack Stress). Defaults to the last
    /// mode the user chose — never locked in at onboarding.
    @Published var mode: ChatMode = ChatMode.lastUsed
    /// Set when the deterministic crisis gate trips — the UI shows a resource card.
    @Published var showCrisisResource = false
    /// True once the resource card has been shown this session. An explicit crisis
    /// signal still pauses the flow with `crisisReply` on every trip, but the modal
    /// itself only presents once — otherwise a conversation that mentions the same
    /// word again re-triggers the sheet on every subsequent message.
    private var hasShownCrisisResource = false
    /// Drives the one-time "what is a Thought Journal" education sheet, shown the
    /// first time the user ever lands in Thought Journal mode.
    @Published var showThoughtJournalEducation = false

    /// A same-day, not-yet-woven session found for this mode — offered as
    /// "resume where you left off" once the check below resolves. Non-nil only
    /// briefly, between that check landing and the user (or the view) acting
    /// on it.
    @Published var resumableSession: ChatSession?

    /// The calm, non-judgemental line shown when the crisis gate trips. We pause the
    /// flow here in both modes rather than let the model keep going.
    static let crisisReply = "I want to pause for a second. What you're describing sounds really heavy, and I'm a journaling tool — not a substitute for real support. If you might be in danger, please reach out: in the US you can call or text 988 (Suicide & Crisis Lifeline), any time. I'm still here whenever you want to keep writing."

    let userId: String
    private let service = JournalService()
    /// This conversation's own persisted identity — see ChatSession.swift.
    /// `var`, not `let`: `resume(_:)` adopts an existing session's id/start
    /// time, and `setMode(_:)` mints a fresh one for the new thread.
    private var sessionId = UUID().uuidString
    private var sessionStartedAt = Date()
    /// Rolling running-state memory (see `ChatSessionState`), refreshed every 6 user
    /// turns and passed to `nextChatTurn` so a long session stays coherent without
    /// the old "forget everything before this point" instruction.
    private var sessionState: ChatSessionState?
    /// The in-flight send/reveal `Task`, retained so it can actually be cancelled —
    /// previously fire-and-forget, so discarding a conversation or leaving the screen
    /// mid-turn let the network call keep running and land its reply/autosave anyway.
    private var activeTask: Task<Void, Never>?

    /// Public read access to the session's start time — used by the "ready to
    /// close" card to estimate how long the exchange has run.
    var startedAt: Date { sessionStartedAt }

    /// Number of replies the user has given.
    var userTurnCount: Int { messages.filter { $0.role == .user }.count }
    var hasUserContent: Bool { userTurnCount > 0 }
    /// Total words the user has contributed across the conversation.
    var userWordCount: Int {
        messages.filter { $0.role == .user }
            .map { $0.text.split { $0 == " " || $0 == "\n" }.count }
            .reduce(0, +)
    }
    /// When weaving / wrapping-up is offered, by mode.
    /// • Normal: only once there's real material (≥2 turns and ≥12 words, matching
    ///   weaveEntry's floor) so it never appears after one short reply and silently
    ///   passes through raw text.
    /// • Thought Journal: an exit ramp — the user can "wrap up & save" any time after
    ///   engaging. Floor raised from 1 turn to 3 to match the mode's own prompt rule
    ///   ("never deliver the snapshot before their third message" — ChatMode.swift) —
    ///   the manual "wrap up" button shouldn't be reachable sooner than the AI itself
    ///   is allowed to conclude.
    var canWeave: Bool {
        switch mode {
        case .cbt:    return readyToWeave || userTurnCount >= 3
        case .normal: return readyToWeave || (userTurnCount >= 2 && userWordCount >= 12)
        }
    }

    var seedContext: String?

    init(userId: String, seedContext: String? = nil) {
        self.userId = userId
        self.seedContext = seedContext
        if let seed = seedContext {
            messages = [ChatMessage(role: .spilr, text: "Your mirror flagged something: \(seed)\n\nDoes that track? What's going on with that?")]
        } else {
            messages = [ChatMessage(role: .spilr, text: AIService.chatOpener(for: mode))]
        }

        // Refresh the cached LifeContext block `nextChatTurn` reads, so a user who
        // opens Daily Chat without ever having opened Mirror still gets it — this
        // used to be a side effect of MirrorViewModel.performLoad() only. Fire-and-
        // forget: the first turn or two may go out without it if this hasn't
        // resolved yet, same tolerance every other AI surface in the app has for a
        // slow network.
        Task { [userId] in
            let ctx = await SelfModelService.shared.lifeContext(for: userId)
            AIService.cacheLifeContext(ctx)
        }
        // Same for SelfModel itself — `confirmedChatContext()` reads
        // SelfModelService.shared.selfModel, which is empty until `.load(for:)` has
        // run at least once this launch.
        Task { [userId] in
            await SelfModelService.shared.load(for: userId)
        }

        // Offer to resume a same-day, un-woven session in this mode — but only
        // for a plain fresh open. A `seedContext` open is a deliberate NEW
        // conversation Mirror just started; interrupting it with an unrelated
        // resume prompt would be confusing, not helpful.
        if seedContext == nil {
            let mode = self.mode
            Task { [weak self] in
                guard let self,
                      let found = await ChatSessionService.shared.fetchMostRecent(userId: userId, mode: mode),
                      found.wovenEntryId == nil,
                      Calendar.current.isDateInToday(found.updatedAt)
                else { return }
                self.resumableSession = found
            }
        }
    }

    /// Adopts a previously-persisted session in place of the fresh opener
    /// `init` already showed. `sessionId`/`sessionStartedAt` switch to the
    /// resumed session's own, so subsequent saves patch the SAME document
    /// rather than starting a second one alongside it.
    func resume(_ session: ChatSession) {
        // `setMode` guards the same way — an in-flight turn is writing into
        // `messages` by index (see `revealReply`), and replacing the array out from
        // under it would either corrupt that write or silently drop the resume.
        guard !isThinking, !isRevealing else { return }
        sessionId = session.id
        sessionStartedAt = session.startedAt
        messages = session.messages
        resumableSession = nil
        // The resumed session has no cached quick replies for its last turn —
        // asking the model again on the next send is preferable to showing
        // stale chips for text that may no longer be the newest message.
        suggestions = []
        sessionState = nil
        // A resumed long session would otherwise start the next turn with no
        // running-state context at all until the next 6-turn checkpoint — refresh
        // it immediately so continuity doesn't have a blind spot right at resume.
        if userTurnCount > 6 {
            let historySnapshot = messages
            Task.detached(priority: .utility) { [weak self] in
                guard let state = try? await AIService.shared.summariseSession(history: historySnapshot) else { return }
                await MainActor.run { self?.sessionState = state }
            }
        }
    }

    /// The user chose to start fresh instead of resuming. The declined session
    /// is left as-is (not deleted) — it simply stops being "resumable" once
    /// its `updatedAt` is no longer today.
    func dismissResumePrompt() {
        resumableSession = nil
    }

    /// Deletes this conversation's persisted session outright. Called from the
    /// "Leave this conversation?" alert's Discard action — see
    /// `ChatSessionService.delete`'s doc comment for why this matters.
    func discardSession() {
        cancelActiveTask()
        ChatSessionService.shared.delete(id: sessionId, userId: userId)
    }

    /// Cancels any in-flight send/reveal `Task` without deleting the session —
    /// used when the screen is dismissed mid-turn (see `DailyChatView.onDisappear`).
    /// Without this, leaving the screen let the network call complete and land its
    /// reply + autosave into a conversation nobody is looking at anymore.
    func cancelActiveTask() {
        activeTask?.cancel()
    }

    /// Fire-and-forget autosave of the conversation so far. Called after every
    /// completed turn (and right when the user's own message lands, before the
    /// AI call, so a kill mid-request doesn't lose it) — never awaited, same
    /// discipline as every other write in this app.
    private func persistSession() {
        ChatSessionService.shared.save(ChatSession(
            id: sessionId,
            userId: userId,
            mode: mode,
            messages: messages,
            startedAt: sessionStartedAt,
            updatedAt: Date()
        ))
    }

    /// Switch modes. The two flows are different enough that we start a fresh thread
    /// with the new mode's opener. A genuinely new thread gets its own session
    /// identity too, rather than continuing to patch the old mode's document.
    func setMode(_ newMode: ChatMode) {
        guard newMode != mode, !isThinking, !isRevealing else { return }
        mode = newMode
        ChatMode.lastUsed = newMode
        readyToWeave = false
        draft = ""
        suggestions = []
        messages = [ChatMessage(role: .spilr, text: AIService.chatOpener(for: newMode))]
        sessionId = UUID().uuidString
        sessionStartedAt = Date()
        sessionState = nil
        resumableSession = nil
        Haptics.tap()
        maybeShowThoughtJournalEducation()
        AnalyticsManager.shared.logEvent(newMode == .cbt ? .cbtModeStarted : .dailyChatStarted)
    }

    /// Shows the one-time education sheet the first time the user is in Thought
    /// Journal mode — whether they switched into it or the view opened there
    /// because it was their last-used mode. No-op afterwards.
    func maybeShowThoughtJournalEducation() {
        guard mode == .cbt, !ThoughtJournalEducation.hasSeen else { return }
        ThoughtJournalEducation.hasSeen = true
        showThoughtJournalEducation = true
    }

    // MARK: - Send a reply

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking, !isRevealing else { return }

        Haptics.tap()                         // light tap the instant the reply is sent
        messages.append(ChatMessage(role: .user, text: trimmed))
        draft = ""
        // The chips answered the PREVIOUS Spilr line — gone the instant this
        // reply is sent, whether or not the user actually tapped one.
        suggestions = []
        // Autosave right away, before the AI call — the riskiest window for
        // losing this message is exactly the one about to open.
        persistSession()

        // CHAT'S OWN CRISIS GATE — a tiered version of the deterministic filter the
        // pattern engine uses (see `PatternSafety.chatCrisisLevel`). Only an explicit,
        // unambiguous signal pauses the flow; the corpus-gate's raw substring list
        // over-triggers on ordinary sentences ("my anxiety was high again today",
        // "I need to purge my inbox") in a way that's costless for a background
        // pattern scan and is not costless when it ends a live conversation.
        switch PatternSafety.chatCrisisLevel(in: trimmed) {
        case .explicit:
            messages.append(ChatMessage(role: .spilr, text: Self.crisisReply))
            // The resource card itself presents once per session — the calming reply
            // above still lands on every trip, but the modal doesn't re-stack if the
            // same word comes up again later in the same conversation.
            if !hasShownCrisisResource {
                hasShownCrisisResource = true
                showCrisisResource = true
            }
            persistSession()
            return
        case .ambiguous, .none:
            break
        }

        isThinking = true
        let history = messages
        let activeMode = mode
        let state = sessionState
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            let turn: ChatTurn
            do {
                turn = try await AIService.shared.nextChatTurn(history: history, mode: activeMode, sessionState: state)
            } catch is CancellationError {
                return
            } catch AIError.blockedBySafety {
                if Task.isCancelled { return }
                await self.revealReply(
                    "I can't go there — but I'm still here. What else is on your mind?",
                    ready: false
                )
                return
            } catch AIError.budgetExceeded {
                if Task.isCancelled { return }
                await self.revealReply(
                    "AI replies are paused for now — you can keep writing, and I'll pick back up soon.",
                    ready: self.userTurnCount >= 2
                )
                return
            } catch {
                turn = AIService.shared.localNextTurn(history: history, mode: activeMode)
            }
            if Task.isCancelled { return }
            await self.revealReply(turn.reply, ready: turn.readyToWeave, suggestions: turn.suggestions)
        }
    }

    /// Types Spilr's reply out word-by-word so a line feels composed in the moment
    /// rather than pasted in whole. The network call itself is not streamed — this is
    /// a purely client-side reveal over the already-received text, budgeted to ~0.7s
    /// total so long replies never drag. Runs on the main actor (class is @MainActor).
    private func revealReply(_ full: String, ready: Bool, suggestions: [String] = []) async {
        // Drop the typing dots and land a soft haptic as the first words appear.
        isThinking = false
        isRevealing = true
        Haptics.replyLanded()

        let idx = messages.count
        messages.append(ChatMessage(role: .spilr, text: ""))

        let words = full.split(separator: " ", omittingEmptySubsequences: false)
        // Per-word delay derived from length so total reveal ≈ 0.7s, clamped 12–45ms.
        let perWordMs = max(12, min(45, 700 / max(words.count, 1)))
        let perWordNs = UInt64(perWordMs) * 1_000_000

        var shown = ""
        for (i, word) in words.enumerated() {
            guard idx < messages.count else { break }   // bail if the thread changed under us
            shown += (i == 0 ? "" : " ") + word
            messages[idx].text = shown
            try? await Task.sleep(nanoseconds: perWordNs)
        }
        if idx < messages.count { messages[idx].text = full }   // guarantee the final text

        readyToWeave = readyToWeave || ready
        isRevealing = false
        // Chips land only once the line has finished typing itself out, so they
        // never appear beside a reply that's still mid-reveal.
        self.suggestions = suggestions
        persistSession()
        maybeRefreshSessionState()
    }

    /// Kicks a `ChatSessionState` refresh every 6 user turns — detached and never
    /// awaited, so a slow or failed refresh never delays the next reply. See
    /// `ChatSessionState`'s doc comment for why this replaced the old
    /// "forget everything before this point" instruction.
    private func maybeRefreshSessionState() {
        guard userTurnCount > 0, userTurnCount % 6 == 0 else { return }
        let historySnapshot = messages
        Task.detached(priority: .utility) { [weak self] in
            guard let state = try? await AIService.shared.summariseSession(history: historySnapshot) else { return }
            await MainActor.run { self?.sessionState = state }
        }
    }

    // MARK: - Weave into an entry

    func weave() {
        // `!isThinking, !isRevealing` added: without it, weave could snapshot
        // `messages` while `revealReply` is still mid-append/mid-mutation for the
        // current turn, capturing a partially-typed line into the woven entry.
        guard !isWeaving, !isThinking, !isRevealing, canWeave else { return }
        isWeaving = true
        let history = messages
        let activeMode = mode
        Task { [weak self] in
            guard let self else { return }
            let woven: String
            if activeMode == .cbt {
                // Thought Journal weave keeps structure — it produces the snapshot card.
                woven = (try? await AIService.shared.weaveThoughtJournalSummary(from: history))
                    ?? AIService.shared.localWeaveEntry(from: history)
            } else {
                woven = (try? await AIService.shared.weaveEntry(from: history))
                    ?? AIService.shared.localWeaveEntry(from: history)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.wovenPreview = woven
                self.showPreview = true
                self.isWeaving = false
            }
        }
    }

    // MARK: - Save the woven entry
    //
    // Mirrors TimedSessionViewModel.saveEntry: save instantly with local heuristics,
    // then enrich (insights / echo / river) in detached background tasks. The only
    // difference is sessionType == .dailyChat.

    func save(entryText: String) {
        let trimmed = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sentiment  = LocalAI.detectSentiment(from: trimmed)
        let reflection = SpilrVoice.localReflection(from: trimmed, sentiment: sentiment)

        var tags = (mode == .cbt) ? ["reflection", "reframe"] : ["chat"]
        for topic in LocalAI.extractTopics(from: trimmed) where !tags.contains(topic) && tags.count < 5 {
            tags.append(topic)
        }

        let entry = JournalEntry(
            userId: userId,
            content: trimmed,
            tags: tags,
            sessionType: (mode == .cbt) ? .cbtReframe : .dailyChat,
            aiSummaryBullets: reflection.observations,
            aiQuestion: reflection.question,
            sentimentLabel: sentiment
        )
        service.createEntry(entry)
        if mode == .cbt {
            AnalyticsManager.shared.logEvent(.cbtModeCompleted)
        } else {
            AnalyticsManager.shared.logEvent(.dailyChatCompleted)
        }

        // Point the persisted session at the entry it became — see
        // ChatSession.swift. Fire-and-forget, same as every other write here.
        ChatSessionService.shared.save(ChatSession(
            id: sessionId,
            userId: userId,
            mode: mode,
            messages: messages,
            startedAt: sessionStartedAt,
            updatedAt: Date(),
            wovenEntryId: entry.id
        ))

        // Background enrichment — silent on failure, never blocks.
        let svc            = service
        let entryId        = entry.id
        let uid            = userId
        let entryCreatedAt = entry.createdAt

        Task.detached(priority: .utility) {
            guard let insights = try? await AIService.shared.generateInsights(from: trimmed) else { return }
            svc.updateEntryInsights(entryId: entryId, userId: uid, insights: insights)
        }
        Task.detached(priority: .background) {
            await EchoExtractionService.shared.extractAndStore(
                entryText:      trimmed,
                entryId:        entryId,
                userId:         uid,
                entryCreatedAt: entryCreatedAt
            )
        }
        // Mirror analysis (Prompt A) — the woven chat entry feeds the same
        // structured EntryAnalysis pipeline as free-write and 90-second entries.
        // Self-persisting, never throws.
        Task.detached(priority: .background) {
            _ = await AIService.shared.analyzeEntry(
                entryId: entryId,
                userId:  uid,
                text:    trimmed
            )
        }
    }
}

// MARK: - View

struct DailyChatView: View {

    let onSave: () -> Void
    /// Set when reached via the start sheet's "Talk it out" row — opens the
    /// mic immediately instead of waiting for a tap.
    let startWithDictation: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: DailyChatViewModel
    @StateObject private var speech = SpeechManager()
    /// Spilr Redesign 3c's expanded compose state. Layout truth lives in
    /// `isComposeExpanded`, not focus — focus is a consequence, set after the
    /// layout flips (see `expandCompose`/`collapseCompose`). There is exactly
    /// one focusable field in the whole view (the expanded `TextEditor`), so
    /// this needs no enum: the at-rest capsule's `TextField` only ever
    /// *renders* `vm.draft`, it never takes focus itself.
    @State private var isComposeExpanded = false
    @FocusState private var expandedFocused: Bool
    /// The question being answered, snapshotted at expand time — not read
    /// live, since the last Spilr message mutates word-by-word while
    /// `revealReply` is still typing it out.
    @State private var answeringQuestion = ""
    @State private var showDiscardAlert = false
    @State private var hasStartedDictation = false
    /// The "ready to close" card is dismissable per-turn via "Keep talking" —
    /// reset back to visible the instant the user sends a new message (see the
    /// `.onChange(of: vm.userTurnCount)` below), so it resurfaces after every fresh
    /// exchange instead of staying hidden for the rest of the session.
    ///
    /// Tracks `userTurnCount`, not `messages.count`: the latter also ticks up when
    /// Spilr's placeholder message is appended at the START of `revealReply` (before
    /// a single word of the reply has typed out), which was re-showing this large
    /// card and shoving the still-typing reply further up the screen on every turn.
    @State private var dismissedWeaveCard = false

    init(
        userId: String,
        seedContext: String? = nil,
        startWithDictation: Bool = false,
        onSave: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.startWithDictation = startWithDictation
        _vm = StateObject(wrappedValue: DailyChatViewModel(userId: userId, seedContext: seedContext))
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                modePicker
                thread
                weaveBar
                suggestionChips
                inputBar
            }

            if isComposeExpanded {
                ExpandedComposeView(
                    draft: $vm.draft,
                    focused: $expandedFocused,
                    answeringQuestion: answeringQuestion,
                    isWaitingOnSpilr: vm.isThinking || vm.isRevealing,
                    onDone: collapseCompose,
                    onSend: sendFromExpanded
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $vm.showCrisisResource) {
            PatternResourceCardView(onDismiss: { vm.showCrisisResource = false })
        }
        .sheet(isPresented: $vm.showThoughtJournalEducation) {
            ThoughtJournalEducationView(onDismiss: { vm.showThoughtJournalEducation = false })
        }
        .task {
            vm.maybeShowThoughtJournalEducation()
            AnalyticsManager.shared.logEvent(vm.mode == .cbt ? .cbtModeStarted : .dailyChatStarted)
            if startWithDictation, !hasStartedDictation {
                hasStartedDictation = true
                await speech.toggle(existingText: vm.draft)
            }
        }
        // A presentation firing while the compose surface is expanded (the
        // weave preview is the reachable one — crisis and discard already
        // collapse via `send()`/the alert flow) would otherwise appear
        // stacked on top of it.
        .onChange(of: vm.showPreview) { _, showing in
            if showing { collapseCompose() }
        }
        // A fresh exchange re-earns the "ready to close" card even if it was
        // dismissed with "Keep talking" on an earlier turn.
        .onChange(of: vm.userTurnCount) { _, _ in dismissedWeaveCard = false }
        .alert("Leave this conversation?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                vm.discardSession()
                dismiss()
            }
            Button("Keep chatting", role: .cancel) {}
        } message: {
            Text("Your conversation won't be saved unless you weave it into an entry first.")
        }
        .alert("Resume where you left off?", isPresented: Binding(
            get: { vm.resumableSession != nil },
            set: { if !$0 { vm.dismissResumePrompt() } }
        )) {
            Button("Resume") {
                if let session = vm.resumableSession { vm.resume(session) }
            }
            Button("Start fresh", role: .cancel) { vm.dismissResumePrompt() }
        } message: {
            Text("You have an earlier conversation from today that hasn't been turned into an entry yet.")
        }
        .sheet(isPresented: $vm.showPreview) {
            if let woven = vm.wovenPreview {
                WovenEntryPreviewSheet(
                    initialText: woven,
                    onSave: { finalText in
                        vm.save(entryText: finalText)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        vm.showPreview = false
                        onSave()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                    },
                    onBack: { vm.showPreview = false }
                )
            }
        }
        .onChange(of: speech.liveText) { _, live in
            // Mirror the live dictation transcript into the draft as the user speaks.
            // Stale post-stop results are filtered inside SpeechManager itself (see
            // `discardPendingResults`) rather than guarded on `isRecording` here —
            // the recognizer writes its FINAL corrected transcript and then stops in
            // the same main-actor block, so an isRecording check would arrive too
            // late and throw away the punctuation/last-word fixups.
            vm.draft = live
        }
        .onDisappear {
            speech.stop()
            vm.cancelActiveTask()
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                // If the user has written at least one reply, confirm before discarding.
                if vm.hasUserContent {
                    showDiscardAlert = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            BloomMarkView(size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Today with Spilr")
                    .font(AppTheme.editorialDisplay(size: 20))
                    .foregroundStyle(AppTheme.ink)
                Text("nothing saved until you choose")
                    .font(AppTheme.editorialBody(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Mode picker
    // Session-based, not onboarding-locked: switch between Casual Vent and the
    // Thought Journal at any time. Switching starts a fresh thread for the new mode.
    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(ChatMode.allCases) { m in
                Button { vm.setMode(m) } label: {
                    Text(m.pillLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(vm.mode == m ? AppTheme.cream : AppTheme.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if vm.mode == m {
                                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                                   startPoint: .leading, endPoint: .trailing)
                                } else {
                                    AppTheme.cream.opacity(0.6)
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(vm.mode == m ? 0 : 0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Thread
    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(vm.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if vm.isThinking {
                        typingIndicator.id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: vm.isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // Keep the newest words in view while Spilr's reply types itself out.
            .onChange(of: vm.messages.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // Asymmetric corners, tail pointing toward whichever side the bubble
    // came from — Spilr's bottom-leading corner is sharp, the user's
    // bottom-trailing corner is. No avatar on either: the header's bloom
    // mark carries Spilr's identity for the whole screen now.
    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        let isSpilr = message.role == .spilr
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: isSpilr ? 8 : 24,
            bottomTrailingRadius: isSpilr ? 24 : 8,
            topTrailingRadius: 24,
            style: .continuous
        )
        HStack(alignment: .bottom, spacing: 8) {
            if !isSpilr { Spacer(minLength: 44) }

            Text(message.text)
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(isSpilr ? AppTheme.ink : AppTheme.cream)
                .lineSpacing(3)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    Group {
                        if isSpilr {
                            AppTheme.cream.opacity(0.85)
                        } else {
                            LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                )
                .clipShape(shape)
                .overlay(shape.stroke(AppTheme.inkSoft.opacity(isSpilr ? 0.12 : 0), lineWidth: 1))

            if isSpilr { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isSpilr ? .leading : .trailing)
        .transition(.move(edge: isSpilr ? .leading : .trailing).combined(with: .opacity))
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.inkSoft.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(vm.isThinking ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: vm.isThinking
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(AppTheme.cream.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Weave bar — the "ready to close" card (Spilr Redesign 2c)
    //
    // Inline rather than a modal sheet — the composer stays reachable right
    // below it, so "keep talking" is just typing, and "keep talking" the
    // button only needs to hide the card for the rest of this turn (see
    // `dismissedWeaveCard`). No "felt deeper than usual" line: nothing in the
    // app computes session depth, and inventing a threshold here would be
    // exactly the fake precision this redesign elsewhere argues against.
    @ViewBuilder
    private var weaveBar: some View {
        if vm.canWeave && !dismissedWeaveCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(vm.userTurnCount) \(vm.userTurnCount == 1 ? "EXCHANGE" : "EXCHANGES") · \(sessionDurationText)")
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.inkSoft)

                Text("Keep this as an entry?")
                    .font(AppTheme.editorialDisplay(size: 19))
                    .foregroundStyle(AppTheme.ink)

                Text("Spilr will turn this into a short entry in your own voice. You can edit every line before it's saved.")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Button { vm.weave() } label: {
                    HStack(spacing: 8) {
                        if vm.isWeaving {
                            ProgressView().tint(AppTheme.cream).scaleEffect(0.85)
                            Text("Weaving your entry…")
                        } else {
                            Image(systemName: "wand.and.stars").font(.system(size: 14))
                            Text(vm.mode.weaveLabel)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(vm.isWeaving)

                HStack {
                    Spacer()
                    Button("Keep talking") {
                        withAnimation(.easeOut(duration: 0.2)) { dismissedWeaveCard = true }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)

                    Text("·").foregroundStyle(AppTheme.inkSoft.opacity(0.4))

                    Button("Discard — save nothing") { showDiscardAlert = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft.opacity(0.6))
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(18)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 16, x: 0, y: -4)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// A rounded, approximate duration — "~3 MIN", never "~3.2 MIN". Read live
    /// at render time rather than ticking, since the card only needs to be
    /// roughly right, not a stopwatch.
    private var sessionDurationText: String {
        let minutes = max(1, Int((Date().timeIntervalSince(vm.startedAt) / 60).rounded()))
        return "~\(minutes) MIN"
    }

    // MARK: - Suggestion chips (Casual Vent quick replies)
    //
    // Tapping a chip fills the draft rather than sending immediately — the
    // composer elsewhere in this screen promises "nothing sends until you tap
    // ↑", and a chip is no exception.
    @ViewBuilder
    private var suggestionChips: some View {
        if !vm.suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.suggestions, id: \.self) { suggestion in
                        Button {
                            vm.draft = suggestion
                            vm.suggestions = []
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.inkSoft)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(AppTheme.cream.opacity(0.9))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.14), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Input bar
    //
    // Composer sizing follows iMessage / WhatsApp / Day One: ONE line at rest,
    // growing only as the person actually types, capped at six lines before it
    // scrolls internally.
    //
    // What was wrong before: `TextEditor` is greedy vertically, so
    // `.frame(minHeight: 22, maxHeight: 110)` didn't mean "grow from 22 to 110" —
    // it meant a permanent 110pt field. Stacking the 44pt mic and 44pt send in a
    // column beside it set a ~96pt floor of its own. The composer was ~130pt tall
    // before a single character was typed, eating roughly a fifth of the screen and
    // pushing Spilr's newest reply up out of view.
    //
    // Three changes: `TextField(axis: .vertical)` with `lineLimit(1...6)` auto-grows
    // natively (and brings a real placeholder, so the overlaid-Text hack is gone);
    // the two buttons sit side by side on the baseline instead of stacked; and mic
    // and send swap in place rather than both being permanently present — the
    // familiar pattern where the mic becomes a send button once there's something
    // to send.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Renders `vm.draft` (including live dictation) but takes no
            // direct input itself — tapping it opens the expanded writing
            // surface instead (see `expandCompose`). The keyboard is never up
            // at the moment of that hand-off (down here, comes up once in the
            // expanded editor), so there's no dismiss/re-present flicker to
            // engineer around, and no second focus target to keep in sync.
            TextField("Answer however much you like\u{2026}", text: $vm.draft, axis: .vertical)
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.ink)
                .tint(AppTheme.terracotta)
                .lineLimit(1...6)
                .allowsHitTesting(false)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AppTheme.cream.opacity(0.8))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { expandCompose() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the full writing view")

            // One 38pt circle that swaps role. Mic while the field is empty; send the
            // moment there's a draft. Recording keeps the stop control visible.
            Group {
                if hasDraft {
                    // Swap on hasDraft, NOT canSend. canSend is also false while Spilr
                    // is thinking or typing — driving the swap off it would flip the
                    // button back to a mic mid-turn with the person's text still in the
                    // field. It stays a send button and simply dims instead.
                    Button { speech.stop(); vm.send() } label: {
                        composerCircle(
                            systemName: "arrow.up",
                            fill: canSend ? AppTheme.ink : AppTheme.inkSoft.opacity(0.4),
                            tint: AppTheme.cream
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Voice dictation — tap to talk; the live transcript streams into
                    // the draft (see .onChange(speech.liveText)). Same SpeechManager
                    // the write flows use. Works in both modes.
                    Button {
                        Task { await speech.toggle(existingText: vm.draft) }
                    } label: {
                        composerCircle(
                            systemName: speech.isRecording ? "stop.fill" : "mic.fill",
                            fill: speech.isRecording ? AppTheme.terracotta : AppTheme.cream.opacity(0.8),
                            tint: speech.isRecording ? AppTheme.cream : AppTheme.ink,
                            bordered: !speech.isRecording
                        )
                        .scaleEffect(speech.isRecording ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: speech.isRecording)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isThinking || vm.isRevealing)
                    .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hasDraft)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppTheme.paper)
    }

    /// Shared circular button face for the composer's mic / send control
    /// (`size: 38`, the default) and the expanded surface's send button
    /// (`size: 40`).
    private func composerCircle(
        systemName: String,
        fill: Color,
        tint: Color,
        bordered: Bool = false,
        size: CGFloat = 38
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(AppTheme.inkSoft.opacity(bordered ? 0.15 : 0), lineWidth: 1)
            )
    }

    /// There's something in the field — drives the mic ⇄ send swap.
    private var hasDraft: Bool {
        !vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// There's something in the field AND Spilr is free to receive it.
    private var canSend: Bool {
        hasDraft && !vm.isThinking && !vm.isRevealing
    }

    // MARK: - Expanded compose state (Spilr Redesign 3c)

    private func expandCompose() {
        // Snapshot, not a live read — the last Spilr message mutates
        // word-by-word while `revealReply` is still typing it out, and a live
        // binding would animate the strip's text along with it.
        answeringQuestion = vm.messages.last { $0.role == .spilr }?.text ?? ""
        // The expanded footer has no mic — cut a live dictation session
        // cleanly here rather than let its late final transcript clobber
        // whatever gets typed in the expanded editor.
        speech.stop()
        withAnimation(.easeOut(duration: 0.20)) { isComposeExpanded = true }
        expandedFocused = true
    }

    private func collapseCompose() {
        expandedFocused = false
        withAnimation(.easeOut(duration: 0.20)) { isComposeExpanded = false }
    }

    private func sendFromExpanded() {
        // Send BEFORE collapsing — collapsing first would leave `vm.draft`
        // populated for a frame, visibly flashing the old text back into the
        // at-rest capsule before `send()` clears it. `vm.send()` re-checks
        // its own `!isThinking && !isRevealing` guard, so this is safe even
        // if called while the footer's send button should have been disabled.
        vm.send()
        collapseCompose()
    }
}

// MARK: - Expanded compose surface

/// The dedicated writing surface Spilr Redesign 3c's expanded compose state
/// presents (see `DailyChatView.expandCompose()`). A `TextEditor`, not the
/// at-rest capsule's `TextField`: the two states need different scroll
/// semantics (grow-to-6-lines vs. scroll-internally on a long draft), and one
/// field trying to do both loses caret-follow on exactly the long-draft case
/// this state exists for.
private struct ExpandedComposeView: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    /// Snapshotted at expand time by the caller — see `expandCompose()`.
    let answeringQuestion: String
    let isWaitingOnSpilr: Bool
    let onDone: () -> Void
    let onSend: () -> Void

    private var wordCount: Int {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0 == " " || $0 == "\n" }
            .count
    }

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                contextStrip
                editor
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Today with Spilr")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Button("Done", action: onDone)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.terracotta)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(AppTheme.paper)
    }

    /// The question being answered, pinned for context. `AppTheme.lavWash`,
    /// not `AppTheme.lav` — `lav` collapses onto `terracotta` in the Moon
    /// palette, which would make this strip read as an accent surface rather
    /// than a quiet aside on that theme.
    private var contextStrip: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("ANSWERING")
                .font(AppTheme.mono(size: 9))
                .tracking(1.4)
                .foregroundStyle(AppTheme.lavDeep)
            Text(answeringQuestion)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.lavWash.opacity(0.5))
        .overlay(
            Rectangle().fill(AppTheme.lavDeep.opacity(0.22)).frame(height: 1),
            alignment: .bottom
        )
    }

    // `TextEditor` carries its own ~5pt text-container inset, so 15pt of
    // external padding here lands text at ~20pt — matching `contextStrip`'s
    // 20pt padding above it, rather than the two misaligning.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("Answer however much you like\u{2026}")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.55))
                    .padding(.horizontal, 15)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(4)
                .tint(AppTheme.terracotta)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.never)
                .padding(.horizontal, 15)
                .focused(focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(wordCount) \(wordCount == 1 ? "WORD" : "WORDS")")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)

            Text(isWaitingOnSpilr
                 ? "Spilr is still writing\u{2026}"
                 : "Take your time \u{2014} nothing sends until you tap \u{2191}")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.slate)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Circle())
                    .shadow(color: AppTheme.terracotta.opacity(0.32), radius: 8, x: 0, y: 4)
                    .opacity(hasDraft && !isWaitingOnSpilr ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!hasDraft || isWaitingOnSpilr)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.paper)
    }
}

// MARK: - Haptics
//
// Small, consistent haptic vocabulary for the chat: a light tap when the person
// sends, and a softer tap when Spilr's line lands. Kept here (not a shared util)
// so the chat's feel can be tuned without touching other surfaces.
private enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }
    static func replyLanded() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.7)
    }
}

// MARK: - Woven entry preview sheet
//
// Shows the woven first-person entry, editable, before it's committed. The user can
// tweak the wording, save it as a normal entry, or go back to keep chatting.
private struct WovenEntryPreviewSheet: View {
    let initialText: String
    let onSave: (String) -> Void
    let onBack: () -> Void

    @State private var text: String

    init(initialText: String, onSave: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onBack = onBack
        _text = State(initialValue: initialText)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your entry")
                                .font(AppTheme.editorialDisplay(size: 26))
                                .foregroundStyle(AppTheme.ink)
                            Text("Woven from your chat, in your own words. Edit anything, then save.")
                                .font(AppTheme.editorialBody(size: 14))
                                .foregroundStyle(AppTheme.inkSoft)
                                .lineSpacing(3)
                        }
                        .padding(.top, 8)

                        TextEditor(text: $text)
                            .font(AppTheme.editorialBody(size: 17))
                            .foregroundStyle(AppTheme.ink)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .lineSpacing(5)
                            .frame(minHeight: 240)
                            .padding(14)
                            .background(AppTheme.cream.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.terracotta.opacity(0.25), lineWidth: 1.5)
                            )

                        Button { onSave(trimmed) } label: {
                            Text("Save entry")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.cream)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(Capsule())
                                .opacity(trimmed.isEmpty ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmed.isEmpty)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Keep chatting", action: onBack)
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
    }
}

// MARK: - Thought Journal education (one-time)
//
// Shown the first time the user lands in Thought Journal mode. Plain, warm
// language answering the two questions a first-timer has: what is this, and how
// does it help? No clinical vocabulary. Persistence of the "seen" flag lives in
// `ThoughtJournalEducation` below.

private struct ThoughtJournalEducationView: View {

    let onDismiss: () -> Void

    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        Point(symbol: "text.bubble",
              title: "One thought at a time",
              body: "Spilr asks a single, low-pressure question, then follows your lead — whether you're venting, stuck on a task, or just emptying your head."),
        Point(symbol: "arrow.triangle.branch",
              title: "It helps you untangle it",
              body: "Naming the trigger, the feeling, and the thought underneath makes a worry feel smaller and clearer — one gentle step at a time."),
        Point(symbol: "sparkles",
              title: "You leave with a snapshot",
              body: "When you're done, it becomes a short Journal Snapshot you can look back on. Nothing clinical — just your own words, tidied up.")
    ]

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🧠")
                            .font(.system(size: 40))
                        Text("Your Thought Journal")
                            .font(AppTheme.editorialDisplay(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("A calm space to think something through — one step at a time.")
                            .font(AppTheme.editorialBody(size: 16))
                            .foregroundStyle(AppTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: point.symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppTheme.terracotta)
                                    .frame(width: 30, height: 30)
                                    .background(AppTheme.cream.opacity(0.7))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(point.body)
                                        .font(AppTheme.editorialBody(size: 14))
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Text("Private to you. Nothing is saved until you choose to.")
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button(action: onDismiss) {
                        Text("Start")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Thought Journal education persistence

/// Remembers whether the one-time Thought Journal education sheet has been shown.
enum ThoughtJournalEducation {
    private static let storageKey = "spilr.thoughtJournal.educationSeen"

    static var hasSeen: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}
