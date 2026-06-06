//
//  NinetySecondSessionView.swift
//  DailyJournal
//
//  The 90-second timed journal entry. The constraint is the feature.
//

import SwiftUI

struct NinetySecondSessionView: View {

    let userId: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: NinetySecondViewModel
    @StateObject private var speech = SpeechManager()
    @FocusState private var isFocused: Bool
    @State private var micError: String?
    // One-time, on-device hint that surfaces the mic on the timed screen — voice
    // is the fastest way to fill 90 seconds. Cleared the first time it's used.
    @AppStorage("seen90sVoiceHint") private var seen90sVoiceHint = false

    init(userId: String, prompt: String? = nil, onSave: @escaping () -> Void) {
        self.userId = userId
        self.onSave = onSave
        _vm = StateObject(wrappedValue: NinetySecondViewModel(
            userId: userId,
            prompt: prompt ?? LocalAI.todayPrompt()
        ))
    }

    var body: some View {
        ZStack {
            AppTheme.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                promptArea
                timerRing
                textArea
                bottomBar
            }
        }
        .onAppear {
            vm.start()
            isFocused = true
            // Mic permission is requested lazily when the user taps the mic,
            // not on appear — so we never prompt people who only want to type.
        }
        .onDisappear { speech.stop() }
        // Append speech transcript whenever it updates
        .onChange(of: speech.partialTranscript) { _, newText in
            guard !newText.isEmpty else { return }
            vm.voiceTranscript = newText
        }
        .onChange(of: speech.isRecording) { _, recording in
            if !recording && !vm.voiceTranscript.isEmpty {
                // Recording stopped — commit transcript into content
                let separator = vm.content.isEmpty ? "" : " "
                vm.content += separator + vm.voiceTranscript
                vm.voiceTranscript = ""
            }
        }
        .onChange(of: vm.didAutoSave) { _, saved in
            if saved { onSave(); dismiss() }
        }
        // Surface mic/speech errors so failures are never silent
        .onChange(of: speech.errorMessage) { _, message in
            micError = message
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

    // MARK: - Prompt
    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY'S PROMPT")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
            Text(vm.prompt)
                .font(AppTheme.editorialDisplay(size: 26))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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

    // MARK: - Text area
    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if vm.content.isEmpty && vm.voiceTranscript.isEmpty {
                Text("Start typing or tap the mic to speak.")
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.slate.opacity(0.7))
                    .italic()
                    .padding(.top, 10)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            // Live voice preview shown in a different style while recording
            if speech.isRecording && !vm.voiceTranscript.isEmpty {
                Text(vm.content + (vm.content.isEmpty ? "" : " ") + vm.voiceTranscript)
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(5)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottomTrailing) {
                        // Pulse dot while recording
                        Circle()
                            .fill(AppTheme.terracotta)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                    }
            } else {
                TextEditor(text: $vm.content)
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isFocused)
                    .lineSpacing(5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bottom bar with mic button
    private var bottomBar: some View {
        HStack {
            Text("\(vm.content.split(separator: " ").count) words")
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.inkSoft)
                .monospacedDigit()

            Spacer()

            // Mic button + one-time hint bubble
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
                        // Pulsing ring while active
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
            // Intentionally NOT disabled when permission is denied — tapping it
            // surfaces the "Open Settings" alert so the user can recover.
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
                Text("") // placeholder to keep layout stable
                    .font(AppTheme.mono(size: 11))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .padding(.top, 8)
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

    let prompt: String
    let userId: String

    private var timer: Timer?
    private let service = JournalService()

    init(userId: String, prompt: String) {
        self.userId = userId
        self.prompt = prompt
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

        if timeRemaining == 0 {
            stop()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                didAutoSave = true
            } else {
                showTimeUpAlert = true
            }
        } else if timeRemaining == 10 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func saveEntry() {
        stop()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Step 1 – save with local heuristics immediately (no await)
        let sentiment = LocalAI.detectSentiment(from: trimmed)
        let bullets   = LocalAI.generateBullets(from: trimmed)
        let question  = LocalAI.generateQuestion(from: trimmed, sentiment: sentiment)

        let entry = JournalEntry(
            userId: userId,
            content: trimmed,
            sessionType: .ninetySecond,
            aiSummaryBullets: bullets,
            aiQuestion: question,
            sentimentLabel: sentiment
        )
        service.createEntry(entry)

        // Step 2 – Gemini enrichment + Echo extraction in background, silent on failure.
        // Both run as independent detached tasks so neither can block the other.
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
    }
}
