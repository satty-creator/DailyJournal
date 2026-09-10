//
//  TeachSpilrSheet.swift
//  DailyJournal
//
//  "Teach Spilr" — the eraser, two taps from anything Spilr says
//  (mirror-v3-prd-2026-09-10.md §5.2, principle 8).
//
//  Free text goes to `profileCorrections`, which the nightly miner already
//  reads as HARD EXCLUSIONS before it writes anything. That is what makes this
//  a correction rather than a complaint box: what the user writes here changes
//  what the model is allowed to say next time (PI-010 — corrections outrank
//  inference).
//

import SwiftUI

struct TeachSpilrSheet: View {

    let subject: String
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !subject.isEmpty {
                    Text("“\(subject)”")
                        .font(AppTheme.editorialBody(size: 14).italic())
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("What did Spilr get wrong?")
                    .font(AppTheme.editorialDisplay(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                TextEditor(text: $text)
                    .focused($focused)
                    .font(AppTheme.editorialBody(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(AppTheme.paperWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(minHeight: 140)

                Text("Spilr reads this before it writes anything else about you.")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)

                Spacer()
            }
            .padding(20)
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("Teach Spilr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSubmit?(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Thread proof sheet

/// The proof behind a thread row. Same shape as the Today proof sheet, built
/// from the thread's own dot strip rather than a single observation: the strip
/// IS the evidence — thirty days of the user's own calendar, with the days it
/// appeared filled in and the exception ringed.
struct ThreadProofSheetView: View {

    let thread: MirrorThread
    var onAsk: (() -> Void)?
    var onTeach: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(thread.title)
                        .font(AppTheme.editorialDisplay(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        tile(big: "\(thread.n)", small: "different days")
                        if let since = thread.sinceDate.flatMap(MirrorThread.shortDate) {
                            tile(big: since, small: "first seen")
                        }
                        if thread.counterEvidenceCount > 0 {
                            tile(big: "\(thread.counterEvidenceCount)", small: "pushed back")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("last 30 days")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(1)
                            .textCase(.uppercase)
                        DotStripView(dots: thread.dots, dotSize: 8, spacing: 3)
                        if let softened = thread.softenedLine {
                            Text(softened)
                                .font(AppTheme.editorialBody(size: 13))
                                .foregroundStyle(AppTheme.terracotta)
                        }
                    }

                    VStack(spacing: 0) {
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                        row("Ask Spilr about this", icon: "arrow.up.right") { onAsk?() }
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                        row("Teach Spilr", icon: "pencil.line") { onTeach?() }
                        Divider().overlay(AppTheme.inkSoft.opacity(0.15))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("This thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss?() }
                }
            }
        }
    }

    private func tile(big: String, small: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(big)
                .font(AppTheme.editorialDisplay(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(small)
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
