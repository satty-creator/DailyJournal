//
//  TodayReadCardView.swift
//  DailyJournal
//
//  "Today's Read" — the daily hook that replaces the prompt card on Home.
//
//  The read is shown directly (no "tap to reveal" gate, which previously only
//  worked once per launch). There's no felt-true / too-sharp / not-me feedback
//  loop — the card's only job is to show the read and offer a way to reply.
//  "Receipts" is relabelled to make it obvious it's the evidence the read is
//  drawn from.
//

import SwiftUI

struct TodayReadCardView: View {

    let read: DailyRead

    /// "reply in 90s" — opens the 90-second session.
    let onReply: () -> Void

    @SwiftUI.State private var replied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            // The read line — shown straight away. Calm and readable: lighter
            // weight, generous line spacing, ink on a soft surface.
            Text(read.readText)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            // The evidence this read is drawn from.
            if !read.receiptChips.isEmpty {
                receiptsRow
                    .padding(.bottom, 22)
            }

            if replied {
                Text("you took it to the page.")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                    .transition(.opacity)
            } else {
                replyButton
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 8)
        .animation(.easeOut(duration: 0.3), value: replied)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("today's read")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(2)
                .textCase(.uppercase)
            Spacer()
            ShareReadButton(read: read)
        }
    }

    // MARK: - Receipts (the evidence behind the read)

    private var receiptsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("drawn from your entries")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft.opacity(0.7))
                .tracking(1.4)
                .textCase(.uppercase)

            Text(read.receiptChips.joined(separator: "  ·  "))
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var replyButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) { replied = true }
            onReply()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                Text("reply in 90s")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(AppTheme.rose2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
