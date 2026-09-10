//
//  JournalTemplate.swift
//  DailyJournal
//
//  "Templates" — Spilr Redesign 3b's guided-journal catalog.
//
//  Each template is a short sequence of `TemplateStep`s run by
//  `TemplateRunnerView`, then woven into one journal entry (see
//  `AIService+Template.swift`). The five sessions below keep the app's
//  existing titles, accents and ids, but their steps are adapted from
//  published frameworks — see `TemplateContent.swift` for the content and
//  `TemplateEvidence` for what's actually cited.
//
//  Integrity note: only `after-a-hard-conversation`, `untangle-a-decision`
//  and `gratitude-gently` carry a `.clinical` evidence claim, each backed by
//  a real source in `TemplateEvidenceLibrary`. `morning-pages` and
//  `wind-down` are `.practice` — no clinical trial supports either format,
//  and their copy says so. Never move a template to `.clinical` without a
//  source to put in its `TemplateEvidence`.
//

import SwiftUI

// MARK: - Steps

/// One question in a guided template run.
struct TemplateStep: Identifiable, Hashable {
    enum ScaleRole: Hashable {
        case before, after
    }

    enum Kind: Hashable {
        case text(placeholder: String)
        case choice(options: [String])
        /// A 0–10 self-rating, rendered as six buttons (0,2,4,6,8,10) like the
        /// prototype. `role` is how the review screen finds the before/after
        /// pair to build a delta — see `JournalTemplate.scaleDelta`.
        case scale(role: ScaleRole)
    }

    /// Stable key into `TemplateRunnerViewModel.answers` — NOT the array index,
    /// so a future reorder of `steps` can't silently reattach an in-progress
    /// answer (or a resumed draft) to the wrong question.
    let id: String
    /// Short noun shown as the review card's eyebrow, e.g. "Situation".
    let label: String
    let question: String
    let helper: String
    let kind: Kind
}

// MARK: - Answers

/// One answered (or skipped) step. A separate type from `String` so a chip
/// selection and a 0–10 rating don't have to round-trip through text.
enum TemplateAnswer: Equatable {
    case text(String)
    case choice(String)
    case scale(Int)

    var displayValue: String {
        switch self {
        case .text(let s), .choice(let s): return s
        case .scale(let n):                return "\(n)"
        }
    }

    var isAnswered: Bool {
        switch self {
        case .text(let s):
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choice, .scale:
            return true
        }
    }

    var scaleValue: Int? {
        if case .scale(let n) = self { return n }
        return nil
    }
}

// MARK: - Evidence

/// What a template's structure is actually based on. Deliberately split into
/// two kinds so the gallery and the "Why these?" sheet never blur a clinical
/// claim into a product one — see the integrity note at the top of this file.
enum TemplateEvidenceKind {
    /// A published clinical framework or research study.
    case clinical
    /// A widely-used writing/product pattern. Explicitly NOT a therapy claim.
    case practice
}

struct TemplateEvidence: Identifiable {
    struct Source: Identifiable {
        let label: String
        let url: URL
        var id: String { url.absoluteString }
    }

    let id: String
    let kind: TemplateEvidenceKind
    /// Short badge text on a template card, e.g. "NHS · CBT thought record".
    let pill: String
    /// The longer "Framework" text shown on the review screen and in the
    /// "Why these?" sheet.
    let blurb: String
    /// Empty for most `.practice` evidence — there's nothing to cite.
    let sources: [Source]
}

// MARK: - Template

struct JournalTemplate: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let minutes: Int
    /// Freeform tags the gallery's filter chips match against (lowercase).
    let tags: [String]
    /// A key path into the *live* palette, resolved at render via `accentColor`
    /// — see the note below. NEVER store a resolved `Color` on this type.
    let accent: KeyPath<ThemePalette, Color>
    let isFeatured: Bool
    let steps: [TemplateStep]
    let evidence: TemplateEvidence

    /// `AppTheme.rose` etc. are computed `static var`s that read the mutable
    /// `AppTheme.active`, which `ThemeManager` reassigns on every theme change.
    /// But `JournalTemplate.all` below is a `static let` — if `accent` stored
    /// a resolved `Color`, it would be captured once at first access and never
    /// follow a theme switch. Keeping it a key path and resolving here means
    /// every read reflects whatever palette is active *right now*.
    var accentColor: Color { AppTheme.active[keyPath: accent] }

    /// Steps are shown to the user in this count, replacing the old stored
    /// `promptCount: Int` — a number that had already drifted out of sync
    /// with two of the five templates before this file was rewritten.
    var stepCount: Int { steps.count }

    private func scaleStep(_ role: TemplateStep.ScaleRole) -> TemplateStep? {
        steps.first {
            if case .scale(let r) = $0.kind { return r == role }
            return false
        }
    }

    var beforeScaleStep: TemplateStep? { scaleStep(.before) }
    var afterScaleStep: TemplateStep? { scaleStep(.after) }
}

extension JournalTemplate {
    /// The five sessions shown in the mockup. Order matches: the featured
    /// card first, then the four-card grid in its original order. Titles,
    /// ids and accents are unchanged from the original catalog — only the
    /// steps and evidence are new (see `TemplateContent.swift`).
    static let all: [JournalTemplate] = [
        JournalTemplate(
            id: "after-a-hard-conversation",
            title: "After a hard conversation",
            blurb: "Process what was said \u{2014} and what wasn\u{2019}t.",
            minutes: 5,
            tags: ["clarity"],
            accent: \.rose,
            isFeatured: true,
            steps: TemplateContent.afterAHardConversation,
            evidence: TemplateEvidenceLibrary.neffSelfCompassion
        ),
        JournalTemplate(
            id: "morning-pages",
            title: "Morning pages",
            blurb: "Clear the clutter before the day starts.",
            minutes: 4,
            tags: ["clarity"],
            accent: \.peach,
            isFeatured: false,
            steps: TemplateContent.morningPages,
            evidence: TemplateEvidenceLibrary.productPattern
        ),
        JournalTemplate(
            id: "gratitude-gently",
            title: "Gratitude, gently",
            blurb: "One person, and what they actually did.",
            minutes: 4,
            tags: ["calm"],
            accent: \.mint,
            isFeatured: false,
            steps: TemplateContent.gratitudeGently,
            evidence: TemplateEvidenceLibrary.gratitudeRCT
        ),
        JournalTemplate(
            id: "untangle-a-decision",
            title: "Untangle a decision",
            blurb: "Weigh a choice you keep circling.",
            minutes: 7,
            tags: ["clarity"],
            accent: \.lav,
            isFeatured: false,
            steps: TemplateContent.untangleADecision,
            evidence: TemplateEvidenceLibrary.nhsThoughtRecord
        ),
        JournalTemplate(
            id: "wind-down",
            title: "Wind down",
            blurb: "Set the day down before sleep.",
            minutes: 4,
            tags: ["sleep", "calm"],
            accent: \.blue,
            isFeatured: false,
            steps: TemplateContent.windDown,
            evidence: TemplateEvidenceLibrary.productPattern
        )
    ]
}
