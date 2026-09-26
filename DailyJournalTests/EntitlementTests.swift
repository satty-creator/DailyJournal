//
//  EntitlementTests.swift
//  DailyJournalTests
//
//  Owner bypass and "which 402s earn a paywall". The owner list must match
//  functions/lib/entitlement.js — test/entitlement.test.js pins the server side.
//

import XCTest
@testable import DailyJournal

final class EntitlementTests: XCTestCase {

    func testOwnerEmailsBypassCaseInsensitively() {
        XCTAssertTrue(OwnerAccess.isOwner(email: "satakshi1710@gmail.com", uid: nil))
        XCTAssertTrue(OwnerAccess.isOwner(email: " SatakSP@gmail.com ", uid: nil))
        XCTAssertTrue(OwnerAccess.isOwner(email: "ssahni30@gmail.com", uid: nil))
    }

    func testOwnerUidsBypassWithoutEmail() {
        XCTAssertTrue(OwnerAccess.isOwner(email: nil, uid: "KrLOcdVDPKVjmmxhu85N3tibeRH3"))
    }

    func testEveryoneElseIsNotAnOwner() {
        XCTAssertFalse(OwnerAccess.isOwner(email: "someone@example.com", uid: "abc"))
        XCTAssertFalse(OwnerAccess.isOwner(email: nil, uid: nil))
        XCTAssertFalse(OwnerAccess.isOwner(email: "", uid: nil))
    }

    func testAppReviewDemoAccountMustSeeThePaywall() {
        XCTAssertFalse(OwnerAccess.isOwner(email: "test@spilr.com", uid: "gqRvwbUxQxO3pGGdSZaj3nltzAz2"))
    }

    func testOnlyAFinishedPreviewEarnsAPaywall() {
        XCTAssertTrue(EntitlementService.budgetReasonWarrantsPaywall("preview_ended"))
        XCTAssertTrue(EntitlementService.budgetReasonWarrantsPaywall("expired"))
        // A paying user at today's safety cap must never be shown a paywall.
        XCTAssertFalse(EntitlementService.budgetReasonWarrantsPaywall("daily_budget"))
        XCTAssertFalse(EntitlementService.budgetReasonWarrantsPaywall("surface_cap"))
        XCTAssertFalse(EntitlementService.budgetReasonWarrantsPaywall(nil))
    }

    func testReleaseBuildsNeverTakeTheDebugBypass() {
        #if !DEBUG
        XCTAssertFalse(TestLaunchConfig.debugBuildBypassesPaywall)
        XCTAssertFalse(TestLaunchConfig.usesEmulator)
        #endif
        XCTAssertTrue(TestLaunchConfig.functionsBaseURL.hasPrefix("http"))
    }
}
