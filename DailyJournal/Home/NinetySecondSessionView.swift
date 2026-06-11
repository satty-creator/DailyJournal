//
//  NinetySecondSessionView.swift
//  DailyJournal
//
//  The 90-second timed journal entry. The constraint is the feature.
//
//  Now carries the Hint Ladder: an optional, tiny, progressively-smaller support
//  layer so a user is never dropped onto a naked blank page. A manual hint button
//  is always available; a soft "still blank?" rescue appears only after quiet
//  inactivity; voice mode offers a say-able phrase instead of a 90-second demand;
//  and a user who can't write or talk can still save a trace.
//

import SwiftUI

struct NinetySecondSessionView: View {

    let userId: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: NinetySecondViewModel
    @StateObject private var hints: HintEngine
    @StateObject private var speech = SpeechManager()
    @FocusState private var isFocused: Bool
    @State private var micError: String?
    @State private var showHintPanel = false
    @State private var rescueDismissed = false
    /// The starter currently shown. Seeded from an explicit override or the
    /// engine, and re-rolled by the gentler / direct / weirder controls.
    @State private var displayedPrompt: String
    /// True only while the view hasn't yet adopted a Gemini-upgraded starter.
    @State private var usingExplicitPrompt: Bool
    /// Pebbles chosen inline on the writing screen. The pebble picker is no longer
    /// a separate gating step — you can start writing immediately and (optionally)
    /// tap a pebble to make the starter more specific.
    @State private var selectedPebbles: [String]
    // One-time, on-device hint that surfaces the mic on the timed screen — voice
    // is the fastest way to fill 90 seconds. Cleared the first time it's used.
    @AppStorage("seen90sVoiceHint") private var seen90sVoiceHint = false

    /// Primary initialiser. `hintContext` carries the chosen pebbles / mode /
    /// personal level. `prompt` is an optional explicit starter (used by pattern
    /// callbacks) that overrides the pebble-derived one.
    init(
        userId: String,
        hintContext: HintContext = HintContext(),
        prompt: String? = nil,
        onSave: @escaping () -> Void
    ) {
        self.userId = userId
        self.onSave = onSave
        _vm = StateObject(wrappedValue: NinetySecondViewModel(
            userId: userId,
            pebbles: hintContext.pebbles
        ))
        _hints = StateObject(wrappedValue: HintEngine(context: hintContext))

        let starter = prompt
            ?? (hintContext.mode == .talk
                ? HintLadder.voicePrompt(pebbles: hintContext.pebbles)
                : HintLadder.starterPrompt(pebbles: hintContext.pebbles, personal: hintContext.personal))
        _displayedPrompt = State(initialValue: starter)
        _usingExplicitPrompt = State(initialValue: prompt != nil)
        _selectedPebbles = State(initialValue: hintContext.pebbles)
    }

    private var isTalk: Bool { hints.context.mode == .talk }

    /// The soft rescue shows only when the user has sat blank for a while, hasn't
    /// dismissed it, isn't recording, and hasn't asked for fewer hints today.
    private var shouldShowRescue: Bool {
        vm.secondsBlank >= 15
            && !rescueDismissed
            && !hints.hintsQuietedToday
            && !speech.isRecording
            && vm.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                promptArea
                timerRing
                if shouldShowRescue { rescueBanner }
                textArea
                bottomBar
            }
        }
        .onAppear {
            vm.start()
            isFocused = !isTalk
        }
        .onDisappear { speech.stop() }
        // Adopt the Gemini-upgraded starter once it arrives — but never clobber a
        // starter the user is actively shaping, or an explicit pattern prompt.
        .onChange(of: hints.bundle) { _, newBundle in
            guard !usingExplicitPrompt, newBundle.source == "gemini" else { return }
            displayedPrompt = isTalk ? newBundle.starterTalk : newBundle.starterWrite
        }
        // Mirror the live transcript into the entry as the user speaks. liveText
        // only mutates during an active recognition session, so this never
        // clobbers text typed after recording stops — and, crucially, the spoken
        // words are already committed to `vm.content` the instant they're heard.
        // That means stopping the mic (or hitting Save mid-recording) can no
        // longer lose the transcript. This mirrors the proven editor approach.
        .onChange(of: speech.liveText) { _, live in
            vm.content = live
        }
        .onChange(of: vm.didAutoSave) { _, saved in
            if saved { onSave(); dismiss() }
        }
        .onChange(of: speech.errorMessage) { _, message in
            micError = message
        }
        .sheet(isPresented: $showHintPanel) {
            HintPanelView(
                engine: hints,
                onUse: { fragment in
                    useHint(fragment)
                    showHintPanel = false
                },
                onSaveTrace: {
                    showHintPanel = false
                    vm.saveTrace()
                }
            )
        }
        .alert("Microphone unavailable", isPresented: Binding(
            get: { micError != nil },
            set: { if !$0 { micError = nil } }
        )) {
            Button("Open Settings") {
                micError = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { micError = nil }
        } message: {
            Text(micError ?? "")
        }
        .alert("Time's up.", isPresented: $vm.showTimeUpAlert) {
            Button("Save entry") {
                vm.saveEntry(); onSave(); dismiss()
            }
        } message: {
            Text("Your 90 seconds are up. Saving what you wrote.")
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            Button {
                speech.stop()
                vm.stop()
                dismiss()
            } label: {
                Text("Discard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.inkSoft)
            }

            Spacer()

            Text("ninety")
                .font(AppTheme.editorialDisplay(size: 18))
                .foregroundStyle(AppTheme.terracotta)
                .italic()

            Spacer()

            Button {
                speech.stop()
                vm.saveEntry()
                dismiss()
            } label: {
                Text("Save now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(vm.content.isEmpty ? AppTheme.slate : AppTheme.terracotta)
            }
            .disabled(vm.content.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Prompt / starter hint
    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isTalk ? "SAY THIS, THEN KEEP GOING IF YOU WANT" : "STARTER HINT")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
            Text(displayedPrompt)
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: displayedPrompt)

            // Re-roll the starter without leaving the page. Only local restyles —
            // instant, no network. Hidden when an explicit prompt was supplied.
            if !usingExplicitPrompt {
                HStack(spacing: 8) {
                    if isTalk {
                        restylePill("shorter") { displayedPrompt = hints.restyledVoice(.short) }
                        restylePill("give choices") { displayedPrompt = hints.restyledVoice(.choice) }
                    } else {
                        restylePill("gentler") { displayedPrompt = hints.restyledStarter(.gentle) }
                        restylePill("more direct") { displayedPrompt = hints.restyledStarter(.direct) }
                        restylePill("weirder") { displayedPrompt = hints.restyledStarter(.weird) }
                    }
                }

                // Inline pebble strip — replaces the old separate picker screen.
                // Optional: tap to make the starter specific without leaving the page.
                pebbleStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Inline pebble strip
    private var pebbleStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT TOUCHED TODAY?  ·  OPTIONAL")
                .font(AppTheme.mono(size: 9))
                .tracking(1.5)
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HintLadder.pebbleBank.filter { !HintLadder.personalPebbles.contains($0) }, id: \.self) { pebble in
                        let isSelected = selectedPebbles.contains(pebble)
                        Button { togglePebble(pebble) } label: {
                            Text(pebble)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkSoft)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? AppTheme.lav : AppTheme.paperWarm)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func togglePebble(_ pebble: String) {
        if let idx = selectedPebbles.firstIndex(of: pebble) {
            selectedPebbles.remove(at: idx)
        } else {
            guard selectedPebbles.count < HintLadder.maxPebbles else { return }
            selectedPebbles.append(pebble)
        }
        // Keep what gets saved + the starter in sync with the inline selection.
        vm.pebbles = selectedPebbles
        displayedPrompt = HintLadder.starterPrompt(pebbles: selectedPebbles, personal: hints.context.personal)
    }

    private func restylePill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.paperWarm)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timer ring
    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.paperWarm, lineWidth: 5)
                .frame(width: 88, height: 88)

            Circle()
                .trim(from: 0, to: vm.progress)
                .stroke(
                    vm.timeRemaining <= 15 ? AppTheme.terracottaDeep : AppTheme.terracotta,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: vm.progress)

            VStack(spacing: 1) {
                Text("\(vm.timeRemaining)")
                    .font(AppTheme.editorialDisplay(size: 28))
                    .foregroundStyle(vm.timeRemaining <= 15 ? AppTheme.terracottaDeep : AppTheme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("sec")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Soft blank rescue
    //
    // Appears once, quietly, after the user has been blank for a while. It never
    // nags: it offers the smallest possible start and a one-tap dismiss, plus a
    // way to save a blank drop and be done.
    private var rescueBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AppTheme.terracotta)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Still blank?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(isTalk ? "Want the smallest thing you could say?" : "Want the smallest possible start?")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)

                HStack(spacing: 8) {
                    Button {
                        showHintPanel = true
                    } label: {
                        Text("hint me")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(AppTheme.sun).clipShape(Capsule())
                    }
                    Button {
                        vm.saveBlankDrop()
                    } label: {
                        Text("save a blank drop")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.inkSoft)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(AppTheme.cream).clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button {
                withAnimation { rescueDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(14)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Text area (with floating hint button)
    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if vm.content.isEmpty {
                Text(isTalk ? "Tap the mic and say one sentence." : "Start typing or tap the mic to speak.")
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.slate.opacity(0.7))
                    .italic()
                    .padding(.top, 10)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            // Single source of truth: the editor is always bound to vm.content,
            // which updates live while recording (see the liveText onChange). The
            // spoken text is part of the editable buffer, so it's never lost on stop.
            TextEditor(text: $vm.content)
                .font(AppTheme.editorialBody(size: 17))
                .foregroundStyle(AppTheme.ink)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)
                .lineSpacing(5)
                .overlay(alignment: .topTrailing) {
                    if speech.isRecording {
                        Circle()
                            .fill(AppTheme.terracotta)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                            .padding(.top, 10)
                    }
                }

            // The always-available, subtle hint button. This is the missing piece:
            // the user doesn't have to go back or think — just tap "hint".
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showHintPanel = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .bold))
                            Text("hint")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.sun)
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.cardShadow, radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 4)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bottom bar with mic button
    private var bottomBar: some View {
        HStack {
            // In talk mode, a quiet "I'm silent" door to the say-able hints.
            if isTalk {
                Button {
                    showHintPanel = true
                } label: {
                    Text("I'm silent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(AppTheme.paperWarm).clipShape(Capsule())
                }
            } else {
                Text("\(vm.content.split(separator: " ").count) words")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                isFocused = false
                seen90sVoiceHint = true
                Task { await speech.toggle(existingText: vm.content) }
            } label: {
                ZStack {
                    Circle()
                        .fill(speech.isRecording ? AppTheme.terracotta : AppTheme.ink)
                        .frame(width: 48, height: 48)

                    if speech.isRecording {
                        Circle()
                            .stroke(AppTheme.terracotta.opacity(0.4), lineWidth: 2)
                            .frame(width: 62, height: 62)
                            .scaleEffect(speech.isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)
                    }

                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.cream)
                }
            }
            .overlay(alignment: .top) {
                if !seen90sVoiceHint && !speech.isRecording {
                    VStack(spacing: 2) {
                        Text("Tap to speak")
                            .font(AppTheme.mono(size: 10))
                            .tracking(1)
                            .foregroundStyle(AppTheme.cream)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.ink)
                            .clipShape(Capsule())
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .fixedSize()
                    .offset(y: -42)
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: seen90sVoiceHint)

            Spacer()

            if vm.timeRemaining <= 20 && vm.timeRemaining > 0 {
                Text("Almost there")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.terracotta)
                    .transition(.opacity)
            } else {
                Text("")
                    .font(AppTheme.mono(size: 11))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .padding(.top, 8)
    }

    // MARK: - Insert a chosen hint
    //
    // In talk mode the hint becomes the say-able prompt. In write mode it lands in
    // the editor: replacing an empty field, or appended on its own line if the
    // user has already started. The hint never overwrites real words.
    private func useHint(_ fragment: String) {
        let clean = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if isTalk {
            displayedPrompt = clean
        } else if vm.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vm.content = clean
            isFocused = true
        } else {
            vm.content += "\n" + clean
            isFocused = true
        }
        rescueDismissed = true
    }
}

// MARK: - ViewModel
@MainActor
final class NinetySecondViewModel: ObservableObject {

    @Published var content: String = ""
    @Published var voiceTranscript: String = ""   // live partial from speech
    @Published var timeRemaining: Int = 90
    @Published var progress: Double = 1.0
    @Published var showTimeUpAlert = false
    @Published var didAutoSave = false
    /// Seconds the user has been completely blank (no typing, no transcript).
    /// Drives the soft "still blank?" rescue. Resets the moment anything appears.
    @Published var secondsBlank: Int = 0

    let userId: String
    /// The pebbles chosen for this session — attached to traces / blank drops.
    /// Mutable so inline pebble selection on the writing screen updates what gets
    /// saved (the picker is no longer a separate gating step).
    var pebbles: [String]

    private var timer: Timer?
    private let service = JournalService()

    init(userId: String, pebbles: [String] = []) {
        self.userId = userId
        self.pebbles = pebbles
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard timeRemaining > 0 else { return }
        timeRemaining -= 1
        progress = Double(timeRemaining) / 90.0

        // Track blank time for the soft rescue. content now reflects live speech
        // too, so this single check covers both typing and dictation.
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            secondsBlank += 1
        } else {
            secondsBlank = 0
        }

        if timeRemaining == 0 {
            stop()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Out of time and still blank: a blank drop is better than nothing,
                // and it's never framed as failure.
                saveBlankDrop()
            } else {
                showTimeUpAlert = true
            }
        } else if timeRemaining == 10 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Save a tap-only trace (no words today)
    func saveTrace() {
        stop()
        service.saveTrace(userId: userId, pebbles: pebbles, blank: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        didAutoSave = true
    }

    // MARK: - Save a blank drop (showed up with nothing)
    func saveBlankDrop() {
        stop()
        service.saveTrace(userId: userId, pebbles: pebbles, blank: true)
        didAutoSave = true
    }

    func saveEntry() {
        stop()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Step 1 – save with local heuristics immediately (no await)
        let sentiment  = LocalAI.detectSentiment(from: trimmed)
        let reflection = NinetyVoice.localReflection(from: trimmed, sentiment: sentiment)
        let bullets    = reflection.observations
        let question   = reflection.question

        // Enrich the chosen pebbles with a few content-derived topical tags so
        // entries aren't limited to a mood word. Pebbles come first.
        var mergedTags = pebbles
        for topic in LocalAI.extractTopics(from: trimmed) where !mergedTags.contains(topic) && mergedTags.count < 5 {
            mergedTags.append(topic)
        }

        let entry = JournalEntry(
            userId: userId,
            content: trimmed,
            tags: mergedTags,
            sessionType: .ninetySecond,
            aiSummaryBullets: bullets,
            aiQuestion: question,
            sentimentLabel: sentiment
        )
        service.createEntry(entry)

        // Step 2 – Gemini enrichment + Echo extraction in background, silent on failure.
        let svc             = service
        let entryId         = entry.id
        let uid             = userId
        let entryCreatedAt  = entry.createdAt

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

        // River mark — saves a local mark instantly, upgrades with Gemini if keyed.
        Task.detached(priority: .background) {
            await RiverService().generateMark(
                entryText:      trimmed,
                entryId:        entryId,
                userId:         uid,
                entryCreatedAt: entryCreatedAt
            )
        }
    }
}
