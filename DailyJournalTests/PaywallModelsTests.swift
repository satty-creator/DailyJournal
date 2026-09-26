//
//  PaywallModelsTests.swift
//  DailyJournalTests
//
//  The paywall's copy rules. These are the lines App Review reads (3.1.2
//  disclosure) and the lines that decide conversion, so they're pinned.
//

import XCTest
@testable import DailyJournal

final class PaywallModelsTests: XCTestCase {

    private let twoWeeks = TrialOffer(value: 2, unit: .week)

    private func plan(_ kind: PaywallPlan.Kind, _ price: String, _ value: Decimal, trial: TrialOffer? = nil) -> PaywallPlan {
        PaywallPlan(id: "\(kind)", kind: kind, localizedPrice: price, price: value, trial: trial)
    }

    // MARK: Trial phrasing

    func testTrialPhrase() {
        XCTAssertEqual(twoWeeks.phrase, "2 weeks")
        XCTAssertEqual(TrialOffer(value: 1, unit: .month).phrase, "1 month")
        XCTAssertEqual(TrialOffer(value: 3, unit: .day).phrase, "3 days")
        XCTAssertEqual(twoWeeks.approximateDays, 14)
    }

    // MARK: CTA

    func testCTAStatesTheTrialNotThePrice() {
        let monthly = plan(.monthly, "$5.99", 5.99, trial: twoWeeks)
        XCTAssertEqual(PaywallCopy.ctaTitle(for: monthly), "Start 2 weeks free")
        XCTAssertFalse(PaywallCopy.ctaTitle(for: monthly).contains("$"),
                       "Never put the price in the button — it lives in the fine print.")
    }

    func testCTAWithoutTrialAndForLifetime() {
        XCTAssertEqual(PaywallCopy.ctaTitle(for: plan(.annual, "$29.99", 29.99)), "Continue")
        XCTAssertEqual(PaywallCopy.ctaTitle(for: plan(.lifetime, "$79.99", 79.99)), "Unlock for life")
        XCTAssertEqual(PaywallCopy.ctaTitle(for: nil), "Continue")
    }

    // MARK: Required disclosure (App Review 3.1.2)

    func testFinePrintDisclosesTrialPriceRenewalAndCancellation() {
        let text = PaywallCopy.finePrint(for: plan(.monthly, "$5.99", 5.99, trial: twoWeeks))
        XCTAssertTrue(text.contains("2 weeks free"))
        XCTAssertTrue(text.contains("$5.99/month"))
        XCTAssertTrue(text.contains("Renews automatically"))
        XCTAssertTrue(text.contains("Cancel anytime"))
    }

    func testFinePrintForAnnualWithoutTrial() {
        let text = PaywallCopy.finePrint(for: plan(.annual, "$29.99", 29.99))
        XCTAssertTrue(text.contains("$29.99/year"))
        XCTAssertTrue(text.contains("renews automatically"))
        XCTAssertFalse(text.contains("free"))
    }

    func testFinePrintForLifetimeSaysNoSubscription() {
        let text = PaywallCopy.finePrint(for: plan(.lifetime, "$79.99", 79.99))
        XCTAssertTrue(text.contains("$79.99"))
        XCTAssertTrue(text.contains("No subscription"))
    }

    func testPriceLines() {
        XCTAssertEqual(plan(.monthly, "$5.99", 5.99).priceLine, "$5.99/month")
        XCTAssertEqual(plan(.annual, "$29.99", 29.99).priceLine, "$29.99/year")
        XCTAssertEqual(plan(.lifetime, "$79.99", 79.99).priceLine, "$79.99 once")
    }

    // MARK: Savings badge

    func testAnnualSavingsMatchesAppStorePrices() {
        // $5.99 × 12 = $71.88 vs $29.99 → 58% saving.
        XCTAssertEqual(PaywallCopy.annualSavingsPercent(monthly: 5.99, annual: 29.99), 58)
    }

    func testNoSavingsClaimWhenAnnualIsntCheaper() {
        XCTAssertNil(PaywallCopy.annualSavingsPercent(monthly: 5.99, annual: 80))
        XCTAssertNil(PaywallCopy.annualSavingsPercent(monthly: 5.99, annual: 70), "Under 5% isn't worth a badge")
        XCTAssertNil(PaywallCopy.annualSavingsPercent(monthly: 0, annual: 29.99))
    }

    // MARK: Selection + order

    func testDefaultSelectionPrefersAnEligibleTrial() {
        let plans = [plan(.annual, "$29.99", 29.99), plan(.monthly, "$5.99", 5.99, trial: twoWeeks)]
        XCTAssertEqual(PaywallCopy.defaultSelection(plans)?.kind, .monthly)
    }

    func testDefaultSelectionFallsBackToAnnual() {
        let plans = [plan(.monthly, "$5.99", 5.99), plan(.annual, "$29.99", 29.99), plan(.lifetime, "$79.99", 79.99)]
        XCTAssertEqual(PaywallCopy.defaultSelection(plans)?.kind, .annual)
        XCTAssertNil(PaywallCopy.defaultSelection([]))
    }

    func testDisplayOrderIsYearlyMonthlyLifetime() {
        let sorted = PaywallCopy.sorted([
            plan(.lifetime, "$79.99", 79.99), plan(.monthly, "$5.99", 5.99), plan(.annual, "$29.99", 29.99),
        ])
        XCTAssertEqual(sorted.map(\.kind), [.annual, .monthly, .lifetime])
    }

    // MARK: Headlines + dismissal

    func testHeadlinesPerTrigger() {
        XCTAssertEqual(PaywallCopy.headline(for: .aiLimit), "Your free preview has ended.")
        XCTAssertEqual(PaywallCopy.headline(for: .onboarding), PaywallCopy.headline(for: .profile))
    }

    func testAILimitSubheadPromisesWritingStaysFree() {
        XCTAssertTrue(PaywallCopy.subhead(for: .aiLimit, trial: nil).contains("Writing stays free"))
        XCTAssertTrue(PaywallCopy.subhead(for: .onboarding, trial: twoWeeks).contains("2 weeks free"))
        XCTAssertFalse(PaywallCopy.subhead(for: .onboarding, trial: nil).contains("free"))
    }

    func testOnlyTheOnboardingPaywallDelaysNotYet() {
        XCTAssertGreaterThan(PaywallCopy.dismissDelay(for: .onboarding), 0)
        XCTAssertEqual(PaywallCopy.dismissDelay(for: .profile), 0)
        XCTAssertEqual(PaywallCopy.dismissDelay(for: .aiLimit), 0)
    }
}
