//
//  PaywallStore.swift
//  DailyJournal
//
//  Where the paywall gets its plans and how it buys them. The view only ever
//  talks to `PaywallStore`, so the UI tests can swap in fixed plans
//  (`FixturePaywallStore`, DEBUG only) and exercise the whole flow without
//  StoreKit, a sandbox account, or network.
//

import Foundation
import RevenueCat

protocol PaywallStore {
    /// Plans from the current Offering, with trials only where the user is
    /// actually eligible. Throws when nothing purchasable could be loaded.
    func loadPlans() async throws -> [PaywallPlan]
    /// Returns true when the purchase unlocked Pro, false if the user cancelled.
    func purchase(_ plan: PaywallPlan) async throws -> Bool
    /// Returns true when a restore found an active Pro entitlement.
    func restore() async throws -> Bool
}

enum PaywallStoreError: LocalizedError {
    case noPackages
    case planUnavailable

    var errorDescription: String? {
        switch self {
        case .noPackages:      return "Spilr Pro isn't available right now."
        case .planUnavailable: return "That plan isn't available right now."
        }
    }
}

enum PaywallStores {
    /// The store the app should use in this launch.
    static func make() -> PaywallStore {
        #if DEBUG
        if TestLaunchConfig.usesFixturePaywall { return FixturePaywallStore() }
        #endif
        return RevenueCatPaywallStore()
    }
}

// MARK: - RevenueCat (production)

final class RevenueCatPaywallStore: PaywallStore {

    /// Packages from the last `loadPlans()`, keyed by package identifier, so a
    /// purchase buys exactly the package whose price was on screen.
    private var packages: [String: Package] = [:]

    func loadPlans() async throws -> [PaywallPlan] {
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.current, !offering.availablePackages.isEmpty else {
            throw PaywallStoreError.noPackages
        }
        let available = offering.availablePackages
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: available)

        packages = Dictionary(uniqueKeysWithValues: available.map { ($0.identifier, $0) })

        return available.map { pkg in
            let product = pkg.storeProduct
            var trial: TrialOffer?
            if let intro = product.introductoryDiscount,
               intro.paymentMode == .freeTrial,
               eligibility[pkg]?.status == .eligible {
                trial = TrialOffer(value: intro.subscriptionPeriod.value,
                                   unit: Self.unit(intro.subscriptionPeriod.unit))
            }
            return PaywallPlan(
                id: pkg.identifier,
                kind: Self.kind(pkg.packageType),
                localizedPrice: product.localizedPriceString,
                price: product.price,
                trial: trial
            )
        }
    }

    func purchase(_ plan: PaywallPlan) async throws -> Bool {
        guard let pkg = packages[plan.id] else { throw PaywallStoreError.planUnavailable }
        let result = try await Purchases.shared.purchase(package: pkg)
        if result.userCancelled { return false }
        return result.customerInfo.entitlements[EntitlementService.proEntitlementId]?.isActive == true
    }

    func restore() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        return info.entitlements[EntitlementService.proEntitlementId]?.isActive == true
    }

    private static func kind(_ type: PackageType) -> PaywallPlan.Kind {
        switch type {
        case .monthly:  return .monthly
        case .annual:   return .annual
        case .lifetime: return .lifetime
        default:        return .other
        }
    }

    private static func unit(_ unit: SubscriptionPeriod.Unit) -> TrialOffer.Unit {
        switch unit {
        case .day:   return .day
        case .week:  return .week
        case .month: return .month
        case .year:  return .year
        @unknown default: return .day
        }
    }
}

#if DEBUG
// MARK: - Fixture (UI tests only)

/// Fixed plans matching App Store Connect as of Sept 2026, so UI tests can
/// assert on real-looking copy. Purchasing just flips the local Pro flag.
final class FixturePaywallStore: PaywallStore {
    static let plans: [PaywallPlan] = [
        PaywallPlan(id: "$rc_monthly", kind: .monthly, localizedPrice: "$5.99", price: 5.99,
                    trial: TrialOffer(value: 2, unit: .week)),
        PaywallPlan(id: "$rc_annual", kind: .annual, localizedPrice: "$29.99", price: 29.99, trial: nil),
        PaywallPlan(id: "$rc_lifetime", kind: .lifetime, localizedPrice: "$79.99", price: 79.99, trial: nil),
    ]

    func loadPlans() async throws -> [PaywallPlan] { Self.plans }

    func purchase(_ plan: PaywallPlan) async throws -> Bool {
        await MainActor.run { EntitlementService.shared.debugGrantPro() }
        return true
    }

    func restore() async throws -> Bool { false }
}
#endif
