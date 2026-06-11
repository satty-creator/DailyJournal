//
//  MemoryProfileService.swift
//  DailyJournal
//
//  Composes the MemoryProfile from the user's entries + pattern callbacks,
//  deterministically and on-device, then caches it (and its prompt context) to
//  UserDefaults so:
//    • the Echoes feed can show it instantly, and
//    • the AI prompt builders can read a fresh `cachedPromptContext()` with no
//      extra plumbing through every call site.
//
//  Nothing here blocks the UI: callers await build() when convenient (e.g. the
//  Echoes tab on load), and the cache is what the synchronous AI paths read.
//

import Foundation
import FirebaseAuth

final class MemoryProfileService {

    static let shared = MemoryProfileService()
    private init() {}

    private let journal   = JournalService()
    private let callbacks = PatternCallbackService()
    private let defaults  = UserDefaults.standard

    // MARK: - Build

    /// Fetches entries + callbacks, composes the profile, caches it, returns it.
    @discardableResult
    func build(for userId: String) async -> MemoryProfile {
        async let entriesTask = (try? await journal.fetchAllEntries(for: userId)) ?? []
        async let callbackTask = (try? await callbacks.fetchAll(for: userId)) ?? []
        let entries  = await entriesTask
        let cbs      = await callbackTask

        let profile = Self.compose(entries: entries, callbacks: cbs)
        cache(profile, for: userId)
        return profile
    }

    // MARK: - Compose (pure)

    static func compose(entries: [JournalEntry], callbacks: [PatternCallback]) -> MemoryProfile {
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

        // ── Recurring entities (pattern-callback subjects + frequent tags) ─
        var entities: [String] = []
        var seen = Set<String>()
        let add: (String) -> Void = { raw in
            let key = raw.lowercased()
            guard !raw.isEmpty, !seen.contains(key) else { return }
            seen.insert(key); entities.append(raw)
        }
        for cb in callbacks { if let e = cb.entity { add(e) } }
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

        return MemoryProfile(
            recurringThemes:   Array(themes),
            recurringEntities: entities,
            topMoodRaw:        topMood?.rawValue,
            totalEntries:      entries.count,
            activeDaysLast30:  activeLast30,
            activeDaysThisWeek: activeWeek,
            firstEntryDate:    first,
            lastEntryDate:     last,
            generatedAt:       now
        )
    }

    // MARK: - Cache

    private func profileKey(_ uid: String) -> String { "memoryProfile-\(uid)" }
    private func ctxKey(_ uid: String) -> String { "memoryPromptCtx-\(uid)" }

    private func cache(_ profile: MemoryProfile, for userId: String) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: profileKey(userId))
        }
        defaults.set(profile.promptContext(), forKey: ctxKey(userId))
    }

    func cachedProfile(for userId: String) -> MemoryProfile? {
        guard let data = defaults.data(forKey: profileKey(userId)),
              let profile = try? JSONDecoder().decode(MemoryProfile.self, from: data)
        else { return nil }
        return profile
    }

    /// The cached prompt-context block for the signed-in user (or "").
    /// Safe to call from any thread — UserDefaults reads are thread-safe and this
    /// is what the synchronous AI prompt builders use.
    func cachedPromptContext() -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "" }
        return defaults.string(forKey: ctxKey(uid)) ?? ""
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
