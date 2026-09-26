//
//  MemoryProfileService.swift
//  DailyJournal
//
//  Composes the MemoryProfile from the user's entries, deterministically and
//  on-device, then caches it (and its prompt context) to UserDefaults so:
//    • the Echoes feed can show it instantly, and
//    • the AI prompt builders can read a fresh `cachedPromptContext()` with no
//      extra plumbing through every call site.
//
//  Nothing here blocks the UI: callers await build() when convenient (e.g. the
//  Echoes tab on load), and the cache is what the synchronous AI paths read.
//
//  Used to also pull recurring entities from Pattern Callbacks; that system was
//  cut (see PATTERNS_MERGE_PLAN.md), so entities now come from tags alone.
//

import Foundation
import FirebaseAuth

final class MemoryProfileService {

    static let shared = MemoryProfileService()
    private init() {}

    private let journal   = JournalService()
    private let defaults  = UserDefaults.standard

    // MARK: - Build

    /// Fetches entries + recent events, composes the profile, caches it, returns it.
    ///
    /// Debounced because `load()` on the Today tab fires this on appear, on
    /// pull-to-refresh and after every entry save — often within seconds of each
    /// other — and each run reads the entire entry corpus (`fetchAllEntries` is
    /// unbounded, kept that way for this service). A profile up to a minute stale
    /// is harmless to all six of its consumers; re-reading every entry three
    /// times in ten seconds is not free.
    @discardableResult
    func build(for userId: String, force: Bool = false) async -> MemoryProfile {
        if !force,
           let cached = cachedProfile(for: userId),
           Date().timeIntervalSince(cached.generatedAt) < Self.minRebuildInterval {
            return cached
        }
        async let entriesTask = (try? await journal.fetchAllEntries(for: userId)) ?? []
        async let eventsTask = EventService.shared.fetchRecent(for: userId, limit: 20)
        let entries = await entriesTask
        let events  = await eventsTask
        let profile = Self.compose(entries: entries, events: events)
            .removing(suppressedKeys(for: userId))
        cache(profile, for: userId)
        return profile
    }

    private static let minRebuildInterval: TimeInterval = 60

    // MARK: - Compose (pure)

    static func compose(entries: [JournalEntry], events: [JournalEvent] = []) -> MemoryProfile {
        guard !entries.isEmpty else { return .empty }

        let cal = Calendar.current
        let now = Date()
        let cutoff30 = cal.date(byAdding: .day, value: -30, to: now)!
        let cutoff7  = cal.date(byAdding: .day, value: -7,  to: now)!

        // ── Cadence ──────────────────────────────────────────────────────
        let days: (Date) -> Set<Date> = { since in
            Set(entries.filter { $0.createdAt >= since }
                .map { cal.startOfDay(for: $0.createdAt) })
        }
        let activeLast30 = days(cutoff30).count
        let activeWeek   = days(cutoff7).count
        let first = entries.map(\.createdAt).min()
        let last  = entries.map(\.createdAt).max()

        // ── Recurring themes (entries mentioning a word, stop-words removed) ──
        // Counted once per entry: the number is rendered into every AI prompt as
        // "work (in 12 entries)", and a reader — human or model — takes that to
        // mean twelve occasions, not one long entry that said "work" twelve times.
        var wordCounts: [String: Int] = [:]
        for entry in entries {
            let words = Set(entry.content.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 && !stopWords.contains($0) })
            for w in words { wordCounts[w, default: 0] += 1 }
        }
        let themes = wordCounts
            .filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { MemoryProfile.Theme(word: $0.key, count: $0.value) }

        // ── Recurring entities (frequent tags) ──────────────────────────────
        var entities: [String] = []
        var seen = Set<String>()
        let add: (String) -> Void = { raw in
            let key = raw.lowercased()
            guard !raw.isEmpty, !seen.contains(key) else { return }
            seen.insert(key); entities.append(raw)
        }
        var tagCounts: [String: Int] = [:]
        for entry in entries { for t in entry.tags { tagCounts[t, default: 0] += 1 } }
        for (tag, count) in tagCounts.sorted(by: { $0.value > $1.value }) where count >= 2 {
            add(tag)
        }
        entities = Array(entities.prefix(6))

        // ── Top mood (last 30 days, fall back to all-time) ─────────────────
        let moodCount: ([JournalEntry]) -> [Mood: Int] = { list in
            var c: [Mood: Int] = [:]
            for e in list { if let m = e.mood { c[m, default: 0] += 1 } }
            return c
        }
        var moods = moodCount(entries.filter { $0.createdAt >= cutoff30 })
        if moods.isEmpty { moods = moodCount(entries) }
        // "Mood lately tends toward…" off a single logged mood is not a tendency,
        // and the prompt has no way to tell one reading from thirty.
        let topMood = moods.values.reduce(0, +) >= 3
            ? moods.max { $0.value < $1.value }?.key
            : nil

        // ── Emotional vocabulary ─────────────────────────────────────────────
        // The word the person reaches for straight after an emotion anchor.
        // "so " and "been " used to be anchors: neither is first-person nor
        // emotional, so "been reading" and "also tired" both qualified — and the
        // result is injected into every prompt as the vocabulary to mirror back.
        let standardEmotions = Set(LocalAI.sentimentLabels.map { $0.lowercased() }
            + ["okay", "fine", "good", "bad", "weird", "strange", "better", "worse"])
        let emotionAnchors = ["feel ", "felt ", "feeling ", "i'm ", "i am "]
        // Present participles that follow "i'm" far more often than a feeling does.
        let notFeelings: Set<String> = ["going", "doing", "getting", "trying", "looking",
                                        "working", "thinking", "talking", "making", "taking",
                                        "coming", "having", "writing", "reading", "sitting",
                                        "waiting", "supposed", "meeting", "starting"]
        var emoWordCounts: [String: Int] = [:]
        for entry in entries {
            let lower = entry.content.lowercased()
            for anchor in emotionAnchors {
                var searchRange = lower.startIndex..<lower.endIndex
                while let anchorRange = lower.range(of: anchor, range: searchRange) {
                    searchRange = anchorRange.upperBound..<lower.endIndex

                    // The anchor has to start its own word — unanchored matching
                    // found "so " inside "also " and "i am " inside "hi ambition".
                    let startsWord = anchorRange.lowerBound == lower.startIndex
                        || !lower[lower.index(before: anchorRange.lowerBound)].isLetter
                    guard startsWord else { continue }

                    // "I don't feel numb" is not evidence for "numb".
                    guard !isNegated(String(lower[..<anchorRange.lowerBound].suffix(24))) else { continue }

                    guard let word = lower[anchorRange.upperBound...].prefix(20)
                            .components(separatedBy: CharacterSet.alphanumerics.inverted).first,
                          word.count >= 4,
                          !standardEmotions.contains(word),
                          !stopWords.contains(word),
                          !notFeelings.contains(word)
                    else { continue }
                    emoWordCounts[word, default: 0] += 1
                }
            }
        }
        let emotionalVocab = emoWordCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { MemoryProfile.Theme(word: $0.key, count: $0.value) }

        // ── Coping patterns ──────────────────────────────────────────────────
        // "[X] helps" / "[X] makes it worse", tallied across entries. This is the
        // weakest inference in the profile and it used to be the least guarded:
        // an unanchored "help" matched inside "helpless", negation was invisible,
        // one sentence ever was enough, and the negative branch threw away the
        // phrase and asserted "makes it worse" — so "therapy doesn't help" was
        // stored as a stronger claim than the person made. Four rules now:
        // hurt phrases are tested first (every one contains a help word),
        // matching is word-boundary, a negated or wishful clause is skipped
        // rather than guessed at, and the person's own phrase is what is kept.
        var copingTallies: [String: (phrase: String, count: Int)] = [:]
        let helpVerbs = ["help", "helps", "helped", "calms", "calmed", "eases", "eased"]
        let hurtPhrases = ["makes it worse", "made it worse", "makes things worse",
                           "makes me worse", "doesn't help", "does not help",
                           "didn't help", "did not help", "never helps", "never helped"]
        for entry in entries {
            for sentence in entry.content.components(separatedBy: CharacterSet(charactersIn: ".!?\n")) {
                for clause in Self.clauses(of: sentence) {
                    let lower = clause.lowercased().trimmingCharacters(in: .whitespaces)
                    guard !lower.isEmpty else { continue }

                    var hit: (phrase: String, range: Range<String.Index>, negative: Bool)?
                    for phrase in hurtPhrases {
                        if let r = Self.rangeOfWord(phrase, in: lower) {
                            hit = (phrase, r, true); break
                        }
                    }
                    if hit == nil {
                        for verb in helpVerbs {
                            if let r = Self.rangeOfWord(verb, in: lower) {
                                hit = (verb, r, false); break
                            }
                        }
                    }
                    guard let found = hit else { continue }

                    let before = String(lower[..<found.range.lowerBound])
                    // "walking never helped", "I wish walking helped" — neither is
                    // evidence that walking helps. Silence beats a wrong claim.
                    if !found.negative && Self.isNegated(before) { continue }

                    let subject = before
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty && !stopWords.contains($0) }
                        .suffix(3).joined(separator: " ")
                    guard subject.count >= 3 else { continue }

                    let key = subject + (found.negative ? "_neg" : "")
                    if copingTallies[key] != nil {
                        copingTallies[key]!.count += 1
                    } else {
                        copingTallies[key] = ("\(subject) \(found.phrase)", 1)
                    }
                }
            }
        }
        // Two occasions minimum, matching the vocabulary threshold. One sentence,
        // once, is not something to carry into every prompt for months.
        let copingSignals = copingTallies.values
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .map { MemoryProfile.Signal(text: $0.phrase, count: $0.count) }

        // ── Notable moments (from JournalEvent, not from entries) ──────────
        // Top 3 by salience — a concrete outcome and a named need beat a bare
        // situation. Rendered as "situation → outcome" (or "situation → need
        // was <need>" when there's no outcome yet) so it reads as one specific
        // remembered thing, not another aggregate.
        let notableMoments = events
            .sorted { $0.salience > $1.salience }
            .prefix(3)
            .map { event -> String in
                if let outcome = event.outcome, !outcome.isEmpty {
                    return "\(event.situation) → \(outcome)"
                }
                if let need = event.need, !need.isEmpty {
                    return "\(event.situation) — what they needed: \(need)"
                }
                return event.situation
            }

        return MemoryProfile(
            recurringThemes:    Array(themes),
            recurringEntities:  entities,
            emotionalVocabulary: Array(emotionalVocab),
            copingPatterns:     Array(copingSignals.prefix(6)),
            notableMoments:     Array(notableMoments),
            topMoodRaw:         topMood?.rawValue,
            totalEntries:       entries.count,
            activeDaysLast30:   activeLast30,
            activeDaysThisWeek: activeWeek,
            firstEntryDate:     first,
            lastEntryDate:      last,
            generatedAt:        now
        )
    }

    // MARK: - Cache

    private func profileKey(_ uid: String) -> String { "memoryProfile-\(uid)" }
    private func ctxKey(_ uid: String) -> String { "memoryPromptCtx-\(uid)" }
    private func suppressedKey(_ uid: String) -> String { "memorySuppressed-\(uid)" }

    private func cache(_ profile: MemoryProfile, for userId: String) {
        if let data = try? JSONEncoder().encode(profile) {
            KeychainHelper.save(data, forKey: profileKey(userId))
        }
        defaults.set(profile.promptContext(), forKey: ctxKey(userId))
    }

    func cachedProfile(for userId: String) -> MemoryProfile? {
        guard let data = KeychainHelper.load(forKey: profileKey(userId)),
              let profile = try? JSONDecoder().decode(MemoryProfile.self, from: data)
        else { return nil }
        return profile
    }

    // MARK: - Forgetting

    /// `MemoryProfile.Item.id`s the person has removed. Kept separately from the
    /// cached profile so it survives the rebuild that immediately follows.
    func suppressedKeys(for userId: String) -> Set<String> {
        Set(defaults.stringArray(forKey: suppressedKey(userId)) ?? [])
    }

    /// Removes one item and rewrites the cache straight away, so the next prompt
    /// built — which reads the cache synchronously — is already without it.
    func forget(_ item: MemoryProfile.Item, for userId: String) {
        var keys = suppressedKeys(for: userId)
        keys.insert(item.id)
        defaults.set(Array(keys), forKey: suppressedKey(userId))
        if let profile = cachedProfile(for: userId) {
            cache(profile.removing(keys), for: userId)
        }
    }

    func restoreForgotten(for userId: String) {
        defaults.removeObject(forKey: suppressedKey(userId))
    }

    /// Sign-out and account deletion both left the profile and its rendered
    /// prompt block on the device — a digest of someone's journal outliving the
    /// session it belongs to.
    func clearCache(for userId: String) {
        KeychainHelper.delete(forKey: profileKey(userId))
        defaults.removeObject(forKey: ctxKey(userId))
        defaults.removeObject(forKey: suppressedKey(userId))
    }

    /// The cached prompt-context block for the signed-in user (or ""), with
    /// `SpilrVoice.intentContext()` (the onboarding goals/tone the person
    /// chose for themselves — Spilr Redesign 2a) appended. Every AI prompt
    /// builder in the app already ends with a call to this function, so
    /// folding intent in here — rather than adding it at each of those call
    /// sites individually — is what makes it genuinely "shape every prompt"
    /// rather than only the ones someone remembered to update.
    /// Safe to call from any thread — UserDefaults reads are thread-safe and this
    /// is what the synchronous AI prompt builders use.
    func cachedPromptContext() -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "" }
        let memory = defaults.string(forKey: ctxKey(uid)) ?? ""
        return memory + SpilrVoice.intentContext()
    }

    /// A short comma-joined list of the person's already-recurring themes +
    /// names/places, for seeding THEME echo extraction. "" until a profile exists.
    func cachedRecurrenceSeed() -> String {
        guard let uid = Auth.auth().currentUser?.uid,
              let profile = cachedProfile(for: uid) else { return "" }
        let themeWords = profile.recurringThemes.prefix(6).map { $0.word }
        let combined = Array((themeWords + profile.recurringEntities).prefix(8))
        return combined.joined(separator: ", ")
    }

    // MARK: - Text helpers

    /// `range(of:)` with word boundaries on both ends. Plain `contains("help")`
    /// is true of "helpless", "unhelpful" and "helpfully", which is how
    /// "I felt helpless after the call" became a POSITIVE coping signal.
    private static func rangeOfWord(_ phrase: String, in haystack: String) -> Range<String.Index>? {
        var search = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: phrase, range: search) {
            let openBefore = r.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: r.lowerBound)].isLetter
            let openAfter = r.upperBound == haystack.endIndex
                || !haystack[r.upperBound].isLetter
            if openBefore && openAfter { return r }
            guard r.upperBound < haystack.endIndex else { return nil }
            search = r.upperBound..<haystack.endIndex
        }
        return nil
    }

    /// Apostrophes are stripped rather than split on, so "don't" is tested as
    /// "dont" — splitting on non-alphanumerics turns it into "don" + "t", and
    /// neither half is a negation marker.
    private static func isNegated(_ text: String) -> Bool {
        let squashed = text.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        return squashed.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains { negationMarkers.contains($0) }
    }

    private static let negationMarkers: Set<String> = [
        "not", "never", "no", "none", "hardly", "barely", "rarely", "seldom",
        "wish", "wished", "wishing", "dont", "doesnt", "didnt", "wont", "wouldnt",
        "cant", "cannot", "couldnt", "isnt", "wasnt", "arent", "werent", "nothing"
    ]

    /// A subject taken as "the last three words before the verb" walks straight
    /// across a clause boundary: "I called mum and a long walk helped" gives
    /// "mum long walk". Splitting first keeps the subject inside its own clause.
    private static func clauses(of sentence: String) -> [String] {
        sentence.components(separatedBy: CharacterSet(charactersIn: ",;:"))
            .flatMap { $0.components(separatedBy: " and ") }
            .flatMap { $0.components(separatedBy: " but ") }
            .flatMap { $0.components(separatedBy: " so ") }
            .flatMap { $0.components(separatedBy: " because ") }
    }

    // MARK: - Stop words (shared with the Patterns word cloud heuristic)

    private static let stopWords: Set<String> = [
        "the","a","an","and","or","but","in","on","at","to","for","of","with","i","is","it","my",
        "me","was","be","have","had","that","this","are","not","do","did","so","as","we","he","she",
        "they","you","just","can","will","would","could","should","what","when","how","why","been",
        "from","all","by","if","about","up","out","like","his","her","its","their","our","your","im",
        "dont","cant","wont","feel","think","know","get","got","go","went","still","than","more",
        "really","very","too","even","then","there","here","also","back","time","way","some","into",
        "over","after","before","because","being","were","does","much","many","them","off","only"
    ]
}
