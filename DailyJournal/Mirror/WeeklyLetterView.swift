//
//  WeeklyLetterView.swift
//  DailyJournal
//
//  The full-screen reader for the weekly Mirror letter (§3.10). This is
//  where the density the daily Line gives up now lives — three sentences,
//  opened on purpose.
//

import SwiftUI

struct WeeklyLetterView: View {
    let letter: MirrorLetter
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("your week")
                        .font(AppTheme.mono(size: 11))
                        .tracking(1.5)
                        .foregroundStyle(AppTheme.inkSoft)
                        .textCase(.uppercase)

                    Text(letter.letter)
                        .font(AppTheme.editorialDisplay(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let quote = letter.quote {
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(AppTheme.editorialBody(size: 15).italic())
                            .foregroundStyle(AppTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(AppTheme.terracotta)
                }
            }
        }
    }
}

// MARK: - Banner (shown above the daily card while unread and recent)

struct WeeklyLetterBanner: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.lav)
                Text("Your week, in three sentences.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(14)
            .background(AppTheme.lav.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.lav.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
