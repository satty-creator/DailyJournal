//
//  SafetyAndParsingTests.swift
//  DailyJournalTests
//
//  The crisis gate and the Gemini response parser. Both sit in front of
//  every AI surface; a regression in either is a safety or trust bug.
//

import XCTest
@testable import DailyJournal

final class PatternSafetyTests: XCTestCase {

    func testExplicitCrisisLanguageTripsTheCorpusGate() {
        XCTAssertTrue(PatternSafety.containsCrisisSignal(in: "Some days I want to die."))
        XCTAssertTrue(PatternSafety.corpusHasCrisisSignal(["fine day", "thinking about suicide again"]))
    }

    func testOrdinaryEntriesDoNotTripIt() {
        XCTAssertFalse(PatternSafety.corpusHasCrisisSignal([
            "Work was long but the walk home was nice.",
            "Coffee with Maya, then an early night.",
        ]))
    }

    func testChatTierIsExplicitForUnambiguousSignals() {
        XCTAssertEqual(PatternSafety.chatCrisisLevel(in: "I want to kill myself"), .explicit)
    }

    func testChatTierDoesNotEndAConversationOverAMetaphor() {
        XCTAssertNotEqual(PatternSafety.chatCrisisLevel(in: "I need to purge my inbox"), .explicit)
        XCTAssertEqual(PatternSafety.chatCrisisLevel(in: "Had a lovely lunch today"), .none)
    }
}

final class LocalAITests: XCTestCase {

    func testLowContentThreshold() {
        XCTAssertTrue(LocalAI.isLowContent("ok"))
        XCTAssertTrue(LocalAI.isLowContent("so tired today"))
        XCTAssertFalse(LocalAI.isLowContent("Walked to the river after work and felt calmer."))
    }

    func testSentimentIsAlwaysAKnownLabel() {
        for text in ["I'm so grateful for my sister today.", "Everything went wrong and I'm furious.", "Meh."] {
            let label = LocalAI.detectSentiment(from: text)
            XCTAssertNotNil(LocalAI.normalizedSentiment(label), "\(label) isn't in sentimentLabels")
        }
    }

    func testNormalizedSentimentRejectsInventedLabels() {
        XCTAssertEqual(LocalAI.normalizedSentiment("  grateful "), "Grateful")
        XCTAssertNil(LocalAI.normalizedSentiment("Ecstatic"))
        XCTAssertNil(LocalAI.normalizedSentiment(nil))
    }

    func testTopicsRespectTheLimit() {
        let topics = LocalAI.extractTopics(from: "Work meeting, then gym, then dinner with family and a long call with mom about work.", limit: 2)
        XCTAssertLessThanOrEqual(topics.count, 2)
    }
}

final class GeminiParsingTests: XCTestCase {

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testParsesText() throws {
        let data = json(["candidates": [["content": ["parts": [["text": "Hello"]]], "finishReason": "STOP"]]])
        let result = try AIService.parseTextCandidate(data)
        XCTAssertEqual(result.text, "Hello")
        XCTAssertFalse(result.truncated)
    }

    func testFlagsTruncation() throws {
        let data = json(["candidates": [["content": ["parts": [["text": "Half a"]]], "finishReason": "MAX_TOKENS"]]])
        XCTAssertTrue(try AIService.parseTextCandidate(data).truncated)
    }

    func testSafetyBlocksAreDistinctFromParseErrors() {
        let blockedPrompt = json(["promptFeedback": ["blockReason": "SAFETY"]])
        XCTAssertThrowsError(try AIService.parseTextCandidate(blockedPrompt)) { error in
            guard case AIError.blockedBySafety = error else { return XCTFail("got \(error)") }
        }
        let blockedCandidate = json(["candidates": [["finishReason": "SAFETY"]]])
        XCTAssertThrowsError(try AIService.parseTextCandidate(blockedCandidate)) { error in
            guard case AIError.blockedBySafety = error else { return XCTFail("got \(error)") }
        }
    }

    func testMalformedResponsesThrowParseError() {
        XCTAssertThrowsError(try AIService.parseTextCandidate(Data("not json".utf8))) { error in
            guard case AIError.parseError = error else { return XCTFail("got \(error)") }
        }
        XCTAssertThrowsError(try AIService.parseTextCandidate(json(["candidates": []]))) { error in
            guard case AIError.parseError = error else { return XCTFail("got \(error)") }
        }
    }
}
