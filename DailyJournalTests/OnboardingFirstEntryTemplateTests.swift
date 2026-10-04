//
//  OnboardingFirstEntryTemplateTests.swift
//  DailyJournalTests
//
//  `JournalTemplate.onboardingFirstEntry` — the guided template onboarding's
//  first entry runs. Pins the step order and the before/after scale roles
//  `SecondLookView`'s delta and `TemplateRunnerViewModel.save` both depend on.
//

import XCTest
@testable import Spilr

final class OnboardingFirstEntryTemplateTests: XCTestCase {

    func testStepOrderAndKinds() {
        let template = JournalTemplate.onboardingFirstEntry(openingQuestion: "What's going on?")
        let ids = template.steps.map(\.id)
        XCTAssertEqual(ids, [
            "heavy-before", "situation", "thought", "evidence-for", "evidence-against",
            "balanced", "heavy-after",
        ])
    }

    func testOpeningQuestionIsWiredIntoTheSituationStep() {
        let template = JournalTemplate.onboardingFirstEntry(openingQuestion: "What's the actual thing?")
        let situation = template.steps.first { $0.id == "situation" }
        XCTAssertEqual(situation?.question, "What's the actual thing?")
        guard case .text = situation?.kind else {
            return XCTFail("situation step should be free text")
        }
    }

    func testBeforeAndAfterStepsCoverTheFullZeroToTenRange() {
        let template = JournalTemplate.onboardingFirstEntry(openingQuestion: "?")
        XCTAssertEqual(template.beforeScaleStep?.id, "heavy-before")
        XCTAssertEqual(template.afterScaleStep?.id, "heavy-after")

        guard
            case .scale(let beforeRole, let beforeValues) = template.beforeScaleStep?.kind,
            case .scale(let afterRole, let afterValues) = template.afterScaleStep?.kind
        else {
            return XCTFail("before/after steps should be .scale")
        }
        XCTAssertEqual(beforeRole, .before)
        XCTAssertEqual(afterRole, .after)
        XCTAssertEqual(beforeValues, Array(0...10))
        XCTAssertEqual(afterValues, Array(0...10))
    }

    func testNotIncludedInTheTemplateGallery() {
        XCTAssertFalse(JournalTemplate.all.contains { $0.id == "onboarding-first-entry" })
    }

    func testExistingTemplatesKeepTheirSixButtonScale() {
        guard let untangle = JournalTemplate.all.first(where: { $0.id == "untangle-a-decision" }) else {
            return XCTFail("untangle-a-decision should still be in the gallery")
        }
        guard case .scale(_, let values) = untangle.beforeScaleStep?.kind else {
            return XCTFail("expected a .scale step")
        }
        XCTAssertEqual(values, [0, 2, 4, 6, 8, 10])
    }
}
