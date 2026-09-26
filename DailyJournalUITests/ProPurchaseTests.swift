//
//  ProPurchaseTests.swift
//  DailyJournalUITests
//
//  Profile → paywall → purchase, and what App Review checks on the way.
//

import XCTest

final class ProPurchaseTests: SpilrUITestCase {

    private func openPaywallFromProfile() {
        tap("home.profile", timeout: 25)
        let getPro = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Get Spilr Pro'")).firstMatch
        XCTAssertTrue(getPro.waitForExistence(timeout: 10), "Profile should offer Spilr Pro to a free user")
        getPro.tap()
        assertAppears("paywall.headline")
    }

    /// Guideline 3.1.2: price, length, auto-renewal, cancel, Terms, Privacy,
    /// Restore — all on the paywall.
    func testPaywallCarriesEverythingAppReviewRequires() {
        launch(as: .profile, onboardingDone: true)
        assertInMainApp()
        openPaywallFromProfile()

        let finePrint = element("paywall.finePrint").label
        XCTAssertTrue(finePrint.contains("$5.99/month"), finePrint)
        XCTAssertTrue(finePrint.contains("Renews automatically"), finePrint)
        XCTAssertTrue(finePrint.contains("Cancel anytime"), finePrint)
        XCTAssertTrue(element("paywall.restore").exists)
        XCTAssertTrue(element("paywall.terms").exists)
        XCTAssertTrue(element("paywall.privacy").exists)

        // Switching plan updates the button and the disclosure.
        tap("paywall.plan.annual")
        XCTAssertEqual(element("paywall.cta").label, "Continue")
        XCTAssertTrue(element("paywall.finePrint").label.contains("$29.99/year"))
        tap("paywall.plan.lifetime")
        XCTAssertEqual(element("paywall.cta").label, "Unlock for life")

        // From Profile, "Not yet" works immediately.
        tap("paywall.notYet", timeout: 3)
        assertDoesNotAppear("paywall.headline", within: 2)
    }

    func testBuyingProUnlocksItInProfile() {
        launch(as: .purchase, onboardingDone: true)
        assertInMainApp()
        openPaywallFromProfile()

        tap("paywall.cta")
        assertDoesNotAppear("paywall.headline", within: 3)
        let status = element("profile.proStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "You\u{2019}re on Spilr Pro")
    }
}
