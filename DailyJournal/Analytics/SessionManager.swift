//
//  SessionManager.swift
//  DailyJournal
//
//  Tracks app lifecycle and per-session metrics.
//
//  A "session" here is one uninterrupted stretch in the foreground: it opens
//  the first time the app becomes active and closes when the app actually
//  enters the background. GA4 counts sessions its own way (a 30-minute
//  inactivity window) and this deliberately does not try to match it — what
//  this class exists for is the one number GA4 cannot derive, which is how
//  many entries were written during the stretch.
//

import UIKit
import Combine

@MainActor
final class SessionManager: NSObject, ObservableObject {

    static let shared = SessionManager()

    private static let signupDateKey = "user_signup_date"

    private var sessionStartTime: Date?
    private var entriesWrittenThisSession = 0
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupLifecycleTracking()
    }

    private func setupLifecycleTracking() {
        // didBecomeActive, not didFinishLaunching. SwiftUI creates this object
        // lazily from the `@StateObject` in DailyJournalApp, which can happen
        // after `didFinishLaunchingNotification` has already been posted — a
        // launch subscription is a race there is no reason to run.
        // didBecomeActive always fires after this object exists, on a cold
        // launch and on every return from background alike.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.beginSessionIfNeeded()
            }
            .store(in: &cancellables)

        // didEnterBackground, not willResignActive. willResignActive fires for
        // Control Centre, the notification shade, an incoming call and every
        // system alert — none of which is the user leaving — which reported
        // ~50% more departures than actually happened (165 against 112 real
        // backgroundings over 28 days).
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.endSession()
            }
            .store(in: &cancellables)
    }

    /// Opens a session unless one is already open.
    ///
    /// The guard is the point: after a transient interruption iOS posts
    /// didBecomeActive again with no didEnterBackground in between, and without
    /// it every Control Centre pull would restart the clock mid-session.
    private func beginSessionIfNeeded() {
        guard sessionStartTime == nil else { return }

        sessionStartTime = Date()
        entriesWrittenThisSession = 0

        // Tenure is a user property now, not a parameter on a session event,
        // so every event this person sends is already segmented by it. Set at
        // the start of each session so it stays current as the user ages.
        let signupDate = UserDefaults.standard.object(forKey: Self.signupDateKey) as? Date ?? Date()
        let daysSinceSignup = Calendar.current.dateComponents(
            [.day], from: signupDate, to: Date()
        ).day ?? 0

        Task { @MainActor in
            AnalyticsManager.shared.setDaysSinceSignup(daysSinceSignup)
        }
    }

    /// Closes the session and clears the clock so the next didBecomeActive
    /// opens a fresh one.
    ///
    /// Both of these used to be set once at app launch and never reset, so the
    /// second backgrounding of a launch reported a duration measured from the
    /// cold start, the third a longer one still, and `entries_written`
    /// accumulated across the entire lifetime of the process. 112 session_ended
    /// events landed across 44 GA4 sessions in 28 days, nearly all of them
    /// cumulative rather than per-session.
    private func endSession() {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let entriesWritten = entriesWrittenThisSession

        sessionStartTime = nil
        entriesWrittenThisSession = 0

        Task { @MainActor in
            AnalyticsManager.shared.trackSessionEnded(
                duration: duration,
                entriesWritten: entriesWritten
            )
        }
    }

    // MARK: - Public API

    func recordEntryWritten() {
        entriesWrittenThisSession += 1
    }

    func recordSignupDate() {
        UserDefaults.standard.set(Date(), forKey: Self.signupDateKey)
    }
}
