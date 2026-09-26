//
//  CalendarService.swift
//  DailyJournal
//
//  Read-only Google Calendar access for the Calendar tab (Home → calendar
//  icon). Phase 1: view-only. Deliberately does NOT feed anything into AI
//  prompts or Firestore — this is a live, user-initiated read screen, not a
//  background context feed. That's future scope (see CalendarView.swift).
//
//  Reuses the same GIDSignIn + Firebase pattern as AuthService's Google
//  sign-in (see AuthService.signInWithGoogle), but requests an *additional*,
//  narrower scope (calendar.events.readonly) rather than authenticating —
//  a user signed in with Apple or email gets a Google session created solely
//  for calendar access, which is never exchanged into a Firebase credential
//  so it can't silently change their sign-in provider.
//

import Foundation
import UIKit
import GoogleSignIn
import FirebaseCore

final class CalendarService {
    static let shared = CalendarService()
    private init() {}

    enum Status: Equatable {
        case notConnected
        /// A Google session exists but doesn't (or no longer) carries the
        /// calendar scope — e.g. the user declined it, or revoked it from
        /// their Google Account settings.
        case scopeDenied
        case connected
    }

    struct CalendarEvent: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let location: String?
        let isAllDay: Bool
    }

    enum CalendarError: Error {
        case notConnected
        case presentationUnavailable
        case requestFailed
    }

    private static let scope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private static let connectedKey = "spilr.calendarConnected"

    var isConnected: Bool {
        UserDefaults.standard.bool(forKey: Self.connectedKey)
    }

    func currentStatus() -> Status {
        guard isConnected else { return .notConnected }
        guard let user = GIDSignIn.sharedInstance.currentUser,
              user.grantedScopes?.contains(Self.scope) == true else {
            return .scopeDenied
        }
        return .connected
    }

    /// Requests calendar read access, presenting Google's consent screen.
    /// Returns `true` only if the specific calendar scope was granted — a
    /// user can complete the flow while declining just that scope, which
    /// must read as "not connected," not success.
    @discardableResult
    func connect() async -> Bool {
        guard let presenter = await Self.rootViewController() else { return false }

        do {
            let grantedScopes: [String]?
            if let existingUser = GIDSignIn.sharedInstance.currentUser {
                let result = try await existingUser.addScopes([Self.scope], presenting: presenter)
                grantedScopes = result.user.grantedScopes
            } else {
                guard let clientID = FirebaseApp.app()?.options.clientID else { return false }
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter, hint: nil, additionalScopes: [Self.scope]
                )
                grantedScopes = result.user.grantedScopes
            }

            guard grantedScopes?.contains(Self.scope) == true else {
                UserDefaults.standard.set(false, forKey: Self.connectedKey)
                return false
            }
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            return true
        } catch {
            return false
        }
    }

    /// Stops using the calendar locally. Does not force a Google sign-out
    /// (would break auth for users who signed in with Google) and can't
    /// revoke the scope server-side — only the user's Google Account
    /// settings can do that.
    func disconnect() {
        UserDefaults.standard.set(false, forKey: Self.connectedKey)
    }

    /// Fetches events for the month containing `date` (padded a week on each
    /// side so a calendar grid's leading/trailing days from adjacent months
    /// aren't missing events), from the primary Google Calendar only.
    /// Title, time, and location only — never description/attendees.
    func fetchEvents(monthContaining date: Date) async throws -> [CalendarEvent] {
        guard isConnected, let user = GIDSignIn.sharedInstance.currentUser else {
            throw CalendarError.notConnected
        }

        let refreshedUser: GIDGoogleUser
        do {
            refreshedUser = try await user.refreshTokensIfNeeded()
        } catch {
            throw CalendarError.notConnected
        }
        let accessToken = refreshedUser.accessToken.tokenString

        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let timeMin = calendar.date(byAdding: .day, value: -7, to: monthInterval.start) ?? monthInterval.start
        let timeMax = calendar.date(byAdding: .day, value: 7, to: monthInterval.end) ?? monthInterval.end

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: Self.isoFormatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: Self.isoFormatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        guard let url = components.url else { throw CalendarError.requestFailed }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CalendarError.requestFailed
        }

        guard let http = response as? HTTPURLResponse else { throw CalendarError.requestFailed }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                // Scope likely revoked on Google's side — reflect that locally
                // so the UI naturally offers "Connect" again.
                UserDefaults.standard.set(false, forKey: Self.connectedKey)
            }
            throw CalendarError.requestFailed
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["items"] as? [[String: Any]]
        else { return [] }

        return items.compactMap(Self.parseEvent)
    }

    // MARK: - Parsing

    private static func parseEvent(_ item: [String: Any]) -> CalendarEvent? {
        guard let id = item["id"] as? String,
              let startInfo = item["start"] as? [String: Any],
              let endInfo = item["end"] as? [String: Any]
        else { return nil }

        let title = (item["summary"] as? String) ?? "(No title)"
        let location = item["location"] as? String

        if let dateOnly = startInfo["date"] as? String,
           let endDateOnly = endInfo["date"] as? String,
           let start = dayFormatter.date(from: dateOnly),
           let end = dayFormatter.date(from: endDateOnly) {
            return CalendarEvent(id: id, title: title, start: start, end: end, location: location, isAllDay: true)
        }

        guard
            let startStr = startInfo["dateTime"] as? String,
            let endStr = endInfo["dateTime"] as? String,
            let start = parseDateTime(startStr),
            let end = parseDateTime(endStr)
        else { return nil }

        return CalendarEvent(id: id, title: title, start: start, end: end, location: location, isAllDay: false)
    }

    private static func parseDateTime(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? fractionalISOFormatter.date(from: string)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Presentation

    @MainActor
    private static func rootViewController() async -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else { return nil }
        return rootViewController
    }
}
