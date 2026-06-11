//
//  JournalEditorView.swift
//  DailyJournal
//

import SwiftUI

struct JournalEditorView: View {

    @StateObject private var viewModel: JournalEditorViewModel
    @StateObject private var speech = SpeechManager()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isContentFocused: Bool
    @State private var showFutureSelfSheet = false
    @State private var showDeleteConfirm = false
    @State private var micError: String?
    // True only when the user explicitly taps the "send to future self" button.
    // A normal save no longer forces the future-self sheet open.
    @State private var wantsFutureSelf = false

    private let onSave: (() -> Void)?
    /// Fires with the just-saved entry so a list can insert it optimistically
    /// (no wait on a re-fetch). Optional and additive — existing callers unaffected.
    private let onSaveEntry: ((JournalEntry) -> Void)?

    // NOTE: `onSave` is intentionally the LAST parameter so existing trailing-
    // closure call sites (e.g. `JournalEditorView(userId:existingEntry:) { … }`)
    // keep binding to it rather than to `onSaveEntry`.
    init(
        userId: String,
        existingEntry: JournalEntry? = nil,
        initialMood: Mood? = nil,
        onSaveEntry: ((JournalEntry) -> Void)? = nil,
        onSave: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: JournalEditorViewModel(userId: userId, existingEntry: existingEntry, initialMood: initialMood)
        )
        self.onSave = onSave
        self.onSaveEntry = onSaveEntry
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        dateStamp
                        if viewModel.didRestoreDraft {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 10))
                                Text("Draft restored")
                                    .font(AppTheme.mono(size: 10))
                                    .tracking(1)
                            }
                            .foregroundStyle(AppTheme.terracotta)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                            .task {
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                withAnimation { viewModel.didRestoreDraft = false }
                            }
                        }
                        moodWeatherPicker
                        // A way in for the blank page — an AI-sharpened, probing
                        // starter the user can tap to drop in. Only for brand-new,
                        // still-empty entries; vanishes the moment they write.
                        if !viewModel.isEditing && viewModel.content.isEmpty {
                            FreeWriteStarterView(initialMood: viewModel.selectedMood) { fragment in
                                viewModel.content = fragment
                                viewModel.updateSentiment()
                                viewModel.persistDraft()
                                isContentFocused = true
                            }
                            .padding(.bottom, 24)
                            .transition(.opacity)
                        }
                        contentArea
                        if !viewModel.aiSummaryBullets.isEmpty && viewModel.isEditing {
                            aiSummarySection
                        }
                        tagSection
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .onAppear {
                if !viewModel.isEditing { isContentFocused = true }
                // Mic permission is requested lazily when the user taps the mic
                // in the bottom bar — not when the editor opens.
            }
            .safeAreaInset(edge: .bottom) { micBottomBar }
            .onDisappear { speech.stop() }
            // Live transcription: mirror the running transcript into the editor
            // as the user speaks. The final result also flows through here, so
            // nothing extra needs to be committed when recording stops.
            .onChange(of: speech.liveText) { _, live in
                // liveText only mutates during an active recognition session, so
                // this never overwrites text the user types after recording ends.
                viewModel.content = live
            }
            .onChange(of: viewModel.didSaveSuccessfully) { _, saved in
                if saved {
                    if let savedEntry = viewModel.savedEntry { onSaveEntry?(savedEntry) }
                    onSave?()
                    // Only open the future-self sheet when the user explicitly
                    // asked for it via the toolbar; a plain save just dismisses.
                    if wantsFutureSelf && !viewModel.isEditing {
                        showFutureSelfSheet = true
                    } else {
                        dismiss()
                    }
                }
            }
            // onDismiss fires whether user picks a date OR taps "Not now"
            .sheet(isPresented: $showFutureSelfSheet, onDismiss: { dismiss() }) {
                if let entry = viewModel.savedEntry {
                    FutureSelfSheet(entry: entry) { /* sheet will dismiss, onDismiss → editor dismisses */ }
                }
            }
            .onChange(of: viewModel.didDeleteSuccessfully) { _, deleted in
                if deleted {
                    onSave?()
                    dismiss()
                }
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
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Entry", role: .destructive) {
                    viewModel.delete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: - Date stamp
    private var dateStamp: some View {
        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            .font(AppTheme.mono(size: 11))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(0.5)
            .padding(.bottom, 20)
            .padding(.top, 4)
    }

    // MARK: - Weather mood picker
    private var moodWeatherPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW DID TODAY FEEL?")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)

            HStack(spacing: 8) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    Button {
                        viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
                    } label: {
                        VStack(spacing: 4) {
                            Text(mood.faceEmoji).font(.title3)
                            Text(mood.scaleLabel)
                                .font(AppTheme.mono(size: 8))
                                .tracking(0.3)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            viewModel.selectedMood == mood
                                ? AppTheme.moodColor(mood).opacity(0.15)
                                : AppTheme.cream
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(
                                viewModel.selectedMood == mood
                                    ? AppTheme.moodColor(mood)
                                    : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                        .foregroundStyle(
                            viewModel.selectedMood == mood
                                ? AppTheme.moodColor(mood)
                                : AppTheme.inkSoft
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Live sentiment
            if let sentiment = viewModel.sentimentLabel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.sentimentColor(sentiment))
                        .frame(width: 6, height: 6)
                    Text(sentiment.lowercased())
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.sentimentColor(sentiment))
                        .tracking(1)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 24)
        .animation(.easeInOut(duration: 0.3), value: viewModel.sentimentLabel)
    }

    // MARK: - Content editor
    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if viewModel.content.isEmpty {
                    Text("What's on your mind?")
                        .font(AppTheme.editorialBody(size: 19))
                        .foregroundStyle(AppTheme.slate.opacity(0.7))
                        .italic()
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.content)
                    .font(AppTheme.editorialBody(size: 19))
                    .foregroundStyle(AppTheme.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 220)
                    .focused($isContentFocused)
                    .lineSpacing(5)
                    .onChange(of: viewModel.content) { _, _ in
                        viewModel.updateSentiment()
                        viewModel.persistDraft()
                    }
            }

            HStack {
                Text("\(viewModel.wordCount) words")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.slate)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.bottom, 16)

            Divider()
                .overlay(AppTheme.inkSoft.opacity(0.12))
                .padding(.bottom, 20)
        }
    }

    // MARK: - AI summary (shown when editing an existing entry)
    private var aiSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NINETY HEARD")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta)
                    .tracking(2)
                Spacer()
                if let entry = viewModel.shareableEntry {
                    ShareInsightButton(entry: entry)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.aiSummaryBullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("—")
                            .font(AppTheme.mono(size: 12))
                            .foregroundStyle(AppTheme.terracotta)
                        Text(bullet)
                            .font(AppTheme.editorialBody(size: 14))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.paperWarm)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let question = viewModel.aiQuestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(.top, 2)
                    Text(question)
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .italic()
                        .lineSpacing(2)
                }
                .padding(.top, 4)
            }

            Divider()
                .overlay(AppTheme.inkSoft.opacity(0.12))
                .padding(.vertical, 16)
        }
    }

    // MARK: - Tag editor
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAGS")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)

            if !viewModel.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)")
                                .font(AppTheme.mono(size: 12))
                                .foregroundStyle(AppTheme.terracotta)
                            Button {
                                viewModel.removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.terracotta.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }

            if viewModel.tags.count < 5 {
                HStack {
                    TextField("Add a tag…", text: $viewModel.tagInput)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ink)
                        .submitLabel(.done)
                        .onSubmit { viewModel.submitTag() }

                    if !viewModel.tagInput.isEmpty {
                        Button("Add") { viewModel.submitTag() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
                .padding(12)
                .background(AppTheme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if viewModel.isEditing {
                // Delete button — only shown when editing an existing entry
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.terracottaDeep)
                }
            } else {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        ToolbarItem(placement: .principal) {
            Text(viewModel.isEditing ? "Edit entry" : "New entry")
                .font(AppTheme.mono(size: 12))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
        }
        // Send to future self — opt-in. Saves the entry, then opens the
        // delivery-date sheet. Only offered for new entries.
        ToolbarItem(placement: .navigationBarTrailing) {
            if !viewModel.isEditing {
                Button {
                    wantsFutureSelf = true
                    viewModel.save()
                } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 15))
                        .foregroundStyle(viewModel.canSave ? AppTheme.terracotta : AppTheme.slate)
                }
                .disabled(!viewModel.canSave)
            }
        }
        // Save / Update — the mic now lives in the bottom bar (see micBottomBar)
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(viewModel.isEditing ? "Update" : "Save") {
                wantsFutureSelf = false
                viewModel.save()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(viewModel.canSave ? AppTheme.terracotta : AppTheme.slate)
            .disabled(!viewModel.canSave)
        }
    }

    // MARK: - Bottom bar with mic button (mirrors the 90-second screen)
    private var micBottomBar: some View {
        HStack {
            Text("\(viewModel.wordCount) words")
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.inkSoft)
                .monospacedDigit()

            Spacer()

            // Mic button
            Button {
                isContentFocused = false
                Task { await speech.toggle(existingText: viewModel.content) }
            } label: {
                ZStack {
                    Circle()
                        .fill(speech.isRecording ? AppTheme.terracotta : AppTheme.ink)
                        .frame(width: 48, height: 48)

                    if speech.isRecording {
                        Circle()
                            .stroke(AppTheme.terracotta.opacity(0.4), lineWidth: 2)
                            .frame(width: 62, height: 62)
                            .scaleEffect(1.1)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)
                    }

                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.cream)
                }
            }
            // Not disabled when denied — tapping surfaces the Open Settings alert.

            Spacer()

            // Balances the word count on the leading edge so the mic stays centered.
            Text("\(viewModel.wordCount) words")
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(.clear)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Free-write starter
//
// Brings the Hint Ladder's starter to the open blank page. It owns its own
// HintEngine (empty pebbles, write mode), so it shows a sharp local starter
// instantly and quietly upgrades to the AI-sharpened one when it arrives. The
// user can re-roll the angle (gentler / direct / weirder) or tap to drop it in.
private struct FreeWriteStarterView: View {
    let initialMood: Mood?
    let onUse: (String) -> Void

    @StateObject private var hints = HintEngine(
        context: HintContext(pebbles: [], personal: .safe, mode: .write)
    )
    @State private var prompt: String
    /// Once the user re-rolls, stop auto-adopting the AI starter over their choice.
    @State private var userRerolled = false

    init(initialMood: Mood? = nil, onUse: @escaping (String) -> Void) {
        self.initialMood = initialMood
        self.onUse = onUse
        // If we arrived here from a mood check-in, open with a mood-tuned prompt
        // rather than a generic one.
        if let mood = initialMood {
            _prompt = State(initialValue: LocalAI.moodPrompt(for: mood))
        } else {
            _prompt = State(initialValue: HintLadder.starterPrompt(pebbles: [], personal: .safe))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEED A WAY IN?")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(2)
                Spacer()
                if hints.bundle.source == "gemini" {
                    Text("for you")
                        .font(AppTheme.mono(size: 9)).tracking(1)
                        .foregroundStyle(AppTheme.terracotta)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppTheme.terracotta.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            Button { onUse(prompt) } label: {
                Text(prompt)
                    .font(AppTheme.editorialDisplay(size: 20))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppTheme.rose2.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: prompt)

            HStack(spacing: 8) {
                pill("gentler")     { reroll(.gentle) }
                pill("more direct") { reroll(.direct) }
                pill("weirder")     { reroll(.weird) }
                Spacer()
                Text("tap to use")
                    .font(AppTheme.mono(size: 9)).tracking(1)
                    .foregroundStyle(AppTheme.slate)
            }
        }
        .onChange(of: hints.bundle) { _, newBundle in
            // Don't let the generic AI starter clobber a mood-tuned prompt or a
            // prompt the user has already reshaped.
            guard initialMood == nil, !userRerolled, newBundle.source == "gemini" else { return }
            withAnimation { prompt = newBundle.starterWrite }
        }
    }

    private func reroll(_ style: HintLadder.PromptStyle) {
        userRerolled = true
        prompt = hints.restyledStarter(style)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(AppTheme.paperWarm)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
