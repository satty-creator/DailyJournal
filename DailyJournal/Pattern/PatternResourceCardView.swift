//
//  PatternResourceCardView.swift
//  DailyJournal
//
//  The SAFETY FLOW. When the detection window contains self-harm, suicide,
//  eating-disorder, or substance signals, we never generate a pattern callback.
//  Instead we surface this — a soft, opt-in card. It does not diagnose, does not
//  alarm, and does not push resources at the person: support is revealed only if
//  they choose to tap. One card. Always dismissable.
//

import SwiftUI

struct PatternResourceCardView: View {

    /// Dismiss the card (records the 3-day cool-down in the caller).
    let onDismiss: () -> Void

    @State private var showSupport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text("Some of what you've written lately sounds heavy. No analysis here — just a quiet check-in.")
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if showSupport {
                supportDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showSupport = true }
                } label: {
                    Text("Find someone to talk to")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(AppTheme.paperWarm)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.dusk.opacity(0.4), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "heart")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.dusk)
                Text("a gentle note")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.dusk)
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            Spacer()
            Button(action: onDismiss) {
                Text("dismiss")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .buttonStyle(.plain)
        }
    }

    private var supportDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If you're going through something, talking to someone you trust — a friend, a doctor, or a counsellor — can help more than carrying it alone.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("In the US you can call or text 988 (Suicide & Crisis Lifeline), any time. Elsewhere, a local crisis line or your doctor is a good first step.")
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Text("okay")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.dusk)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
    }
}
