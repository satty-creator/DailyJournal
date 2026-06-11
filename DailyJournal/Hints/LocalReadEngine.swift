//
//  LocalReadEngine.swift
//  DailyJournal
//
//  The always-available, offline fallback that assembles "Today's Read" locally
//  when the overnight server generator hasn't written one (new user, first run,
//  no network last night, or a held-back read).
//
//  Philosophy matches NinetyVoice/LocalAI: heuristic, NON-parroting, with a point
//  of view. It reads coarse signals off recent entries, picks the scenario that
//  best fits, and emits a read in one of the six approved structural formulas at
//  the user's chosen sharpness. Receipt chips are lifted from the user's ACTUAL
//  words so the read is grounded, never generic.
//
//  This engine never calls the network and never throws. If it genuinely has
//  nothing to say (too little signal), it returns a shouldShow == false read so
//  the Home screen falls back to the plain prompt card.
//

import Foundation

enum LocalReadEngine {

    static let promptVersion = "local-read-v1"

    // MARK: - Scenario

    /// The three first-class scenarios from the tone matrix, plus a generic floor.
    private enum Scenario {
        case avoidanceMessaging
        case overAvailability
        case burnoutRest
        case generic
    }

    // MARK: - Entry point

    /// Build a read for `userId` from `recentEntries` (newest first is fine — we
    /// scan all of them). `settings` supplies the sharpness preference and recent
    /// rejection codes so the local read respects the same feedback the user has
    /// been giving the server reads.
    static func makeRead(
        userId: String,
        localDate: Date = Date(),
        recentEntries: [JournalEntry],
        settings: ReadSettings
    ) -> DailyRead {

        let corpus = recentEntries.prefix(14)
        let joined = corpus.map { $0.content }.joined(separator: "\n").lowercased()
        let entryIds = corpus.map { $0.id }

        // Not enough to ground a read → explicit no-show, Home falls back to prompt.
        guard joined.count >= 60 else {
            return noShow(userId: userId, localDate: localDate, reason: "not_enough_signal")
        }

        let sharpness = settings.sharpnessPreference
        let avoidCodes = Set(settings.recentRejectionCodes())

        let scenario = detectScenario(in: joined, avoiding: avoidCodes)
        let chips = receipts(for: scenario, in: corpus, joined: joined)

        // "too vague" history → bias toward the most concrete formulas.
        let preferConcrete = avoidCodes.contains(.tooVague)
        // "too dramatic" history → never reach for the spiciest line.
        let cappedSharpness: ReadSharpness =
            avoidCodes.contains(.tooDramatic) && sharpness == .spicy ? .direct : sharpness

        let tone = pickTone(for: cappedSharpness, scenario: scenario, seed: daySeed(localDate))
        let line = readLine(scenario: scenario, tone: tone, preferConcrete: preferConcrete)

        return DailyRead(
            userId: userId,
            localDate: localDate,
            readText: line.read,
            receiptChips: chips,
            replyPrompt: line.reply,
            shareSafeText: line.share,
            tone: tone,
            sharpnessLevel: cappedSharpness,
            safetyLevel: .none,
            confidence: 0.55,                 // honest: a local read is a decent guess, not a server-grade one
            shouldShow: true,
            sourceEntryIds: entryIds,
            modelProvider: "local",
            modelName: "local-engine",
            promptVersion: promptVersion
        )
    }

    // MARK: - No-show

    private static func noShow(userId: String, localDate: Date, reason: String) -> DailyRead {
        DailyRead(
            userId: userId,
            localDate: localDate,
            readText: "",
            receiptChips: [],
            replyPrompt: "",
            shareSafeText: "",
            tone: .soft,
            sharpnessLevel: .direct,
            safetyLevel: .none,
            confidence: 0,
            shouldShow: false,
            doNotShowReason: reason,
            sourceEntryIds: [],
            modelProvider: "local",
            modelName: "local-engine",
            promptVersion: promptVersion
        )
    }

    // MARK: - Scenario detection

    private static func detectScenario(in text: String, avoiding: Set<ReadRejectionCode>) -> Scenario {
        func hits(_ words: [String]) -> Int { words.filter { text.contains($0) }.count }

        let avoidance = hits(["message", "text", "reply", "respond", "unread", "left on read",
                              "haven't answered", "ignored", "dm", "email back", "owe her", "owe him"])
        let availability = hits(["everyone needs", "no time for me", "available", "saying yes",
                                "couldn't say no", "drained by people", "back to back", "everyone wants",
                                "people pleasing", "spread thin"])
        let burnout = hits(["exhausted", "burnt out", "burned out", "no energy", "need a break",
                            "can't rest", "guilty resting", "tired", "running on empty", "depleted",
                            "should be productive"])

        // Honour "wrong topic" by deprioritising the strongest scenario when the
        // user keeps telling us we picked the wrong thing.
        var scores: [(Scenario, Int)] = [
            (.avoidanceMessaging, avoidance),
            (.overAvailability, availability),
            (.burnoutRest, burnout)
        ]
        if avoiding.contains(.wrongTopic) {
            scores = scores.map { ($0.0, max(0, $0.1 - 1)) }
        }

        let best = scores.max { $0.1 < $1.1 }
        if let best, best.1 >= 1 { return best.0 }
        return .generic
    }

    // MARK: - Receipts (grounding chips)

    /// 2–4 small, lowercase tokens lifted from the user's actual words/contexts.
    private static func receipts(for scenario: Scenario, in entries: ArraySlice<JournalEntry>, joined: String) -> [String] {
        // Tags the user actually attached (pebbles/contexts) are the cleanest chips.
        let tagChips = entries
            .flatMap { $0.tags }
            .filter { !$0.isEmpty && $0 != "trace" && $0 != "blank-drop" }
            .map { $0.lowercased() }

        // Scenario-specific keyword chips found literally in the corpus.
        let vocab: [String]
        switch scenario {
        case .avoidanceMessaging: vocab = ["message", "reply", "unread", "later", "avoided", "text"]
        case .overAvailability:   vocab = ["everyone", "yes", "available", "no time", "drained"]
        case .burnoutRest:        vocab = ["tired", "rest", "break", "productive", "guilty", "empty"]
        case .generic:            vocab = ["should", "tomorrow", "again", "stuck", "fine", "busy"]
        }
        let found = vocab.filter { joined.contains($0) }

        // De-dupe, preserve order: tags first (most personal), then found vocab.
        var seen = Set<String>()
        let merged = (tagChips + found).filter { seen.insert($0).inserted }

        if merged.count >= 2 { return Array(merged.prefix(4)) }

        // Fallback chips so the receipts row is never empty or a single chip.
        switch scenario {
        case .avoidanceMessaging: return ["messages", "avoided", "later"]
        case .overAvailability:   return ["everyone", "yes", "no time"]
        case .burnoutRest:        return ["tired", "rest", "should"]
        case .generic:            return ["your words", "your pattern"]
        }
    }

    // MARK: - Tone selection

    private static func daySeed(_ date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
    }

    /// Maps the sharpness preference onto an actual tone. Kept deliberately CALM
    /// and observational: the performative `.funny` lines ("limited series",
    /// "hostage taker") read as loud/gimmicky, so the local engine no longer
    /// reaches for them. `.spicy` is used only occasionally even at the spiciest
    /// preference; most days land on `.soft`/`.direct`.
    private static func pickTone(for sharpness: ReadSharpness, scenario: Scenario, seed: Int) -> ReadTone {
        switch sharpness {
        case .soft:
            return .soft
        case .direct:
            return .direct
        case .spicy:
            return seed % 3 == 0 ? .spicy : .direct
        }
    }

    // MARK: - The lines (tone matrix + formula fallbacks)

    private struct ReadLine {
        let read: String
        let reply: String
        let share: String
    }

    private static func readLine(scenario: Scenario, tone: ReadTone, preferConcrete: Bool) -> ReadLine {
        switch scenario {

        case .avoidanceMessaging:
            switch tone {
            case .soft:
                return ReadLine(
                    read:  "The message may be smaller than the feeling around it.",
                    reply: "What's the actual message, with the dread stripped off?",
                    share: "the message is smaller than the feeling around it.")
            case .direct:
                return ReadLine(
                    read:  "You are making the reply bigger than the message.",
                    reply: "What would you write if the reply didn't have to be perfect?",
                    share: "making the reply bigger than the message.")
            case .funny:
                return ReadLine(
                    read:  "Your brain has turned one unread message into a limited series.",
                    reply: "What's the one-line ending to this show in your head?",
                    share: "one unread message, somehow a limited series.")
            case .spicy:
                return ReadLine(
                    read:  "The message is not the main character. Your imagined performance is.",
                    reply: "What are you actually rehearsing for?",
                    share: "the message isn't the main character. the performance is.")
            }

        case .overAvailability:
            switch tone {
            case .soft:
                return ReadLine(
                    read:  "You may be giving the day access to you before checking what you have left.",
                    reply: "What did you have left this morning, before anyone asked?",
                    share: "giving the day access before checking what's left.")
            case .direct:
                return ReadLine(
                    read:  "You are answering your day before answering yourself.",
                    reply: "What would you have said today if you'd asked yourself first?",
                    share: "answering the day before answering yourself.")
            case .funny:
                return ReadLine(
                    read:  "Your availability has severe main-character syndrome.",
                    reply: "Who got the version of you that you didn't?",
                    share: "your availability has main-character syndrome.")
            case .spicy:
                return ReadLine(
                    read:  "You keep acting completely available and then wondering why you feel invaded.",
                    reply: "Where did you say yes today that was really a no?",
                    share: "completely available, then surprised you feel invaded.")
            }

        case .burnoutRest:
            switch tone {
            case .soft:
                return ReadLine(
                    read:  "Your day is asking for rest, but your routine is asking for permission.",
                    reply: "What would rest look like if you didn't have to earn it?",
                    share: "asking for rest, waiting for permission.")
            case .direct:
                return ReadLine(
                    read:  "You are treating rest like a chore you have to complete.",
                    reply: "What's the smallest rest you'd actually let yourself take?",
                    share: "treating rest like a chore to complete.")
            case .funny:
                return ReadLine(
                    read:  "You negotiate with taking a break like you're talking to a hostage taker.",
                    reply: "What's the break offering, and why don't you trust it?",
                    share: "negotiating with a break like a hostage taker.")
            case .spicy:
                return ReadLine(
                    read:  "You treat your body like an administrative task to deal with when the day is done.",
                    reply: "What did your body ask for today that you filed for later?",
                    share: "treating your body like an admin task for later.")
            }

        case .generic:
            // Formula-driven fallbacks. "too vague" history → use the most concrete
            // ones (Formula 2 / Formula 5) and skip the abstract space-claim.
            if preferConcrete {
                return ReadLine(
                    read:  "Your words say \u{201C}I'm fine.\u{201D} Your pattern says you explain fine too hard.",
                    reply: "What were you defending when you said you were fine?",
                    share: "your words say fine. your pattern explains it too hard.")
            }
            switch tone {
            case .soft:
                return ReadLine(
                    read:  "The unfinished thing is taking more space than it deserves.",
                    reply: "What's the unfinished thing, named in one line?",
                    share: "the unfinished thing is taking more space than it deserves.")
            case .direct:
                return ReadLine(
                    read:  "The problem is not that you did nothing. It is that one thing got to define the day.",
                    reply: "What did you actually do today that didn't count to you?",
                    share: "one unfinished thing got to define the whole day.")
            case .funny:
                return ReadLine(
                    read:  "Tomorrow is stealing too much of tonight, and it didn't even ask.",
                    reply: "What is tonight allowed to be, if tomorrow waits its turn?",
                    share: "tomorrow keeps stealing tonight without asking.")
            case .spicy:
                return ReadLine(
                    read:  "Stop asking whether you did enough. Ask why what you did doesn't count to you.",
                    reply: "What did you manage today that you refuse to credit?",
                    share: "stop asking if you did enough. ask why it doesn't count.")
            }
        }
    }
}
