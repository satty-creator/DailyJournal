//
//  EchoAnsweredView.swift
//  DailyJournal
//
//  Shown as a sheet when the user confirms an echo ("done ✓", "it happened", etc.).
//  Shows the past quote, an optional free-text response the user can leave,
//  and a quiet closing note from ninety. No celebration, no streak counter,
//  no green checkmark. Just a small closing line — then it's gone.
//

import SwiftUI

struct EchoAnsweredView: View {

    let echo: Echo
    // No onClose callback needed — the parent sheet's onDismiss handles
    // the Firestore write and pendingEcho clearance via vm.answerEcho().

    @State private var response: String = ""
    @FocusState private var isResponseFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    closedGlyph
                        .padding(.top, 32)
                        .padding(.bottom, 28)

                    resolvedCard
                        .padding(.bottom, 20)

                    if !response.isEmpty {
                        nowYouSaidCard
                            .padding(.bottom, 20)
                    } else {
                        responsePrompt
                            .padding(.bottom, 20)
                    }

                    gentleNote
                        .padding(.bottom, 36)

                    closeButton
                }
                .padding(.horizontal, 28)
            }
        }
        .onAppear {
            // Small delay so the sheet finishes its presentation animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isResponseFocused = false
            }
        }
    }

    // MARK: - Glyph header

    private var closedGlyph: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("✺")
                .font(AppTheme.editorialDisplay(size: 56))
                .foregroundStyle(AppTheme.terracotta)

            Text("An echo, closed")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Resolved card (the past quote)

    private var resolvedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Origin label
            HStack {
                Text(echo.sourceEntryCreatedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 10)

            // The past quote
            Text("\u{201C}\(echo.quote)\u{201D}")
                .font(AppTheme.editorialBody(size: 15))
                .italic()
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Optional response area

    private var responsePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How did it go? (optional)")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1.5)
                .textCase(.uppercase)

            ZStack(alignment: .topLeading) {
                if response.isEmpty {
                    Text("A line or two — or nothing at all.")
                        .font(AppTheme.editorialBody(size: 14))
                        .italic()
                        .foregroundStyle(AppTheme.slate.opacity(0.6))
                        .allowsHitTesting(false)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $response)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.ink)
                    .italic()
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isResponseFocused)
                    .frame(minHeight: 68)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isResponseFocused
                            ? AppTheme.terracotta.opacity(0.4)
                            : AppTheme.inkSoft.opacity(0.15),
                            lineWidth: 1)
            )
            .onTapGesture { isResponseFocused = true }
        }
    }

    // MARK: - Populated "now you said" card (shown when response is non-empty)

    private var nowYouSaidCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider between past and present
            HStack {
                Rectangle()
                    .fill(AppTheme.inkSoft.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.bottom, 12)

            Text("You said")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1.5)
                .textCase(.uppercase)
                .padding(.bottom, 6)

            // Editable in-place so user can still correct
            ZStack(alignment: .topLeading) {
                TextEditor(text: $response)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.ink)
                    .italic()
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isResponseFocused)
                    .frame(minHeight: 50)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Ninety's gentle closing note

    private var gentleNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ninety, quietly")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1.5)
                .textCase(.uppercase)

            Text(closingNote)
                .font(AppTheme.editorialBody(size: 14))
                .italic()
                .foregroundStyle(AppTheme.cream)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            dismiss()
            // vm.answerEcho() is invoked by the parent sheet's onDismiss — no call needed here.
        } label: {
            Text("Close echo")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(AppTheme.ink.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 40)
    }

    // MARK: - Closing note copy (keyed by echo type)

    private var closingNote: String {
        switch echo.type {
        case .intention:
            return "Most of the things you dread doing, you do. And they're rarely as heavy as you expected."
        case .openLoop:
            return "The things you wait on with dread usually turn out to be just events. Not verdicts."
        case .theme:
            return "The thread is still there. That's not a problem — it's just something your mind keeps returning to."
        case .moodMarker:
            return "Two weeks changes more than it feels like it will. You've moved, even if it doesn't look like it yet."
        }
    }
}
