//
//  AskView.swift
//  DailyJournal
//
//  Grounded Q&A over the user's own entries. Extracted out of MirrorView.swift
//  (Phase 1 of the Mirror redesign) — self-contained, and also used from
//  HomeView.swift.
//

import SwiftUI

struct AskCitation: Identifiable {
    let id = UUID()
    let entryId: String
    let date: Date
    let quote: String
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
    /// Loaded lazily, on first use — not passed in from `MirrorViewModel` any
    /// more. Mirror's own load no longer holds a live corpus in memory just so
    /// Ask has something to filter (see ai note on `MirrorViewModel.entries`);
    /// Ask is opened rarely enough that a fetch on demand, off Mirror's critical
    /// path, is the right trade. `Task` (not a plain `async let`) so repeated
    /// `ask()` calls in one session share the same completed fetch instead of
    /// re-querying.
    private let entriesTask: Task<[JournalEntry], Never>
    private let hypotheses: [PatternHypothesis]

    let suggestions = [
        "What patterns do you notice in my entries?",
        "When was the last time I wrote something positive?",
        "What do I keep avoiding or not talking about?"
    ]

    init(userId: String) {
        self.userId = userId
        self.hypotheses = MirrorGraphService.shared.hypotheses
        let service = JournalService()
        self.entriesTask = Task {
            (try? await service.fetchEntriesForMirror(for: userId)) ?? []
        }
    }

    var hasStarted: Bool { !messages.isEmpty }
    private static let maxTurns = 3

    func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        if PatternSafety.containsCrisisSignal(in: question) {
            showCrisisResource = true
            return
        }

        messages.append(AskMessage(role: .user, text: question))
        draft = ""
        isThinking = true

        let contextHypotheses = hypotheses
        let priorContext = messages.suffix(Self.maxTurns * 2)
            .map { $0.role == .user ? "Q: \($0.text)" : "A: \($0.text)" }
            .joined(separator: "\n")
        Task { [weak self] in
            guard let self else { return }
            // Almost always already resolved by the time a user has read the
            // intro and typed a question; this only actually waits on a very
            // fast tap of one of the suggestion chips.
            let entries = await self.entriesTask.value
            let candidates = Self.retrieve(for: question, from: entries)
            let reply = await Self.answer(
                question: question,
                candidates: candidates,
                hypotheses: contextHypotheses,
                priorContext: priorContext.isEmpty ? nil : priorContext
            )
            self.messages.append(reply)
            self.isThinking = false
        }
    }

    // MARK: Retrieval (on-device)

    private static let stopwords: Set<String> = [
        "the","a","an","and","or","but","to","of","in","on","at","for","i","me",
        "my","is","it","was","did","do","does","when","what","why","how","last",
        "feel","felt","about","that","this","with","you","your","have","has"
    ]

    private static let emotionSynonyms: [String: [String]] = [
        "happy": ["joy", "joyful", "good", "great", "content", "satisfied", "pleased", "glad", "excited", "elated"],
        "sad": ["down", "low", "unhappy", "miserable", "blue", "depressed", "gloomy", "heavy"],
        "angry": ["frustrated", "annoyed", "irritated", "furious", "mad", "rage", "pissed"],
        "anxious": ["worried", "nervous", "stressed", "tense", "uneasy", "restless", "overwhelmed"],
        "calm": ["peaceful", "relaxed", "serene", "settled", "grounded", "still", "quiet"],
        "tired": ["exhausted", "drained", "burnt", "burned", "fatigued", "depleted", "spent"],
        "lonely": ["alone", "isolated", "disconnected", "invisible"]
    ]

    private static func expandWithSynonyms(_ tokens: Set<String>) -> Set<String> {
        var expanded = tokens
        for token in tokens {
            if let synonyms = emotionSynonyms[token] {
                expanded.formUnion(synonyms)
            }
            for (key, synonyms) in emotionSynonyms where synonyms.contains(token) {
                expanded.insert(key)
                expanded.formUnion(synonyms)
            }
        }
        return expanded
    }

    private static func retrieve(for question: String, from entries: [JournalEntry]) -> [JournalEntry] {
        let byRecency = entries.sorted { $0.createdAt > $1.createdAt }

        if entries.count <= 15 { return byRecency }

        let rawTokens = Set(question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) })
        let tokens = expandWithSynonyms(rawTokens)

        func score(_ e: JournalEntry) -> Int {
            guard !tokens.isEmpty else { return 0 }
            let body = e.content.lowercased()
            return tokens.reduce(0) { $0 + (body.contains($1) ? 1 : 0) }
        }

        let ranked = byRecency
            .map { (entry: $0, s: score($0)) }
            .sorted { a, b in a.s != b.s ? a.s > b.s : a.entry.createdAt > b.entry.createdAt }

        let hits = ranked.filter { $0.s > 0 }.prefix(10).map { $0.entry }
        var seen = Set<String>()
        var out: [JournalEntry] = []
        for e in (hits + byRecency.prefix(6)) where !seen.contains(e.id) {
            seen.insert(e.id)
            out.append(e)
            if out.count >= 14 { break }
        }
        return out
    }

    // MARK: Grounded answer

    private static func answer(question: String, candidates: [JournalEntry], hypotheses: [PatternHypothesis] = [], priorContext: String? = nil) async -> AskMessage {
        guard AIService.shared.isAIAvailable, !candidates.isEmpty else {
            return AskMessage(role: .spilr,
                text: "I can only go on what you've written, and I don't have enough here yet. Try asking about a specific person, feeling, or stretch of days.")
        }

        let byId = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM yyyy"

        let rendered = candidates.map { e -> String in
            let body = e.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = body.count > 600 ? String(body.prefix(600)) + "…" : body
            return "[\(e.id)] \(df.string(from: e.createdAt)): \(clipped)"
        }.joined(separator: "\n\n")

        let patternKeywords = ["pattern", "always", "keep doing", "tend to", "struggle",
                               "notice", "recurring", "loop", "habit", "theme"]
        let questionLower = question.lowercased()
        let isPatternQuestion = patternKeywords.contains { questionLower.contains($0) }

        let patternContext: String
        if isPatternQuestion && !hypotheses.isEmpty {
            let rendered = hypotheses.prefix(4).map { h in
                let quotes = h.evidence.prefix(2).map { "\"\($0.quote)\"" }.joined(separator: "; ")
                let daysAgo = Calendar.current.dateComponents([.day], from: h.firstSeenAt, to: Date()).day ?? 0
                return "- Pattern: \"\(h.userFacingTitle)\" (seen \(h.timesSeen)×, first \(daysAgo) days ago)\n  Evidence: \(quotes.isEmpty ? "—" : quotes)"
            }.joined(separator: "\n")
            patternContext = """

            WHAT SPILR HAS NOTICED (use as additional context, cite if relevant):
            \(rendered)
            """
        } else {
            patternContext = ""
        }

        let prompt = """
        \(SpilrVoice.system)

        The person is asking a question about their own life. Answer it using their
        journal entries below as your source of truth.

        How to answer:
        - Ground everything in what they actually wrote. Don't invent events, names, or
          feelings that aren't in the entries.
        - Be specific and warm. Name the real things — people, days, moments — and quote
          their own words where it helps. Notice patterns across entries when they're there.
        - Two to five sentences. Talk to them directly ("you").
        - If the entries genuinely don't touch the question, say so briefly and honestly
          (e.g. "You didn't write about that"). Don't pad or guess.
        - No advice, no diagnosis, no clinical language.
        \(patternContext)

        Return ONLY valid JSON, no markdown fences:
        {
          "answer": "your reply as plain text",
          "citations": [ { "entryId": "an id from below", "quote": "a short exact phrase from that entry" } ]
        }
        \(MemoryProfileService.shared.cachedPromptContext())

        \(priorContext.map { "CONVERSATION SO FAR:\n\($0)\n" } ?? "")Question:
        \"\"\"
        \(question)
        \"\"\"

        Their entries (id · date · text):
        \(rendered)
        """

        do {
            let data = try await AIService.shared.generate(
                prompt: prompt, maxTokens: 700, temperature: 0.4, wantJSON: true, surface: "mirror_ask"
            )
            guard
                let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let cands   = root["candidates"] as? [[String: Any]],
                let content = cands.first?["content"] as? [String: Any],
                let parts   = content["parts"] as? [[String: Any]],
                let text    = parts.first?["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return AskMessage(role: .spilr,
                    text: "I couldn't read your entries just now. Try again in a moment.")
            }

            let (answerText, citations) = parseAnswer(text, byId: byId)
            guard !answerText.isEmpty else {
                return AskMessage(role: .spilr,
                    text: "I couldn't find a clear answer in your entries for that. Try asking it a different way.")
            }
            return AskMessage(role: .spilr, text: answerText, citations: citations)
        } catch {
            return AskMessage(role: .spilr,
                text: "Something got in the way of reading your entries just now. Try again in a moment.")
        }
    }

    private static func parseAnswer(_ raw: String, byId: [String: JournalEntry]) -> (String, [AskCitation]) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let jsonData = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let answer = obj["answer"] as? String,
           !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            var valid: [AskCitation] = []
            if let rawCites = obj["citations"] as? [[String: Any]] {
                for c in rawCites {
                    guard
                        let eid   = c["entryId"] as? String,
                        let quote = c["quote"]   as? String,
                        let entry = byId[eid]
                    else { continue }
                    let needle = quote.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !needle.isEmpty, entry.content.lowercased().contains(needle) else { continue }
                    valid.append(AskCitation(entryId: eid, date: entry.createdAt, quote: quote))
                }
            }
            return (answer.trimmingCharacters(in: .whitespacesAndNewlines), valid)
        }

        return (text, [])
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
                    Text("Reading your entries…")
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
            Text("Ask about your entries")
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
            Text("I'll answer using only what you've written — and show you which entries it came from.")
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
                                Text(c.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTheme.mono(size: 9))
                                    .foregroundStyle(AppTheme.inkSoft)
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
