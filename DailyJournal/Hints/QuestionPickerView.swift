//
//  QuestionPickerView.swift
//  DailyJournal
//
//  Replaces PebblePickerView. Presented as a sheet from HomeView when the user
//  taps "No words yet? Pick a question."
//
//  Steps (PRD §6):
//  1. Pick pebbles (optional, up to 3)
//  2. Choose mode (write / talk)
//  3. Choose closeness (how personal)
//  4. "Just ask me one" skips manual selection and starts with the best question
//  5. Or choose a specific question from a small deck, then start the session
//

import SwiftUI

struct QuestionPickerView: View {

    let userId: String
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selected: [String] = []
    @State private var mode: QuestionMode = .write
    @State private var personal: QuestionPersonal = .safe
    @State private var sessionContext: QuestionContext?
    @State private var toast: String?
    @State private var showDeck = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        intro
                        modeToggle
                        pebbleSection
                        personalSection
                        actions
                        if showDeck { questionDeck }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                if let msg = toast { toastView(msg) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("pick a question")
                        .font(AppTheme.mono(size: 12))
                        .tracking(1)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            .fullScreenCover(item: $sessionContext) { ctx in
                NinetySecondSessionView(userId: userId, hintContext: ctx.asHintContext()) {
                    // session saved
                }
                .onDisappear {
                    onComplete()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What touched today?")
                .font(AppTheme.editorialDisplay(size: 30))
                .foregroundStyle(AppTheme.ink)
            Text("Pick up to three pebbles to get a more specific question. Or just tap \u{201C}ask me one\u{201D} and go.")
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
        }
    }

    // MARK: - Write / Talk

    private var modeToggle: some View {
        HStack(spacing: 12) {
            modeCard(.write, title: "Write", blurb: "A tiny sentence, messy notes, or one true thing.")
            modeCard(.talk,  title: "Talk",  blurb: "Say one sentence, pause, or save a trace.")
        }
    }

    private func modeCard(_ m: QuestionMode, title: String, blurb: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = m }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.editorialDisplay(size: 18))
                    .foregroundStyle(AppTheme.ink)
                Text(blurb)
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(mode == m ? AppTheme.rose2 : AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(mode == m ? AppTheme.terracotta.opacity(0.6) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pebbles

    private var pebbleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STARTER PEBBLES")
                    .font(AppTheme.mono(size: 10))
                    .tracking(2)
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Text("\(selected.count)/\(QuestionBank.maxPebbles)")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta)
            }

            FlowLayout(spacing: 9) {
                ForEach(QuestionBank.pebbleBank, id: \.self) { pebble in
                    pebbleChip(pebble)
                }
            }

            Text(selected.isEmpty
                 ? "No pebbles yet — you'll get a universal question."
                 : "Today: " + selected.joined(separator: " · "))
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func pebbleChip(_ pebble: String) -> some View {
        let isSelected = selected.contains(pebble)
        let isPersonal = QuestionBank.personalPebbles.contains(pebble)
        let isLocked   = isPersonal && personal != .me

        return Button {
            toggle(pebble)
        } label: {
            Text(pebble)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(chipBackground(isSelected: isSelected, isPersonal: isPersonal))
                .clipShape(Capsule())
                .opacity(isLocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private func chipBackground(isSelected: Bool, isPersonal: Bool) -> Color {
        if isSelected { return isPersonal ? AppTheme.sun : AppTheme.lav }
        return isPersonal ? AppTheme.sun.opacity(0.25) : AppTheme.cream
    }

    // MARK: - Personal level

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW PERSONAL?")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)

            Picker("How personal", selection: $personal) {
                ForEach(QuestionPersonal.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: personal) { _, newValue in
                if newValue != .me {
                    selected.removeAll { QuestionBank.personalPebbles.contains($0) }
                }
            }

            Text(personal.blurb + " Personal questions stay in-app — never on your lock screen.")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(1)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            // Primary: just ask me one — skips deck, goes straight to session
            Button {
                let ctx = QuestionContext(pebbles: selected, personal: personal, mode: mode)
                sessionContext = ctx
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: mode == .talk ? "mic.fill" : "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Just ask me one")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppTheme.ink)
                .clipShape(Capsule())
            }

            // Secondary: browse questions first
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDeck.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showDeck ? "Hide questions" : "Pick a question")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Image(systemName: showDeck ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.mint)
                .clipShape(Capsule())
            }

            // Trace shortcut
            Button {
                JournalService().saveTrace(userId: userId, pebbles: selected, blank: false)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast("Trace saved. That counts.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onComplete(); dismiss()
                }
            } label: {
                Text("Save as a trace")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.cream)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Question deck

    private var questionDeck: some View {
        let ctx = QuestionContext(pebbles: selected, personal: personal, mode: mode)
        let bundle = QuestionMixer.localBundle(for: ctx)
        let deck = Array((bundle.specific + bundle.gentle).prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            Text("SUGGESTED FOR YOU")
                .font(AppTheme.mono(size: 10))
                .tracking(2)
                .foregroundStyle(AppTheme.inkSoft)

            ForEach(deck) { card in
                questionDeckCard(card)
            }
        }
    }

    private func questionDeckCard(_ card: QuestionCard) -> some View {
        Button {
            let ctx = QuestionContext(
                pebbles: selected,
                personal: personal,
                mode: mode,
                explicitQuestion: card.question,
                source: card.source
            )
            sessionContext = ctx
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.lead.uppercased())
                    .font(AppTheme.mono(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(card.question)
                    .font(AppTheme.editorialBody(size: 15))
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(accentColor(card.accent).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func toggle(_ pebble: String) {
        if let idx = selected.firstIndex(of: pebble) {
            selected.remove(at: idx)
        } else {
            guard selected.count < QuestionBank.maxPebbles else {
                showToast("Pick up to \(QuestionBank.maxPebbles) pebbles.")
                return
            }
            selected.append(pebble)
        }
        withAnimation(.easeInOut(duration: 0.15)) { showDeck = false }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.2)) { if toast == msg { toast = nil } }
        }
    }

    private func toastView(_ msg: String) -> some View {
        VStack {
            Text(msg)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.ink.opacity(0.94))
                .clipShape(Capsule())
                .padding(.top, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func accentColor(_ accent: QuestionCard.Accent) -> Color {
        switch accent {
        case .soft: return AppTheme.rose2
        case .mint: return AppTheme.mint
        case .lav:  return AppTheme.lav
        case .sun:  return AppTheme.sun
        }
    }
}

// MARK: - QuestionContext → HintContext bridge

extension QuestionContext {
    /// Temporary bridge so QuestionPickerView can launch NinetySecondSessionView
    /// while it still expects a HintContext. Remove once session view is migrated.
    func asHintContext() -> HintContext {
        HintContext(
            pebbles: pebbles,
            personal: HintPersonal(rawValue: personal.rawValue) ?? .safe,
            mode: HintMode(rawValue: mode.rawValue) ?? .write
        )
    }
}
