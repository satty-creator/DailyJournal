//
//  OnboardingPaywallTests.swift
//  DailyJournalUITests
//
//  "The app earns the Spilr Pro paywall first" — it only shows after a
//  completed guided first entry, never on skip, and always only once.
//

import XCTest

final class OnboardingPaywallTests: SpilrUITestCase {

    /// Skipping the guided first entry goes straight to Today — no paywall,
    /// not even later. (The AI-limit and Profile paywall triggers are
    /// untouched — this only covers the onboarding trigger.)
    func testSkippingTheFirstEntryGoesHomeWithoutPaywall() {
        launch(as: .onboardingLater)
        walkOnboardingToFirstQuestion()
        tap("onboarding.later")

        assertInMainApp()
        assertDoesNotAppear("paywall", within: 3)
    }

    /// The full guided-entry path: onboarding intake → guided first entry →
    /// weave → save → Second look → paywall.
    func testCompletingTheGuidedFirstEntryEndsOnSecondLookThenPaywall() {
        launch(as: .onboardingChat)
        walkOnboardingToFirstQuestion()
        tap("onboarding.answer")

        let secondLookContinue = completeGuidedFirstEntry(before: 7, after: 4)
        XCTAssertTrue(secondLookContinue.waitForExistence(timeout: 20), "Second look never appeared")
        // The delta eased (7 → 4), so the payoff's delta line should show.
        XCTAssertTrue(app.staticTexts["You came in at 7, you're leaving at 4."].waitForExistence(timeout: 5))
        secondLookContinue.tap()

        assertAppears("paywall.headline", timeout: 25)

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

    /// Declining AI during onboarding still completes: no "SPILR ASKS" label
    /// backed by a model call, no AI bullets on Second look, but the entry
    /// still saves and the delta line still shows (it's the user's own
    /// numbers, not generated text).
    func testLocalOnlyConsentStillCompletesTheGuidedEntry() {
        launch(as: .onboardingChat)
        walkOnboardingToFirstQuestion(declineAI: true)
        tap("onboarding.answer")

        let secondLookContinue = completeGuidedFirstEntry(before: 6, after: 2)
        XCTAssertTrue(secondLookContinue.waitForExistence(timeout: 20), "Second look never appeared")
        XCTAssertTrue(app.staticTexts["You came in at 6, you're leaving at 2."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WHAT YOU WROTE"].waitForExistence(timeout: 20),
                      "Local-only consent should fall back to the user's own words, never generated bullets")
        secondLookContinue.tap()

        assertAppears("paywall.headline", timeout: 25)
    }

    /// Backing out of the guided entry without saving doesn't finish
    /// onboarding — no paywall, and the first-entry card is still there.
    func testExitingTheGuidedEntryWithoutSavingDoesNotQueueThePaywall() {
        launch(as: .onboardingChat)
        walkOnboardingToFirstQuestion()
        tap("onboarding.answer")

        tap("scale.5")
        // Exit immediately via the X button with an answer already given —
        // triggers the confirm alert.
        app.buttons.matching(NSPredicate(format: "label == 'Exit exercise'")).firstMatch.tap()
        app.buttons["Discard answers"].tap()

        assertAppears("onboarding.later")
        assertDoesNotAppear("paywall", within: 2)
    }

    /// The paywall shows once. A relaunch must not show it again.
    func testOnboardingPaywallShowsOnlyOnce() {
        launch(as: .onboardingLater)
        walkOnboardingToFirstQuestion()
        tap("onboarding.answer")
        completeGuidedFirstEntry().tap()
        tap("paywall.notYet", timeout: 25)
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
