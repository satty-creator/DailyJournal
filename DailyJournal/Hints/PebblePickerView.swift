//
//  PebblePickerView.swift
//  DailyJournal
//
//  "What touched today?" — the small context step before a session. The user
//  drops up to three pebbles so the hint can be specific without being creepy,
//  picks write vs talk, and chooses how personal the hints may get. From here
//  they either ask for a hint (→ the session) or save a trace and be done.
//
//  Choosing pebbles is entirely optional: every button works with zero pebbles,
//  because a naked blank page is the thing we're trying to avoid.
//

import SwiftUI

struct PebblePickerView: View {

    let userId: String
    /// Called after the user finishes a session or saves a trace, so Home can refresh.
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selected: [String] = []
    @State private var mode: HintMode = .write
    @State private var personal: HintPersonal = .safe
    @State private var sessionContext: HintContext?
    @State private var toast: String?

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
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                if let toast { toastView(toast) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("drop a pebble")
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
                NinetySecondSessionView(userId: userId, hintContext: ctx) {
                    // session saved
                }
                .onDisappear {
                    // Whether saved or discarded, bubble up + close the picker.
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
            Text("Pick up to three. This makes the hint specific without asking a big question. You can also skip straight to a hint.")
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
        }
    }

    // MARK: - Write / Talk
    private var modeToggle: some View {
        HStack(spacing: 12) {
            modeCard(.write, title: "Write", blurb: "A tiny sentence, messy notes, or three words.")
            modeCard(.talk,  title: "Talk",  blurb: "Say one sentence, pause, or save a trace.")
        }
    }

    private func modeCard(_ m: HintMode, title: String, blurb: String) -> some View {
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
                Text("\(selected.count)/\(HintLadder.maxPebbles)")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.terracotta)
            }

            FlowLayout(spacing: 9) {
                ForEach(HintLadder.pebbleBank, id: \.self) { pebble in
                    pebbleChip(pebble)
                }
            }

            Text(selected.isEmpty
                 ? "No pebbles yet — you can still get a soft hint."
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
        let isPersonal = HintLadder.personalPebbles.contains(pebble)
        // Personal-phrase pebbles are locked unless the user opted into "my words".
        let isLocked = isPersonal && personal != .me

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
                ForEach(HintPersonal.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: personal) { _, newValue in
                // Dropping out of "my words" releases any locked personal pebbles.
                if newValue != .me {
                    selected.removeAll { HintLadder.personalPebbles.contains($0) }
                }
            }

            Text(personal.blurb + " Personal hints stay in-app — never on your lock screen.")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(1)
        }
    }

    // MARK: - Actions
    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                sessionContext = HintContext(pebbles: selected, personal: personal, mode: mode)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: mode == .talk ? "mic.fill" : "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Make me a hint")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppTheme.ink)
                .clipShape(Capsule())
            }

            Button {
                JournalService().saveTrace(userId: userId, pebbles: selected, blank: false)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast("Trace saved. That counts.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onComplete(); dismiss()
                }
            } label: {
                Text("Save as a trace")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.mint)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers
    private func toggle(_ pebble: String) {
        if let idx = selected.firstIndex(of: pebble) {
            selected.remove(at: idx)
        } else {
            guard selected.count < HintLadder.maxPebbles else {
                showToast("Pick up to \(HintLadder.maxPebbles) pebbles.")
                return
            }
            selected.append(pebble)
        }
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
}

// HintContext drives `.fullScreenCover(item:)`, which needs Identifiable.
extension HintContext: Identifiable {
    var id: String { "\(mode.rawValue)|\(personal.rawValue)|\(pebbles.joined(separator: ","))" }
}
