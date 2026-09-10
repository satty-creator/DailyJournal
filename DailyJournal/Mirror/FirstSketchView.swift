//
//  FirstSketchView.swift
//  DailyJournal
//
//  The unlock ceremony shown at 7 entries — "Spilr's first sketch of you."
//  Presented as a sheet or full-screen cover from HomeView or MirrorView.
//

import SwiftUI

struct FirstSketchView: View {

    let selfModel: SelfModel
    /// `users/{uid}/derived/firstSeven`, when the nightly job has written it
    /// (Mirror v3 M8). Preferred over the SelfModel-derived cards below,
    /// because it is built from COUNTED facts — "1,140 words in 7 days",
    /// "'lucky' — 3 times, every time after 8pm" — rather than from truncated
    /// hypothesis prose. Nil for an account the job hasn't reached, in which
    /// case this falls back to the original behaviour.
    var serverCard: FirstSevenCard? = nil
    let onDismiss: () -> Void

    @State private var ringAnimate = false

    private var sketchItems: [(eyebrow: String, title: String, sentence: String)] {
        // Server-computed facts win. They carry real numbers the user can
        // check, which is the entire point of the replacement (§5.7).
        if let serverCard, !serverCard.cards.isEmpty {
            var items = serverCard.cards.map {
                (eyebrow: $0.eyebrow, title: $0.text, sentence: "")
            }
            if let title = serverCard.threadTitle {
                items.append((eyebrow: "one thread so far",
                              title: title,
                              sentence: serverCard.threadN.map { "Seen on \($0) different days." } ?? ""))
            } else if let observation = serverCard.observationText {
                // Labelled honestly as an observation, NOT a pattern — at 7
                // entries almost nobody has a thread, and saying so is what
                // earns belief later (§5.7).
                items.append((eyebrow: "an observation, not a pattern yet",
                              title: observation, sentence: ""))
            }
            return Array(items.prefix(4))
        }
        // No character truncation here any more — the card's Text already has
        // `.fixedSize(horizontal: false, vertical: true)` and wraps fully. A
        // hard `prefix(120)` chop instead cut mid-word with no ellipsis and
        // no visual signal that it happened (mirror-v3-prd-2026-09-10.md §1,
        // "maybe to fend o").
        var items: [(String, String, String)] = []

        if let rule = selfModel.coreRules.first(where: { $0.stability != .retired }) {
            items.append(("rule you may carry", rule.title,
                          rule.hypothesis.isEmpty ? rule.title : rule.hypothesis))
        }
        if let protective = selfModel.protectiveStrategies.first(where: { $0.stability != .retired }) {
            items.append(("protective move", protective.title,
                          protective.hypothesis.isEmpty ? protective.title : protective.hypothesis))
        }
        if let part = selfModel.innerParts.first(where: { $0.confidence > 0.3 }) {
            items.append(("part that shows up", part.name,
                          part.description.isEmpty ? part.name : part.description))
        }
        if let help = selfModel.whatHelps.first(where: { $0.stability != .retired }) {
            items.append(("what softens it", help.title,
                          help.hypothesis.isEmpty ? help.title : help.hypothesis))
        }

        return Array(items.prefix(4))
    }

    /// A real question, verbatim — never a declarative hypothesis title with
    /// "?" appended. `coreRules`/`protectiveStrategies` titles are statements
    /// ("You go quiet when things get close"), and appending "?" to one
    /// produced a bare tag question at best and a doubled "…?" at worst when
    /// the title already ended in punctuation
    /// (mirror-v3-prd-2026-09-10.md §1). Until the miner writes an actual
    /// question field onto these hypotheses, there is no source that
    /// qualifies — this returns nil and `questionCard` is simply omitted (M8).
    private var openQuestion: String? {
        if let serverQuestion = serverCard?.question,
           serverQuestion.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
            return serverQuestion
        }
        func asQuestion(_ title: String) -> String? {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasSuffix("?") else { return nil }
            return trimmed
        }
        if let unratedRule = selfModel.coreRules.first(where: {
            $0.userStatus == .unrated && $0.stability == .emerging
        }), let q = asQuestion(unratedRule.title) {
            return q
        }
        if let unratedProtective = selfModel.protectiveStrategies.first(where: {
            $0.userStatus == .unrated && $0.stability == .emerging
        }), let q = asQuestion(unratedProtective.title) {
            return q
        }
        return nil
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 20)
                    titleSection
                    ringSection
                    if !sketchItems.isEmpty {
                        sketchCards
                    }
                    if let question = openQuestion {
                        questionCard(question: question)
                    }
                    closeButton
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.3)) {
                ringAnimate = true
            }
        }
    }

    // MARK: - Title section

    private var titleSection: some View {
        VStack(spacing: 10) {
            Text("Spilr's first sketch of you")
                .font(AppTheme.editorialDisplay(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            Text("From \(serverCard?.entriesAtUnlock ?? 7) spills, here is what Spilr is learning to watch.")
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Ring

    private var ringSection: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.paperWarm, lineWidth: 12)

            Circle()
                .trim(from: 0, to: ringAnimate ? 84.0 / 360.0 : 0)
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.terracotta, AppTheme.lav, AppTheme.terracotta],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(serverCard?.entriesAtUnlock ?? 7)")
                .font(AppTheme.editorialDisplay(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(width: 88, height: 88)
    }

    // MARK: - Sketch cards

    private var sketchCards: some View {
        VStack(spacing: 14) {
            ForEach(Array(sketchItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.eyebrow.uppercased())
                        .font(AppTheme.mono(size: 9))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(1.2)

                    Text(item.title)
                        .font(AppTheme.editorialDisplay(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.sentence)
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .softCard(cornerRadius: 22, padding: 16)
            }
        }
    }

    // MARK: - Question card

    private func questionCard(question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your question for the next 7 days:")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)

            Text(question)
                .font(AppTheme.editorialDisplay(size: 18, weight: .semibold).italic())
                .foregroundStyle(AppTheme.terracotta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.terracotta.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.terracotta.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button { onDismiss() } label: {
            Text("Got it")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
