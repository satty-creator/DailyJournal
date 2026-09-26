//
//  PushNotificationManager.swift
//  DailyJournal
//
//  Firebase Cloud Messaging (FCM) plumbing — device token registration.
//
//  Flow:
//    1. The app asks the user for notification permission, then registers with
//       APNs (Apple Push Notification service).
//    2. FCM sits on top of APNs and hands us a device token via the
//       MessagingDelegate.
//    3. We persist that token at `users/{uid}/pushTokens/{token}` for any
//       future server-side push to target this device.
//
//  CONSOLE STEP (one-time, not code): an APNs Auth Key (.p8) must be uploaded to
//  the Firebase project under Project Settings → Cloud Messaging, and the app
//  target needs the Push Notifications capability + the "remote notification"
//  background mode.
//

import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {

    static let shared = PushNotificationManager()
    private override init() { super.init() }

    private let db = Firestore.firestore()

    /// Synthetic errors for failure paths that don't hand us a real `Error`,
    /// so they can still go through `AnalyticsManager.trackError`'s normal
    /// convention instead of disappearing silently.
    private enum PushError: Error {
        case permissionDenied
    }

    /// Snapshot of every link in the push chain, for Profile → Developer.
    /// Each field answers one "why didn't it arrive?" question.
    struct Diagnostics {
        var permission: UNAuthorizationStatus
        var registeredForRemote: Bool
        var apnsTokenPresent: Bool
        var fcmToken: String?
        var tokenSavedInFirestore: Bool
        var fcmError: String?
    }

    // MARK: - Setup

    /// Wire up the FCM + notification-centre delegates. Call once at launch,
    /// AFTER `FirebaseApp.configure()` has run.
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for permission and, if granted, register with APNs. Safe to call on
    /// every Home appearance — iOS only shows the system prompt once.
    func requestAuthorization() {
        // UI tests: the system alert would sit over the app and make every
        // element un-tappable. Push has its own diagnostics (Profile → Developer).
        if TestLaunchConfig.isUITest { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                AnalyticsManager.shared.trackError(error, context: "push_authorization_request_failed")
            }
            guard granted else {
                AnalyticsManager.shared.trackError(PushError.permissionDenied, context: "push_permission_denied")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Current OS-level notification authorization — lets the UI tell "haven't
    /// asked yet" apart from "denied" apart from "on", none of which
    /// `requestAuthorization()` alone can distinguish once the system prompt
    /// has already been shown once.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Re-registers with APNs on every launch when permission is already
    /// granted. Apple's guidance is to call `registerForRemoteNotifications`
    /// at each launch — the APNs token can change (restore from backup, new
    /// device, OS update) and previously we only registered at the moment of
    /// the permission prompt, so a changed token was never picked up.
    func registerIfAuthorized() {
        Task {
            let status = await currentAuthorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Walks the whole chain: OS permission → APNs registration → FCM token →
    /// Firestore. Used by Profile → Developer.
    func diagnostics() async -> Diagnostics {
        var d = Diagnostics(
            permission: await currentAuthorizationStatus(),
            registeredForRemote: UIApplication.shared.isRegisteredForRemoteNotifications,
            apnsTokenPresent: Messaging.messaging().apnsToken != nil,
            fcmToken: nil,
            tokenSavedInFirestore: false,
            fcmError: nil
        )
        do {
            let token = try await Messaging.messaging().token()
            d.fcmToken = token
            if let uid = Auth.auth().currentUser?.uid {
                let snap = try? await db.collection("users").document(uid)
                    .collection("pushTokens").document(token).getDocument(source: .server)
                d.tokenSavedInFirestore = snap?.exists == true
                // Self-heal: if we have a token but it never reached Firestore,
                // write it now — this is the exact state push was stuck in.
                if !d.tokenSavedInFirestore { saveToken(token) }
            }
        } catch {
            d.fcmError = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "fcm_token_fetch_failed")
        }
        return d
    }

    // MARK: - Token persistence

    /// Persist the FCM token for the signed-in user. Keyed by the token itself so
    /// a device that re-registers updates in place and stale tokens accumulate
    /// harmlessly (the sender prunes on `messaging/registration-token-not-registered`).
    func saveToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("pushTokens").document(token)
            .setData([
                "token":     token,
                "platform":  "ios",
                "updatedAt": Timestamp(date: Date())
            ], merge: true) { error in
                // Still fire-and-forget (nothing waits on this), but a failed
                // write is no longer silent.
                if let error {
                    AnalyticsManager.shared.trackError(error, context: "push_token_save_failed")
                }
            }
    }

    /// Re-persists whatever FCM token is already cached, once a uid is known.
    ///
    /// `configure()` wires the `MessagingDelegate` at app launch, before
    /// Firebase Auth necessarily has a resolved `currentUser`. If FCM hands us
    /// an already-cached token during that window, `saveToken` silently drops
    /// it (no uid yet) — and since the token hasn't changed, FCM has no reason
    /// to redeliver it later, so the drop is permanent. Call this once sign-in
    /// resolves to close that gap.
    func resaveCurrentTokenIfNeeded() {
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                // Most common cause: no APNs token yet (permission not granted,
                // or APNs registration failed). Logged so it isn't invisible.
                AnalyticsManager.shared.trackError(error, context: "fcm_token_fetch_failed")
            }
            guard let token else { return }
            Task { @MainActor in self?.saveToken(token) }
        }
    }

    /// Best-effort removal of the current device token on sign-out so the user
    /// stops receiving reads on a device they've left.
    ///
    /// `nonisolated` on purpose: `AuthService.signOut()` must call this BEFORE
    /// `Auth.auth().signOut()` clears `currentUser` (a fire-and-forget
    /// `Task { @MainActor in ... }` wouldn't run in time — sign-out proceeds
    /// synchronously right after). `AuthService` itself isn't `@MainActor`, so
    /// this needs to be callable without hopping actors. Safe because the body
    /// only touches thread-safe Firebase SDK statics, not this instance's
    /// isolated state — hence `Firestore.firestore()` here rather than `db`.
    nonisolated func removeCurrentToken() {
        guard let uid = Auth.auth().currentUser?.uid,
              let token = Messaging.messaging().fcmToken else { return }
        Firestore.firestore().collection("users").document(uid)
            .collection("pushTokens").document(token)
            .delete(completion: nil)
    }
}

// MARK: - MessagingDelegate

extension PushNotificationManager: MessagingDelegate {

    nonisolated func messaging(_ messaging: Messaging,
                               didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in self.saveToken(fcmToken) }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    /// Show the read's banner even when the app is in the foreground — the whole
    /// point is the morning curiosity hook.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// The user tapped a push (banner, lock screen, or notification centre) —
    /// route by the `type` the server put in `data`. FCM merges `data` straight
    /// into `userInfo`, so no FCM-specific parsing is needed here. Exactly three
    /// values exist today (`sendPushToUser` call sites in `functions/index.js`):
    /// "weekly_letter", "daily_reading", "unlock_hint". Anything else — including
    /// a payload with no `type` at all — does nothing, the same as before this
    /// method existed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let type = response.notification.request.content.userInfo["type"] as? String
        await MainActor.run {
            switch type {
            case "weekly_letter":
                // The Mirror tab fetches the letter fresh from the server on this
                // flag — a push means one was just written, and the cache-first
                // read `loadLatest` normally uses would still show last week's.
                AppRouter.shared.openWeeklyLetter()
            case "daily_reading", "unlock_hint":
                // Both are about writing/reading on Home, not the Mirror tab —
                // "daily_reading" surfaces via HomeView's `spilrNoticedCard`
                // (reads `mirrorVM.bridgeInsightTitle`), and "unlock_hint" is a
                // nudge to write, not a Mirror destination.
                AppRouter.shared.selectedTab = .today
            default:
                break
            }
        }
    }
}
