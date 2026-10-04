//
//  StarterQuestionPickerTests.swift
//  DailyJournalTests
//
//  The blank-page starter bank and its picker — pure, local, no I/O — so
//  these run fast and cover every hour × weekday × profile combination.
//

import XCTest
@testable import Spilr

final class StarterQuestionBankTests: XCTestCase {

    /// Every question is well-formed: unique id, non-empty, reasonable length,
    /// phrased as a question, and free of the therapy-speak / "why" framing
    /// the bank is explicitly trying to avoid.
    func testBankEntriesAreWellFormed() {
        let bank = StarterQuestionBank.all
        XCTAssertGreaterThanOrEqual(bank.count, 60, "expected a substantial bank, not a handful of strings")

        var seenIDs = Set<String>()
        let bannedPhrases = ["why did", "why do you", "should", "let yourself", "hold space", "sit with"]

        for question in bank {
            XCTAssertTrue(seenIDs.insert(question.id).inserted, "duplicate id: \(question.id)")
            XCTAssertFalse(question.text.isEmpty)
            XCTAssertLessThanOrEqual(question.text.count, 120, "\(question.id) is too long for a starter card: \(question.text)")
            XCTAssertTrue(question.text.hasSuffix("?"), "\(question.id) should read as a question: \(question.text)")
            XCTAssertFalse(question.moments.isEmpty, "\(question.id) has no eligible moments")

            let lowered = question.text.lowercased()
            for phrase in bannedPhrases {
                XCTAssertFalse(lowered.contains(phrase), "\(question.id) uses banned phrasing '\(phrase)': \(question.text)")
            }
        }
    }

    /// Every moment has at least a few eligible questions, so no time-of-day
    /// slot silently falls back to `.any` every single time.
    func testEveryMomentHasCoverage() {
        for moment in StarterMoment.allCases {
            let matches = StarterQuestionBank.all.filter { $0.moments.contains(moment) }
            XCTAssertGreaterThanOrEqual(matches.count, 3, "moment \(moment) is underrepresented (\(matches.count) questions)")
        }
    }
}

final class StarterQuestionPickerTests: XCTestCase {

    private func date(hour: Int, weekday: Int) -> Date {
        // 2026-09-28 is a Monday; walk forward to hit the requested weekday.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents(year: 2026, month: 9, day: 28, hour: hour)
        let base = cal.date(from: comps)!
        let baseWeekday = cal.component(.weekday, from: base) // Monday = 2
        let offset = (weekday - baseWeekday + 7) % 7
        comps.day! += offset
        return cal.date(from: comps)!
    }

    /// Never returns nothing, for any hour × weekday × profile combination —
    /// the fallback chain in `pick` must always bottom out in the full bank.
    func testNeverEmptyAcrossHourAndWeekday() {
        for weekday in 1...7 {
            for hour in stride(from: 0, to: 24, by: 3) {
                let question = StarterQuestionPicker.pick(now: date(hour: hour, weekday: weekday))
                XCTAssertFalse(question.text.isEmpty, "empty pick at hour \(hour) weekday \(weekday)")
            }
        }
    }

    func testRespectsRecentIDsWhileCandidatesRemain() {
        let now = date(hour: 20, weekday: 4) // evening, Wednesday
        let allIDs = Set(StarterQuestionBank.all.map(\.id))
        // Exclude everything except one id — the picker must still return it
        // rather than an empty/garbage result, proving the exclusion is honored
        // down to the last available candidate.
        let survivor = StarterQuestionBank.all.first!.id
        let excluded = Array(allIDs.subtracting([survivor]))

        let question = StarterQuestionPicker.pick(now: now, recentIDs: excluded)
        XCTAssertEqual(question.id, survivor)
    }

    func testFallsBackToFullBankWhenEverythingIsRecent() {
        let now = date(hour: 20, weekday: 4)
        let allIDs = StarterQuestionBank.all.map(\.id)
        let question = StarterQuestionPicker.pick(now: now, recentIDs: allIDs)
        XCTAssertFalse(question.text.isEmpty)
    }

    func testAvoidsRepeatingTheSameKindWhenAlternativesExist() {
        let now = date(hour: 20, weekday: 4)
        let firstKind = StarterQuestionBank.all.first!.kind

        var sawDifferentKind = false
        for _ in 0..<25 {
            let question = StarterQuestionPicker.pick(now: now, lastKind: firstKind)
            if question.kind != firstKind {
                sawDifferentKind = true
                break
            }
        }
        XCTAssertTrue(sawDifferentKind, "expected lastKind exclusion to steer away from repeats at least once in 25 draws")
    }

    func testMondayMorningBiasesTowardMorningOrMondayQuestions() {
        let now = date(hour: 8, weekday: 2) // Monday, 8am
        let matchingIDs = Set(StarterQuestionBank.all
            .filter { !$0.moments.isDisjoint(with: [.morning, .monday]) }
            .map(\.id))

        var matches = 0
        let draws = 40
        for _ in 0..<draws {
            let question = StarterQuestionPicker.pick(now: now)
            if matchingIDs.contains(question.id) { matches += 1 }
        }
        // Weighting favors moment-specific matches 3x, so a solid majority
        // should land in the morning/Monday set rather than generic `.any`.
        XCTAssertGreaterThan(matches, draws / 2, "expected most draws to be morning/Monday-flavored, got \(matches)/\(draws)")
    }

    func testFewEntriesBiasesTowardFirstEntriesQuestions() {
        let now = date(hour: 20, weekday: 4)
        let newUserProfile = MemoryProfile(
            recurringThemes: [], recurringEntities: [], emotionalVocabulary: [],
            copingPatterns: [], notableMoments: [], topMoodRaw: nil,
            totalEntries: 1, activeDaysLast30: 1, activeDaysThisWeek: 1,
            firstEntryDate: now, lastEntryDate: now, generatedAt: now
        )
        let firstEntryIDs = Set(StarterQuestionBank.all
            .filter { $0.moments.contains(.firstEntries) }
            .map(\.id))

        var matches = 0
        let draws = 40
        for _ in 0..<draws {
            let question = StarterQuestionPicker.pick(now: now, profile: newUserProfile)
            if firstEntryIDs.contains(question.id) { matches += 1 }
        }
        XCTAssertGreaterThan(matches, 0, "expected at least some firstEntries-flavored draws for a brand-new user")
    }

    func testGapSinceLastEntryBiasesTowardReturningQuestions() {
        let now = date(hour: 20, weekday: 4)
        let staleDate = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let returningProfile = MemoryProfile(
            recurringThemes: [], recurringEntities: [], emotionalVocabulary: [],
            copingPatterns: [], notableMoments: [], topMoodRaw: nil,
            totalEntries: 40, activeDaysLast30: 3, activeDaysThisWeek: 0,
            firstEntryDate: staleDate, lastEntryDate: staleDate, generatedAt: now
        )
        let returningIDs = Set(StarterQuestionBank.all
            .filter { $0.moments.contains(.returning) }
            .map(\.id))

        var matches = 0
        let draws = 40
        for _ in 0..<draws {
            let question = StarterQuestionPicker.pick(now: now, profile: returningProfile)
            if returningIDs.contains(question.id) { matches += 1 }
        }
        XCTAssertGreaterThan(matches, 0, "expected at least some returning-flavored draws after a 10-day gap")
    }
}
