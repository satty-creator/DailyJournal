//
//  OnboardingPaywallTests.swift
//  DailyJournalUITests
//
//  "Every new user sees the Spilr Pro paywall right after onboarding" —
//  and can always get past it without paying.
//

import XCTest

final class OnboardingPaywallTests: SpilrUITestCase {

    /// Skip writing → land in the app → paywall → "Not yet" → Today tab.
    func testSkippingTheFirstEntryStillEndsOnThePaywall() {
        launch(as: .onboardingLater)
        walkOnboardingToFirstQuestion()
        tap("onboarding.later")

        assertAppears("paywall.headline", timeout: 20)
        XCTAssertTrue(app.staticTexts["It takes a few weeks to see a pattern."].exists)

        // Real App Store Connect terms via the fixture store: monthly carries
        // the 2-week trial, so it's pre-selected and the CTA says so.
        XCTAssertEqual(element("paywall.cta").label, "Start 2 weeks free")
        XCTAssertTrue(element("paywall.plan.monthly").exists)
        XCTAssertTrue(element("paywall.plan.annual").exists)
        XCTAssertTrue(element("paywall.plan.lifetime").exists)

        // "Not yet" is held back briefly on the onboarding paywall, then works.
        tap("paywall.notYet", timeout: 10)
        assertInMainApp()
        assertDoesNotAppear("paywall", within: 2)
    }

    /// The full first-entry path: onboarding → Daily Chat (stubbed Spilr) →
    /// weave → save → paywall.
    func testFirstEntryThroughDailyChatEndsOnThePaywall() {
        launch(as: .onboardingChat)
        walkOnboardingToFirstQuestion()
        tap("onboarding.answer")

        sendChatMessage("Work was loud today and I kept thinking about the move.")
        // The emulator's Gemini stub always asks this back.
        XCTAssertTrue(app.staticTexts["What part of that stayed with you most?"].waitForExistence(timeout: 20),
                      "Spilr's reply never arrived — is SPILR_GEMINI_STUB=1 set on the emulator?")
        sendChatMessage("Probably that I haven't told anyone yet.")

        tap("chat.wrapUp", timeout: 20)
        tap("chat.review.save", timeout: 30)

        assertAppears("paywall.headline", timeout: 25)
        tap("paywall.notYet", timeout: 10)
        assertInMainApp()
    }

    /// The paywall shows once. A relaunch must not show it again.
    func testOnboardingPaywallShowsOnlyOnce() {
        launch(as: .onboardingLater)
        walkOnboardingToFirstQuestion()
        tap("onboarding.later")
        tap("paywall.notYet", timeout: 20)
        assertInMainApp()

        // Relaunch WITHOUT resetting state.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-UITests", "-UseFirebaseEmulator", "-UITestFixturePaywall",
                                 "-DisableDebugProBypass",
                                 "-UITestSignIn", "\(E2EAccount.onboardingLater.rawValue):\(E2EAccount.password)"]
        again.launch()
        app = again
        assertInMainApp()
        assertDoesNotAppear("paywall", within: 4)
    }
}
