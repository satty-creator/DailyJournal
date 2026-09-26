//
//  PaywallPresenter.swift
//  DailyJournal
//
//  Presents the Spilr Pro paywall from anywhere — including from inside a
//  full-screen cover like Daily Chat, where a SwiftUI `.sheet` on the tab view
//  underneath can't present ("only one sheet at a time"). It finds the
//  top-most view controller and presents a hosting controller on top of it.
//
//  Throttling lives here too, so no call site can nag:
//    - never while one is already showing
//    - never for Pro users, owners, or debug builds (see EntitlementService)
//    - the AI-limit paywall at most once per 20 hours
//

import SwiftUI
import UIKit

@MainActor
enum PaywallPresenter {

    private static weak var current: UIViewController?

    static let aiLimitCooldown: TimeInterval = 20 * 60 * 60
    private static let lastAILimitShownKey = "spilr.paywall.lastAILimitShownAt"
    private static let pendingOnboardingKey = "spilr.paywall.pendingOnboarding"

    /// Set by onboarding when it finishes; consumed by MainTabView.
    static var hasPendingOnboardingPaywall: Bool {
        get { UserDefaults.standard.bool(forKey: pendingOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingOnboardingKey) }
    }

    static var isShowing: Bool { current != nil }

    /// In-memory claim on the onboarding paywall. MainTabView's `.task` can run
    /// more than once (the tab view is rebuilt as RootView transitions), and
    /// each run awaits before presenting — without this, a second run
    /// presented a second paywall right after the user dismissed the first.
    static var onboardingPaywallClaimed = false

    /// Whether a paywall for `trigger` should be shown right now.
    static func shouldPresent(_ trigger: PaywallTrigger, now: Date = Date()) -> Bool {
        if isShowing { return false }
        if EntitlementService.shared.hasProAccess { return false }
        if trigger == .aiLimit,
           let last = UserDefaults.standard.object(forKey: lastAILimitShownKey) as? Date,
           now.timeIntervalSince(last) < aiLimitCooldown {
            return false
        }
        return true
    }

    /// Presents the paywall on top of whatever is on screen. `onDismiss` runs
    /// after it closes (whether or not the user bought).
    static func present(_ trigger: PaywallTrigger, onDismiss: (() -> Void)? = nil) {
        guard shouldPresent(trigger) else { onDismiss?(); return }
        guard let top = topViewController() else { onDismiss?(); return }

        if trigger == .aiLimit {
            UserDefaults.standard.set(Date(), forKey: lastAILimitShownKey)
        }

        // Weak: the hosting controller owns this closure, so a strong capture
        // would leak the paywall (and keep `isShowing` true forever).
        weak var host: UIHostingController<AnyView>?
        let view = SpilrPaywallView(trigger: trigger) {
            host?.dismiss(animated: true) { onDismiss?() }
        }
        .environmentObject(ThemeManager.shared)
        .preferredColorScheme(ThemeManager.shared.colorScheme)

        let controller = UIHostingController(rootView: AnyView(view))
        controller.modalPresentationStyle = trigger == .onboarding ? .fullScreen : .pageSheet
        // Swipe-to-dismiss would skip "Not yet"'s delay on the onboarding
        // paywall; the view itself re-enables it once "Not yet" appears.
        controller.isModalInPresentation = trigger == .onboarding
        host = controller
        current = controller
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
