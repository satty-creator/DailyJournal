//
//  InvitationCardView.swift
//  DailyJournal
//
//  The dark hero card on Home — always present, always the primary way in.
//
//  It used to end in a `Begin →` / `Something else` pair, where `Begin` named
//  no destination and `Something else` opened a sheet whose loudest row went
//  straight back to where `Begin` already went. That pair is now a tap-to-write
//  pill (with the mic as its own control) over a two-chip rail, so all four
//  ways in — chat, voice, blank page, templates — are one tap from here and
//  nothing is hidden behind a menu.
//
//  `AppTheme.cream` and `AppTheme.ink`/`AppTheme.inkRaised` are always
//  contrasting opposites within a given palette (that's what makes `cream`
//  usable as "inverse (on-dark) text" per its own doc comment in
//  AppTheme.swift), so this card's foreground-on-gradient styling stays
//  legible across every theme without a special dark-mode case — including
//  Moon, where `ink`/`inkRaised` are themselves already pale and the card
//  becomes the brightest thing on the screen instead of the darkest, exactly
//  the same "loudest card here" role it plays everywhere else. The same
//  invariant is why the pill is cream-on-ink and its mic is ink-on-cream:
//  those are the only two tokens guaranteed to invert together.
//

import SwiftUI

struct InvitationCardView: View {
    /// `nil` while day-one-ness hasn't been confirmed yet (entries still
    /// loading) — renders the returning-user copy, redacted, rather than
    /// guessing and risking a visible rewrite once we know. Only the prose is
    /// redacted; the pill and rail always render live (a redacted-looking tap
    /// target that nonetheless works is worse than either state).
    let dayOne: Bool?
    /// Pill body — Daily Chat, keyboard.
    let onWrite: () -> Void
    /// Mic — Daily Chat with dictation already running.
    let onSpeak: () -> Void
    let onBlankPage: () -> Void
    let onTemplates: () -> Void

    private var copy: (title: String, body: String) {
        (dayOne ?? false)
            ? (
                "Want to spend a few minutes with yourself?",
                "I\u{2019}ll ask one gentle question and take it from there \u{2014} you answer however much you like. No blank page, no timer."
              )
            : (
                "Ready when you are.",
                // Deliberately still one line rather than nothing: the card
                // would otherwise change height the moment `dayOne` resolves.
                "About two minutes, your call once we\u{2019}re in."
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

            writePill
            modeRail
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 20, x: 0, y: 12)
    }

    // MARK: - Write pill
    //
    // Two SIBLING buttons sharing one capsule, not a button nested in a
    // button's label: a label isn't an interactive container, so a nested mic
    // either gets its taps swallowed or fires both actions — which here would
    // silently open the chat with the mic hot. Siblings keep two real Buttons,
    // two accessibility elements and two disjoint hit rects, with the capsule
    // as pure decoration on the HStack.

    private var writePill: some View {
        HStack(spacing: 8) {
            Button(action: onWrite) {
                Text("Answer today\u{2019}s question\u{2026}")
                    .font(AppTheme.editorialBody(size: 15))
                    // No .opacity() here. inkSoft-on-cream is 4.73:1 in Bloom,
                    // the tightest palette; fading it drops that under AA.
                    // "Placeholder" is signalled by size and weight instead.
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    // Without this the empty run to the right of the text
                    // isn't hittable — only the glyphs would be.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Answer today\u{2019}s question")
            .accessibilityHint("Opens a conversation with Spilr.")
            .accessibilityIdentifier("home.startChat")

            Button(action: onSpeak) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(width: 44, height: 44)   // HIG minimum target
                    .background(AppTheme.ink, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Answer out loud")
            .accessibilityHint("Opens the conversation with the microphone already on.")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(height: 56)
        // `.background(_:in:)`, not `.background()` + `.clipShape()` — a
        // clipShape on the container clips hit-testing too, which eats the
        // mic's hit region where its circle meets the capsule's rounded end.
        .background(AppTheme.cream, in: Capsule())
    }

    // MARK: - Mode rail
    //
    // The two doors the pill isn't. Icons are the retired start sheet's own
    // vocabulary, so the rail reads as those rows compressed.

    private var modeRail: some View {
        HStack(spacing: 8) {
            railChip(icon: "square.and.pencil", title: "Blank page", action: onBlankPage)
            railChip(icon: "square.grid.2x2.fill", title: "Templates", action: onTemplates)
            Spacer(minLength: 0)
        }
    }

    private func railChip(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .bold))
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.cream.opacity(0.92))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(AppTheme.cream.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(AppTheme.cream.opacity(0.22), lineWidth: 1))
            // Pads the ~33pt capsule out to a 44pt target without changing
            // the visual rhythm (the rail pulls the 6 back off below).
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
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
