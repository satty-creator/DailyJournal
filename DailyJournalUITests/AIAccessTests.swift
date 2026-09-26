//
//  AIAccessTests.swift
//  DailyJournalUITests
//
//  Server-side enforcement, end to end: the emulator's geminiProxy runs the
//  real Spilr Pro gate (functions/lib/entitlement.js). A user whose free
//  preview is over gets a 402 and the app answers with the paywall; the
//  owner never does.
//

import XCTest

final class AIAccessTests: SpilrUITestCase {

    func testPreviewEndedUserGetsThePaywallFromDailyChat() {
        launch(as: .previewEnded, onboardingDone: true)
        assertInMainApp()

        // Whichever AI surface asks first gets the 402 — Home may call one on
        // load before we ever open the chat. Either way the paywall appears
        // exactly once (the 20h cooldown stops a second one).
        var sawPaywall = false
        func expectPaywall(timeout: TimeInterval) {
            assertAppears("paywall.headline", timeout: timeout)
            XCTAssertTrue(app.staticTexts["Your free preview has ended."].exists)
            tap("paywall.notYet", timeout: 5)
            sawPaywall = true
        }
        if element("paywall.headline").waitForExistence(timeout: 4) { expectPaywall(timeout: 1) }

        openChatFromHome()
        sendChatMessage("Long day. Mostly thinking about the interview.")

        // 402 preview_ended → AIService → EntitlementService → paywall on top of chat.
        if !sawPaywall { expectPaywall(timeout: 20) }
        // Writing is never gated: the chat is still there and says so honestly.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'keep writing'")).firstMatch
                        .waitForExistence(timeout: 10))
    }

    func testOwnerNeverSeesThePaywallAndGetsAIReplies() {
        launch(as: .owner)
        walkOnboardingToFirstQuestion()
        tap("onboarding.later")
        assertInMainApp()
        assertDoesNotAppear("paywall", within: 5)

        openChatFromHome()
        sendChatMessage("Testing the owner bypass.")
        XCTAssertTrue(app.staticTexts["What part of that stayed with you most?"].waitForExistence(timeout: 20))
        assertDoesNotAppear("paywall", within: 3)
    }
}
