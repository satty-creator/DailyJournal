//
//  SessionManager.swift
//  DailyJournal
//
//  Tracks app lifecycle (foreground/background) and session metrics.
//  Logs session duration, entries written, etc. when app closes.

import UIKit
import Combine

@MainActor
final class SessionManager: NSObject, ObservableObject {

    static let shared = SessionManager()

    private var sessionStartTime: Date?
    private var appReturnedFromBackground = false
    private var entriesWrittenThisSession = 0
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupLifecycleTracking()
    }

    private func setupLifecycleTracking() {
        NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in
                self?.trackAppLaunch()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.trackAppResumed()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.trackAppBackgrounded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.trackAppClosed()
            }
            .store(in: &cancellables)
    }

    private func trackAppLaunch() {
        sessionStartTime = Date()
        entriesWrittenThisSession = 0

        // Calculate days after signup
        let userDefaults = UserDefaults.standard
        let signupDate = userDefaults.object(forKey: "user_signup_date") as? Date ?? Date()
        let daysAfterSignup = Calendar.current.dateComponents([.day], from: signupDate, to: Date()).day ?? 0

        Task { @MainActor in
            AnalyticsManager.shared.trackSessionStarted(daysAfterSignup: daysAfterSignup)
        }
    }

    private func trackAppResumed() {
        appReturnedFromBackground = true
        Task { @MainActor in
            AnalyticsManager.shared.logEvent(.appForegrounded)
        }
    }

    private func trackAppBackgrounded() {
        Task { @MainActor in
            AnalyticsManager.shared.logEvent(.appBackgrounded)
        }
    }

    private func trackAppClosed() {
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            Task { @MainActor in
                AnalyticsManager.shared.trackSessionEnded(
                    duration: duration,
                    entriesWritten: entriesWrittenThisSession
                )
            }
        }
    }

    // MARK: - Public API

    func recordEntryWritten() {
        entriesWrittenThisSession += 1
    }

    func recordSignupDate() {
        UserDefaults.standard.set(Date(), forKey: "user_signup_date")
    }
}
