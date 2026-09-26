//
//  EntitlementService.swift
//  DailyJournal
//
//  Thin wrapper around RevenueCat's CustomerInfo so the rest of the app can ask
//  "does this user have Spilr Pro?" without every call site touching the SDK.
//
//  This is a UI-layer convenience only — it does NOT gate AI calls. The real
//  enforcement is server-side: `geminiProxy` (and the server's own AI jobs)
//  check `aiUsage/{uid}` via functions/lib/entitlement.js, which the
//  `revenueCatWebhook` keeps current. A client-side flag can lag the server
//  (e.g. right after a purchase, before the webhook lands) — never trust this
//  for anything a user could exploit, only for what to show.
//
//  `hasProAccess` is what the UI should read. It is true for:
//    - an active `spilr_ai_mood_journal_pro` entitlement (trial or paid)
//    - the founder's accounts (OwnerAccess — mirrored on the server)
//    - DEBUG builds run from Xcode (see TestLaunchConfig), unless disabled
//
//  See REVENUECAT_SETUP.md.
//

import Foundation
import FirebaseAuth
import RevenueCat

@MainActor
final class EntitlementService: ObservableObject {

    static let shared = EntitlementService()
    private init() {
        observeCustomerInfo()
        observeAuth()
    }

    /// Must match the identifier created in the RevenueCat dashboard
    /// (Product catalog → Entitlements) — see REVENUECAT_SETUP.md — and
    /// `PRO_ENTITLEMENT_ID` in functions/lib/entitlement.js.
    static let proEntitlementId = "spilr_ai_mood_journal_pro"

    /// RevenueCat says the Pro entitlement is active (includes the free trial).
    @Published private(set) var isPro = false
    /// The signed-in account is one of the founder's (OwnerAccess).
    @Published private(set) var isOwner = false
    /// DEBUG-only: set by the UI tests' fixture store after a "purchase".
    @Published private(set) var debugProGranted = false

    private var authHandle: AuthStateDidChangeListenerHandle?

    /// What every paywall/upsell decision should read.
    var hasProAccess: Bool {
        isPro || isOwner || debugProGranted || TestLaunchConfig.debugBuildBypassesPaywall
    }

    /// Label for Profile's Pro row.
    var accessLabel: String {
        if isPro || debugProGranted { return "You\u{2019}re on Spilr Pro" }
        if isOwner { return "Spilr Pro \u{00B7} owner access" }
        return "Spilr Pro \u{00B7} debug build"
    }

    /// Refreshes `isPro` from RevenueCat. Call after sign-in and after a
    /// purchase/restore completes, where the UI wants an immediate read
    /// rather than waiting on the stream below to emit. Degrades silently —
    /// a failed read just means the UI shows "Upgrade" a beat longer than
    /// necessary, never the reverse — but the error itself is logged.
    func refresh() async {
        updateOwner(Auth.auth().currentUser)
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements[Self.proEntitlementId]?.isActive == true
        } catch {
            AnalyticsManager.shared.trackError(error, context: "entitlement_refresh_failed")
        }
    }

    /// Called by AIService when the server answers 402. `reason` is the
    /// server's (functions/lib/entitlement.js `decideAccess`):
    ///   preview_ended / expired → the free preview is over: show the paywall
    ///   daily_budget / surface_cap → a PAYING user hit today's safety cap:
    ///                                never show a paywall for that
    func noteAIBudgetExceeded(reason: String?) {
        guard Self.budgetReasonWarrantsPaywall(reason) else { return }
        PaywallPresenter.present(.aiLimit)
    }

    /// Pure, so it's unit-tested: only "your free preview is over" earns a
    /// paywall. A paying user's daily cap, a surface cap, or a 402 with no
    /// reason (e.g. Mirror Ask's own daily limit) never does.
    nonisolated static func budgetReasonWarrantsPaywall(_ reason: String?) -> Bool {
        reason == "preview_ended" || reason == "expired"
    }

    #if DEBUG
    func debugGrantPro() { debugProGranted = true }
    #endif

    /// Keeps `isPro` current without a manual `refresh()` call, so a renewal
    /// or expiry that happens while the app isn't showing Profile (or the
    /// paywall) is reflected the moment RevenueCat's cache updates. Runs for
    /// the lifetime of the app — this is a singleton that never deinits.
    private func observeCustomerInfo() {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.isPro = info.entitlements[Self.proEntitlementId]?.isActive == true
            }
        }
    }

    private func observeAuth() {
        updateOwner(Auth.auth().currentUser)
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.updateOwner(user) }
        }
    }

    private func updateOwner(_ user: User?) {
        isOwner = OwnerAccess.isOwner(email: user?.email, uid: user?.uid)
    }
}
