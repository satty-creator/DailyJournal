//
//  OnboardingIntentTests.swift
//  DailyJournalTests
//
//  `OnboardingIntent`'s UserDefaults round-trips, the struggle-options union,
//  and the tone suggestion — the intake state that reaches every AI prompt
//  via `SpilrVoice.intentContext()`.
//

import XCTest
@testable import Spilr

final class OnboardingIntentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearOnboardingKeys()
    }

    override func tearDown() {
        clearOnboardingKeys()
        super.tearDown()
    }

    private func clearOnboardingKeys() {
        let defaults = UserDefaults.standard
        for key in [
            "spilr.onboardingGoals", "spilr.spilrTone", "spilr.onboardingStruggle",
            "spilr.onboardingStruggleDetail", "spilr.onboardingPeople", "spilr.onboardingBaseline",
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Round trips

    func testGoalsRoundTrip() {
        OnboardingIntent.selectedGoals = [.quietMyHead, .makeADecision]
        XCTAssertEqual(OnboardingIntent.selectedGoals, [.quietMyHead, .makeADecision])
    }

    func testToneDefaultsToCurious() {
        XCTAssertEqual(OnboardingIntent.tone, .curious)
        OnboardingIntent.tone = .direct
        XCTAssertEqual(OnboardingIntent.tone, .direct)
    }

    func testStruggleAndDetailRoundTrip() {
        XCTAssertNil(OnboardingIntent.struggle)
        OnboardingIntent.struggle = "work"
        OnboardingIntent.struggleDetail = "a deadline I keep missing"
        XCTAssertEqual(OnboardingIntent.struggle, "work")
        XCTAssertEqual(OnboardingIntent.struggleDetail, "a deadline I keep missing")
    }

    func testBaselineDistinguishesNilFromZero() {
        XCTAssertNil(OnboardingIntent.baseline)
        OnboardingIntent.baseline = 0
        XCTAssertEqual(OnboardingIntent.baseline, 0)
    }

    func testPeopleRoundTrip() {
        let people = [OnboardingPerson(role: "partner", name: "Alex"), OnboardingPerson(role: "boss", name: nil)]
        OnboardingIntent.people = people
        XCTAssertEqual(OnboardingIntent.people, people)
    }

    func testPersonDisplayLabelFallsBackToRole() {
        XCTAssertEqual(OnboardingPerson(role: "boss", name: nil).displayLabel, "boss")
        XCTAssertEqual(OnboardingPerson(role: "boss", name: "  ").displayLabel, "boss")
        XCTAssertEqual(OnboardingPerson(role: "boss", name: "Sam").displayLabel, "Sam")
    }

    // MARK: - struggleOptions(for:)

    func testStruggleOptionsUnionsAndDedupes() {
        // quietMyHead and makeADecision both list "work" and "money" — each
        // should appear once, in goal-iteration order.
        let options = OnboardingIntent.struggleOptions(for: [.quietMyHead, .makeADecision])
        XCTAssertEqual(options.filter { $0 == "work" }.count, 1)
        XCTAssertEqual(options.filter { $0 == "money" }.count, 1)
        XCTAssertLessThanOrEqual(options.count, 6)
    }

    func testStruggleOptionsCapsAtSix() {
        let options = OnboardingIntent.struggleOptions(for: Set(JournalGoal.allCases))
        XCTAssertLessThanOrEqual(options.count, 6)
    }

    func testStruggleOptionsAlwaysOffersACatchAllWhenRoom() {
        let options = OnboardingIntent.struggleOptions(for: [.quietMyHead])
        XCTAssertTrue(options.contains("something vague"))
    }

    func testStruggleOptionsEmptyForNoGoals() {
        XCTAssertTrue(OnboardingIntent.struggleOptions(for: []).isEmpty)
    }

    // MARK: - suggestedTone(for:)

    func testSuggestedToneMatchesSingleGoal() {
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: [.quietMyHead]), .gentle)
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: [.understandRelation]), .curious)
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: [.makeADecision]), .direct)
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: [.buildTheHabit]), .curious)
    }

    func testSuggestedToneIsStableRegardlessOfSetOrder() {
        // `JournalGoal.allCases` order decides the winner, not `Set` iteration
        // order, which Swift doesn't guarantee — quietMyHead comes first.
        let goals: Set<JournalGoal> = [.makeADecision, .quietMyHead, .buildTheHabit]
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: goals), .gentle)
    }

    func testSuggestedToneFallsBackToCuriousForNoGoals() {
        XCTAssertEqual(OnboardingIntent.suggestedTone(for: []), .curious)
    }

    // MARK: - intentContext()

    func testIntentContextEmptyWithNoGoals() {
        XCTAssertEqual(SpilrVoice.intentContext(), "")
    }

    func testIntentContextIncludesStruggleAndDetail() {
        OnboardingIntent.selectedGoals = [.quietMyHead]
        OnboardingIntent.struggle = "sleep"
        OnboardingIntent.struggleDetail = "waking up at 3am"

        let context = SpilrVoice.intentContext()
        XCTAssertTrue(context.contains("Right now what feels hardest: sleep"))
        XCTAssertTrue(context.contains("waking up at 3am"))
    }

    func testIntentContextOmitsStruggleLineWhenUnanswered() {
        OnboardingIntent.selectedGoals = [.quietMyHead]
        let context = SpilrVoice.intentContext()
        XCTAssertFalse(context.contains("Right now what feels hardest"))
    }
}
