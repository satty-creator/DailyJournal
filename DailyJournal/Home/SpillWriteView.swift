//
//  SpillWriteView.swift
//  DailyJournal
//
//  The "Spill" write screen.
//
//  Layout: screen-head + Reset + "send to future self", the prompt card, an
//  optional mood picker, the textarea, a photo upload zone, a bottom control row
//  (small mic + word-count / save-state), the "Save exactly as written" button,
//  and a live on-device "mirror" shelf. (The 90-second countdown ring and the
//  "pick a lens" seed grid were removed to reduce pre-writing friction.)
//
//  The mic lives small at the bottom; tapping it dictates, with the live
//  transcript streaming into the editor (SpeechManager).
//
//  It reuses TimedSessionViewModel purely as the save engine (saveEntry persists
//  the entry + kicks off enrichment / Echo / River marks).
//
//  See todaysreadprd.md.
//

import SwiftUI
import UIKit

struct SpillWriteView: View {

    let userId: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TimedSessionViewModel
    @FocusState private var isFocused: Bool

    @StateObject private var speech = SpeechManager()
    @State private var photoUIImage: UIImage?
    @State private var saved = false
    @State private var micError: String?
    @State private var selectedMood: Mood? = nil
    @State private var showResetConfirm = false
    @State private var showDraftRestored = false
    /// "Send to future self" — saves the entry, then opens the delivery-date
    /// sheet. The only reachable entry point into FutureSelfSheet; the editor's
    /// old paperplane toolbar button lived behind a branch that could never run.
    @State private var showFutureSelfSheet = false

    // Live mirror shelf — shown after 40 words with a 1-second entrance delay
    // so it doesn't interrupt mid-sentence. Dismissed when word count drops back below 40.
    @State private var showMirror = false

    // Starter "question" — same engine the pencil's blank-page starter uses, so a
    // free spill always opens with a probing prompt the user can re-roll.
    @StateObject private var hints: HintEngine
    @State private var displayedPrompt: String

    init(userId: String, onSave: @escaping () -> Void) {
        self.userId = userId
        self.onSave = onSave
        _vm = StateObject(wrappedValue: TimedSessionViewModel(userId: userId))
        let engine = HintEngine(userId: userId)
        _hints = StateObject(wrappedValue: engine)
        // Prime the displayed prompt from the starter question bank — not a
        // Mirror seed, which assumes enough history to reflect a pattern back
        // and reads as an odd, abstract opener on a blank-page write.
        _displayedPrompt = State(initialValue: engine.next())
    }

    private var trimmed: String {
        vm.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var wordCount: Int {
        trimmed.isEmpty ? 0 : trimmed.split { $0 == " " || $0 == "\n" }.count
    }

    private let editorAnchor = "spillEditorAnchor"

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        screenHead
                        promptCard
                        moodPicker
                        editor
                            .id(editorAnchor)
                        uploadZone
                        saveButton
                        aiShelf
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                // The editor sits below the prompt card + mood picker, so once the
                // keyboard is up only a sliver of it is visible. Nothing else tells
                // this outer ScrollView to follow the cursor as text grows, so we
                // drive it explicitly: on focus, and on every keystroke/dictated
                // chunk, keep the editor's bottom edge (where the cursor lives)
                // pinned just above the keyboard/mic bar.
                .onChange(of: isFocused) { _, focused in
                    guard focused else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy.scrollTo(editorAnchor, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: vm.content) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(editorAnchor, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { micFloatingBar }
        .onChange(of: vm.content) { _, _ in
            saved = false
            vm.persistDraft()
        }
        // Mirror shelf: appear after 40 words (matching the structure button threshold)
        // with a 1-second delay so it doesn't interrupt mid-sentence.
        .onChange(of: wordCount) { _, count in
            if count >= 40 && !showMirror {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard wordCount >= 40 else { return }  // re-check — user may have deleted
                    withAnimation(.easeInOut(duration: 0.35)) { showMirror = true }
                }
            } else if count < 40 && showMirror {
                withAnimation(.easeInOut(duration: 0.2)) { showMirror = false }
            }
        }
        // Mirror the live transcript into the entry as the person speaks.
        // Guard on isRecording so a stale liveText value from a previous session
        // can't overwrite text the user typed after stopping the mic.
        .onChange(of: speech.liveText) { _, live in
            guard speech.isRecording else { return }
            vm.content = live
        }
        .onChange(of: speech.errorMessage) { _, message in micError = message }
        .onAppear {
            isFocused = true
            AnalyticsManager.shared.trackEntryCompositionStarted(sessionType: "timed")
            if vm.didRestoreDraft {
                showDraftRestored = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { showDraftRestored = false }
                }
            }
        }
        .onDisappear { speech.stop() }
        .alert("Clear this entry?", isPresented: $showResetConfirm) {
            Button("Clear", role: .destructive) {
                AnalyticsManager.shared.trackEntryDiscarded(sessionType: "timed", wordCount: wordCount)
                speech.stop()
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.content = ""
                    saved = false
                }
                vm.clearDraft()
            }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
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
        // onDismiss fires whether the user picks a delivery date or taps "Not
        // now" — either way the entry is already saved, so hand back to the
        // caller and close, mirroring the plain save button's flow.
        .sheet(isPresented: $showFutureSelfSheet, onDismiss: {
            onSave()
            dismiss()
        }) {
            if let entry = vm.savedEntry {
                FutureSelfSheet(entry: entry) { }
            }
        }
    }

    // MARK: - Screen head (title + reset)
    private var screenHead: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
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

                Spacer()

                // Labeled, not a bare icon: a small unlabeled paperplane was the
                // only entry point into future-self letters and went unnoticed.
                // A pill that names the action makes the feature discoverable.
                Button {
                    vm.saveEntry(photo: photoUIImage, mood: selectedMood)
                    saved = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showFutureSelfSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Future self")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(trimmed.isEmpty ? AppTheme.slate : AppTheme.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(
                        (trimmed.isEmpty ? AppTheme.inkSoft : AppTheme.terracotta).opacity(0.2),
                        lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .accessibilityLabel("Send to future self")

                Button {
                    if trimmed.isEmpty {
                        // Nothing to lose — clear without asking.
                        speech.stop()
                        vm.clearDraft()
                    } else {
                        showResetConfirm = true
                    }
                } label: {
                    Text("Reset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.cream.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spill")
                    .font(AppTheme.editorialDisplay(size: 30))
                    .foregroundStyle(AppTheme.ink)
                Text("Saved exactly as written.")
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
            }

            if showDraftRestored {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                    Text("Draft restored")
                        .font(AppTheme.mono(size: 10))
                        .tracking(1)
                }
                .foregroundStyle(AppTheme.terracotta)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Prompt card (starter "question" + re-roll)
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("need a way in?")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
                .textCase(.uppercase)

            Text(displayedPrompt)
                .font(AppTheme.editorialBody(size: 17))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: displayedPrompt)

            rerollPill("another one", icon: "arrow.triangle.2.circlepath") {
                displayedPrompt = hints.next()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cream.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
    }

    private func rerollPill(_ title: String, icon: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppTheme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.paperWarm)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editor
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if vm.content.isEmpty {
                Text("No polishing. No deleting. Spill what is actually here…")
                    .font(AppTheme.editorialBody(size: 17))
                    .foregroundStyle(AppTheme.slate.opacity(0.7))
                    .italic()
                    .padding(.top, 18)
                    .padding(.leading, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $vm.content)
                .font(AppTheme.editorialBody(size: 17))
                .foregroundStyle(AppTheme.ink)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)
                .lineSpacing(5)
                .frame(minHeight: 200, maxHeight: 340)
                .padding(12)
        }
        .background(AppTheme.cream.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Photo upload zone (local preview; opt-in)
    private var uploadZone: some View {
        PhotoAttachCard(image: $photoUIImage)
    }

    // MARK: - Mood picker (compact — optional, shows above editor)
    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("how do you feel?")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMood = selectedMood == mood ? nil : mood
                        }
                        if selectedMood == mood {
                            AnalyticsManager.shared.logEvent(.moodClicked, parameters: ["mood": mood.rawValue])
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(mood.faceEmoji).font(.system(size: 22))
                            Text(mood.scaleLabel)
                                .font(AppTheme.mono(size: 7))
                                .tracking(0.2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // A fixed height, not just `maxWidth: .infinity` — see
                        // the same fix in JournalEditorView's mood picker:
                        // "Very pleasant"/"Very unpleasant" wrap to 2 lines
                        // while the rest fit on 1, so the chips were uneven.
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.vertical, 8)
                        .background(
                            selectedMood == mood
                                ? AppTheme.moodColor(mood).opacity(0.15)
                                : AppTheme.cream.opacity(0.7)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(
                                selectedMood == mood
                                    ? AppTheme.moodColor(mood)
                                    : AppTheme.inkSoft.opacity(0.15),
                                lineWidth: 1.5
                            )
                        )
                        .foregroundStyle(
                            selectedMood == mood
                                ? AppTheme.moodColor(mood)
                                : AppTheme.inkSoft
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AppTheme.cream.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Floating mic bar (always visible above keyboard)
    //
    // Lives in .safeAreaInset(edge: .bottom) so it stays pinned above the
    // keyboard — previously the mic was inside the ScrollView and got hidden
    // as soon as the keyboard raised.
    private var micFloatingBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .monospacedDigit()
                Text(speech.isRecording
                     ? "Listening…"
                     : (saved ? "Saved exactly as written" : "Draft saved on this device"))
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(speech.isRecording ? AppTheme.terracotta
                                     : (saved ? AppTheme.terracotta : AppTheme.inkSoft))
                    .animation(.easeInOut(duration: 0.2), value: speech.isRecording)
            }
            Spacer()
            micButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Mic button — voice → live transcription into the editor.
    private var micButton: some View {
        Button {
            // Capture text BEFORE dismissing the keyboard — isFocused = false may
            // trigger a pending autocorrect commit that would race with the async
            // task and corrupt the existingText snapshot.
            let textSnapshot = vm.content
            isFocused = false
            Task { await speech.toggle(existingText: textSnapshot) }
        } label: {
            ZStack {
                if speech.isRecording {
                    Circle()
                        .stroke(AppTheme.terracotta.opacity(0.4), lineWidth: 3)
                        .frame(width: 58, height: 58)
                        .scaleEffect(speech.isRecording ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: speech.isRecording)
                }
                Circle()
                    .fill(speech.isRecording ? AppTheme.terracotta : AppTheme.ink)
                    .frame(width: 46, height: 46)
                    .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.cream)
            }
            .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start voice entry")
    }

    // MARK: - Save
    private var saveButton: some View {
        Button {
            guard !trimmed.isEmpty else { return }
            vm.saveEntry(photo: photoUIImage, mood: selectedMood)
            saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { dismiss() }
        } label: {
            Text("Save exactly as written")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 12, x: 0, y: 6)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
    }

    // MARK: - Live mirror (on-device, no network)
    //
    // Requires at least 40 words before showing anything (matching the structure
    // button threshold) and enters with a 1-second delay via showMirror state.
    // Topics require phrase-level evidence so a single word doesn't hijack it.
    @ViewBuilder
    private var aiShelf: some View {
        if showMirror {
            let topics    = LocalAI.extractTopics(from: vm.content)
            let sentiment = LocalAI.detectSentiment(from: vm.content)
            VStack(spacing: 10) {
                aiLine(badge: "○",
                       lead: "Live mirror:",
                       body: topics.isEmpty
                            ? "nothing obvious yet — you might be circling something harder to name."
                            : "this is mostly about \(topics.prefix(2).joined(separator: " and ")).")
                aiLine(badge: "♥",
                       lead: "Felt sense:",
                       body: "reads as \(sentiment.lowercased()). No diagnosis — just a mirror.")
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.35), value: "\(topics.first ?? "")-\(sentiment)")
        }
    }

    private func aiLine(badge: String, lead: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            (Text(lead).font(AppTheme.editorialBody(size: 13).weight(.semibold)).foregroundStyle(AppTheme.ink)
             + Text(" " + body).font(AppTheme.editorialBody(size: 13)).foregroundStyle(AppTheme.inkSoft))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppTheme.cream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
    }
}

