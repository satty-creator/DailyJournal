//
//  TestLaunchConfig.swift
//  DailyJournal
//
//  Launch arguments the UI tests (DailyJournalUITests) use to put the app into
//  a known state. Everything here is compiled into DEBUG builds only — a
//  Release/TestFlight/App Store build ignores every one of these flags.
//
//    -UITests                   master switch; implies the rest are honoured
//    -UseFirebaseEmulator       Auth/Firestore/Functions → local emulator suite
//    -UITestResetState          wipe UserDefaults (fresh install) before launch
//    -UITestSignIn email:pass   sign in with email/password at launch
//    -UITestOnboardingDone      skip onboarding (returning user)
//    -UITestGrantAIConsent      pre-accept the AI consent
//    -UITestFixturePaywall      paywall uses fixture plans, not StoreKit
//    -DisableDebugProBypass     debug builds normally skip the paywall; this
//                               turns that off so the paywall can be tested
//
//  See scripts/run-e2e.sh for how the emulator side is seeded.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum TestLaunchConfig {

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static var isUITest: Bool {
        #if DEBUG
        return args.contains("-UITests")
        #else
        return false
        #endif
    }

    static var usesEmulator: Bool {
        #if DEBUG
        return args.contains("-UseFirebaseEmulator")
        #else
        return false
        #endif
    }

    static var usesFixturePaywall: Bool {
        #if DEBUG
        return args.contains("-UITestFixturePaywall")
        #else
        return false
        #endif
    }

    /// Debug builds run from Xcode on the founder's own devices never see the
    /// paywall (the "bypass my device" half of the owner bypass). The UI tests
    /// and anyone previewing the paywall turn it back on.
    static var debugBuildBypassesPaywall: Bool {
        #if DEBUG
        return !args.contains("-DisableDebugProBypass") && !isUITest
        #else
        return false
        #endif
    }

    /// Host for the emulator suite. The Simulator shares the Mac's loopback.
    static let emulatorHost = "127.0.0.1"
    static let emulatorProject = "spilr-100f7"

    /// Base URL for Cloud Functions, prod or emulator.
    static var functionsBaseURL: String {
        if usesEmulator {
            return "http://\(emulatorHost):5001/\(emulatorProject)/us-central1"
        }
        return "https://us-central1-spilr-100f7.cloudfunctions.net"
    }

    /// Call right after `FirebaseApp.configure()` and BEFORE anything touches
    /// Firestore (settings can't change after first use).
    static func applyBeforeFirstUse() {
        #if DEBUG
        guard isUITest || usesEmulator else { return }

        if args.contains("-UITestResetState"), let bundle = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundle)
        }
        if args.contains("-UITestOnboardingDone") {
            UserDefaults.standard.onboardingCompleted = true
        }
        if args.contains("-UITestGrantAIConsent") {
            UserDefaults.standard.aiConsentGranted = true
        }

        if usesEmulator {
            Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "\(emulatorHost):8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
        }
        #endif
    }

    /// Credentials from `-UITestSignIn email:password`, if present.
    static var signInCredentials: (email: String, password: String)? {
        #if DEBUG
        guard let i = args.firstIndex(of: "-UITestSignIn"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
        #else
        return nil
        #endif
    }

    /// Signs in with the test credentials, replacing any existing session.
    static func signInIfRequested() async {
        #if DEBUG
        guard let creds = signInCredentials else { return }
        // A fresh-install run re-signs in even as the same email: the emulator
        // may have been reset since the last run, leaving a stale Keychain
        // session for a uid that no longer exists.
        let fresh = args.contains("-UITestResetState")
        if !fresh, Auth.auth().currentUser?.email == creds.email { return }
        try? Auth.auth().signOut()
        _ = try? await Auth.auth().signIn(withEmail: creds.email, password: creds.password)
        #endif
    }
}
