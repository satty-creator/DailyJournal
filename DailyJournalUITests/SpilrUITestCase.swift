//
//  SpilrUITestCase.swift
//  DailyJournalUITests
//
//  Shared launch + helpers for the end-to-end flows.
//
//  These run the REAL app against the Firebase Emulator Suite (never
//  production), with Gemini stubbed inside the emulator and fixture paywall
//  plans instead of StoreKit. Start everything with:
//
//      ./scripts/run-e2e.sh
//
//  which boots the emulators, seeds the accounts below
//  (scripts/e2e/seed.js), and runs this target.
//

import XCTest

/// Accounts created by scripts/e2e/seed.js. Emulator-only; the password is
/// not a secret.
enum E2EAccount: String {
    case onboardingLater  = "onboarding-later@spilr.test"
    case onboardingChat   = "onboarding-chat@spilr.test"
    case profile          = "profile@spilr.test"
    case purchase         = "purchase@spilr.test"
    case previewEnded     = "preview-ended@spilr.test"
    case owner            = "satakshi1710@gmail.com"

    static let password = "spilr-e2e-password"
}

class SpilrUITestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    /// Launches a fresh install signed in as `account`.
    @discardableResult
    func launch(as account: E2EAccount,
                onboardingDone: Bool = false,
                extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITests",
            "-UseFirebaseEmulator",
            "-UITestResetState",
            "-UITestFixturePaywall",
            "-UITestGrantAIConsent",
            "-DisableDebugProBypass",
            "-UITestSignIn", "\(account.rawValue):\(E2EAccount.password)",
        ] + (onboardingDone ? ["-UITestOnboardingDone"] : []) + extraArgs
        app.launch()
        self.app = app
        return app
    }

    // MARK: - Element helpers

    /// `firstMatch`: during a step transition the outgoing and incoming
    /// screens can both briefly carry the same identifier.
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func tap(_ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let el = element(id)
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(id) never appeared", file: file, line: line)
        waitUntilHittable(el, timeout: timeout, file: file, line: line)
        el.tap()
    }

    func waitUntilHittable(_ el: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "isHittable == true")
        let exp = expectation(for: predicate, evaluatedWith: el)
        let result = XCTWaiter().wait(for: [exp], timeout: timeout)
        XCTAssertEqual(result, .completed, "element not hittable: \(el)", file: file, line: line)
    }

    func assertAppears(_ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(id).waitForExistence(timeout: timeout), "\(id) never appeared", file: file, line: line)
    }

    func assertDoesNotAppear(_ id: String, within seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(element(id).waitForExistence(timeout: seconds), "\(id) appeared but shouldn't have", file: file, line: line)
    }

    /// Walks the full intake — welcome → goals → struggle → people (skipped)
    /// → baseline → tone → AI consent → first-entry card. Picks the first
    /// available option on every step that requires one, and the default
    /// ("Use AI reflections") on consent — pass `declineAI: true` for a test
    /// that specifically wants the local-only path.
    func walkOnboardingToFirstQuestion(declineAI: Bool = false) {
        tap("onboarding.next")       // welcome → goals

        let firstGoal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding.goal.'")).firstMatch
        XCTAssertTrue(firstGoal.waitForExistence(timeout: 30), "Onboarding never started — is the emulator seeded?")
        firstGoal.tap()
        tap("onboarding.next")       // goals → struggle

        let firstStruggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding.struggle.'")).firstMatch
        XCTAssertTrue(firstStruggle.waitForExistence(timeout: 15), "Struggle chips never appeared")
        firstStruggle.tap()
        tap("onboarding.next")       // struggle → people

        tap("onboarding.people.skip") // people → baseline (skipped, optional)

        tap("scale.5")
        tap("onboarding.next")       // baseline → tone

        tap("onboarding.next")       // tone → consent (suggested tone is pre-selected)

        tap(declineAI ? "onboarding.consent.localOnly" : "onboarding.consent.useAI") // consent → first entry

        assertAppears("onboarding.later")
    }

    /// Walks the guided first entry (heavy-before scale, 5 text steps,
    /// heavy-after scale) and saves it from the review screen. Call right
    /// after tapping "onboarding.answer" on the first-entry card.
    @discardableResult
    func completeGuidedFirstEntry(before: Int = 7, after: Int = 4) -> XCUIElement {
        tap("scale.\(before)")
        tap("templateRunner.next")   // heavy-before → situation

        for _ in 0..<5 {
            let field = element("templateRunner.textField")
            XCTAssertTrue(field.waitForExistence(timeout: 15), "Guided entry text field never appeared")
            field.tap()
            field.typeText("Something worth writing down.")
            tap("templateRunner.next")
        }

        tap("scale.\(after)")
        tap("templateRunner.next")   // heavy-after → review (weaves + opens sheet)

        tap("templateReview.save", timeout: 30)
        return element("onboarding.secondLook.continue")
    }

    /// The main tab bar is up (the user is "in the app").
    func assertInMainApp(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: timeout),
                      "Main tabs never appeared", file: file, line: line)
    }

    /// Opens Daily Chat from Today, getting past the one-time "Your Thought
    /// Journal" intro sheet that a chat opened from Home shows first.
    func openChatFromHome() {
        tap("home.startChat", timeout: 20)
        let intro = element("chat.intro.start")
        if intro.waitForExistence(timeout: 4) { intro.tap() }
    }

    /// Types into Daily Chat's expanded composer and sends.
    func sendChatMessage(_ text: String) {
        tap("chat.compose")
        let editor = element("chat.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(text)
        tap("chat.editor.send")
    }
}
