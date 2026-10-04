//
//  TemplateContent.swift
//  DailyJournal
//
//  The step content and evidence citations behind `JournalTemplate.all`. Kept
//  separate from `JournalTemplate.swift` so the catalog stays scannable.
//
//  Voice: direct and concrete, second person — never the clinical register of a
//  thought-record worksheet. A
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

    // MARK: - Shared chip sets (emotions, thinking traps)
    //
    // Pulled out once so every template that added a feelings or
    // thinking-traps step (see the integrity note's "the feelings gap" —
    // `untangleADecision` and `onboardingFirstEntry` cited the NHS thought
    // record's "feelings" steps without ever asking for them) uses the exact
    // same wording. Tapped order is preserved by `TemplateAnswer.choices`,
    // not resorted here.

    static let emotionOptions = [
        "Anxious", "Sad", "Angry", "Ashamed", "Guilty",
        "Hurt", "Lonely", "Overwhelmed", "Frustrated", "Embarrassed"
    ]

    /// Cognitive distortions from the standard CBT thinking-traps list (the
    /// same handful the NHS thought record and most CBT worksheets use).
    /// `chipHelp` below gives each one a one-line, non-clinical definition.
    static let thinkingTrapOptions = [
        "All-or-nothing", "Catastrophising", "Mind reading", "Fortune telling",
        "Overgeneralising", "Should statements", "Labelling",
        "Discounting the good", "Emotional reasoning", "Personalising", "Unfair comparison"
    ]

    static let thinkingTrapHelp: [String: String] = [
        "All-or-nothing": "Seeing it as all good or all bad, with nothing in between.",
        "Catastrophising": "Jumping straight to the worst possible outcome.",
        "Mind reading": "Assuming you know what someone else is thinking about you.",
        "Fortune telling": "Predicting how it'll go, as if it's already decided.",
        "Overgeneralising": "Taking one thing that happened and treating it as a pattern.",
        "Should statements": "Judging yourself or someone else against a rigid \u{201c}should.\u{201d}",
        "Labelling": "Reducing yourself or someone else to one harsh word.",
        "Discounting the good": "Writing off the parts that actually went fine.",
        "Emotional reasoning": "Treating a strong feeling as proof that it's true.",
        "Personalising": "Taking the blame for something that wasn't really about you.",
        "Unfair comparison": "Measuring yourself against someone else's highlight reel."
    ]

    // MARK: - Work through a thought (NHS CBT thought record, full form —
    // situation, thoughts, feelings, body, behaviour, thinking traps, evidence,
    // balanced read, feelings after, next step. The featured template.)

    static let workThroughAThought: [TemplateStep] = [
        TemplateStep(
            id: "situation",
            label: "The situation",
            question: "What happened \u{2014} just the facts?",
            helper: "No interpretation yet. Describe it like a camera would: who, where, what was actually said or done.",
            kind: .text(placeholder: "What happened was\u{2026}"),
            whyThis: "This is \u{201c}situation\u{201d} in a CBT thought record \u{2014} naming what's actually in front of you, before the interpretation.",
            examples: [
                "My manager replied \u{201c}we need to talk\u{201d} and nothing else.",
                "I texted a friend two days ago and still haven't heard back."
            ]
        ),
        TemplateStep(
            id: "thoughts",
            label: "The thought driving it",
            question: "What was the thought, word for word?",
            helper: "The exact sentence that flashed through your head \u{2014} not the tidied-up version. Catch the sharpest one.",
            kind: .text(placeholder: "The thought was\u{2026}"),
            whyThis: "The thought record's \u{201c}automatic thought\u{201d} step \u{2014} the exact words, not the polished version.",
            examples: [
                "\u{201c}They're going to fire me.\u{201d}",
                "\u{201c}I always ruin this.\u{201d}"
            ]
        ),
        TemplateStep(
            id: "emotions",
            label: "What you felt",
            question: "What did you feel?",
            helper: "Name every feeling that showed up \u{2014} pick as many as fit.",
            kind: .multiChoice(options: emotionOptions, allowsOther: true),
            whyThis: "The record's \u{201c}feelings\u{201d} step \u{2014} naming the feeling, separately from the thought that came with it."
        ),
        TemplateStep(
            id: "intensity-before",
            label: "How strong, before",
            question: "How strong is that feeling right now?",
            helper: "0 = barely there \u{00b7} 10 = as strong as it gets.",
            kind: .scale(role: .before)
        ),
        TemplateStep(
            id: "breathe",
            label: "A short pause",
            question: "Before you look closer \u{2014} a minute of box breathing?",
            helper: "Entirely optional. Skip it if you'd rather keep going.",
            kind: .breathing()
        ),
        TemplateStep(
            id: "body",
            label: "Where you felt it",
            question: "Where did your body feel it?",
            helper: "Tight chest, clenched jaw, heavy stomach? The body often flags it before the mind does. Leave blank if nothing stands out.",
            kind: .text(placeholder: "I can feel it in\u{2026}"),
            whyThis: "From the five-areas model alongside thoughts, feelings and behaviour \u{2014} body sensations are often the earliest sign something's up.",
            examples: [
                "Chest went tight and my breathing got shallow.",
                "Jaw clenched, shoulders up by my ears."
            ]
        ),
        TemplateStep(
            id: "behaviour",
            label: "What you did",
            question: "What did you do \u{2014} or want to do?",
            helper: "The action or the urge, even one you resisted. Avoiding, snapping, checking your phone, going quiet \u{2014} all count.",
            kind: .text(placeholder: "I ended up\u{2026}"),
            whyThis: "The fifth area: behaviour. What a thought and feeling actually drove you toward.",
            examples: [
                "Reread the message ten times and didn't reply.",
                "Cancelled plans and stayed in bed."
            ]
        ),
        TemplateStep(
            id: "traps",
            label: "Thinking traps",
            question: "Does your thought fall into any of these?",
            helper: "Pick any that fit \u{2014} or none.",
            kind: .multiChoice(options: thinkingTrapOptions),
            whyThis: "Thinking traps are the thought record's shortcut for spotting a distortion before weighing the evidence.",
            chipHelp: thinkingTrapHelp
        ),
        TemplateStep(
            id: "evidence-for",
            label: "What supports it",
            question: "What real evidence says the thought is true?",
            helper: "Facts only \u{2014} things you could show someone else. Not fears, not hunches.",
            kind: .text(placeholder: "What supports it is\u{2026}"),
            whyThis: "Facts first, before the interpretation \u{2014} this is \u{201c}evidence that supports the thought.\u{201d}",
            examples: [
                "He did say the project was behind.",
                "I missed Tuesday's deadline."
            ]
        ),
        TemplateStep(
            id: "evidence-against",
            label: "What it leaves out",
            question: "What does the thought conveniently leave out?",
            helper: "The facts the first read skipped \u{2014} times it went differently, things that don't fit the story.",
            kind: .text(placeholder: "It leaves out\u{2026}"),
            whyThis: "The record's most-skipped step: evidence the first read leaves out.",
            examples: [
                "My last review was strong.",
                "She was travelling all week \u{2014} that explains the silence."
            ]
        ),
        TemplateStep(
            id: "balanced",
            label: "A more balanced read",
            question: "If a friend said this thought out loud, what would you tell them?",
            helper: "Not a pep talk \u{2014} a fairer, fuller read that holds both the hard parts and the facts you just listed.",
            kind: .text(placeholder: "A more balanced read is\u{2026}"),
            whyThis: "The \u{201c}alternative thought\u{201d} step \u{2014} not necessarily positive, just more complete.",
            examples: [
                "\u{201c}One late deadline doesn't erase a good year.\u{201d}",
                "\u{201c}Silence usually means busy, not angry.\u{201d}"
            ]
        ),
        TemplateStep(
            id: "intensity-after",
            label: "How strong, after",
            question: "How strong does it feel now?",
            helper: "Same 0\u{2013}10 scale. The point is comparison, not precision.",
            kind: .scale(role: .after)
        ),
        TemplateStep(
            id: "next-step",
            label: "One next step",
            question: "What's one small thing you'll do next?",
            helper: "Small enough that you'll actually do it today. One text, one five-minute task, one ask.",
            kind: .text(placeholder: "One thing I can do is\u{2026}"),
            examples: [
                "Send a one-line reply instead of rehearsing a perfect one.",
                "Ask my manager for 10 minutes to check in."
            ]
        )
    ]

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
            id: "emotions",
            label: "What you felt",
            question: "What did you feel afterward?",
            helper: "Pick as many as fit.",
            kind: .multiChoice(options: emotionOptions, allowsOther: true)
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
            id: "emotions",
            label: "What you felt",
            question: "What did you feel about it?",
            helper: "Pick as many as fit.",
            kind: .multiChoice(options: emotionOptions, allowsOther: true),
            whyThis: "The thought record's \u{201c}feelings\u{201d} step \u{2014} naming the feeling, separately from the thought that came with it."
        ),
        TemplateStep(
            id: "traps",
            label: "Thinking traps",
            question: "Does that thought fall into any of these?",
            helper: "Pick any that fit \u{2014} or none.",
            kind: .multiChoice(options: thinkingTrapOptions),
            whyThis: "Thinking traps are the thought record's shortcut for spotting a distortion before weighing the evidence.",
            chipHelp: thinkingTrapHelp
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

    // MARK: - Onboarding's guided first entry (NHS CBT thought record, full
    // 5-step form — same framework as `untangleADecision` above, reworded
    // from "the decision" to whatever's weighing on the person, since the
    // first entry isn't necessarily about a decision). The situation step's
    // question is written per-user at runtime — see
    // `JournalTemplate.onboardingFirstEntry(openingQuestion:)`.

    static func onboardingFirstEntry(openingQuestion: String) -> [TemplateStep] {
        [
            TemplateStep(
                id: "heavy-before",
                label: "How heavy, before",
                question: "How heavy does this feel right now?",
                helper: "0 = light \u{00b7} 10 = very heavy.",
                kind: .scale(role: .before, values: Array(0...10))
            ),
            TemplateStep(
                id: "situation",
                label: "What's going on",
                question: openingQuestion,
                helper: "Just the facts first \u{2014} what's actually happening.",
                kind: .text(placeholder: "What's going on is\u{2026}"),
                whyThis: "This mirrors \u{201c}situation\u{201d} in a CBT thought record \u{2014} naming what's actually in front of you, before the interpretation."
            ),
            TemplateStep(
                id: "thought",
                label: "The thought driving it",
                question: "What thought keeps coming up about it?",
                helper: "Write it exactly as it sounds in your head.",
                kind: .text(placeholder: "The thought is\u{2026}"),
                whyThis: "This is the thought record's \u{201c}automatic thought\u{201d} step \u{2014} write it as it actually sounds, not the tidied-up version."
            ),
            TemplateStep(
                id: "emotions",
                label: "What you felt",
                question: "What did you feel about it?",
                helper: "Pick as many as fit.",
                kind: .multiChoice(options: emotionOptions, allowsOther: true),
                whyThis: "The thought record's \u{201c}feelings\u{201d} step \u{2014} naming the feeling, separately from the thought that came with it."
            ),
            TemplateStep(
                id: "traps",
                label: "Thinking traps",
                question: "Does that thought fall into any of these?",
                helper: "Pick any that fit \u{2014} or none.",
                kind: .multiChoice(options: thinkingTrapOptions),
                whyThis: "Thinking traps are the thought record's shortcut for spotting a distortion before weighing the evidence.",
                chipHelp: thinkingTrapHelp
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
                label: "A fairer read",
                question: "What's a fairer way to see this?",
                helper: "It doesn't have to be positive \u{2014} just fairer and more complete.",
                kind: .text(placeholder: "A fairer read is\u{2026}"),
                whyThis: "The \u{201c}alternative thought\u{201d} step \u{2014} not necessarily positive, just more complete."
            ),
            TemplateStep(
                id: "heavy-after",
                label: "How heavy, after",
                question: "How heavy does it feel now?",
                helper: "Same 0\u{2013}10 scale. The point is comparison, not precision.",
                kind: .scale(role: .after, values: Array(0...10))
            )
        ]
    }

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
            id: "breathe",
            label: "A short pause",
            question: "Start with a minute of box breathing?",
            helper: "Entirely optional. Skip it if you'd rather just write.",
            kind: .breathing()
        ),
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
