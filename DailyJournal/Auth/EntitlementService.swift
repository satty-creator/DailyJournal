//
//  EntitlementService.swift
//  DailyJournal
//
//  Thin wrapper around RevenueCat's CustomerInfo so the rest of the app can ask
//  "is this user Pro?" without every call site touching the SDK directly.
//
//  This is a UI-layer convenience only — it does NOT gate AI calls. The real
//  enforcement is server-side, in `geminiProxy`'s token-budget check against
//  `aiUsage/{uid}.entitlement`, written by `revenueCatWebhook`
//  (functions/index.js). A client-side flag can lag the server truth (e.g.
//  right after a purchase, before the webhook lands) — never trust this for
//  anything a user could exploit, only for what button/copy to show.
//
//  See REVENUECAT_SETUP.md.
//

import Foundation
import RevenueCat

@MainActor
final class EntitlementService: ObservableObject {

    static let shared = EntitlementService()
    private init() {}

    /// Must match the identifier created in the RevenueCat dashboard
    /// (Product catalog → Entitlements) — see REVENUECAT_SETUP.md.
    static let proEntitlementId = "spilr_ai_mood_journal_pro"

    @Published private(set) var isPro = false

    /// Refreshes `isPro` from RevenueCat. Call after sign-in, on Profile
    /// appearing, and after a purchase/restore completes. Fails silently —
    /// a stale read just means the UI shows "Upgrade" a beat longer than
    /// necessary, never the reverse.
    func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        isPro = info.entitlements[Self.proEntitlementId]?.isActive == true
    }
}
