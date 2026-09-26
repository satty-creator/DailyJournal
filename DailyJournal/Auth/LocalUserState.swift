//
//  LocalUserState.swift
//  DailyJournal
//
//  Everything about the signed-in person that lives on the device rather than
//  in Firestore, and what to do with it when their account is deleted.
//
//  Deleting an account used to erase the server and leave the phone untouched,
//  which meant the next person to sign up on the same device inherited the
//  deleted user's state. Concretely, before this existed:
//
//   - `spilr.onboardingCompleted` stayed true, so RootView routed the new
//     account straight past onboarding into MainTabView. They never picked a
//     vibe, never saw the 7-day promise, never wrote a first entry.
//   - `spilr.aiConsentGranted` stayed set, so the new person's journal text
//     was sent for AI processing on a consent someone else had given. That's
//     the one that actually matters — Guideline 5.1.2(i) consent is personal,
//     not per-device.
//   - `spilr.onboardingGoals` and `spilr.spilrTone` stayed set, and those feed
//     `SpilrVoice.intentContext()`, which `cachedPromptContext()` appends to
//     *every* prompt in the app. The deleted user's goals shaped the new
//     user's reflections.
//   - `user_signup_date` stayed set, so every "days since signup" cohort in
//     analytics was measured from the wrong person's signup.
//
//  Sweeping by prefix rather than listing keys is deliberate. A hand-kept list
//  is what drifted in `FirestoreSchema.userSubcollections` and left four
//  collections surviving deletion; here, any future `spilr.` key is covered the
//  day it's written. The two keys outside that namespace are named explicitly
//  because nothing else can find them.
//

import Foundation

enum LocalUserState {

    /// Every device-local key the app writes lives under this namespace.
    private static let userKeyPrefix = "spilr."

    /// The stragglers that predate the namespace convention.
    /// - `ninety.selectedTheme` — chosen in onboarding's vibe picker.
    /// - `user_signup_date` — SessionManager's cohort anchor.
    private static let unnamespacedUserKeys = [
        "ninety.selectedTheme",
        "user_signup_date",
    ]

    /// Returns the device to the state a fresh install would be in.
    ///
    /// Only for account *deletion*. Sign-out deliberately leaves these alone —
    /// it's the same person coming back, and wiping their theme and onboarding
    /// progress every time they signed out would be hostile.
    @MainActor
    static func clearForDeletedAccount() {
        // The live ThemeManager holds the palette in memory and re-persists it
        // on write, so it has to be reset before the sweep — otherwise its
        // `didSet` would put `ninety.selectedTheme` straight back.
        ThemeManager.shared.select(.bloom)

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(userKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        unnamespacedUserKeys.forEach { defaults.removeObject(forKey: $0) }
    }
}
