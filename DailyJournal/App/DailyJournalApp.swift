//
//  DailyJournalApp.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import FirebaseAppCheck
import FirebaseAnalytics
import GoogleSignIn
import RevenueCat

// MARK: - App Check

class NinetyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        AppCheckDebugProvider(app: app)
        #else
        AppAttestProvider(app: app)
        #endif
    }
}

// MARK: - App delegate (push notifications)
//
// SwiftUI's App lifecycle doesn't expose the UIKit remote-notification callbacks
// FCM needs, so we bridge a tiny UIApplicationDelegate. `FirebaseApp.configure()`
// still runs in `DailyJournalApp.init` (before this delegate's didFinishLaunching),
// so Messaging is safe to touch here.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushNotificationManager.shared.configure()
        // Refresh the APNs token every launch when permission already exists.
        PushNotificationManager.shared.registerIfAuthorized()
        return true
    }

    /// APNs handed us a device token — pass it to FCM so it can mint an FCM token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Registration failure is non-fatal: the user simply won't get pushes,
        // and the in-app sealed card still works. But it must not disappear
        // without a trace — this is exactly the failure mode that made a past
        // push outage invisible until a user reported it.
        AnalyticsManager.shared.trackError(error, context: "apns_registration_failed")
    }
}

@main
struct DailyJournalApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = SessionManager.shared

    init() {
        AppCheck.setAppCheckProviderFactory(NinetyAppCheckProviderFactory())
        FirebaseApp.configure()

        // Trial/paid entitlement layer (ai-cost-audit-2026-09-06.md Phase 5,
        // REVENUECAT_SETUP.md). Configured once, early, before any sign-in UI —
        // no appUserID here since the Firebase uid isn't known yet at launch;
        // RevenueCat assigns an anonymous id until AuthService.swift calls
        // Purchases.shared.logIn(uid) right after sign-in. That later logIn call
        // is what makes revenueCatWebhook's app_user_id match the Firebase uid
        // geminiProxy budgets against — see the note in AuthService.swift.
        #if DEBUG
        // Surfaces the underlying StoreKit/offerings error behind a bare
        // "Error 23: configuration" alert — otherwise invisible, since
        // EntitlementService/AuthService both swallow RevenueCat errors with
        // `try?`. Must be set before configure().
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: "appl_cEAPPXndXigFKNIjpttRQWIDEkE")

        // Explicitly enable the modern persistent on-disk cache. Setting only the
        // legacy `cacheSizeBytes` left reads going to the server first on every
        // load; with PersistentCacheSettings, queries can be served from disk
        // instantly (see JournalService's cache-first reads).
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB
        )
        Firestore.firestore().settings = settings

        // UI tests only (DEBUG builds): emulator suite, reset state, etc.
        // Must run before anything reads Firestore — see TestLaunchConfig.
        TestLaunchConfig.applyBeforeFirstUse()

        // Initialize analytics session tracking
        sessionManager.recordSignupDate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(themeManager)
                .environmentObject(sessionManager)
                .onOpenURL { url in
                    // Email verification link (universal link from the inbox).
                    if authViewModel.handleVerificationLink(url) { return }
                    // Completes the Google Sign-In redirect — required for the
                    // GIDSignIn flow started in AuthService to ever return.
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
