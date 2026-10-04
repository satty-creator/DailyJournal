//
//  EarlyObservationSurfacingTests.swift
//  DailyJournalTests
//
//  The 3-entry Mirror unlock surfaces emerging hypotheses through
//  `SelfModelHypothesis.isObservationSurfaceable`, which is deliberately looser
//  than `isProfileSurfaceable` — it drops the `timesSeen >= 3` recurrence floor
//  that was leaving the "observations at 3" promise rendering an empty screen.
//  These assert the two predicates diverge exactly where intended.
//

import XCTest
@testable import DailyJournal

final class EarlyObservationSurfacingTests: XCTestCase {

    private func hyp(
        timesSeen: Int = 1,
        stability: HypothesisStability = .emerging,
        verdict: String = "",
        userStatus: UserHypothesisStatus = .unrated
    ) -> SelfModelHypothesis {
        SelfModelHypothesis(
            title: "Puts work before rest",
            hypothesis: "You tend to keep going when you're already tired.",
            confidence: 0.4,
            stability: stability,
            userStatus: userStatus,
            timesSeen: timesSeen,
            disconfirmationVerdict: verdict
        )
    }

    /// The whole point: a single-entry observation surfaces early, where the
    /// profile gate (timesSeen >= 3) would hide it.
    func testSingleEntryObservationSurfacesEarlyButNotAsProfile() {
        let h = hyp(timesSeen: 1)
        XCTAssertTrue(h.isObservationSurfaceable, "an emerging, non-dropped item must surface as a first observation")
        XCTAssertFalse(h.isProfileSurfaceable, "one entry must not reach the recurrence-gated profile sections")
    }

    /// Disconfirmed items stay hidden in BOTH surfaces — early looseness never
    /// extends to showing something the audit said to drop.
    func testDroppedVerdictNeverSurfaces() {
        let h = hyp(timesSeen: 1, verdict: "drop")
        XCTAssertFalse(h.isObservationSurfaceable)
        XCTAssertFalse(h.isProfileSurfaceable)
    }

    /// Retired items are dead, not merely tentative — they must not come back as
    /// "first observations".
    func testRetiredNeverSurfacesEarly() {
        let h = hyp(timesSeen: 1, stability: .retired)
        XCTAssertFalse(h.isObservationSurfaceable)
    }

    /// A "weaken" verdict is softened, not dropped — it is still a legitimate
    /// early observation.
    func testWeakenedStillSurfacesEarly() {
        let h = hyp(timesSeen: 2, verdict: "weaken")
        XCTAssertTrue(h.isObservationSurfaceable)
    }

    /// Once something has genuinely recurred it qualifies for both surfaces, so
    /// the early section is a superset at this stage, never a conflicting gate.
    func testRecurringQualifiesForBoth() {
        let h = hyp(timesSeen: 3)
        XCTAssertTrue(h.isObservationSurfaceable)
        XCTAssertTrue(h.isProfileSurfaceable)
    }
}
