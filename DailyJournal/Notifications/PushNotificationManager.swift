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
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
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
            ], merge: true)
    }

    /// Best-effort removal of the current device token on sign-out so the user
    /// stops receiving reads on a device they've left.
    func removeCurrentToken() {
        guard let uid = Auth.auth().currentUser?.uid,
              let token = Messaging.messaging().fcmToken else { return }
        db.collection("users").document(uid)
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
}
