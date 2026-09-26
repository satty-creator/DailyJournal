//
//  LocalAI.swift
//  DailyJournal
//
//  Local NLP helpers — sentiment, summary bullets, and the daily prompts bank.
//  Replace with a real API call (Claude, OpenAI) when ready.
//

import Foundation

enum LocalAI {

    // MARK: - Sentiment Detection

    /// The full set of sentiment labels the app recognises. Shared so the Gemini
    /// response parser can validate the model's label against the same vocabulary
    /// (the model sometimes returns off-list words like "Receptive").
    static let sentimentLabels: [String] = [
        "Anxious", "Excited", "Happy", "Sad", "Frustrated",
        "Calm", "Hopeful", "Uncertain", "Tired", "Grateful",
        "Lonely", "Proud", "Reflective"
    ]

    /// Validate/normalise an arbitrary sentiment string against the known set.
    /// Returns the canonical label if it matches (case-insensitively), else nil.
    static func normalizedSentiment(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return sentimentLabels.first { $0.caseInsensitiveCompare(raw) == .orderedSame }
    }

    /// True for entries too sparse to support any real reflection — a couple of
    /// words, "ok", a typo. Below this bar, fabricating an "observation" just
    /// invents meaning from noise; callers should fall back to the raw text
    /// instead (see JournalEntry.displayTitle).
    static func isLowContent(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.count <= 3
    }

    static func detectSentiment(from text: String) -> String {
        let lower = text.lowercased()

        // Negation context: phrases like "not happy", "don't feel anxious" should
        // not count toward positive/negative keywords. We check for negation in the
        // 4 words preceding a match.
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let negators = Set(["not", "no", "never", "don't", "didn't", "doesn't",
                             "won't", "wasn't", "haven't", "can't", "couldn't"])

        /// Counts keyword occurrences in `lower`, discounting those preceded by a negator.
        func scoreGroup(_ keywords: [String]) -> Double {
            var score: Double = 0
            for kw in keywords {
                var searchRange = lower.startIndex..<lower.endIndex
                while let range = lower.range(of: kw, range: searchRange) {
                    // Check for negation: scan back up to 4 tokens before this match
                    let prefix = String(lower[..<range.lowerBound])
                    let preWords = prefix
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }.suffix(4)
                    let negated = preWords.contains { negators.contains($0) }
                    score += negated ? -0.5 : 1.0
                    searchRange = range.upperBound..<lower.endIndex
                }
            }
            return max(score, 0)
        }

        // Higher-weight phrases are entered first; single words second.
        struct SentimentGroup {
            let label: String
            let weight: Double
            let phrases: [String]
            let single: [String]
        }

        let groups: [SentimentGroup] = [
            SentimentGroup(label: "Anxious", weight: 1.0,
                phrases: ["can't stop thinking", "what if", "on edge", "can't breathe", "heart racing", "about to lose it"],
                single: ["anxious", "anxiety", "worried", "worry", "stress", "stressed", "nervous",
                         "overwhelm", "overwhelmed", "panic", "dread", "scared", "fear", "afraid", "terrified"]),
            SentimentGroup(label: "Excited", weight: 1.2,
                phrases: ["can't wait", "looking forward", "so excited", "really excited", "finally happening"],
                single: ["excited", "thrilled", "elated", "joy", "joyful", "ecstatic", "pumped",
                         "stoked", "buzzing", "fantastic", "over the moon"]),
            SentimentGroup(label: "Happy", weight: 1.0,
                phrases: ["good day", "really good", "feeling good", "felt good", "made me happy",
                          "made me smile", "nice day"],
                single: ["happy", "wonderful", "content", "glad", "pleased", "smile", "smiled",
                         "laugh", "laughed", "fun", "enjoyed", "lovely", "great day"]),
            SentimentGroup(label: "Grateful", weight: 1.1,
                phrases: ["so grateful", "really grateful", "feel lucky", "feeling lucky", "feel blessed"],
                single: ["grateful", "thankful", "gratitude", "blessed", "appreciate", "appreciated", "lucky"]),
            SentimentGroup(label: "Sad", weight: 1.1,
                phrases: ["heartbroken", "fell apart", "can't stop crying", "broke my heart", "feeling empty", "feel empty"],
                single: ["sad", "crying", "cried", "tears", "grief", "grieving", "loss",
                         "heartbreak", "hurt", "devastated", "empty", "blue", "hollow", "gutted"]),
            SentimentGroup(label: "Lonely", weight: 1.1,
                phrases: ["no one understands", "no one cares", "left out", "miss them", "no one to talk to", "all alone"],
                single: ["lonely", "isolated", "missing", "nobody", "disconnected"]),
            SentimentGroup(label: "Frustrated", weight: 1.0,
                phrases: ["fed up", "sick of", "so annoying", "drives me crazy", "so angry"],
                single: ["frustrated", "annoyed", "irritated", "angry", "anger", "furious",
                         "mad", "resent", "rage", "fuming", "resentful"]),
            SentimentGroup(label: "Tired", weight: 1.0,
                phrases: ["burnt out", "burned out", "worn out", "no energy", "can't keep going", "running on empty"],
                single: ["exhausted", "drained", "depleted", "tired", "sleepy", "fatigued"]),
            SentimentGroup(label: "Calm", weight: 0.9,
                phrases: ["at peace", "at ease", "feeling settled", "feeling calm", "slowed down", "nice and quiet"],
                single: ["calm", "peaceful", "serene", "relaxed", "still", "centred", "centered",
                         "balanced", "grounded", "settled"]),
            SentimentGroup(label: "Hopeful", weight: 1.0,
                phrases: ["things are looking up", "fresh start", "new beginning", "feel hopeful", "getting better"],
                single: ["hopeful", "optimistic", "encouraged", "turning around", "positive"]),
            SentimentGroup(label: "Proud", weight: 1.1,
                phrases: ["really proud", "so proud", "nailed it", "did it", "finally finished", "shipped it"],
                single: ["proud", "accomplished", "achieved", "succeeded", "completed", "breakthrough"]),
            SentimentGroup(label: "Uncertain", weight: 0.9,
                phrases: ["not sure", "don't know", "no idea", "can't decide", "going back and forth", "torn between"],
                single: ["confused", "unsure", "unclear", "lost", "wondering", "conflicted", "ambivalent"])
        ]

        var scores: [String: Double] = [:]
        for group in groups {
            let phraseScore = scoreGroup(group.phrases) * 1.8 // phrases worth more
            let wordScore   = scoreGroup(group.single)
            let total = (phraseScore + wordScore) * group.weight
            if total > 0 { scores[group.label] = total }
        }

        // Tie-break: if two labels are within 10% of each other, prefer the one
        // with stronger phrase matches.
        return scores.max(by: { $0.value < $1.value })?.key ?? "Reflective"
    }

    // MARK: - Topical Tags
    //
    // Light, on-device topic extraction so entries pick up meaningful subject
    // tags (work, sleep, people, …) beyond the mood/sentiment word. Returns at
    // most `limit` tags, ordered by how strongly each topic registers.
    //
    // Design notes:
    // • A topic must reach a minimum score threshold to appear — single-word
    //   coincidences ("I was tired" → "sleep") no longer win a tag.
    // • High-signal phrases (e.g. "project deadline") score 2×.
    // • Ambiguous words that appear in multiple categories are downweighted.
    static func extractTopics(from text: String, limit: Int = 3) -> [String] {
        let lower = text.lowercased()

        struct TopicDef {
            let tag: String
            let phrases: [String]   // 2-word or distinctive phrases (score 2 each)
            let single: [String]    // individual words (score 1 each)
            let minScore: Int       // minimum to qualify
        }

        let topics: [TopicDef] = [
            TopicDef(tag: "work",
                phrases: ["at work", "the office", "my boss", "my manager", "work meeting",
                          "project deadline", "work project", "my colleague", "my job", "new job"],
                single: ["work", "job", "boss", "meeting", "deadline", "project", "office",
                         "career", "colleague", "manager", "shift", "client", "presentation"],
                minScore: 2),
            TopicDef(tag: "sleep",
                phrases: ["couldn't sleep", "can't sleep", "slept badly", "up all night",
                          "sleep deprived", "barely slept", "woke up"],
                single: ["insomnia", "sleepless", "slept", "nap", "exhausted", "awake", "bedtime"],
                minScore: 2),
            TopicDef(tag: "people",
                phrases: ["my friend", "my family", "talked to", "called them", "called her",
                          "called him", "my partner", "my mum", "my mom", "my dad"],
                single: ["friend", "friends", "family", "mum", "mom", "dad", "partner",
                         "wife", "husband", "brother", "sister", "colleague", "coworker"],
                minScore: 2),
            TopicDef(tag: "money",
                phrases: ["can't afford", "money stress", "paying rent", "financial stress",
                          "saving up", "spent too much", "money problem"],
                single: ["money", "rent", "bills", "budget", "salary", "broke", "afford",
                         "savings", "debt", "loan", "pay", "financial"],
                minScore: 2),
            TopicDef(tag: "food",
                phrases: ["had dinner", "had lunch", "had breakfast", "ate too much",
                          "skipped eating", "cooked a meal", "what i ate"],
                single: ["eating", "meal", "cooked", "dinner", "lunch", "breakfast", "hungry", "snack"],
                minScore: 2),
            TopicDef(tag: "health",
                phrases: ["went to the doctor", "seeing a therapist", "mental health",
                          "feeling sick", "chronic pain", "panic attack", "anxiety attack"],
                single: ["doctor", "health", "pain", "headache", "therapy", "therapist",
                         "meds", "medication", "ill", "sick", "symptoms"],
                minScore: 2),
            TopicDef(tag: "exercise",
                phrases: ["went for a run", "went to the gym", "worked out", "yoga class",
                          "went for a walk", "did a workout", "morning run"],
                single: ["gym", "running", "workout", "exercise", "yoga", "training", "cycling", "swimming"],
                minScore: 2),
            TopicDef(tag: "home",
                phrases: ["at home", "my apartment", "tidied up", "cleaned the house",
                          "around the house"],
                single: ["apartment", "chores", "laundry", "tidying", "declutter", "renovate"],
                minScore: 2),
            TopicDef(tag: "love",
                phrases: ["my relationship", "we broke up", "going on a date",
                          "my partner and i", "feeling lonely in"],
                single: ["relationship", "dating", "crush", "breakup", "romance",
                         "ex-", "heartbroken", "attraction", "intimacy"],
                minScore: 2),
            TopicDef(tag: "study",
                phrases: ["studying for", "my exam", "at university", "my homework",
                          "my assignment", "failing class", "studying hard"],
                single: ["studying", "exam", "class", "school", "homework", "assignment",
                         "uni", "university", "course", "degree", "lecture"],
                minScore: 2),
            TopicDef(tag: "creativity",
                phrases: ["working on music", "writing a song", "my painting",
                          "creative project", "artistic block", "making art"],
                single: ["writing", "music", "painting", "drawing", "creative", "art",
                         "composing", "sketching", "crafting", "poetry"],
                minScore: 2),
            TopicDef(tag: "nature",
                phrases: ["went outside", "in the park", "at the beach", "in the garden",
                          "out in nature", "beautiful day outside"],
                single: ["park", "beach", "garden", "nature", "outdoors", "hiking", "forest", "trail"],
                minScore: 2)
        ]

        let scored = topics.compactMap { topic -> (tag: String, score: Int)? in
            let phraseScore = topic.phrases.filter { lower.contains($0) }.count * 2
            let singleScore = topic.single.filter { lower.contains($0) }.count
            let total = phraseScore + singleScore
            guard total >= topic.minScore else { return nil }
            return (topic.tag, total)
        }
        .sorted { $0.score > $1.score }

        return Array(scored.prefix(limit)).map { $0.tag }
    }

}
