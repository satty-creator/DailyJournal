//
//  PatternDetectionService.swift
//  DailyJournal
//
//  What remains here after the Pattern Callback system was cut (superseded by
//  Pattern Hypothesis / Mirror — see PATTERNS_MERGE_PLAN.md): the crisis-corpus
//  scan that used to gate callback creation. HomeViewModel still needs this —
//  it is the one thing in this file that must not go — so it survives as its
//  own small responsibility instead of a side effect of pattern generation.
//
//  Runs on Home load, throttled to ~once/20h (PatternSettings.shouldRunDetection).
//  If PatternSafety finds a crisis signal anywhere in the recent window, reports
//  .safetyRouted so the caller shows the soft resource card
//  (PatternResourceCardView). Never calls the model, never throws into the UI.
//

import Foundation

enum CrisisScanOutcome {
    case clear
    case safetyRouted
    case skipped
}

final class PatternDetectionService {

    static let shared = PatternDetectionService()
    private init() {}

    private let journalService = JournalService()
    private let windowDays = 60

    /// Runs the scan if (and only if) the throttle allows. Sets the throttle
    /// stamp whenever it actually runs, regardless of outcome.
    func detectIfNeeded(for userId: String) async -> CrisisScanOutcome {
        let settings = PatternSettings(userId: userId)
        guard settings.shouldRunDetection else { return .skipped }

        let all = (try? await journalService.fetchAllEntries(for: userId)) ?? []
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 86400)
        let window = all.filter { $0.createdAt >= cutoff }
        guard !window.isEmpty else { return .skipped }

        settings.lastDetection = Date()

        if PatternSafety.corpusHasCrisisSignal(window.map(\.content)) {
            return .safetyRouted
        }
        return .clear
    }
}
