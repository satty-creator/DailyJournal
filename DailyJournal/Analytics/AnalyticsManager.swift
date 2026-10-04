//
//  AnalyticsManager.swift
//  DailyJournal
//
//  Centralized analytics tracking for Firebase Analytics + custom logging.
//  All user behavior is tracked to understand: page usage, drop-off, engagement.

import Foundation
import FirebaseAnalytics

// MARK: - Analytics Events

/// Screen names sent as `firebase_screen` on the reserved `screen_view`
/// event. Deliberately unprefixed: GA4 already shows these under the
/// `screen_view` event, so a `screen_` prefix rendered every row as
/// "screen_view / screen_home_today".
enum AnalyticsScreen: String {
    case home = "home_today"
    case journal = "journal_list"
    case mirror = "mirror"
    case authLogin = "auth_login"
    case authSignup = "auth_signup"
    case onboarding = "onboarding"
    case entryEditor = "entry_editor"
}

enum AnalyticsEvent: String {
    // Auth events
    case signupStarted = "signup_started"
    case signupCompleted = "signup_completed"
    case loginCompleted = "login_completed"
    case signoutCompleted = "signout_completed"
    case accountDeleted = "account_deleted"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case onboardingVibeSelected = "onboarding_vibe_selected"
    case onboardingStepViewed = "onboarding_step_viewed"
    case onboardingStruggleSelected = "onboarding_struggle_selected"
    case onboardingPeopleCount = "onboarding_people_count"
    case onboardingBaselineSet = "onboarding_baseline_set"
    case onboardingFirstEntryDelta = "onboarding_first_entry_delta"

    // Entry creation
    case entryCompositionStarted = "entry_composition_started"
    case entryCreated = "entry_created"
    case entryEdited = "entry_edited"
    case entryDeleted = "entry_deleted"
    case entryDrafted = "entry_drafted"
    case entryDiscarded = "entry_discarded"

    // Template box-breathing step (see `TemplateStep.Kind.breathing`)
    case templateBreathingCompleted = "template_breathing_completed"
    case templateBreathingSkipped = "template_breathing_skipped"

    // Entry features
    case moodLogged = "mood_logged"
    case moodClicked = "mood_clicked"
    case photoAdded = "photo_added"

    // AI features
    case aiConsentGranted = "ai_consent_granted"
    case aiConsentDenied = "ai_consent_denied"
    case aiConsentToggled = "ai_consent_toggled"
    case aiInsightsGenerated = "ai_insights_generated"
    case aiInsightsFailed = "ai_insights_failed"
    case aiInsightsViewed = "ai_insights_viewed"

    // Google Calendar (view-only, Phase 1 — see Calendar/CalendarService.swift)
    case calendarConnected = "calendar_connected"
    case calendarDisconnected = "calendar_disconnected"
    case calendarConsentDeclined = "calendar_consent_declined"

    // Echo system
    case echoSurfaced = "echo_surfaced"
    case echoAnswered = "echo_answered"
    case echoDismissed = "echo_dismissed"
    case echoExpired = "echo_expired"
    case echoThemeExplored = "echo_theme_explored"

    // Pattern system
    case patternSurfaced = "pattern_surfaced"
    case patternDismissed = "pattern_dismissed"
    case patternExplored = "pattern_explored"
    case patternEvidenceViewed = "pattern_evidence_viewed"
    case patternDetectionFailed = "pattern_detection_failed"

    // Mirror (Self-Model)
    case mirrorHypothesisViewed = "mirror_hypothesis_viewed"
    case mirrorHypothesisCollapsed = "mirror_hypothesis_collapsed"
    case mirrorHypothesisEdited = "mirror_hypothesis_edited"
    case mirrorGraphViewed = "mirror_graph_viewed"

    // Mirror v3.1 — the Person Model (mirror-v3.1-person-model-2026-09-10.md
    // §10). `mirrorReadingFeedback`'s `feedback == "huh"` share IS the
    // "Didn't know that" metric (target >= 25% of shown lines); `feedback ==
    // "almost" && reason == "wrong"` by `shape` is the Not-quite -> Wrong
    // rate the doc asks be broken out per shape.
    case mirrorReadingFeedback = "mirror_reading_feedback"
    case mirrorAskUsed = "mirror_ask_used"
    case mirrorOpenHypothesisTapped = "mirror_open_hypothesis_tapped"
    case weeklyLetterOpened = "weekly_letter_opened"

    // Chat
    case dailyChatStarted = "daily_chat_started"
    case dailyChatCompleted = "daily_chat_completed"
    case cbtModeStarted = "cbt_mode_started"
    case cbtModeCompleted = "cbt_mode_completed"

    // Journal interactions
    case journalFiltered = "journal_filtered"
    case journalSearched = "journal_searched"
    case entryViewed = "entry_viewed"

    // Theme & Appearance
    case themeChanged = "theme_changed"

    // Spilr Pro paywall
    case paywallShown = "paywall_shown"
    case paywallPurchased = "paywall_purchased"
    case paywallDismissed = "paywall_dismissed"

    // Settings
    case settingsOpened = "settings_opened"
    case privacyPolicyViewed = "privacy_policy_viewed"
    case feedbackSent = "feedback_sent"

    // Session events
    //
    // There is deliberately NO custom "session started" event. GA4 already
    // emits `session_start`, and a custom `session_started` one character away
    // from it gave the same report two contradictory session counts (387 vs 44
    // over the same 28 days) with no way to tell which to believe. Tenure is a
    // user property now — `setDaysSinceSignup` — so every event a person sends
    // is already segmented by how long they have been here, which is strictly
    // more useful than the same number on one event.
    //
    // `app_foregrounded` / `app_backgrounded` went the same way: GA4 derives
    // both, and `app_backgrounded` was bound to `willResignActive`, so pulling
    // down Control Centre or receiving a system alert counted as leaving the
    // app (165 of those against 112 real backgroundings).
    //
    // `session_ended` stays, because it carries the one thing GA4 cannot
    // derive: how many entries were written during the session.
    case sessionEnded = "session_ended"

    // Error tracking
    //
    // NOT "firebase_error" — Firebase Analytics silently drops any event whose
    // name starts with a reserved prefix (`firebase_`, `google_`, `ga_`), logging
    // only "[FirebaseAnalytics][I-ACS013007] Event name uses reserved prefix.
    // Ignoring event: firebase_error" to the console. That made trackError(_:context:)
    // — the one path meant to make a silent failure (e.g. a denied Storage write on
    // a photo upload) diagnosable — itself silently do nothing, for every error this
    // app has ever tracked.
    case firebaseError = "app_error"
    case verificationEmailSent = "verification_email_sent"
    case networkError = "network_error"
    case aiServiceError = "ai_service_error"
}

// MARK: - Analytics Manager

@MainActor
final class AnalyticsManager {

    static let shared = AnalyticsManager()
    private init() {}

    // MARK: - Screen Tracking

    /// Track screen view (auto-called by views via onAppear).
    ///
    /// This MUST be the reserved `screen_view` event carrying the reserved
    /// `firebase_screen` / `firebase_screen_class` parameters — GA4's Screens
    /// report, Path exploration and every screen-to-screen funnel read those
    /// keys and nothing else. It previously logged `AnalyticsEvent
    /// .sessionStarted` with a custom `screen_name` param, which meant the app
    /// emitted no screen events at all: the Screens report showed only the
    /// UIKit controllers Firebase auto-collects (`PlatformAlertController`,
    /// `PUPickerUnavailable`), and ~275 of the 387 "session_started" events in
    /// a 28-day window were actually screen views wearing a session's name.
    func trackScreenView(_ screen: AnalyticsScreen, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params[AnalyticsParameterScreenName] = screen.rawValue
        params[AnalyticsParameterScreenClass] = screen.rawValue

        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)

        #if DEBUG
        print("📊 Screen: \(screen.rawValue)")
        #endif
    }

    // MARK: - Event Tracking

    /// Log a custom event with optional parameters.
    ///
    /// No `timestamp` parameter is attached here. GA4 stamps `event_timestamp`
    /// on every event at microsecond precision; the ISO-8601 string this used
    /// to add spent one of the 25 parameter slots available per event (and one
    /// of the 50 registerable custom dimensions, had it ever been registered)
    /// to restate it, and allocated a fresh `ISO8601DateFormatter` each time.
    func logEvent(_ event: AnalyticsEvent, parameters: [String: Any]? = nil) {
        let params = parameters ?? [:]

        Analytics.logEvent(event.rawValue, parameters: params)

        #if DEBUG
        print("📊 Event: \(event.rawValue) | Params: \(params)")
        #endif
    }

    // MARK: - User Properties (Cohort/Segment)

    /// Set user ID for cohort analysis (called after auth)
    func setUserId(_ userId: String) {
        Analytics.setUserID(userId)
    }

    /// Set user property for segmentation (e.g., AI consent, subscription tier)
    func setUserProperty(_ value: String, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    // MARK: - Parameter helpers

    /// GA4 stores a Swift `Bool` as 1/0, which can only be registered as a
    /// custom *metric* and reads as "1" / "0" in every breakdown. A flag we
    /// want to slice by is a dimension, not a measurement, so it goes as text.
    private func flag(_ value: Bool) -> String { value ? "true" : "false" }

    // MARK: - Pre-built Event Shortcuts

    // Auth
    func trackSignupStarted() {
        logEvent(.signupStarted)
    }

    func trackSignupCompleted(provider: String) {
        logEvent(.signupCompleted, parameters: ["provider": provider])
    }

    func trackLoginCompleted(provider: String) {
        logEvent(.loginCompleted, parameters: ["provider": provider])
    }

    // Onboarding
    func trackOnboardingStarted() {
        logEvent(.onboardingStarted)
    }

    func trackOnboardingCompleted(totalSteps: Int, duration: TimeInterval, wroteFirstEntry: Bool = true) {
        logEvent(.onboardingCompleted, parameters: [
            "total_steps": totalSteps,
            "duration_seconds": Int(duration),
            "wrote_first_entry": wroteFirstEntry
        ])
    }

    func trackOnboardingStepViewed(_ step: String) {
        logEvent(.onboardingStepViewed, parameters: ["step": step])
    }

    func trackOnboardingStruggleSelected(option: String, hasDetail: Bool) {
        logEvent(.onboardingStruggleSelected, parameters: ["option": option, "has_detail": hasDetail])
    }

    func trackOnboardingPeopleCount(_ count: Int) {
        logEvent(.onboardingPeopleCount, parameters: ["count": count])
    }

    func trackOnboardingBaselineSet(_ value: Int) {
        logEvent(.onboardingBaselineSet, parameters: ["value": value])
    }

    func trackOnboardingFirstEntryDelta(before: Int?, after: Int?) {
        var params: [String: Any] = [:]
        if let before { params["before"] = before }
        if let after { params["after"] = after }
        logEvent(.onboardingFirstEntryDelta, parameters: params)
    }

    // Entry creation
    func trackEntryCompositionStarted(sessionType: String) {
        logEvent(.entryCompositionStarted, parameters: ["session_type": sessionType])
    }

    /// The activation event — "this person wrote something".
    ///
    /// Called from exactly one place: `EntryEnrichment.run`, the shared
    /// post-save tail every composer already runs. When each surface owned its
    /// own call, two of the four never made it — `TimedSessionViewModel`
    /// (the spill flow, via `SpillWriteView`) and `DailyChatView` both saved
    /// the entry and logged nothing — so the app's single most important event
    /// undercounted by an unknown margin and no two surfaces were comparable.
    /// One call site on the path every composer must take is the only version
    /// of this a fifth composer cannot forget.
    ///
    /// `has_ai_insights` is gone. At save time no composer knows whether AI
    /// enrichment will return anything: the Gemini call is detached and starts
    /// *after* this fires. `ai_available` replaces it with something true at
    /// the moment of the event — whether this person has AI enabled at all —
    /// which is the cohort split that was actually wanted.
    func trackEntryCreated(
        sessionType: String,
        wordCount: Int,
        hasMood: Bool,
        hasPhoto: Bool,
        aiAvailable: Bool,
        compositionSeconds: Int? = nil
    ) {
        var params: [String: Any] = [
            "session_type": sessionType,
            "word_count": wordCount,
            "has_mood": flag(hasMood),
            "has_photo": flag(hasPhoto),
            "ai_available": flag(aiAvailable)
        ]
        // Sent only by composers that actually know when composition began.
        // The freeWrite editor used to pass `Date().timeIntervalSince(entry
        // .createdAt)`, which is always ~0 — `createdAt` is stamped when the
        // entry is constructed, milliseconds before the save — so every
        // composition time this app has ever reported was zero.
        if let compositionSeconds {
            params["composition_time_seconds"] = compositionSeconds
        }

        logEvent(.entryCreated, parameters: params)
    }

    /// The counterpart to `trackEntryCreated`: someone composed and threw it
    /// away. Same `session_type` dimension, so the two can be compared surface
    /// by surface.
    func trackEntryDiscarded(sessionType: String, wordCount: Int) {
        logEvent(.entryDiscarded, parameters: [
            "session_type": sessionType,
            "word_count": wordCount
        ])
    }

    // Mood
    func trackMoodLogged(mood: String) {
        logEvent(.moodLogged, parameters: ["mood": mood])
    }

    // AI
    func trackAIConsentGranted() {
        logEvent(.aiConsentGranted)
        setUserProperty("true", forName: "ai_consent_granted")
    }

    func trackAIConsentDenied() {
        logEvent(.aiConsentDenied)
        setUserProperty("false", forName: "ai_consent_granted")
    }

    func trackAIInsightsGenerated(
        entryType: String,
        bulletCount: Int,
        hasQuestion: Bool,
        latency: TimeInterval
    ) {
        logEvent(.aiInsightsGenerated, parameters: [
            "entry_type": entryType,
            "bullet_count": bulletCount,
            "has_question": hasQuestion,
            "latency_ms": Int(latency * 1000)
        ])
    }

    func trackAIInsightsFailed(error: String) {
        logEvent(.aiInsightsFailed, parameters: ["error": error])
    }

    // Echo
    func trackEchoSurfaced(type: String, confidence: Double) {
        logEvent(.echoSurfaced, parameters: [
            "echo_type": type,
            "confidence": confidence
        ])
    }

    func trackEchoAnswered(hasResponse: Bool) {
        logEvent(.echoAnswered, parameters: ["has_response": hasResponse])
    }

    func trackEchoDismissed() {
        logEvent(.echoDismissed)
    }

    // Pattern
    func trackPatternDismissed() {
        logEvent(.patternDismissed)
    }

    // Mirror v3.1
    func trackMirrorReadingFeedback(feedback: String, reason: String?, shape: String?) {
        var params: [String: Any] = ["feedback": feedback]
        if let reason { params["reason"] = reason }
        if let shape { params["shape"] = shape }
        logEvent(.mirrorReadingFeedback, parameters: params)
    }

    func trackMirrorAskUsed() {
        logEvent(.mirrorAskUsed)
    }

    /// `source` is "banner" (in-app, tapped from the Mirror tab) or "push"
    /// (opened via the notification tap) — separates in-app discovery from
    /// push delivery for the weekly-letter open-rate metric (PRD §10).
    func trackWeeklyLetterOpened(source: String) {
        logEvent(.weeklyLetterOpened, parameters: ["source": source])
    }

    // Journal interactions
    //
    // Deliberately logs the query's LENGTH, never its text — entry content and
    // search terms are private, and Firebase Analytics is not a place private
    // journal text (someone's search for a name, a diagnosis, anything) should
    // ever land, even coarsely. Same reasoning as `EntryEncryption` / the AI
    // consent gate: what leaves the device is minimised on purpose.
    func trackJournalSearched(queryLength: Int) {
        logEvent(.journalSearched, parameters: ["query_length": queryLength])
    }

    // Same reasoning as trackJournalSearched — tags are free-form and can be as
    // personal as a search term (a name, a diagnosis), so only the fact that a
    // filter was applied is logged, never the tag's text.
    func trackJournalFiltered() {
        logEvent(.journalFiltered)
    }

    func trackEntryViewed(sessionType: String, age: TimeInterval) {
        logEvent(.entryViewed, parameters: [
            "session_type": sessionType,
            "age_days": Int(age / 86400)
        ])
    }

    // Session

    /// Tenure as a user property rather than a parameter on one event, so
    /// *every* event this person sends can be split by how long they have been
    /// here — retention, activation and feature use all at once — instead of
    /// only the session event that happened to carry it. Refreshed whenever a
    /// session begins. See the `sessionEnded` note in `AnalyticsEvent` for why
    /// the custom session-start event it replaced is gone.
    func setDaysSinceSignup(_ days: Int) {
        setUserProperty(String(days), forName: "days_since_signup")
    }

    func trackSessionEnded(duration: TimeInterval, entriesWritten: Int) {
        logEvent(.sessionEnded, parameters: [
            "session_duration_seconds": Int(duration),
            "entries_written": entriesWritten
        ])
    }

    // Theme
    func trackThemeChanged(themeId: String, isDark: Bool) {
        logEvent(.themeChanged, parameters: ["theme_id": themeId, "is_dark": isDark])
    }

    // Error tracking
    func trackError(_ error: Error, context: String) {
        logEvent(.firebaseError, parameters: [
            "error_code": (error as NSError).code,
            "error_domain": (error as NSError).domain,
            "context": context
        ])
    }
}

// MARK: - Composer names

extension SessionType {
    /// The name this composer reports to analytics.
    ///
    /// Deliberately not `rawValue`: `.timed`'s raw value is "ninetySecond",
    /// kept for Firestore back-compat, and a dimension value nobody can read is
    /// a dimension nobody uses. `.timed` reports as "spill" because that is the
    /// surface people actually meet it through (`SpillWriteView`).
    var analyticsName: String {
        switch self {
        case .timed:      return "spill"
        case .freeWrite:  return "free_write"
        case .dailyChat:  return "daily_chat"
        case .cbtReframe: return "cbt_reframe"
        case .template:   return "template"
        }
    }
}
