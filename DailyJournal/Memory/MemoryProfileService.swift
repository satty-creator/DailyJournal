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
    @discardableResult
    func build(for userId: String) async -> MemoryProfile {
        async let entriesTask = (try? await journal.fetchAllEntries(for: userId)) ?? []
        async let eventsTask = EventService.shared.fetchRecent(for: userId, limit: 20)
        let entries = await entriesTask
        let events  = await eventsTask
        let profile = Self.compose(entries: entries, events: events)
        cache(profile, for: userId)
        return profile
    }

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

        // ── Recurring themes (word frequency, stop-words removed) ──────────
        var wordCounts: [String: Int] = [:]
        for entry in entries {
            let words = entry.content.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
            for w in words where w.count > 3 && !stopWords.contains(w) {
                wordCounts[w, default: 0] += 1
            }
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
        let topMood = moods.max { $0.value < $1.value }?.key

        // ── Emotional vocabulary ─────────────────────────────────────────────
        // Words the person uses for emotions that aren't in the standard sentiment
        // label set. We scan for words within a 5-word window of emotion anchors
        // ("feel", "felt", "feeling", "i'm", "so") and collect non-standard ones
        // that appear at least twice.
        let standardEmotions = Set(LocalAI.sentimentLabels.map { $0.lowercased() }
            + ["okay", "fine", "good", "bad", "weird", "strange", "better", "worse"])
        let emotionAnchors = ["feel ", "felt ", "feeling ", "i'm ", "i am ", "so ", "been "]
        var emoWordCounts: [String: Int] = [:]
        for entry in entries {
            let lower = entry.content.lowercased()
            for anchor in emotionAnchors {
                var searchRange = lower.startIndex..<lower.endIndex
                while let anchorRange = lower.range(of: anchor, range: searchRange) {
                    let afterAnchor = anchorRange.upperBound..<lower.endIndex
                    // Grab up to 5 chars (word boundary)
                    let slice = lower[afterAnchor].prefix(20)
                    if let word = slice.components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .first, word.count >= 4,
                       !standardEmotions.contains(word), !stopWords.contains(word) {
                        emoWordCounts[word, default: 0] += 1
                    }
                    searchRange = anchorRange.upperBound..<lower.endIndex
                }
            }
        }
        let emotionalVocab = emoWordCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { $0.key }

        // ── Coping patterns ──────────────────────────────────────────────────
        // Sentences containing "[X] help(s)/helped" or "[X] make(s) it worse/better"
        // or "[X] always/never helps" patterns. We extract the subject noun phrase.
        var copingSignals: [String] = []
        var seenCoping = Set<String>()
        let copingPatterns_help = ["help", "helps", "helped", "calms", "calmed", "eases", "eased"]
        let copingPatterns_hurt = ["makes it worse", "made it worse", "doesn't help", "never helps",
                                   "makes things worse", "makes me worse"]
        for entry in entries {
            let sentences = entry.content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            for sentence in sentences {
                let lower = sentence.lowercased().trimmingCharacters(in: .whitespaces)
                // Positive coping
                for pattern in copingPatterns_help {
                    if lower.contains(pattern) {
                        // Take the part before the verb as the subject (up to 4 words)
                        if let range = lower.range(of: pattern) {
                            let subject = String(lower[..<range.lowerBound])
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty && !stopWords.contains($0) }
                                .suffix(3).joined(separator: " ")
                            if subject.count >= 3 {
                                let signal = "\(subject) \(pattern)"
                                if !seenCoping.contains(subject) {
                                    seenCoping.insert(subject)
                                    copingSignals.append(signal)
                                }
                            }
                        }
                    }
                }
                // Negative coping
                for pattern in copingPatterns_hurt {
                    if lower.contains(pattern) {
                        if let range = lower.range(of: pattern) {
                            let subject = String(lower[..<range.lowerBound])
                                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                                .filter { !$0.isEmpty && !stopWords.contains($0) }
                                .suffix(3).joined(separator: " ")
                            if subject.count >= 3 {
                                let signal = "\(subject) makes it worse"
                                if !seenCoping.contains(subject + "_neg") {
                                    seenCoping.insert(subject + "_neg")
                                    copingSignals.append(signal)
                                }
                            }
                        }
                    }
                }
            }
        }

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
