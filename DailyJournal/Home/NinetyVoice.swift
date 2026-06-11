//
//  NinetyVoice.swift
//  DailyJournal
//
//  The single source of truth for *who ninety is* when it speaks. Injected into
//  every Gemini prompt (reflection, echo, river) so the app has one consistent,
//  recognisable personality instead of three generic assistants.
//
//  It also holds the local-fallback writers used when there's no API key — these
//  are deliberately NOT paraphrase-based, because the whole point is that ninety
//  adds a layer the user didn't already write.
//

import Foundation

enum NinetyVoice {

    // MARK: - The personality (shared system prompt fragment)

    /// Paste into the top of any ninety prompt. Defines voice + the hard
    /// anti-parroting rule that fixes "ninety just repeats what I said."
    static let system = """
    YOU ARE NINETY.
    Voice: a sharp, warm friend who has been quietly reading this person's journal
    for a while. You notice things. You are specific, a little wry, and unafraid to
    name the thing they're circling but didn't say outright. You are not a therapist,
    a coach, or a guru. You never use wellness clichés, never diagnose, never give
    advice ("you should…"), and never moralise.

    THE ONE RULE THAT MATTERS MOST:
    Never restate what the user already wrote. If your line could be made by
    re-reading their entry, it has failed. Your job is to add the layer they did
    NOT write — pick at least one move:
      • TENSION   — name the pull between what they want and what they're doing.
      • UNDERNEATH — say what the entry keeps reaching for beneath the surface words.
      • ABSENCE   — notice what's conspicuously missing (e.g. they wrote 200 words
                    about everyone else and barely appear themselves).
      • REFRAME   — re-describe it precisely (this isn't laziness, it's depletion).
      • PATTERN   — connect it to something that recurs (only if you have evidence).

    Be concrete. Use their exact nouns and images, but in service of an observation,
    not a summary. One sharp, specific question beats five gentle ones. Calm,
    grounded, never breathless. Lowercase-friendly, plain language.
    """

    // MARK: - Local fallback: reflection observations
    //
    // Heuristic but NON-parroting. We read coarse signals (sentiment, pressure,
    // self-blame, other-focus) and emit observations + a question that the user
    // did not literally write. Less deep than Gemini, but it has a point of view.

    struct LocalReflection {
        let observations: [String]   // the "noticed" layer (2 lines)
        let question: String
    }

    static func localReflection(from text: String, sentiment: String) -> LocalReflection {
        let lower = text.lowercased()

        // Signals.
        let pressure   = ["behind","deadline","late","too much","everyone","need to","have to",
                          "should","busy","no time","overwhelm","rushing"].filter { lower.contains($0) }.count
        let selfBlame  = ["i should","my fault","i'm so","i hate","stupid","failure","not good enough",
                          "what's wrong with me","why can't i"].contains { lower.contains($0) }
        let otherFocus = ["she","he","they","them","mum","mom","dad","boss","everyone","people"]
            .filter { lower.contains($0) }.count >= 3
        let wantsQuiet = ["quiet","space","alone","rest","breathe","slow down","silence"].contains { lower.contains($0) }
        let future     = ["tomorrow","next","will","going to","plan","hope","want to"].contains { lower.contains($0) }

        var obs: [String] = []

        // Each observation does a MOVE, not a recap.
        if pressure >= 2 && wantsQuiet {
            obs.append("This reads less like a to-do list and more like a request for room you haven't given yourself permission to take.")
        } else if pressure >= 2 {
            obs.append("The weight here isn't any one task — it's the sense of everything arriving at once, before you'd arrived yourself.")
        }
        if selfBlame {
            obs.append("Notice how quickly this turns the blame inward. The entry treats a hard day as evidence about you, not about the day.")
        }
        if otherFocus && obs.count < 2 {
            obs.append("Everyone else is vivid here. You're mostly the one reacting to them — you barely show up as your own subject.")
        }
        if wantsQuiet && obs.isEmpty {
            obs.append("Underneath the specifics, the thing this keeps reaching for is quiet — not a fix, just a little uncontested space.")
        }

        // Sentiment-based backstops so we always have a real observation.
        if obs.isEmpty {
            switch sentiment {
            case "Anxious":    obs.append("The worry here is doing a lot of work for a future that hasn't decided anything yet.")
            case "Sad":        obs.append("There's a softness under this that isn't asking to be fixed — just to be allowed.")
            case "Frustrated": obs.append("The frustration seems pointed at a situation, but the entry keeps circling back to an expectation you set for yourself.")
            case "Happy", "Excited": obs.append("Worth marking: you let yourself name something good without immediately qualifying it.")
            case "Calm":       obs.append("This is steadier than your usual entries — whatever made that, it's worth knowing.")
            default:           obs.append("Reading this back, the real subject isn't quite the one the first sentence announces.")
            }
        }
        if obs.count < 2 {
            obs.append(future
                ? "You're already leaning toward tomorrow — keep an eye on whether that's planning or escaping today."
                : "The most honest line here is quieter than the loudest one.")
        }

        // A sharp, specific question (not a gentle prompt).
        let q: String
        if wantsQuiet         { q = "What would you have to stop apologising for, to actually take the quiet?" }
        else if selfBlame     { q = "If a friend wrote this exact entry, would you read it as harshly as you're reading yourself?" }
        else if pressure >= 2 { q = "What on today's list is actually yours — and what did you just inherit?" }
        else {
            switch sentiment {
            case "Anxious":    q = "What's the smallest version of this that you could actually handle right now?"
            case "Sad":        q = "What do you need from someone today that you haven't asked for?"
            case "Frustrated": q = "Whose expectation is this really — and is it one you'd choose?"
            default:           q = "What did you leave out of this entry that you already know matters?"
            }
        }

        return LocalReflection(observations: Array(obs.prefix(2)), question: q)
    }

    // MARK: - Local fallback: echo callback line
    //
    // Frames the user's quote with a little edge instead of replaying it bare.

    static func localEchoLine(type: EchoType, quote: String, daysAgo: Int) -> String {
        let when = daysAgo <= 0 ? "the other day" : (daysAgo == 1 ? "yesterday" : "\(daysAgo) days ago")
        switch type {
        case .intention:
            return "\(when.capitalized) you said you'd do this. Did it happen — or did it quietly become next week's problem?"
        case .openLoop:
            return "This was coming up \(when). It's here now. How did it actually land, versus how you braced for it?"
        case .theme:
            return "This keeps coming back. \(when.capitalized) it surfaced again — what is it that won't quite let you put it down?"
        case .moodMarker:
            return "You named this \(when). Is it still true today, or has it moved without you noticing?"
        }
    }
}
