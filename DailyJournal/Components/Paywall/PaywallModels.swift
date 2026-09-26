//
//  PaywallModels.swift
//  DailyJournal
//
//  The paywall's view model types, with no StoreKit or RevenueCat in them, so
//  the copy rules (what the button says, what the fine print must disclose,
//  which plan is pre-selected) are unit-testable — see PaywallModelsTests.
//
//  PRICES ARE NEVER HARDCODED. Every price string comes from the App Store via
//  RevenueCat (`StoreProduct.localizedPriceString`), already in the user's
//  currency. App Store Connect is the single source of truth: change a price
//  or the trial there and the paywall follows on the next launch.
//

import Foundation

/// Why the paywall is on screen. Drives the headline and whether "Not yet"
/// is delayed.
enum PaywallTrigger: String, Identifiable {
    /// Right after onboarding — the one moment every new user sees it.
    case onboarding
    /// The server returned 402 because the free AI preview is over.
    case aiLimit
    /// The user tapped "Get Spilr Pro" in Profile.
    case profile

    var id: String { rawValue }
}

/// A free-trial introductory offer, e.g. 2 weeks.
struct TrialOffer: Equatable {
    enum Unit: Equatable { case day, week, month, year }
    let value: Int
    let unit: Unit

    /// "2 weeks", "1 month", "3 days".
    var phrase: String {
        let noun: String
        switch unit {
        case .day:   noun = "day"
        case .week:  noun = "week"
        case .month: noun = "month"
        case .year:  noun = "year"
        }
        return "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    /// Total length in days, for sorting/comparing offers.
    var approximateDays: Int {
        switch unit {
        case .day:   return value
        case .week:  return value * 7
        case .month: return value * 30
        case .year:  return value * 365
        }
    }
}

/// One purchasable option on the paywall.
struct PaywallPlan: Identifiable, Equatable {
    enum Kind: Equatable { case monthly, annual, lifetime, other }

    /// RevenueCat package identifier (e.g. "$rc_monthly").
    let id: String
    let kind: Kind
    /// Localized, from the App Store — e.g. "$5.99", "฿199.00".
    let localizedPrice: String
    /// Price as a number, only used to compute the annual saving.
    let price: Decimal
    /// Only set when the user is actually ELIGIBLE for the trial (Apple gives
    /// one intro offer per subscription group per Apple ID).
    let trial: TrialOffer?

    var title: String {
        switch kind {
        case .monthly:  return "Monthly"
        case .annual:   return "Yearly"
        case .lifetime: return "Lifetime"
        case .other:    return "Spilr Pro"
        }
    }

    /// "$5.99/month", "$29.99/year", "$79.99 once".
    var priceLine: String {
        switch kind {
        case .monthly:  return "\(localizedPrice)/month"
        case .annual:   return "\(localizedPrice)/year"
        case .lifetime: return "\(localizedPrice) once"
        case .other:    return localizedPrice
        }
    }

    var isSubscription: Bool { kind == .monthly || kind == .annual }
}

enum PaywallCopy {

    /// Whole-percent saving of the annual plan over 12 months of monthly,
    /// or nil when there's nothing honest to claim (<5% or missing plans).
    static func annualSavingsPercent(monthly: Decimal, annual: Decimal) -> Int? {
        guard monthly > 0, annual > 0 else { return nil }
        let yearOfMonthly = monthly * 12
        guard annual < yearOfMonthly else { return nil }
        let saving = (yearOfMonthly - annual) / yearOfMonthly * 100
        let pct = NSDecimalNumber(decimal: saving).doubleValue
        let rounded = Int(pct.rounded(.down))
        return rounded >= 5 ? rounded : nil
    }

    /// Which plan starts selected: one with a trial the user can actually take
    /// (the "Start free" path converts best), else yearly, else the first.
    static func defaultSelection(_ plans: [PaywallPlan]) -> PaywallPlan? {
        plans.first(where: { $0.trial != nil })
            ?? plans.first(where: { $0.kind == .annual })
            ?? plans.first
    }

    /// Plans in display order: yearly, monthly, lifetime, anything else.
    static func sorted(_ plans: [PaywallPlan]) -> [PaywallPlan] {
        func rank(_ k: PaywallPlan.Kind) -> Int {
            switch k {
            case .annual:   return 0
            case .monthly:  return 1
            case .lifetime: return 2
            case .other:    return 3
            }
        }
        return plans.sorted { rank($0.kind) < rank($1.kind) }
    }

    /// The main button. States the outcome, never the price.
    static func ctaTitle(for plan: PaywallPlan?) -> String {
        guard let plan else { return "Continue" }
        if let trial = plan.trial { return "Start \(trial.phrase) free" }
        if plan.kind == .lifetime { return "Unlock for life" }
        return "Continue"
    }

    /// Required subscription disclosure under the button (App Review 3.1.2):
    /// length, price, auto-renewal, and how to cancel.
    static func finePrint(for plan: PaywallPlan?) -> String {
        guard let plan else { return "" }
        let keep = "your spills stay yours either way."
        switch plan.kind {
        case .lifetime:
            return "One payment of \(plan.localizedPrice). No subscription — \(keep)"
        case .monthly, .annual, .other:
            let period = plan.kind == .annual ? "year" : "month"
            if let trial = plan.trial {
                return "\(trial.phrase.capitalizedFirst) free, then \(plan.localizedPrice)/\(period). Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before the trial ends — \(keep)"
            }
            return "\(plan.localizedPrice)/\(period), renews automatically until cancelled. Cancel anytime in Settings — \(keep)"
        }
    }

    static func headline(for trigger: PaywallTrigger) -> String {
        switch trigger {
        case .aiLimit:
            return "Your free preview has ended."
        case .onboarding, .profile:
            return "It takes a few weeks to see a pattern."
        }
    }

    static func subhead(for trigger: PaywallTrigger, trial: TrialOffer?) -> String {
        switch trigger {
        case .aiLimit:
            return "Writing stays free, always. Pro brings back Spilr\u{2019}s reflections, the replies in Daily Chat, your Mirror and the Sunday letter."
        case .onboarding, .profile:
            let base = "Pro keeps every thread, every pattern and every shift, as far back as you\u{2019}ve written."
            guard let trial else { return base }
            return base + " \(trial.phrase.capitalizedFirst) free, because that\u{2019}s about how long it takes Spilr to get good."
        }
    }

    /// The onboarding paywall holds "Not yet" back briefly so the offer is
    /// read at least once; everywhere else it can be closed immediately.
    static func dismissDelay(for trigger: PaywallTrigger) -> TimeInterval {
        trigger == .onboarding ? 3 : 0
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
