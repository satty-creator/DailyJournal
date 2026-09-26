//
//  AskView.swift
//  DailyJournal
//
//  Grounded Q&A over the Person Model — mirror-v3.1-person-model-2026-09-10.md
//  §7, Prompt ASK. Answers a question about the user FROM the model
//  (signatures/rules/needs, with receipts), not by re-reading raw entries.
//
//  Server-side (engineering-decisions §1: the client sends structured input,
//  never a prompt) — see functions/index.js `exports.mirrorAsk` and
//  AIService+Mirror.swift's `askMirror(question:userId:)`. Replaces the
//  earlier on-device retrieval + client-built-prompt version; the Person
//  Model is already structured, so "Ask Spilr" no longer needs to re-read
//  300 entries to answer a question.
//

import SwiftUI

struct AskCitation: Identifiable {
    let id = UUID()
    let itemId: String
    let quote: String
    /// A short date label from the server ("12 Aug"), or nil — never a raw
    /// `Date`: the server already resolved it against the user's own local
    /// calendar, and re-parsing it here risks shifting it by a day.
    let dateLabel: String?
}

struct AskMessage: Identifiable {
    enum Role { case user, spilr }
    let id = UUID()
    let role: Role
    var text: String
    var citations: [AskCitation] = []
}

@MainActor
final class AskViewModel: ObservableObject {
    @Published var messages: [AskMessage] = []
    @Published var draft: String = ""
    @Published var isThinking = false
    @Published var showCrisisResource = false

    let userId: String

    let suggestions = [
        "What patterns do you notice in my entries?",
        "When was the last time I wrote something positive?",
        "What do I keep avoiding or not talking about?"
    ]

    init(userId: String) {
        self.userId = userId
    }

    var hasStarted: Bool { !messages.isEmpty }

    func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        // Same crisis gate the server applies again on its own side (rule 8
        // is non-negotiable and re-checked there) — checking here too means
        // the user never sees "thinking…" for a question that was never
        // going to get a real answer.
        if PatternSafety.containsCrisisSignal(in: question) {
            showCrisisResource = true
            return
        }

        messages.append(AskMessage(role: .user, text: question))
        draft = ""
        isThinking = true

        Task { [weak self] in
            guard let self else { return }
            let reply = await Self.answer(question: question, userId: self.userId)
            self.messages.append(reply)
            self.isThinking = false
        }
    }

    private static func answer(question: String, userId: String) async -> AskMessage {
        guard let result = await AIService.shared.askMirror(question: question, userId: userId) else {
            return AskMessage(role: .spilr,
                text: "Something got in the way of reading your Mirror just now. Try again in a moment.")
        }
        let citations = result.citations.map {
            AskCitation(itemId: $0.itemId, quote: $0.quote, dateLabel: $0.date)
        }
        return AskMessage(role: .spilr, text: result.answer, citations: citations)
    }
}

/// The "ask your journal anything" entry point, pinned at the top of the Mirror
/// tab. Lives here rather than inside the Mirror screen because the Mirror tab
/// is now the living profile (SelfModelView) and this card is the only piece of
/// the old daily-digest screen that survived it.
///
/// HomeView has its own `askJournalPill` with different styling — deliberately
/// not shared. Two entry points, two surfaces, one AskView behind them.
struct MirrorAskCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                Text("Ask about your entries\u{2026}")
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppTheme.cream.opacity(0.7))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct AskView: View {
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: AskViewModel
    @FocusState private var inputFocused: Bool

    init(userId: String) {
        self.userId = userId
        _vm = StateObject(wrappedValue: AskViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                VStack(spacing: 0) {
                    thread
                    inputBar
                }
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.terracotta)
                }
            }
            .sheet(isPresented: $vm.showCrisisResource) {
                PatternResourceCardView(onDismiss: { vm.showCrisisResource = false })
            }
        }
    }

    private var thread: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !vm.hasStarted { intro }
                ForEach(vm.messages) { m in messageView(m) }
                if vm.isThinking {
                    Text("Reading your Mirror…")
                        .font(AppTheme.editorialBody(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about yourself")
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
            Text("I'll answer from what Spilr has formulated so far — and show you which signature or receipt it came from.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(vm.suggestions, id: \.self) { q in
                    Button { vm.ask(q) } label: {
                        HStack {
                            Text(q)
                                .font(AppTheme.editorialBody(size: 14))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.cream.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageView(_ m: AskMessage) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.text)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !m.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FROM YOUR ENTRIES")
                            .font(AppTheme.mono(size: 9))
                            .tracking(1.5)
                            .foregroundStyle(AppTheme.inkSoft)
                        ForEach(m.citations) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\u{201C}\(c.quote)\u{201D}")
                                    .font(AppTheme.editorialBody(size: 13))
                                    .italic()
                                    .foregroundStyle(AppTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let dateLabel = c.dateLabel {
                                    Text(dateLabel)
                                        .font(AppTheme.mono(size: 9))
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(AppTheme.cream.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.cream.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything…", text: $vm.draft, axis: .vertical)
                .font(AppTheme.editorialBody(size: 15))
                .focused($inputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.cream.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            Button {
                inputFocused = false
                vm.ask(vm.draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.terracotta)
                    .clipShape(Circle())
                    .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isThinking ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isThinking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
