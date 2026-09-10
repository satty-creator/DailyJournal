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
