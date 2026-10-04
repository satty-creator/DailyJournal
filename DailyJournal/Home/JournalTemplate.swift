//
//  JournalTemplate.swift
//  DailyJournal
//
//  "Templates" — Spilr Redesign 3b's guided-journal catalog.
//
//  Each template is a short sequence of `TemplateStep`s run by
//  `TemplateRunnerView`, then woven into one journal entry (see
//  `AIService+Template.swift`). The original five sessions keep the app's
//  existing titles, accents and ids, but their steps are adapted from
//  published frameworks — see `TemplateContent.swift` for the content and
//  `TemplateEvidence` for what's actually cited.
//
//  Integrity note: only `work-through-a-thought`, `after-a-hard-conversation`,
//  `untangle-a-decision`, `gratitude-gently` and `best-possible-self` carry a
//  `.clinical` evidence claim, each backed by a real source in
//  `TemplateEvidenceLibrary` (the Best Possible Self citation was checked
//  directly against the PubMed abstract, not just carried over from the
//  source prototype — see `TemplateEvidenceLibrary.bestPossibleSelfMetaAnalysis`).
//  `morning-pages` and `wind-down` are `.practice` — no clinical trial
//  supports either format, and their copy says so. Never move a template to
//  `.clinical` without a source to put in its `TemplateEvidence`.
//
//  `work-through-a-thought` is the full NHS CBT thought record (situation,
//  thoughts, feelings, evidence for/against, alternative thought, feelings
//  after), plus a thinking-traps step, a body/behaviour pair from the
//  five-areas model, and an optional box-breathing pause
//  (`Components/BoxBreathingView`) — none of which borrow copy or design from
//  any other app; only the underlying CBT structure, which is public (NHS,
//  "five areas" model). `untangle-a-decision` and `onboarding-first-entry`
//  gained `emotions`/`traps` steps for the same reason: both already cited
//  `nhsThoughtRecord`'s "feelings" step without ever asking for feelings.
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
        /// Multi-select chips — any number of `options` can be on at once.
        /// Used for emotion and thinking-trap steps, where real answers are
        /// rarely just one word. `allowsOther` adds a free-text chip at the
        /// end that opens a one-line text field instead of toggling on its own.
        case multiChoice(options: [String], allowsOther: Bool = false)
        /// A 0–10 self-rating. `role` is how the review screen finds the
        /// before/after pair to build a delta — see `JournalTemplate.scaleDelta`.
        /// `values` is which numbers get their own button — every existing
        /// template uses the original six-button prototype spacing
        /// (0,2,4,6,8,10); onboarding's guided first entry uses the full
        /// 0...10 range instead (see `ZeroToTenScale`).
        case scale(role: ScaleRole, values: [Int] = [0, 2, 4, 6, 8, 10])
        /// A skippable box-breathing pause, `cycles` times around a 4-4-4-4
        /// inhale/hold/exhale/hold square (see `Components/BoxBreathingView`).
        /// Stores no real answer — `TemplateRunnerView` records `.choice("done")`
        /// or `.choice("skipped")` purely so `currentIsAnswered` can tell them
        /// apart; neither value is ever shown or woven.
        case breathing(cycles: Int = 4)
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
    /// Per-step rationale shown in `TemplateRunnerView`'s "Why ask this?" card —
    /// distinct from `TemplateEvidence.blurb`, which is the template-level
    /// citation shown once on the review screen. `nil` means the step shows no
    /// card, even on a `.clinical` template; most steps leave this unset.
    let whyThis: String?
    /// One-line definition per `multiChoice` option, shown under a chip once
    /// it's selected — e.g. what "Mind reading" means. Keyed by the option's
    /// exact string. Empty for steps that don't need it (emotions are
    /// self-explanatory; thinking traps aren't).
    let chipHelp: [String: String]
    /// Sample answers shown under a `.text` step's helper — a quiet "FOR
    /// EXAMPLE" block that shows what a real answer looks like without putting
    /// words in the user's mouth. Empty = no examples (most steps). Only the
    /// text steps use it; chips/scale/breathing are self-evident.
    let examples: [String]

    init(
        id: String, label: String, question: String, helper: String, kind: Kind,
        whyThis: String? = nil, chipHelp: [String: String] = [:], examples: [String] = []
    ) {
        self.id = id
        self.label = label
        self.question = question
        self.helper = helper
        self.kind = kind
        self.whyThis = whyThis
        self.chipHelp = chipHelp
        self.examples = examples
    }
}

// MARK: - Answers

/// One answered (or skipped) step. A separate type from `String` so a chip
/// selection and a 0–10 rating don't have to round-trip through text.
///
/// `Codable` backs `TemplateRunnerViewModel`'s draft persistence — an explicit
/// `kind`-discriminated encoding rather than the synthesized form, so the
/// on-disk shape stays legible (and stable) if a case is ever added.
enum TemplateAnswer: Equatable, Codable {
    case text(String)
    case choice(String)
    case scale(Int)
    /// Multi-select chip picks — order is preserve­d as tapped, which is also
    /// the order the weave prompt and `localWeaveTemplateEntry` see them in.
    case choices([String])

    private enum CodingKeys: String, CodingKey {
        case kind, value
    }
    private enum Kind: String, Codable {
        case text, choice, scale, choices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:    self = .text(try container.decode(String.self, forKey: .value))
        case .choice:  self = .choice(try container.decode(String.self, forKey: .value))
        case .scale:   self = .scale(try container.decode(Int.self, forKey: .value))
        case .choices: self = .choices(try container.decode([String].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(s, forKey: .value)
        case .choice(let s):
            try container.encode(Kind.choice, forKey: .kind)
            try container.encode(s, forKey: .value)
        case .scale(let n):
            try container.encode(Kind.scale, forKey: .kind)
            try container.encode(n, forKey: .value)
        case .choices(let items):
            try container.encode(Kind.choices, forKey: .kind)
            try container.encode(items, forKey: .value)
        }
    }

    var displayValue: String {
        switch self {
        case .text(let s), .choice(let s): return s
        case .scale(let n):                return "\(n)"
        case .choices(let items):          return items.joined(separator: ", ")
        }
    }

    var isAnswered: Bool {
        switch self {
        case .text(let s):
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choice, .scale:
            return true
        case .choices(let items):
            return !items.isEmpty
        }
    }

    var scaleValue: Int? {
        if case .scale(let n) = self { return n }
        return nil
    }

    var choiceValues: [String]? {
        if case .choices(let items) = self { return items }
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
            if case .scale(let r, _) = $0.kind { return r == role }
            return false
        }
    }

    var beforeScaleStep: TemplateStep? { scaleStep(.before) }
    var afterScaleStep: TemplateStep? { scaleStep(.after) }
}

extension JournalTemplate {
    /// The sessions shown in the gallery. Order matches: the featured card
    /// first, then the grid in its original order, with "Best possible self"
    /// appended last. Titles, ids and accents for the original five are
    /// unchanged from the original catalog — only the steps and evidence are
    /// new (see `TemplateContent.swift`).
    static let all: [JournalTemplate] = [
        JournalTemplate(
            id: "work-through-a-thought",
            title: "Work through a thought",
            blurb: "Situation, feelings, thinking traps, evidence \u{2014} the whole thought record.",
            minutes: 8,
            tags: ["clarity", "calm"],
            accent: \.lav,
            isFeatured: true,
            steps: TemplateContent.workThroughAThought,
            evidence: TemplateEvidenceLibrary.nhsThoughtRecord
        ),
        JournalTemplate(
            id: "after-a-hard-conversation",
            title: "After a hard conversation",
            blurb: "Process what was said \u{2014} and what wasn\u{2019}t.",
            minutes: 5,
            tags: ["clarity"],
            accent: \.rose,
            isFeatured: false,
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
            minutes: 8,
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
        ),
        JournalTemplate(
            id: "best-possible-self",
            title: "Best possible self",
            blurb: "Picture a future where things went as well as they reasonably could.",
            minutes: 8,
            tags: ["clarity"],
            accent: \.sun,
            isFeatured: false,
            steps: TemplateContent.bestPossibleSelf,
            evidence: TemplateEvidenceLibrary.bestPossibleSelfMetaAnalysis
        )
    ]

    /// Onboarding's guided first entry — the same NHS thought-record framework
    /// as "Untangle a decision", reworded to whatever's weighing on the person
    /// rather than a decision specifically. `openingQuestion` is a fixed line
    /// (`OnboardingView.openingQuestion`) passed in rather than hardcoded
    /// here, so this function still takes a parameter even though every
    /// caller today passes the same string — it used to be AI-written and
    /// per-user; see that constant's doc comment for why that was dropped.
    ///
    /// Deliberately NOT in `all` above: it never appears in the templates
    /// gallery, only run once from `OnboardingView`.
    static func onboardingFirstEntry(openingQuestion: String) -> JournalTemplate {
        JournalTemplate(
            id: "onboarding-first-entry",
            title: "Your first entry",
            blurb: "A short guided look at what's on your mind.",
            minutes: 6,
            tags: ["clarity"],
            accent: \.lav,
            isFeatured: false,
            steps: TemplateContent.onboardingFirstEntry(openingQuestion: openingQuestion),
            evidence: TemplateEvidenceLibrary.nhsThoughtRecord
        )
    }
}
