//
//  LocalAI.swift
//  DailyJournal
//
//  Local NLP helpers — sentiment, summary bullets, and the daily prompts bank.
//  Replace with a real API call (Claude, OpenAI) when ready.
//

import Foundation

enum LocalAI {

    // MARK: - Daily Prompts Bank
    static let prompts: [String] = [
        "How are you, actually?",
        "What's been taking up the most space in your head today?",
        "What are you pretending not to know?",
        "Name one thing that felt like resistance today.",
        "What do you need that you haven't asked for?",
        "What would you tell a close friend in your exact situation right now?",
        "What went unnoticed today that deserved more attention?",
        "What are you doing out of obligation rather than choice?",
        "What would make tomorrow feel meaningfully different from today?",
        "Who showed up for you this week, even in a small way?",
        "What emotion have you been carrying around all day without naming it?",
        "What's the thing you keep starting but not finishing?",
        "If today had a weather forecast, what would it be?",
        "What are you most afraid to admit — even to yourself?",
        "What would you need to let go of to feel lighter?",
        "Who's voice is loudest in your head when you imagine failing?",
        "What small thing brought you unexpected comfort today?",
        "What's a belief you're holding that might not actually be true?",
        "What did your body try to tell you today that you ignored?",
        "What are you tolerating that you don't have to?",
        "What would the most honest version of you say right now?",
        "What are you proud of that you haven't said out loud yet?",
        "If this week were a chapter in a book, what would the title be?",
        "What conversation have you been avoiding?",
        "What do you keep returning to, mentally, like a bruise you keep pressing?",
        "What's something that used to feel hard that now feels easy?",
        "Where are you being too hard on yourself?",
        "What are you genuinely curious about right now?",
        "What feels unfinished — not in a task sense, but emotionally?",
        "What's one thing you did today that future-you will be glad about?"
    ]

    static func todayPrompt() -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return prompts[day % prompts.count]
    }

    // MARK: - Mood-based prompt
    //
    // When a user logs a mood and is redirected into the editor, the starter
    // should meet that mood rather than being generic. Returns one prompt tuned
    // to the mood's valence.
    static func moodPrompt(for mood: Mood) -> String {
        let options: [String]
        switch mood {
        case .amazing:
            options = [
                "Something's clearly good today — what is it, and what made it land?",
                "What went right today that you want to remember later?",
                "Where did the good feeling actually come from?"
            ]
        case .good:
            options = [
                "What gave today its lift — even a small thing?",
                "What's one good moment worth keeping from today?",
                "What made today feel okay-to-good?"
            ]
        case .neutral:
            options = [
                "Today felt even — what's underneath the ordinary?",
                "Nothing loud today. What quietly mattered anyway?",
                "If today felt flat, what were you actually doing?"
            ]
        case .bad:
            options = [
                "Something weighed on today — what was it? Start anywhere.",
                "What made today harder than you'd have liked?",
                "What's the heaviest thing about today, said plainly?"
            ]
        case .terrible:
            options = [
                "Today was rough. What happened — you don't have to make it tidy.",
                "What hurt most today? One sentence is enough.",
                "What do you most need to get off your chest about today?"
            ]
        }
        return options[Int.random(in: 0..<options.count)]
    }

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

    static func detectSentiment(from text: String) -> String {
        let lower = text.lowercased()

        struct SentimentGroup {
            let label: String
            let keywords: [String]
        }

        let groups: [SentimentGroup] = [
            SentimentGroup(label: "Anxious",    keywords: ["anxious", "anxiety", "worried", "worry", "stress", "stressed", "nervous", "overwhelm", "overwhelmed", "panic", "racing", "dread", "scared", "fear", "afraid", "terrified", "on edge"]),
            SentimentGroup(label: "Excited",    keywords: ["excited", "thrilled", "amazing", "fantastic", "elated", "joy", "joyful", "ecstatic", "pumped", "stoked", "can't wait", "looking forward", "buzzing"]),
            SentimentGroup(label: "Happy",      keywords: ["happy", "great", "wonderful", "good day", "content", "glad", "pleased", "smile", "smiled", "laugh", "laughed", "fun", "enjoyed", "lovely"]),
            SentimentGroup(label: "Grateful",   keywords: ["grateful", "thankful", "gratitude", "blessed", "appreciate", "appreciated", "lucky"]),
            SentimentGroup(label: "Sad",        keywords: ["sad", "crying", "cried", "tears", "grief", "grieving", "loss", "heartbreak", "heartbroken", "hurt", "devastated", "down", "empty", "blue"]),
            SentimentGroup(label: "Lonely",     keywords: ["lonely", "alone", "isolated", "left out", "missing", "miss ", "no one", "nobody"]),
            SentimentGroup(label: "Frustrated", keywords: ["frustrated", "annoyed", "irritated", "angry", "anger", "furious", "mad", "upset", "fed up", "sick of", "resent", "rage"]),
            SentimentGroup(label: "Tired",      keywords: ["tired", "exhausted", "drained", "burnt out", "burned out", "worn out", "no energy", "sleepy", "depleted"]),
            SentimentGroup(label: "Calm",       keywords: ["calm", "peaceful", "serene", "relaxed", "quiet", "still", "centred", "centered", "balanced", "grounded", "at ease", "settled"]),
            SentimentGroup(label: "Hopeful",    keywords: ["hopeful", "optimistic", "looking up", "better", "progress", "forward", "beginning", "fresh start", "things will"]),
            SentimentGroup(label: "Proud",      keywords: ["proud", "accomplished", "achieved", "nailed it", "did it", "finished", "shipped", "won"]),
            SentimentGroup(label: "Uncertain",  keywords: ["not sure", "don't know", "confused", "unsure", "unclear", "lost", "no idea", "maybe", "perhaps", "wondering", "torn", "conflicted"])
        ]

        var scores: [String: Int] = [:]
        for group in groups {
            let count = group.keywords.filter { lower.contains($0) }.count
            if count > 0 { scores[group.label] = count }
        }

        // Only fall back to "Reflective" when nothing emotional registers at all.
        return scores.max(by: { $0.value < $1.value })?.key ?? "Reflective"
    }

    // MARK: - Topical Tags
    //
    // Light, on-device topic extraction so entries pick up meaningful subject
    // tags (work, sleep, people, …) beyond the mood/sentiment word. Returns at
    // most `limit` tags, ordered by how strongly each topic registers.
    static func extractTopics(from text: String, limit: Int = 3) -> [String] {
        let lower = text.lowercased()

        let topics: [(tag: String, keywords: [String])] = [
            ("work",     ["work", "job", "boss", "meeting", "deadline", "project", "office", "career", "colleague", "manager", "shift", "client"]),
            ("sleep",    ["sleep", "slept", "tired", "insomnia", "nap", "rest", "bed", "exhausted", "awake"]),
            ("people",   ["friend", "friends", "family", "mum", "mom", "dad", "partner", "wife", "husband", "people", "conversation", "talked", "call", "called"]),
            ("money",    ["money", "rent", "bills", "budget", "salary", "spent", "broke", "afford", "savings", "pay"]),
            ("food",     ["food", "ate", "eating", "meal", "cooked", "dinner", "lunch", "breakfast", "hungry", "snack"]),
            ("health",   ["sick", "doctor", "health", "pain", "headache", "anxiety", "therapy", "meds", "ill"]),
            ("exercise", ["gym", "run", "ran", "running", "walk", "walked", "workout", "exercise", "yoga", "lifted", "training"]),
            ("home",     ["home", "house", "apartment", "clean", "chores", "laundry", "tidy", "room"]),
            ("love",     ["love", "relationship", "date", "dating", "crush", "breakup", "ex ", "romance"]),
            ("study",    ["study", "studying", "exam", "class", "school", "homework", "assignment", "uni", "university", "course"]),
            ("creativity", ["wrote", "writing", "music", "paint", "painting", "draw", "drawing", "create", "creative", "art"]),
            ("nature",   ["outside", "walk", "park", "beach", "garden", "sun", "rain", "weather", "nature", "sky"])
        ]

        let scored = topics
            .map { topic -> (tag: String, score: Int) in
                (topic.tag, topic.keywords.filter { lower.contains($0) }.count)
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }

        return Array(scored.prefix(limit)).map { $0.tag }
    }

    // MARK: - Summary Bullets
    /// Returns up to 3 short bullets that summarise the entry.
    /// This is intentionally simple local logic — replace with an LLM call for the real product.
    static func generateBullets(from text: String) -> [String] {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 20 }

        guard !sentences.isEmpty else { return [] }

        // Score sentences by emotional weight
        let emotionWords = Set(["feel", "feels", "feeling", "felt", "think", "thought", "want",
                                "need", "wish", "hope", "fear", "love", "hate", "miss", "worry",
                                "wonder", "realize", "realise", "know", "understand", "angry",
                                "sad", "happy", "excited", "scared", "tired", "frustrated", "proud"])

        let scored = sentences.map { s -> (sentence: String, score: Int) in
            let words = s.lowercased().split(separator: " ").map(String.init)
            let score = words.filter { emotionWords.contains($0) }.count
            return (s, score)
        }.sorted { $0.score > $1.score }

        return Array(scored.prefix(3)).map { s in
            // Trim to max 80 chars for display
            let trimmed = s.sentence
            return trimmed.count > 80 ? String(trimmed.prefix(77)) + "…" : trimmed
        }
    }

    // MARK: - Reflective Question
    static func generateQuestion(from text: String, sentiment: String) -> String {
        let questions: [String: [String]] = [
            "Anxious": [
                "What's the worst realistic outcome — and could you handle it?",
                "Whose voice is in your head when you imagine things going wrong?",
                "What would feel like enough to manage this?"
            ],
            "Sad": [
                "What do you need from someone right now — and have you asked?",
                "What would it mean to be gentle with yourself today?",
                "If this sadness could speak, what would it say?"
            ],
            "Frustrated": [
                "What expectation isn't being met — and is that expectation fair?",
                "What part of this is in your control?",
                "What would letting go of this actually feel like?"
            ],
            "Excited": [
                "What would it mean if this went better than you expected?",
                "What are you most afraid of losing if this goes well?",
                "Who needs to know you're excited about this?"
            ],
            "Happy": [
                "What made today different — can you make more of it?",
                "Who contributed to how you're feeling right now?",
                "What would you tell yourself on a harder day to remember this?"
            ],
            "Calm": [
                "What helped you arrive at this feeling?",
                "What would protect this calm if tomorrow gets harder?",
                "What can you appreciate about this moment?"
            ]
        ]

        let fallbacks = [
            "What would the most honest version of you add to this?",
            "What are you not saying here that matters?",
            "If you re-read this in a year, what would surprise you?"
        ]

        let options = questions[sentiment] ?? fallbacks
        return options[Int.random(in: 0..<options.count)]
    }
}
