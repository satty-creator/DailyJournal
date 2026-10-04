//
//  MoodLogServiceTests.swift
//  DailyJournalTests
//
//  `MoodLogPoint`'s Firestore encode/decode round trip — no live Firestore
//  here, just the plain-dictionary shape `MoodLogService` reads and writes.
//

import XCTest
import FirebaseFirestore
@testable import Spilr

final class MoodLogServiceTests: XCTestCase {

    func testFirestoreRoundTrip() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let point = MoodLogPoint(value: 7, source: .baseline, at: at)

        let data = point.toFirestoreData()
        XCTAssertEqual(data["value"] as? Int, 7)
        XCTAssertEqual(data["source"] as? String, "baseline")
        XCTAssertEqual((data["at"] as? Timestamp)?.dateValue().timeIntervalSince1970, at.timeIntervalSince1970, accuracy: 0.001)

        let decoded = MoodLogPoint(from: data)
        XCTAssertEqual(decoded?.value, 7)
        XCTAssertEqual(decoded?.source, .baseline)
    }

    func testDecodeFailsOnMissingFields() {
        XCTAssertNil(MoodLogPoint(from: ["value": 5]))
        XCTAssertNil(MoodLogPoint(from: ["source": "baseline", "at": Timestamp(date: Date())]))
    }

    func testDecodeFailsOnUnknownSource() {
        let data: [String: Any] = ["value": 3, "source": "made_up", "at": Timestamp(date: Date())]
        XCTAssertNil(MoodLogPoint(from: data))
    }

    func testEntryBeforeAndAfterSourcesRoundTrip() {
        for source: MoodLogSource in [.entryBefore, .entryAfter] {
            let point = MoodLogPoint(value: 4, source: source)
            let decoded = MoodLogPoint(from: point.toFirestoreData())
            XCTAssertEqual(decoded?.source, source)
        }
    }
}
