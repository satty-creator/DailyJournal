//
//  TemplateContent.swift
//  DailyJournal
//
//  The step content and evidence citations behind `JournalTemplate.all`. Kept
//  separate from `JournalTemplate.swift` so the catalog stays scannable.
//
//  Voice: direct and concrete, second person, the way `Mirror/MirrorSeeds.swift`
//  talks — never the clinical register of a thought-record worksheet. A
//  question like "What evidence supports that thought?" is what the framework
//  is called; "What actually supports that thought?" is how Spilr asks it.
//
//  Integrity: `TemplateEvidenceLibrary` cites only sources that were actually
//  checked — the NHS thought record, the 293-person gratitude RCT, Kristin
//  Neff's self-compassion exercise, the Best Possible Self meta-analysis
//  (29 studies, 2,909 participants — confirmed against the PubMed abstract),
//  and the Day One / Stoic / Rosebud product links. There is no clinical
//  citation for `morningPages` or `windDown` — both use `productPattern`, and
//  its blurb says plainly that no trial backs the format. Do not add a source
//  here that wasn't actually verified.
//

import Foundation

enum TemplateContent {

    // MARK: - After a hard conversation (Kristin Neff's self-compassion journal,
    // adapted to a conversation)

    static let afterAHardConversation: [TemplateStep] = [
        TemplateStep(
            id: "event",
            label: "The conversation",
            question: "What happened in the conversation?",
            helper: "Just the facts first \u{2014} who said what.",
            kind: .text(placeholder: "The hardest part was\u{2026}")
        ),
        TemplateStep(
            id: "self-talk",
            label: "What you're telling yourself",
            question: "What are you saying to yourself about it now?",
            helper: "Write the voice in your head exactly as it sounds \u{2014} don't soften it yet.",
            kind: .text(placeholder: "I keep thinking\u{2026}")
        ),
        TemplateStep(
            id: "friend-response",
            label: "What you'd tell a friend",
            question: "If a close friend told you this happened to them, what would you say?",
            helper: "Use the tone you'd genuinely use with someone you care about \u{2014} most people would find a conversation like this hard.",
            kind: .text(placeholder: "I'd tell them\u{2026}")
        ),
        TemplateStep(
            id: "fairer-response",
            label: "A fairer response to yourself",
            question: "What's a fairer way to say that to yourself?",
            helper: "It doesn't need to be positive \u{2014} just as fair as what you'd say to someone else.",
            kind: .text(placeholder: "A fairer way to see it is\u{2026}")
        )
    ]

    // MARK: - Untangle a decision (NHS CBT thought record, adapted to a decision)

    static let untangleADecision: [TemplateStep] = [
        TemplateStep(
            id: "choice",
            label: "The decision",
            question: "What's the decision you keep circling?",
            helper: "State it plainly \u{2014} the actual choice, not the whole backstory.",
            kind: .text(placeholder: "The decision is\u{2026}"),
            whyThis: "This mirrors \u{201c}situation\u{201d} in a CBT thought record \u{2014} naming what's actually in front of you, before the interpretation."
        ),
        TemplateStep(
            id: "stuck-before",
            label: "How stuck, before",
            question: "How stuck do you feel about this right now?",
            helper: "0 = not at all \u{00b7} 10 = completely stuck.",
            kind: .scale(role: .before)
        ),
        TemplateStep(
            id: "thought",
            label: "The thought driving it",
            question: "What thought keeps stopping you?",
            helper: "Write it exactly as it sounds in your head.",
            kind: .text(placeholder: "The thought is\u{2026}"),
            whyThis: "This is the thought record's \u{201c}automatic thought\u{201d} step \u{2014} write it as it actually sounds, not the tidied-up version."
        ),
        TemplateStep(
            id: "evidence-for",
            label: "What supports it",
            question: "What actually supports that thought?",
            helper: "Facts, not guesses.",
            kind: .text(placeholder: "What supports it is\u{2026}"),
            whyThis: "Facts first, before the interpretation \u{2014} this is \u{201c}evidence that supports the thought.\u{201d}"
        ),
        TemplateStep(
            id: "evidence-against",
            label: "What it leaves out",
            question: "What does that thought leave out?",
            helper: "Look for the facts the first read skips over.",
            kind: .text(placeholder: "It leaves out\u{2026}"),
            whyThis: "The record's most-skipped step: evidence the first read leaves out."
        ),
        TemplateStep(
            id: "balanced",
            label: "A more balanced read",
            question: "What's a more balanced way to see this?",
            helper: "It doesn't have to be positive \u{2014} just fairer and more complete.",
            kind: .text(placeholder: "A more balanced read is\u{2026}"),
            whyThis: "The \u{201c}alternative thought\u{201d} step \u{2014} not necessarily positive, just more complete."
        ),
        TemplateStep(
            id: "stuck-after",
            label: "How stuck, after",
            question: "How stuck do you feel now?",
            helper: "Same 0\u{2013}10 scale. The point is comparison, not precision.",
            kind: .scale(role: .after)
        )
    ]

    // MARK: - Gratitude, gently (gratitude-letter RCT)

    static let gratitudeGently: [TemplateStep] = [
        TemplateStep(
            id: "person",
            label: "Who",
            question: "Who are you grateful to today?",
            helper: "Pick one person, not a list.",
            kind: .text(placeholder: "I'm grateful to\u{2026}")
        ),
        TemplateStep(
            id: "what-they-did",
            label: "What they did",
            question: "What exactly did they do?",
            helper: "A specific moment or action, not a general trait.",
            kind: .text(placeholder: "They\u{2026}")
        ),
        TemplateStep(
            id: "why-it-mattered",
            label: "Why it mattered",
            question: "Why did that matter to you?",
            helper: "What need, value, or feeling did it touch?",
            kind: .text(placeholder: "It mattered because\u{2026}")
        ),
        TemplateStep(
            id: "what-to-say",
            label: "What you'd want them to know",
            question: "What would you want them to know?",
            helper: "Write it as if they could read this sentence.",
            kind: .text(placeholder: "I want you to know\u{2026}")
        )
    ]

    // MARK: - Morning pages (practice pattern, stream-of-consciousness)

    static let morningPages: [TemplateStep] = [
        TemplateStep(
            id: "loudest",
            label: "What's loudest",
            question: "What's the loudest thing in your head this morning?",
            helper: "Don't edit it \u{2014} just get it down.",
            kind: .text(placeholder: "The loudest thing is\u{2026}")
        ),
        TemplateStep(
            id: "underneath",
            label: "How it makes you feel",
            question: "How is it making you feel \u{2014} and why?",
            helper: "Name the feeling first, then what's driving it.",
            kind: .text(placeholder: "It makes me feel\u{2026}")
        ),
        TemplateStep(
            id: "needs-you",
            label: "What needs you today",
            question: "What actually needs your attention today?",
            helper: "One thing is enough.",
            kind: .text(placeholder: "Today I need to\u{2026}")
        )
    ]

    // MARK: - Best possible self (Best Possible Self intervention meta-analysis)

    static let bestPossibleSelf: [TemplateStep] = [
        TemplateStep(
            id: "future-picture",
            label: "Future picture",
            question: "Pick a point one to three years out. What's gone as well as it reasonably could?",
            helper: "Reasonably possible, not a fantasy \u{2014} something you can actually picture.",
            kind: .text(placeholder: "In a couple of years, if things have gone well\u{2026}")
        ),
        TemplateStep(
            id: "workday",
            label: "An ordinary workday",
            question: "What does an ordinary day look like in that picture?",
            helper: "Concrete details beat aspirations \u{2014} what you're actually doing on a normal Tuesday.",
            kind: .text(placeholder: "On a normal day, I\u{2026}")
        ),
        TemplateStep(
            id: "health-relationships",
            label: "Health & relationships",
            question: "What do your health and relationships look like there?",
            helper: "Routines and behaviors you can picture, not just how you'd feel.",
            kind: .text(placeholder: "My health and the people around me\u{2026}")
        ),
        TemplateStep(
            id: "repeated-actions",
            label: "What got you there",
            question: "What did you keep doing, over and over, to get there?",
            helper: "Look for behaviors, not personality traits.",
            kind: .text(placeholder: "The thing I kept doing was\u{2026}")
        ),
        TemplateStep(
            id: "next-week",
            label: "One step this week",
            question: "What's one action toward this you can take in the next 7 days?",
            helper: "Small enough to actually schedule.",
            kind: .text(placeholder: "This week I will\u{2026}")
        )
    ]

    // MARK: - Wind down (practice pattern, check-in shaped)

    static let windDown: [TemplateStep] = [
        TemplateStep(
            id: "landing",
            label: "How you're landing",
            question: "How are you landing tonight?",
            helper: "Pick the closest match.",
            kind: .choice(options: ["Calm", "Tired", "Wired", "Heavy", "Fine"])
        ),
        TemplateStep(
            id: "set-down",
            label: "What to set down",
            question: "What do you want to set down before you sleep?",
            helper: "Name it so it doesn't have to run in the background all night.",
            kind: .text(placeholder: "I want to set down\u{2026}")
        ),
        TemplateStep(
            id: "went-well",
            label: "What went well",
            question: "What went well today \u{2014} even something small?",
            helper: "Keep it concrete.",
            kind: .text(placeholder: "One thing that went well\u{2026}")
        ),
        TemplateStep(
            id: "tomorrow",
            label: "What can wait",
            question: "What can wait until tomorrow?",
            helper: "Naming it is often enough to actually let it wait.",
            kind: .text(placeholder: "Tomorrow I'll\u{2026}")
        )
    ]
}

// MARK: - Evidence

enum TemplateEvidenceLibrary {
    static let nhsThoughtRecord = TemplateEvidence(
        id: "nhs-thought-record",
        kind: .clinical,
        pill: "NHS \u{00b7} CBT thought record",
        blurb: "Based closely on the NHS's seven-step CBT Thought Record, which the NHS describes as a common CBT exercise: situation, feelings, thoughts, evidence for, evidence against, alternative thought, feelings after. This is a self-reflection tool, not a diagnosis or a replacement for professional care.",
        sources: [
            .init(label: "NHS \u{2014} Thought Record",
                  url: URL(string: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/self-help-cbt-techniques/thought-record/")!)
        ]
    )

    static let gratitudeRCT = TemplateEvidence(
        id: "gratitude-rct",
        kind: .clinical,
        pill: "RCT \u{00b7} 293 participants",
        blurb: "Adapted from gratitude-letter research. A randomized controlled trial of 293 psychotherapy clients found better mental-health outcomes at follow-up in the gratitude-writing group than in expressive-writing or psychotherapy-only conditions.",
        sources: [
            .init(label: "PubMed \u{2014} gratitude writing RCT",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/27139595/")!)
        ]
    )

    static let neffSelfCompassion = TemplateEvidence(
        id: "neff-self-compassion",
        kind: .clinical,
        pill: "Kristin Neff \u{00b7} self-compassion exercise",
        blurb: "Adapted from Kristin Neff's published self-compassion journal, which structures a difficult event through mindfulness, common humanity, and self-kindness \u{2014} here focused on a hard conversation.",
        sources: [
            .init(label: "self-compassion.org \u{2014} Exercise 6",
                  url: URL(string: "https://self-compassion.org/exercises/exercise-6-self-compassion-journal/")!)
        ]
    )

    /// Shared by `morningPages` and `windDown`. Deliberately carries no
    /// clinical claim — see the file header's integrity note.
    static let productPattern = TemplateEvidence(
        id: "product-pattern",
        kind: .practice,
        pill: "Product-proven pattern",
        blurb: "No clinical trial supports this exact format \u{2014} it's a writing/product pattern, not a research-backed protocol. Day One frames its Prompt Packs as a response to the blank-page problem, Stoic's users named custom guided templates their #2 feature request, and Rosebud makes goal-specific Guided Journals a core mode.",
        sources: [
            .init(label: "Day One \u{2014} Prompt Packs",
                  url: URL(string: "https://dayoneapp.com/guides/tips-and-tutorials/prompt-packs/")!),
            .init(label: "Stoic \u{2014} guided templates",
                  url: URL(string: "https://www.getstoic.com/blog/stoic-journal-update-august-2025-25")!),
            .init(label: "Rosebud \u{2014} Guided Journals",
                  url: URL(string: "https://help.rosebud.app/daily-journaling/guided-journals")!)
        ]
    )

    /// Verified against the PubMed abstract directly (not just the prototype's
    /// claim) before writing this as `.clinical` — see the integrity note above.
    /// 29 studies, 2,909 participants total; small-to-medium effects on
    /// wellbeing, optimism and positive affect versus controls.
    static let bestPossibleSelfMetaAnalysis = TemplateEvidence(
        id: "best-possible-self-meta-analysis",
        kind: .clinical,
        pill: "Meta-analysis \u{00b7} n=2,909",
        blurb: "Based on the Best Possible Self intervention. A systematic review and meta-analysis of 29 studies (2,909 participants) found small-to-medium improvements in wellbeing, optimism and positive affect compared with control conditions.",
        sources: [
            .init(label: "PubMed \u{2014} Best Possible Self meta-analysis",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/31545815/")!)
        ]
    )

    /// Backs the "Why these?" sheet. Clinical rows first, then practice.
    static let all: [TemplateEvidence] = [
        nhsThoughtRecord, gratitudeRCT, neffSelfCompassion, bestPossibleSelfMetaAnalysis, productPattern
    ]
}
