//
//  ReadSettings.swift
//  DailyJournal
//
//  On-device controls + lightweight training signals for "Today's Read".
//  All UserDefaults, namespaced by user id — same approach as PatternSettings.
//  Keeping it local means the feedback loop recalibrates the LOCAL ReadEngine
//  immediately and works offline; the server generator reads the same signals
//  back on its next overnight pass via the persisted feedback on each read doc.
//

import Foundation

/// Per-device store for the Read feedback engine. The three feedback rows on a
/// revealed read all funnel into here:
///
///   • "felt true"  → positive weight multiplier on the read's source_pattern_ids
///   • "too sharp"  → steps `sharpnessPreference` one gradient gentler
///   • "not me"     → appends a rejected read id + classification code to history
struct ReadSettings {

    let userId: String

    private var defaults: UserDefaults { .standard }
    private func key(_ name: String) -> String { "read_\(name)_\(userId)" }

    init(userId: String) { self.userId = userId }

    // MARK: - Sharpness preference

    /// The user's current "how hard should it hit?" dial. Defaults to `.direct`.
    /// The local engine reads this to pick a tone; the server generator receives
    /// it as `tone_preference`.
    var sharpnessPreference: ReadSharpness {
        get { ReadSharpness(rawValue: defaults.string(forKey: key("sharpness")) ?? "") ?? .direct }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key("sharpness")) }
    }

    /// "too sharp" loop: drop one gradient (spicy → direct → soft). No-op at floor.
    /// Returns the new level so callers can show the right confirmation copy.
    @discardableResult
    nonmutating func softenSharpness() -> ReadSharpness {
        let next = sharpnessPreference.softer
        sharpnessPreference = next
        return next
    }

    // MARK: - Positive weights ("felt true" / "more like this")

    /// Pattern ids the user has rewarded. Stored as a multiplier map so a pattern
    /// confirmed repeatedly keeps climbing (capped) and the engine can prefer it.
    var patternWeights: [String: Double] {
        get { (defaults.dictionary(forKey: key("weights")) as? [String: Double]) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: key("weights")) }
    }

    /// Tethers a positive multiplier to every source pattern behind a read that
    /// "felt true". Each affirmation adds +0.25, capped at 2.0.
    nonmutating func reward(patternIds: [String]) {
        guard !patternIds.isEmpty else { return }
        var w = patternWeights
        for id in patternIds {
            w[id] = min((w[id] ?? 1.0) + 0.25, 2.0)
        }
        patternWeights = w
    }

    func weight(for patternId: String) -> Double { patternWeights[patternId] ?? 1.0 }

    // MARK: - Rejection history ("not me")

    /// One persisted rejection: which read, classified how, and when. The engine
    /// uses the most recent codes to avoid repeating the same failure mode.
    struct Rejection: Codable {
        let readId: String
        let code: String
        let at: Date
    }

    var rejections: [Rejection] {
        get {
            guard let raw = defaults.data(forKey: key("rejections")),
                  let decoded = try? JSONDecoder().decode([Rejection].self, from: raw)
            else { return [] }
            return decoded
        }
        nonmutating set {
            // Keep only the last 20 — this is a steering signal, not an archive.
            let trimmed = Array(newValue.suffix(20))
            if let data = try? JSONEncoder().encode(trimmed) {
                defaults.set(data, forKey: key("rejections"))
            }
        }
    }

    nonmutating func recordRejection(readId: String, code: ReadRejectionCode) {
        var all = rejections
        all.append(Rejection(readId: readId, code: code.rawValue, at: Date()))
        rejections = all
    }

    /// The rejection codes seen recently, most frequent first — fed to the engine
    /// as soft "don't do this" guidance.
    func recentRejectionCodes(limit: Int = 5) -> [ReadRejectionCode] {
        let counts = Dictionary(grouping: rejections.suffix(12), by: { $0.code })
            .mapValues { $0.count }
        return counts
            .sorted { $0.value > $1.value }
            .compactMap { ReadRejectionCode(rawValue: $0.key) }
            .prefix(limit)
            .map { $0 }
    }
}
