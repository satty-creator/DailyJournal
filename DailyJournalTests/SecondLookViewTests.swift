//
//  SecondLookViewTests.swift
//  DailyJournalTests
//
//  `SecondLookView.deltaToShow` — the rule for onboarding's payoff delta
//  line ("You came in at 7, you're leaving at 4"): shown only when things
//  measurably eased, never on a rise or a flat read.
//

import XCTest
@testable import Spilr

final class SecondLookViewTests: XCTestCase {

    func testShowsDeltaWhenItEased() {
        let delta = SecondLookView.deltaToShow(before: 7, after: 4)
        XCTAssertEqual(delta?.before, 7)
        XCTAssertEqual(delta?.after, 4)
    }

    func testHidesDeltaWhenItRose() {
        XCTAssertNil(SecondLookView.deltaToShow(before: 3, after: 6))
    }

    func testHidesDeltaWhenUnchanged() {
        XCTAssertNil(SecondLookView.deltaToShow(before: 5, after: 5))
    }

    func testHidesDeltaWhenEitherRatingIsMissing() {
        XCTAssertNil(SecondLookView.deltaToShow(before: nil, after: 4))
        XCTAssertNil(SecondLookView.deltaToShow(before: 7, after: nil))
        XCTAssertNil(SecondLookView.deltaToShow(before: nil, after: nil))
    }
}
