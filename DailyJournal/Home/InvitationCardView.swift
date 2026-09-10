//
//  InvitationCardView.swift
//  DailyJournal
//
//  The dark hero card on Home — Spilr Redesign 3a's actual call to action.
//  Always present, always the primary way in.
//
//  `AppTheme.cream` and `AppTheme.ink`/`AppTheme.inkRaised` are always
//  contrasting opposites within a given palette (that's what makes `cream`
//  usable as "inverse (on-dark) text" per its own doc comment in
//  AppTheme.swift), so this card's foreground-on-gradient styling stays
//  legible across every theme without a special dark-mode case — including
//  Moon, where `ink`/`inkRaised` are themselves already pale and the card
//  becomes the brightest thing on the screen instead of the darkest, exactly
//  the same "loudest card here" role it plays everywhere else.
//

import SwiftUI

struct InvitationCardView: View {
    /// `nil` while day-one-ness hasn't been confirmed yet (entries still
    /// loading) — renders the returning-user copy, redacted, rather than
    /// guessing and risking a visible rewrite once we know.
    let dayOne: Bool?
    let onPrimary: () -> Void
    let onMoreWays: () -> Void

    private var copy: (title: String, body: String, cta: String) {
        (dayOne ?? false)
            ? (
                "Want to spend a few minutes with yourself?",
                "I\u{2019}ll ask one gentle question and take it from there \u{2014} you answer however much you like. No blank page, no timer. About 2 minutes.",
                "Begin"
              )
            : (
                "Ready when you are.",
                "We can start fresh \u{2014} or pick up something that\u{2019}s been on your mind lately. About 2 minutes, your call once we\u{2019}re in.",
                "Begin"
              )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BloomMarkView(size: 30)
                Text("TODAY WITH SPILR")
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.cream.opacity(0.75))
            }

            Group {
                Text(copy.title)
                    .font(AppTheme.editorialDisplay(size: 23, weight: .heavy))
                    .foregroundStyle(AppTheme.cream)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(copy.body)
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.cream.opacity(0.74))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .redacted(reason: dayOne == nil ? .placeholder : [])

            HStack(spacing: 14) {
                Button(action: onPrimary) {
                    Text("\(copy.cta) \u{2192}")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.cream)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onMoreWays) {
                    Text("Something else")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.cream.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 20, x: 0, y: 12)
    }

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.ink, AppTheme.inkRaised],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.terracotta.opacity(0.32))
                .frame(width: 150, height: 150)
                .blur(radius: 30)
                .offset(x: 110, y: -70)
        }
    }
}
