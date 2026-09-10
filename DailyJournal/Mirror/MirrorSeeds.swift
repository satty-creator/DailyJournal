// MirrorSeeds.swift
// DailyJournal
//
// The 8 Mirror Seed lenses shown in SpillWriteView.
//

import Foundation

struct MirrorSeed: Identifiable {
    let id: String
    let label: String
    let tagline: String
    let prompt: String

    static let all: [MirrorSeed] = [
        .init(id: "loop",      label: "Loop",      tagline: "Something you keep doing",             prompt: "What did you do today that you've done before, even though it doesn't help?"),
        .init(id: "body",      label: "Body",      tagline: "Physical reactions",                   prompt: "Did your body tense up, go tired, or feel off at any point today? What was happening?"),
        .init(id: "people",    label: "People",    tagline: "Someone on your mind",                 prompt: "Who were you thinking about more than you expected today, and why?"),
        .init(id: "exception", label: "Exception", tagline: "When something shifted",               prompt: "Was there a moment today where something usually hard actually went fine? What was different?"),
        .init(id: "avoided",   label: "Avoided",   tagline: "Something you skipped",                prompt: "Is there something you thought about writing but decided not to? What stopped you?"),
        .init(id: "pattern",   label: "Pattern",   tagline: "A repeat",                             prompt: "Did anything today remind you of something that keeps happening? What's the common thread?"),
        .init(id: "want",      label: "Want",      tagline: "What you actually needed",             prompt: "If you're honest: what did you actually need today that you didn't get?"),
        .init(id: "mask",      label: "Mask",      tagline: "What you showed vs felt",              prompt: "Was there a gap today between how you acted and how you actually felt? What happened?")
    ]
}
