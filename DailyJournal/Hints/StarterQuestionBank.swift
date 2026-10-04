//
//  StarterQuestionBank.swift
//  DailyJournal
//
//  The blank-page starter question — what a user sees before they've typed a
//  single word. Replaces the old `HintLadder` pebble-combo engine, which
//  nothing fed pebbles into any more, so every user saw the same one fixed
//  question ("What's one small thing today that you haven't let yourself feel
//  yet?") forever, and the three re-roll pills cycled 4 fixed strings each.
//
//  This is a curated, on-device question bank — no AI call. That mirrors why
//  the Gemini starter enrichment layer was cut (11% of AI spend for one line
//  of text — see ai-cost-audit-2026-09-06.md §3.2), and it's instant and works
//  offline, which a blank-page starter has to be.
//
//  Writing rules for every question in `all` (research grounded, not vibes):
//   • Concrete and episodic, not abstract — anchor to a time, place or moment.
//     Specific cues retrieve richer memory than general ones do.
//   • Ask "what", not "why" — "why" tends to produce rumination and
//     rationalising; "what" produces noticing (Eurich's self-insight work).
//   • Facts *and* feelings in the same breath (Pennebaker's expressive-writing
//     framing), not just "how do you feel".
//   • Answerable badly in one sentence. No "should", no diagnosing, no
//     therapy-speak ("hold space", "sit with", "let yourself feel").
//   • Mixed valence — savouring/good-things prompts belong here too (Seligman's
//     "Three Good Things", Bryant's savouring), not only difficulty.
//   • Occasional self-distancing ("if a friend told you this…" — Kross) and
//     forward-looking prompts with a concrete near-term anchor (implementation
//     intentions), not "what are your goals".
//
//  Design rules carried over from the old ladder (still the PRD):
//   • Hints are optional and tiny. Never shame, nag, diagnose, or perform.
//   • Nothing here is personal — every question in this bank is safe to show
//     anywhere, with no per-user phrasing. (The old `HintPersonal` "light"/"me"
//     tiers had no live input — pebbles were never wired up — so they're not
//     carried forward. If personalization comes back, it should read
//     `MemoryProfile` directly rather than resurrect that scaffolding.)
//

import Foundation

// MARK: - Question

/// One entry in the starter bank.
struct StarterQuestion: Identifiable, Equatable {
    let id: String
    let text: String
    let kind: StarterKind
    let moments: Set<StarterMoment>
}

/// A rough content category — used only to avoid showing two questions of the
/// same shape back to back when re-rolling.
enum StarterKind: String, CaseIterable {
    case episode   // a specific moment in the day
    case sensory   // body / physical texture of the day
    case people    // who was around, how it landed
    case savour    // good-things / savouring
    case openLoop  // unfinished business, lists, avoidance
    case forward   // the next 24 hours
    case distance  // self-distancing ("a friend")
    case arrival   // first-time / returning-after-a-gap openers
}

/// When a question is eligible to be picked. `.any` questions are always
/// eligible but are weighted below a moment-matched question.
enum StarterMoment: String, CaseIterable {
    case morning     // before noon
    case afternoon   // noon–5pm
    case evening     // 5pm–10pm
    case lateNight    // 10pm–4am
    case weekend
    case monday
    case friday
    case firstEntries // fewer than 3 entries ever
    case returning    // 4+ days since the last entry
    case any
}

// MARK: - Bank

enum StarterQuestionBank {

    /// All starter questions. Text is kept to a single sentence, ≤120 chars,
    /// and always ends in "?" (enforced by `StarterQuestionPickerTests`).
    static let all: [StarterQuestion] = [

        // MARK: morning
        q("m1", "What's the first thing your mind went to when you woke up?", .episode, [.morning]),
        q("m2", "What are you dreading and looking forward to today, in the same breath?", .forward, [.morning]),
        q("m3", "What's already used up some of your energy, and it's not even noon?", .sensory, [.morning]),
        q("m4", "What's one thing today that you'd actually like to go well?", .forward, [.morning]),
        q("m5", "Who's the first person you thought about this morning?", .people, [.morning]),
        q("m6", "What did you do in the first twenty minutes after waking up?", .episode, [.morning]),
        q("m7", "What's the weather doing to your mood today?", .sensory, [.morning, .any]),
        q("m8", "What's on your plate today that you're quietly hoping gets cancelled?", .openLoop, [.morning]),

        // MARK: afternoon
        q("a1", "What's happened since you woke up that you'd actually tell a friend about?", .episode, [.afternoon]),
        q("a2", "Where were you at lunchtime, and what was actually on your mind?", .episode, [.afternoon]),
        q("a3", "What's the most annoying thing that's happened today so far?", .episode, [.afternoon]),
        q("a4", "What have you eaten today, and did any of it feel like a choice?", .sensory, [.afternoon]),
        q("a5", "Who have you talked to today, and how did you feel right after?", .people, [.afternoon]),
        q("a6", "What's still sitting unanswered in your messages right now?", .openLoop, [.afternoon]),
        q("a7", "What's the smallest thing that's gone right today?", .savour, [.afternoon]),
        q("a8", "What have you been putting off since this morning?", .openLoop, [.afternoon]),

        // MARK: evening
        q("e1", "Where were you at 3pm today, and what was on your mind?", .episode, [.evening]),
        q("e2", "What were the best ten minutes of today?", .savour, [.evening]),
        q("e3", "What's one thing that happened today that you haven't told anyone yet?", .episode, [.evening]),
        q("e4", "Was it a task, a person, or a thought that took the most out of you today?", .sensory, [.evening]),
        q("e5", "What did you do today that you'd do again tomorrow if you could?", .savour, [.evening]),
        q("e6", "Who took up the most space in your head today, and did they know it?", .people, [.evening]),
        q("e7", "What's one thing today that went differently than you expected?", .episode, [.evening]),
        q("e8", "What did you skip today that you usually do?", .openLoop, [.evening]),
        q("e9", "What's the most honest one-word summary of today?", .sensory, [.evening]),
        q("e10", "What conversation from today is still playing back in your head?", .people, [.evening]),

        // MARK: late night
        q("n1", "Is it a thought keeping you up, a feeling, or just the quiet?", .sensory, [.lateNight]),
        q("n2", "What's the last thing that happened today that's still with you?", .episode, [.lateNight]),
        q("n3", "What are you not ready to stop thinking about yet?", .openLoop, [.lateNight]),
        q("n4", "If you fell asleep right now, what would you be leaving unfinished?", .openLoop, [.lateNight]),
        q("n5", "What's one thing from today you want to remember, even a small one?", .savour, [.lateNight]),

        // MARK: weekday anchors
        q("mo1", "What's one thing this week you're already bracing for?", .forward, [.monday]),
        q("mo2", "What would make this week feel different from last week?", .forward, [.monday]),
        q("mo3", "What are you walking into this week that you didn't choose?", .openLoop, [.monday]),
        q("fr1", "Now that the week's nearly done, what did it turn out to be about?", .episode, [.friday]),
        q("fr2", "What's one thing from this week you're glad is over?", .savour, [.friday]),
        q("fr3", "What from this week do you want to carry into the weekend, and what do you want to drop?", .forward, [.friday]),

        // MARK: weekend
        q("we1", "What did you do today that nobody asked you to?", .savour, [.weekend]),
        q("we2", "What's the difference between how today felt and how a weekday feels?", .sensory, [.weekend]),
        q("we3", "What did you do today that had absolutely no purpose, and was it good?", .savour, [.weekend]),
        q("we4", "Who did you spend today with, or did you spend it alone on purpose?", .people, [.weekend]),
        q("we5", "What's one thing you meant to do this weekend that you haven't yet?", .openLoop, [.weekend]),

        // MARK: general episode / people / body / open loop / distance / forward (.any)
        q("g1", "What's one specific moment from today you could replay like a scene?", .episode, [.any]),
        q("g2", "What did you do today that you've done a hundred times before?", .episode, [.any]),
        q("g3", "What's a small thing someone said today that's stuck with you?", .people, [.any]),
        q("g4", "Who made today easier, even a little, and did you notice at the time?", .people, [.any]),
        q("g5", "Was there a call, a message, or a conversation you avoided today?", .people, [.any]),
        q("g6", "Did today land in your shoulders, your jaw, your stomach, or nowhere at all?", .sensory, [.any]),
        q("g7", "What's your energy right now, actually, not the version you'd tell someone at work?", .sensory, [.any]),
        q("g8", "What in your body is tired that has nothing to do with sleep?", .sensory, [.any]),
        q("g9", "What's on your list that's actually bothering you, not just waiting?", .openLoop, [.any]),
        q("g10", "What have you been meaning to say to someone and haven't?", .openLoop, [.any]),
        q("g11", "What's one thing today that you did on autopilot?", .episode, [.any]),
        q("g12", "What's something today that was harder than it should've been?", .episode, [.any]),
        q("g13", "What's one thing you noticed today that you'd normally scroll past?", .sensory, [.any]),
        q("g14", "What made you laugh today, if anything did?", .savour, [.any]),
        q("g15", "What's one thing today that surprised you, even slightly?", .episode, [.any]),
        q("g16", "What did you choose today that you didn't have to choose?", .episode, [.any]),
        q("g17", "If a friend described your day back to you, what would they notice that you haven't?", .distance, [.any]),
        q("g18", "What would you tell a friend who'd had your exact day?", .distance, [.any]),
        q("g19", "If today were a headline, what would it say?", .distance, [.any]),
        q("g20", "What's one thing in the next 24 hours you'd like to go a certain way?", .forward, [.any]),
        q("g21", "What's one small thing you could do tomorrow that today didn't leave room for?", .forward, [.any]),
        q("g22", "What are you hoping tomorrow undoes from today?", .forward, [.any]),
        q("g23", "What's a decision you made today, even a tiny one?", .episode, [.any]),
        q("g24", "What's something today that you're still deciding how you feel about?", .episode, [.any]),
        q("g25", "What's one thing today that you did purely for yourself?", .savour, [.any]),
        q("g26", "What's a text or message you got today that you haven't answered yet?", .openLoop, [.any]),
        q("g27", "What's one thing today that you handled better than you expected to?", .savour, [.any]),
        q("g28", "What's something you almost said out loud today, but didn't?", .openLoop, [.any]),
        q("g29", "What place did you spend the most time in today, and how did it feel to be there?", .sensory, [.any]),
        q("g30", "What's one thing today that felt like it belonged to yesterday instead?", .episode, [.any]),

        // MARK: arrival (first entries / returning after a gap)
        q("fe1", "What made you want to open a journal today?", .arrival, [.firstEntries]),
        q("fe2", "What's one thing you'd want to look back on and remember about today?", .arrival, [.firstEntries]),
        q("fe3", "What's going on right now that made today feel worth writing down?", .arrival, [.firstEntries]),
        q("re1", "It's been a few days. What's been taking up the space?", .arrival, [.returning]),
        q("re2", "What's changed since you last wrote here?", .arrival, [.returning]),
        q("re3", "What's the thing you'd have written about if you'd written every day this week?", .arrival, [.returning]),
    ]

    private static func q(_ id: String, _ text: String, _ kind: StarterKind, _ moments: Set<StarterMoment>) -> StarterQuestion {
        StarterQuestion(id: id, text: text, kind: kind, moments: moments)
    }
}

// MARK: - Picker

/// Pure, deterministic-given-its-inputs selection logic (randomness aside) so
/// it's trivially unit testable without touching Firestore or UserDefaults.
enum StarterQuestionPicker {

    /// Picks one question for right now.
    ///
    /// - Parameters:
    ///   - now: wall-clock time, used for time-of-day and weekday moments.
    ///   - profile: the cached `MemoryProfile`, if any — used only for the
    ///     `.firstEntries` / `.returning` moments, never for personalized text.
    ///   - recentIDs: IDs shown recently, to avoid repeats. Ignored if
    ///     honoring it would leave nothing to pick from.
    ///   - lastKind: the kind of the immediately-previous question, so a
    ///     re-roll doesn't just repeat the same shape of question.
    static func pick(
        now: Date = Date(),
        profile: MemoryProfile? = nil,
        recentIDs: [String] = [],
        lastKind: StarterKind? = nil
    ) -> StarterQuestion {
        let moments = activeMoments(now: now, profile: profile)
        let bank = StarterQuestionBank.all
        let recent = Set(recentIDs)

        // Step the filters down until something's left — momentMatch+fresh+kind
        // is the ideal draw, but each constraint is allowed to give way rather
        // than ever returning nothing.
        let momentMatched = bank.filter { !$0.moments.isDisjoint(with: moments) }
        let pools: [[StarterQuestion]] = [
            momentMatched.filter { !recent.contains($0.id) && $0.kind != lastKind },
            momentMatched.filter { !recent.contains($0.id) },
            momentMatched,
            bank.filter { !recent.contains($0.id) },
            bank,
        ]
        let pool = pools.first(where: { !$0.isEmpty }) ?? bank

        // Weight moment-specific matches (anything beyond plain `.any`) about
        // 3x over generic `.any` questions so context still shows through
        // even once the anti-repeat filters have widened the pool.
        let weighted = pool.flatMap { question -> [StarterQuestion] in
            let isSpecific = !question.moments.subtracting([.any]).isDisjoint(with: moments)
            return Array(repeating: question, count: isSpecific ? 3 : 1)
        }

        return weighted.randomElement() ?? bank[0]
    }

    private static func activeMoments(now: Date, profile: MemoryProfile?) -> Set<StarterMoment> {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday

        var moments: Set<StarterMoment> = [.any]

        switch hour {
        case 4..<12:  moments.insert(.morning)
        case 12..<17: moments.insert(.afternoon)
        case 17..<22: moments.insert(.evening)
        default:      moments.insert(.lateNight)
        }

        if weekday == 1 || weekday == 7 { moments.insert(.weekend) }
        if weekday == 2 { moments.insert(.monday) }
        if weekday == 6 { moments.insert(.friday) }

        if let profile {
            if profile.totalEntries < 3 {
                moments.insert(.firstEntries)
            } else if let last = profile.lastEntryDate,
                      let days = cal.dateComponents([.day], from: last, to: now).day,
                      days >= 4 {
                moments.insert(.returning)
            }
        }

        return moments
    }
}
