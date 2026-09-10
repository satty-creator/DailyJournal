//
//  JournalEditorView.swift
//  DailyJournal
//

import SwiftUI
import PhotosUI
import UIKit

struct JournalEditorView: View {

    @StateObject private var viewModel: JournalEditorViewModel
    @StateObject private var speech = SpeechManager()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isContentFocused: Bool
    @State private var showDeleteConfirm = false
    @State private var micError: String?
    // Photo picker state (edit mode)
    @State private var photoItem: PhotosPickerItem?
    @State private var photoUIImage: UIImage?

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
                        contentArea
                        // Was gated on `isEditing`, so a brand-new free-write entry
                        // had no way to attach a photo at all — the picker only
                        // appeared after saving and reopening. `save(photo:)`
                        // already handles the new-entry upload path correctly; this
                        // was purely the view withholding the affordance.
                        photoSection
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
                if let sessionType = viewModel.sessionTypeLabel {
                    AnalyticsManager.shared.trackEntryViewed(
                        sessionType: sessionType,
                        age: Date().timeIntervalSince(viewModel.entryDate)
                    )
                }
            }
            .safeAreaInset(edge: .bottom) { micBottomBar }
            .onDisappear { speech.stop() }
            // Live transcription: mirror the running transcript into the editor
            // as the user speaks. The final result also flows through here, so
            // nothing extra needs to be committed when recording stops.
            .onChange(of: speech.liveText) { _, live in
                // Only mirror liveText → content while recording is active.
                // Guarding on isRecording prevents a stale liveText value from
                // a previous session from clobbering text the user typed after
                // recording ended.
                guard speech.isRecording else { return }
                viewModel.content = live
            }
            .onChange(of: viewModel.didSaveSuccessfully) { _, saved in
                if saved {
                    if let savedEntry = viewModel.savedEntry { onSaveEntry?(savedEntry) }
                    onSave?()
                    dismiss()
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
            // Load selected photo into UIImage for preview and upload
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        photoUIImage = ui
                    }
                }
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
        .trackScreen(.entryEditor)
    }

    // MARK: - Date stamp
    private var dateStamp: some View {
        Text(viewModel.entryDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
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
                        if viewModel.selectedMood == mood {
                            AnalyticsManager.shared.logEvent(.moodClicked, parameters: ["mood": mood.rawValue])
                        }
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
                    Text(SpilrVoice.sentenceCased(sentiment))
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

    // MARK: - Photo section (edit mode: shows existing + allows add/change)
    @ViewBuilder
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show new locally-picked photo (preview before upload)
            if let uiImage = photoUIImage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PHOTO")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(2)
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text("Change")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.terracotta)
                        }
                    }
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.bottom, 20)
            } else if let urlString = viewModel.photoURL, let url = URL(string: urlString) {
                // Show existing saved photo
                HStack {
                    Text("PHOTO")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(2)
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Change")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
                entryPhoto(url)
            } else {
                // No photo yet — show an add button
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.terracotta)
                        Text("Add a photo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.terracotta.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AppTheme.terracotta.opacity(0.35),
                                          style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Attached photo (shown when viewing an existing entry)
    private func entryPhoto(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHOTO")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Couldn't load photo")
                    }
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 80)
                default:
                    ProgressView()
                        .tint(AppTheme.terracotta)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(AppTheme.paperWarm)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.bottom, 20)
    }

    // MARK: - AI summary (shown when editing an existing entry)
    private var aiSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPILR HEARD")
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
        .onAppear {
            AnalyticsManager.shared.logEvent(.aiInsightsViewed)
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
        // Save / Update — the mic now lives in the bottom bar (see micBottomBar).
        // "Send to future self" now lives on SpillWriteView, the screen that
        // actually creates new entries — this editor only ever opens on an
        // existing one, so there's nothing left here to schedule a delivery for.
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(viewModel.isEditing ? "Update" : "Save") {
                viewModel.save(photo: photoUIImage)
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
