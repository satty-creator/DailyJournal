//
//  DailyChatView.swift
//  DailyJournal
//
//  Daily Chat — a Day One-style interactive journaling surface. Spilr opens with a
//  question, the person replies in a familiar chat thread, Spilr asks adaptive
//  follow-ups, and at any point the conversation can be "woven" into a first-person
//  journal entry (a Journal Snapshot) that's saved like any other (Echoes / River /
//  Patterns all pick it up). AI drives both the follow-ups and the weaving. A failed
//  turn surfaces an inline retry rather than a canned local question — see `send()`
//  and `AIService+Chat.swift`'s header comment; the weave still degrades to a plain
//  transcript stitch (`localWeaveEntry`) so a finished conversation is never lost.
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
    /// Photo picked on the preview sheet. Lives here, not in the sheet, so it
    /// survives "Keep chatting" → weave again. Not persisted with the session.
    @Published var attachedPhoto: UIImage?
    /// True when the last `nextChatTurn` call failed for any reason other than the
    /// two named product responses (`blockedBySafety`, `budgetExceeded`, which show
    /// their own in-thread reply). No canned Spilr line stands in for a real one —
    /// this drives an inline "Couldn't reach Spilr" row with a Retry action instead.
    /// See `send()` / `requestNextTurn()`.
    @Published var turnFailed = false
    /// Set when the deterministic crisis gate trips — the UI shows a resource card.
    @Published var showCrisisResource = false
    /// True once the resource card has been shown this session. An explicit crisis
    /// signal still pauses the flow with `crisisReply` on every trip, but the modal
    /// itself only presents once — otherwise a conversation that mentions the same
    /// word again re-triggers the sheet on every subsequent message.
    private var hasShownCrisisResource = false
    /// Drives the one-time "what is a Thought Journal" education sheet, shown the
    /// first time the user ever opens a chat (outside onboarding).
    @Published var showThoughtJournalEducation = false

    /// A same-day, not-yet-woven session found for this user — offered as
    /// "resume where you left off" once the check below resolves. Non-nil only
    /// briefly, between that check landing and the user (or the view) acting
    /// on it.
    @Published var resumableSession: ChatSession?

    /// The calm, non-judgemental line shown when the crisis gate trips. We pause the
    /// flow here rather than let the model keep going.
    static let crisisReply = "I want to pause for a second. What you're describing sounds really heavy, and I'm a journaling tool — not a substitute for real support. If you might be in danger, please reach out: in the US you can call or text 988 (Suicide & Crisis Lifeline), any time. I'm still here whenever you want to keep writing."

    let userId: String
    private let service = JournalService()
    /// This conversation's own persisted identity — see ChatSession.swift.
    /// `var`, not `let`: `resume(_:)` adopts an existing session's id/start time.
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
    /// When saving is offered — the header's "Save" button. An exit ramp the user
    /// can take any time after they've said something: it used to be gated on a
    /// 3-turn floor, which meant the only way to save early was to keep answering,
    /// and the save affordance simply wasn't there for the first few exchanges.
    /// A short session still weaves fine — `weaveThoughtJournalSummary` writes
    /// "Not covered this time" for missing fields, and below its own 8-word floor
    /// the local transcript stitch takes over.
    ///
    /// Onboarding's first-ever session keeps a slightly higher floor (≥2 turns and
    /// ≥12 words) because there the inline "ready to close" card is driven by this
    /// too — see `isOnboarding` and `DailyChatView.showsWeaveCard`.
    var canWeave: Bool {
        if isOnboarding {
            return readyToWeave || (userTurnCount >= 2 && userWordCount >= 12)
        }
        return readyToWeave || hasUserContent
    }

    var seedContext: String?
    /// True for onboarding's first-ever session — lowers `canWeave`'s floor and
    /// suppresses the one-time Thought Journal education sheet, which would
    /// otherwise stack over the onboarding cover. See `OnboardingView`.
    let isOnboarding: Bool

    init(userId: String, seedContext: String? = nil, isOnboarding: Bool = false) {
        self.userId = userId
        self.seedContext = seedContext
        self.isOnboarding = isOnboarding
        if let seed = seedContext {
            messages = [ChatMessage(role: .spilr, text: "Your mirror flagged something: \(seed)\n\nDoes that track? What's going on with that?")]
        } else {
            messages = [ChatMessage(role: .spilr, text: AIService.chatOpener)]
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
        // Same for the Person Model layer — DerivedService is otherwise only
        // loaded by the Mirror tab, so a user who opens chat straight from Home
        // would get neither the model context `nextChatTurn` now reads nor a
        // live opener without this. A plain fresh open (no seed, nothing sent
        // yet) SWAPS IN Prompt Q's own pick for tonight — the discriminating
        // question the Person Model most wants answered — in place of the
        // static opener, once it resolves. Guarded tight: only replaces the
        // placeholder while the session is still exactly that, a placeholder,
        // and only after the deterministic topic gate clears it.
        if seedContext == nil {
            Task { [weak self, userId] in
                await DerivedService.shared.load(for: userId)
                guard let self, self.userTurnCount == 0, self.seedContext == nil,
                      let question = DerivedService.shared.personModel.nextQuestion,
                      !PersonModelChatContext.isDisabled(
                        question.question,
                        sensitiveTopicsDisabled: AIService.shared.sensitiveTopicsDisabledCached())
                else { return }
                self.messages = [ChatMessage(role: .spilr, text: question.question)]
            }
        } else {
            Task { [userId] in await DerivedService.shared.load(for: userId) }
        }

        // Offer to resume a same-day, un-woven session — but only for a plain
        // fresh open. A `seedContext` open is a deliberate NEW conversation Mirror
        // just started; interrupting it with an unrelated resume prompt would be
        // confusing, not helpful.
        if seedContext == nil {
            Task { [weak self] in
                guard let self,
                      let found = await ChatSessionService.shared.fetchMostRecent(userId: userId),
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
        // An in-flight turn is writing into `messages` by index (see `revealReply`),
        // and replacing the array out from under it would either corrupt that write
        // or silently drop the resume.
        guard !isThinking, !isRevealing else { return }
        sessionId = session.id
        sessionStartedAt = session.startedAt
        messages = session.messages
        resumableSession = nil
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
            messages: messages,
            startedAt: sessionStartedAt,
            updatedAt: Date()
        ))
    }

    /// Shows the one-time education sheet the first time the user opens a chat —
    /// skipped during onboarding, which would otherwise stack it over the
    /// onboarding cover (see `isOnboarding`). No-op afterwards.
    func maybeShowThoughtJournalEducation() {
        guard !isOnboarding, !ThoughtJournalEducation.hasSeen else { return }
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

        requestNextTurn()
    }

    /// Asks the model for Spilr's next line and reveals it. Split out from `send()`
    /// so `retryLastTurn()` can re-run the same request without re-appending the
    /// user's message, which is already in `messages` and already persisted.
    ///
    /// No local fallback on a generic failure — see the file header comment.
    /// `turnFailed` drives an inline "Couldn't reach Spilr" row with Retry instead
    /// of putting a canned question in Spilr's mouth mid-conversation.
    private func requestNextTurn() {
        turnFailed = false
        isThinking = true
        let history = messages
        let state = sessionState
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let turn = try await AIService.shared.nextChatTurn(history: history, sessionState: state)
                if Task.isCancelled { return }
                await self.revealReply(turn.reply, ready: turn.readyToWeave)
            } catch is CancellationError {
                return
            } catch AIError.blockedBySafety {
                if Task.isCancelled { return }
                await self.revealReply(
                    "I can't go there — but I'm still here. What else is on your mind?",
                    ready: false
                )
            } catch AIError.budgetExceeded {
                if Task.isCancelled { return }
                await self.revealReply(
                    // Covers both a finished free preview (AIService also opens
                    // the Spilr Pro paywall for that) and a paying user's daily
                    // cap, so it promises nothing about when replies return.
                    "I can't reply right now \u{2014} keep writing, and you can still wrap this up as an entry.",
                    ready: self.userTurnCount >= 2
                )
            } catch {
                if Task.isCancelled { return }
                self.isThinking = false
                self.turnFailed = true
            }
        }
    }

    /// Retries the turn that just failed — see `turnFailed`.
    func retryLastTurn() {
        guard turnFailed, !isThinking, !isRevealing else { return }
        requestNextTurn()
    }

    /// Types Spilr's reply out word-by-word so a line feels composed in the moment
    /// rather than pasted in whole. The network call itself is not streamed — this is
    /// a purely client-side reveal over the already-received text, budgeted to ~0.7s
    /// total so long replies never drag. Runs on the main actor (class is @MainActor).
    private func revealReply(_ full: String, ready: Bool) async {
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
        Task { [weak self] in
            guard let self else { return }
            // Thought Journal weave keeps structure — it produces the snapshot card.
            // Falls back to a plain transcript stitch on failure so a finished
            // conversation is never lost.
            let woven = (try? await AIService.shared.weaveThoughtJournalSummary(from: history))
                ?? AIService.shared.localWeaveEntry(from: history)
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
    // then enrich via the shared EntryEnrichment tail. The only difference is
    // sessionType == .cbtReframe.

    func save(entryText: String) {
        let trimmed = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Sentiment and tags are derived data and stay local. Reflection is
        // AI-only — `EntryEnrichment` patches it in when Gemini answers. This is
        // the entry the first-entry celebration sheet watches, so leaving these
        // unset is what lets that sheet tell "still waiting" apart from "done".
        let sentiment  = LocalAI.detectSentiment(from: trimmed)

        let sessionType: SessionType = .cbtReframe
        var tags = ["reflection", "reframe"]
        for topic in LocalAI.extractTopics(from: trimmed) where !tags.contains(topic) && tags.count < 5 {
            tags.append(topic)
        }

        let entry = JournalEntry(
            userId: userId,
            content: trimmed,
            tags: tags,
            sessionType: sessionType,
            sentimentLabel: sentiment
        )
        service.createEntry(entry)
        // dailyChatCompleted is the "chat saved" series; cbtModeCompleted stays as
        // its own event for continuity with data from when it was mode-specific.
        AnalyticsManager.shared.logEvent(.dailyChatCompleted)
        AnalyticsManager.shared.logEvent(.cbtModeCompleted)

        // Point the persisted session at the entry it became — see
        // ChatSession.swift. Fire-and-forget, same as every other write here.
        ChatSessionService.shared.save(ChatSession(
            id: sessionId,
            userId: userId,
            messages: messages,
            startedAt: sessionStartedAt,
            updatedAt: Date(),
            wovenEntryId: entry.id
        ))

        // Background enrichment — silent on failure, never blocks. Shared with
        // every other composer via `EntryEnrichment`.
        EntryEnrichment.run(
            entryId: entry.id,
            userId: userId,
            entryCreatedAt: entry.createdAt,
            text: trimmed,
            photo: attachedPhoto,
            service: service,
            sessionType: sessionType,
            composedFrom: sessionStartedAt
        )

        // Chat write-back — "track whether exercise actually helps" / "that's
        // not true about me" / "stop tracking work", said IN the conversation,
        // applied now that the session has produced something worth trusting.
        // One extra AI call per session, never per turn (see
        // AIService+Chat.extractModelOps). Fire-and-forget: a user who saves
        // and leaves must not wait on this.
        let historySnapshot = messages
        let sid = sessionId
        let uid = userId
        Task.detached(priority: .utility) {
            guard let ops = try? await AIService.shared.extractModelOps(history: historySnapshot),
                  !ops.isEmpty
            else { return }
            await MainActor.run {
                DailyChatViewModel.applyModelOps(ops, sessionId: sid, userId: uid)
            }
        }
    }

    /// Applies chat-derived model writes (see `AIService+Chat.extractModelOps`).
    /// Static and called from a detached background task after `save()` — no
    /// `self` needed, and none of this should be entangled with the sheet's own
    /// dismissal. Each `.confirm`/`.notMe` op is applied ONLY if it targets an
    /// item the conversation actually had in front of it (one of the rows
    /// `PersonModelChatContext` handed the model) — a lite model can propose a
    /// plausible-looking id that was never shown, and that must never reach a
    /// real document.
    private static func applyModelOps(_ ops: [AIService.ParsedModelOp], sessionId: String, userId: String) {
        guard !userId.isEmpty else { return }
        let knownItemIds = Set(DerivedService.shared.personModelItems.map(\.id))

        for parsed in ops {
            switch parsed.op {
            case .confirm, .notMe:
                guard let itemId = parsed.targetItemId, knownItemIds.contains(itemId) else { continue }
                DerivedService.shared.markPersonModelItemStatus(
                    itemId: itemId,
                    userStatus: parsed.op == .confirm ? "this_is_me" : "not_me",
                    userId: userId
                )
                if parsed.op == .notMe {
                    // A correction is still the ground-truth channel Prompt F
                    // reads (functions/lib/prompts.js "USER CORRECTIONS OUTRANK
                    // YOUR INFERENCE") — the direct personModel write above is
                    // what actually retires it tonight; this is the audit
                    // record and the exclusion text for future runs.
                    SelfModelService.shared.submitCorrection(
                        ProfileCorrection(
                            userId: userId,
                            feedbackType: .notMe,
                            hypothesisId: itemId,
                            userCorrection: "\(parsed.subject) — said in chat: \"\(parsed.quote)\"",
                            correctionCategory: "chat"
                        ),
                        userId: userId
                    )
                }
            case .untrackTopic:
                Task {
                    var ctx = await SelfModelService.shared.lifeContext(for: userId)
                    if !ctx.sensitiveTopicsDisabled.contains(where: { $0.caseInsensitiveCompare(parsed.subject) == .orderedSame }) {
                        ctx.sensitiveTopicsDisabled.append(parsed.subject)
                        SelfModelService.shared.saveLifeContext(ctx, userId: userId)
                        AIService.cacheLifeContext(ctx)
                    }
                }
            case .track:
                Task {
                    var ctx = await SelfModelService.shared.lifeContext(for: userId)
                    if !ctx.primaryFocus.contains(where: { $0.caseInsensitiveCompare(parsed.subject) == .orderedSame }) {
                        var focus = ctx.primaryFocus
                        focus.append(parsed.subject)
                        ctx.primaryFocus = Array(focus.suffix(5))
                        SelfModelService.shared.saveLifeContext(ctx, userId: userId)
                        AIService.cacheLifeContext(ctx)
                    }
                }
            }

            SelfModelService.shared.recordModelOp(
                ModelOp(op: parsed.op, targetItemId: parsed.targetItemId,
                        subject: parsed.subject, quote: parsed.quote, sessionId: sessionId),
                userId: userId
            )
        }
    }
}

// MARK: - View

struct DailyChatView: View {

    let onSave: () -> Void
    /// Set when reached via the home invitation card's mic — opens the chat in
    /// voice-first mode (see `isVoiceMode`) with the mic already listening.
    let startWithDictation: Bool
    /// Voice-first mode: the composer is replaced by `voicePanel` — one big
    /// talk/send button, the live transcript above it, and stopping sends. The
    /// mic entry point used to open the exact same screen as the text entry
    /// point with the mic quietly hot, so the two felt identical. The keyboard
    /// button in the panel drops back to the normal composer for the rest of
    /// the session.
    @State private var isVoiceMode: Bool

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
    /// "Keep talking" hides the "ready to close" card for the rest of the
    /// session. It used to reset on every new user message, which re-popped the
    /// big card after every other reply — nagging, and the header's "Save" is
    /// always there anyway, so once dismissed it stays dismissed.
    @State private var dismissedWeaveCard = false

    /// - Parameter isOnboarding: onboarding's first-ever session — lowers the save
    ///   floor and suppresses the one-time education sheet. See
    ///   `DailyChatViewModel.isOnboarding`.
    init(
        userId: String,
        seedContext: String? = nil,
        startWithDictation: Bool = false,
        isOnboarding: Bool = false,
        onSave: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.startWithDictation = startWithDictation
        _isVoiceMode = State(initialValue: startWithDictation)
        _vm = StateObject(wrappedValue: DailyChatViewModel(userId: userId, seedContext: seedContext, isOnboarding: isOnboarding))
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                thread
                weaveBar
                retryRow
                if isVoiceMode {
                    voicePanel
                } else {
                    inputBar
                }
            }

            if isComposeExpanded {
                ExpandedComposeView(
                    draft: $vm.draft,
                    focused: $expandedFocused,
                    answeringQuestion: answeringQuestion,
                    isWaitingOnSpilr: vm.isThinking || vm.isRevealing,
                    isRecording: speech.isRecording,
                    speechError: speech.errorMessage,
                    onMic: toggleExpandedDictation,
                    onDone: collapseCompose,
                    onSend: sendFromExpanded
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $vm.showCrisisResource) {
            PatternResourceCardView(onDismiss: { vm.showCrisisResource = false })
        }
        .sheet(isPresented: $vm.showThoughtJournalEducation, onDismiss: {
            // Voice mode holds its auto-start while the one-time education sheet
            // is up (see `.task`) — a hot mic behind a sheet the user is reading
            // would transcribe them reading it.
            startVoiceModeDictationIfNeeded()
        }) {
            ThoughtJournalEducationView(onDismiss: { vm.showThoughtJournalEducation = false })
        }
        .task {
            vm.maybeShowThoughtJournalEducation()
            // dailyChatStarted is the "chat opened" series; cbtModeStarted stays as
            // its own event for continuity with data from when it was mode-specific.
            AnalyticsManager.shared.logEvent(.dailyChatStarted)
            AnalyticsManager.shared.logEvent(.cbtModeStarted)
            if !vm.showThoughtJournalEducation {
                startVoiceModeDictationIfNeeded()
            }
        }
        // A presentation firing while the compose surface is expanded (the
        // weave preview is the reachable one — crisis and discard already
        // collapse via `send()`/the alert flow) would otherwise appear
        // stacked on top of it.
        .onChange(of: vm.showPreview) { _, showing in
            if showing { collapseCompose() }
        }
        // Typing into the draft while dictation is running ends the dictation —
        // otherwise the next partial transcript would overwrite what was just
        // typed. Dictation's own writes arrive via `liveText` below and always
        // equal it, so they never trip this.
        .onChange(of: vm.draft) { _, new in
            if speech.isRecording && new != speech.liveText { speech.stop() }
        }
        .alert("Leave this conversation?", isPresented: $showDiscardAlert) {
            if vm.canWeave {
                Button("Save as entry") { vm.weave() }
            }
            Button("Discard", role: .destructive) {
                vm.discardSession()
                dismiss()
            }
            Button("Keep chatting", role: .cancel) {}
        } message: {
            Text("Your conversation won't be saved unless you turn it into an entry first.")
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
                    photo: $vm.attachedPhoto,
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
            saveButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// The always-available save. Present from the first reply onward so saving
    /// never depends on the "ready to close" card having appeared (or not having
    /// been dismissed) — see `canWeave`.
    @ViewBuilder
    private var saveButton: some View {
        if vm.canWeave {
            Button { speech.stop(); vm.weave() } label: {
                HStack(spacing: 6) {
                    if vm.isWeaving {
                        ProgressView().tint(AppTheme.cream).scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    }
                    Text("Save")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .opacity(vm.isThinking || vm.isRevealing ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.isWeaving || vm.isThinking || vm.isRevealing)
            .accessibilityLabel("Save as entry")
            .accessibilityIdentifier("chat.save")
            .transition(.opacity.combined(with: .scale))
        }
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
    // button hides the card for the rest of the session (see
    // `dismissedWeaveCard`). Shown only once Spilr has actually delivered the
    // snapshot (`readyToWeave`) — not on a turn count, which popped it up after
    // almost every reply. Saving earlier is the header's `saveButton`.
    // Onboarding keeps its turn-count trigger: there the card IS the first-entry
    // path the step-3 copy points at. No "felt deeper than usual" line: nothing in the
    // app computes session depth, and inventing a threshold here would be
    // exactly the fake precision this redesign elsewhere argues against.
    @ViewBuilder
    private var weaveBar: some View {
        if showsWeaveCard {
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
                            Text("Wrap up & save")
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
                .accessibilityIdentifier("chat.wrapUp")
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

    private var showsWeaveCard: Bool {
        guard !dismissedWeaveCard else { return false }
        return vm.isOnboarding ? vm.canWeave : vm.readyToWeave
    }

    /// A rounded, approximate duration — "~3 MIN", never "~3.2 MIN". Read live
    /// at render time rather than ticking, since the card only needs to be
    /// roughly right, not a stopwatch.
    private var sessionDurationText: String {
        let minutes = max(1, Int((Date().timeIntervalSince(vm.startedAt) / 60).rounded()))
        return "~\(minutes) MIN"
    }

    // MARK: - Retry row
    //
    // Shown when a chat turn fails for any reason other than the two named product
    // responses (blocked-by-safety, budget-exceeded), which already reply in-thread.
    // No canned Spilr line stands in for a real one — see `DailyChatViewModel.send()`.
    @ViewBuilder
    private var retryRow: some View {
        if vm.turnFailed {
            HStack(spacing: 10) {
                Text("Couldn't reach Spilr")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Button("Retry") { vm.retryLastTurn() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AppTheme.terracotta)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.cream.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.inkSoft.opacity(0.14), lineWidth: 1))
            .padding(.horizontal, 20)
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
                .accessibilityIdentifier("chat.compose")

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
                    // Voice dictation opens the SAME expanded writing surface typing
                    // does, already listening — so talking and typing land in one
                    // place, where the transcript can be stopped, read, edited and
                    // then sent. It used to dictate straight into this one-line
                    // capsule, where the mic flipped to a send button the moment the
                    // first word arrived, leaving no way to stop and review.
                    Button { expandCompose(dictate: true) } label: {
                        composerCircle(
                            systemName: "mic.fill",
                            fill: AppTheme.cream.opacity(0.8),
                            tint: AppTheme.ink,
                            bordered: true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isThinking || vm.isRevealing)
                    .accessibilityLabel("Dictate")
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

    // MARK: - Voice panel (voice-first mode)
    //
    // Replaces `inputBar` when the chat was opened from the home mic. One big
    // button carries the whole loop: tap to talk, tap again to send what you
    // said. If the recognizer ends on its own (a long pause), the transcript
    // waits with the button as send and a small mic to add more. The keyboard
    // button leaves voice mode for the rest of the session, carrying any
    // transcript into the expanded editor.
    private var voicePanel: some View {
        VStack(spacing: 10) {
            if hasDraft {
                ScrollView {
                    Text(vm.draft)
                        .font(AppTheme.editorialBody(size: 16))
                        .foregroundStyle(AppTheme.ink)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.cream.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Text(voiceCaption)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(speech.errorMessage != nil ? AppTheme.terracottaDeep : AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    speech.stop()
                    isVoiceMode = false
                    expandCompose()
                } label: {
                    composerCircle(systemName: "keyboard", fill: AppTheme.cream.opacity(0.8),
                                   tint: AppTheme.ink, bordered: true, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Type instead")

                Spacer()

                Button(action: voiceMainAction) {
                    Image(systemName: voiceMainIcon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(width: 76, height: 76)
                        .background(
                            LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(Circle())
                        .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 12, x: 0, y: 6)
                        .scaleEffect(speech.isRecording ? 1.06 : 1.0)
                        .animation(speech.isRecording
                                   ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                   : .default,
                                   value: speech.isRecording)
                        .opacity(isWaitingOnSpilr ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isWaitingOnSpilr)
                .accessibilityLabel(speech.isRecording ? "Stop and send" : (hasDraft ? "Send" : "Talk"))
                .accessibilityIdentifier("chat.voice.main")

                Spacer()

                // Add more to a transcript the recognizer ended on its own.
                // Invisible (but still spacing) otherwise, so the big button
                // stays centred.
                Button {
                    Task { await speech.toggle(existingText: vm.draft) }
                } label: {
                    composerCircle(systemName: "mic.fill", fill: AppTheme.cream.opacity(0.8),
                                   tint: AppTheme.ink, bordered: true, size: 44)
                }
                .buttonStyle(.plain)
                .opacity(hasDraft && !speech.isRecording && !isWaitingOnSpilr ? 1 : 0)
                .disabled(!hasDraft || speech.isRecording || isWaitingOnSpilr)
                .accessibilityLabel("Add more")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(AppTheme.paper)
        .animation(.easeOut(duration: 0.2), value: hasDraft)
    }

    private var isWaitingOnSpilr: Bool { vm.isThinking || vm.isRevealing }

    private var voiceMainIcon: String {
        if speech.isRecording { return "stop.fill" }
        return hasDraft ? "arrow.up" : "mic.fill"
    }

    private var voiceCaption: String {
        if isWaitingOnSpilr { return "Spilr is replying\u{2026}" }
        if let error = speech.errorMessage, !speech.isRecording { return error }
        if speech.isRecording { return "Listening \u{2014} tap when you're done to send" }
        if hasDraft { return "Tap to send, or add more" }
        return "Tap to talk"
    }

    private func voiceMainAction() {
        guard !isWaitingOnSpilr else { return }
        if speech.isRecording {
            // Stop BEFORE send — `stop()` closes the recognizer's result gate, so
            // a late partial can't refill the draft `send()` just cleared.
            speech.stop()
            if hasDraft { vm.send() }
        } else if hasDraft {
            vm.send()
        } else {
            Task { await speech.toggle(existingText: vm.draft) }
        }
    }

    /// The voice-mode auto-start — once per presentation, and never behind the
    /// education sheet (its `onDismiss` calls this again).
    private func startVoiceModeDictationIfNeeded() {
        guard isVoiceMode, !hasStartedDictation, !speech.isRecording else { return }
        hasStartedDictation = true
        Task { await speech.toggle(existingText: vm.draft) }
    }

    // MARK: - Expanded compose state (Spilr Redesign 3c)

    /// - Parameter dictate: open already listening, keyboard down — the capsule's
    ///   mic. Typing into the editor at any point ends the dictation (see
    ///   `.onChange(of: vm.draft)`), and the footer mic toggles it.
    private func expandCompose(dictate: Bool = false) {
        // Snapshot, not a live read — the last Spilr message mutates
        // word-by-word while `revealReply` is still typing it out, and a live
        // binding would animate the strip's text along with it.
        answeringQuestion = vm.messages.last { $0.role == .spilr }?.text ?? ""
        withAnimation(.easeOut(duration: 0.20)) { isComposeExpanded = true }
        if dictate {
            expandedFocused = false
            if !speech.isRecording {
                Task { await speech.toggle(existingText: vm.draft) }
            }
        } else {
            expandedFocused = true
        }
    }

    private func toggleExpandedDictation() {
        // Keyboard down while listening, so the transcript isn't hidden under it.
        if !speech.isRecording { expandedFocused = false }
        Task { await speech.toggle(existingText: vm.draft) }
    }

    private func collapseCompose() {
        speech.stop()
        expandedFocused = false
        withAnimation(.easeOut(duration: 0.20)) { isComposeExpanded = false }
    }

    private func sendFromExpanded() {
        // Stop dictation first (see `voiceMainAction`), then send BEFORE
        // collapsing — collapsing first would leave `vm.draft` populated for a
        // frame, visibly flashing the old text back into the at-rest capsule
        // before `send()` clears it. `vm.send()` re-checks its own
        // `!isThinking && !isRevealing` guard, so this is safe even if called
        // while the footer's send button should have been disabled.
        speech.stop()
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
    let isRecording: Bool
    let speechError: String?
    let onMic: () -> Void
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

    private var footerCaption: String {
        if isRecording { return "Listening \u{2014} tap \u{25A0} to stop" }
        if let speechError { return speechError }
        return isWaitingOnSpilr
            ? "Spilr is still writing\u{2026}"
            : "Take your time \u{2014} nothing sends until you tap \u{2191}"
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
                .accessibilityIdentifier("chat.editor")
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

            Text(footerCaption)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(speechError != nil && !isRecording ? AppTheme.terracottaDeep : AppTheme.slate)
                .lineLimit(2)

            Spacer(minLength: 0)

            // Dictation lives here too, so talking and typing share one surface.
            Button(action: onMic) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isRecording ? AppTheme.cream : AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(isRecording ? AppTheme.terracotta : AppTheme.cream.opacity(0.8))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.inkSoft.opacity(isRecording ? 0 : 0.15), lineWidth: 1))
                    .scaleEffect(isRecording ? 1.06 : 1.0)
                    .animation(isRecording
                               ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                               : .default,
                               value: isRecording)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop dictation" : "Dictate")
            .accessibilityIdentifier("chat.editor.mic")

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
            .accessibilityIdentifier("chat.editor.send")
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
    @Binding var photo: UIImage?
    let onSave: (String) -> Void
    let onBack: () -> Void

    @State private var text: String

    init(initialText: String, photo: Binding<UIImage?>, onSave: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        self.initialText = initialText
        _photo = photo
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

                        PhotoAttachCard(image: $photo)

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
                        .accessibilityIdentifier("chat.review.save")
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
// Shown the first time the user opens a chat (outside onboarding — see
// `isOnboarding`). Plain, warm language answering the two questions a
// first-timer has: what is this, and how does it help? No clinical vocabulary.
// Persistence of the "seen" flag lives in `ThoughtJournalEducation` below.

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
                    .accessibilityIdentifier("chat.intro.start")

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
