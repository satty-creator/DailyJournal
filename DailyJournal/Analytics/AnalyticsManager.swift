//
//  AnalyticsManager.swift
//  DailyJournal
//
//  Centralized analytics tracking for Firebase Analytics + custom logging.
//  All user behavior is tracked to understand: page usage, drop-off, engagement.

import Foundation
import FirebaseAnalytics

// MARK: - Analytics Events

enum AnalyticsScreen: String {
    case home = "screen_home_today"
    case journal = "screen_journal_list"
    case mirror = "screen_mirror"
    case authLogin = "screen_auth_login"
    case authSignup = "screen_auth_signup"
    case onboarding = "screen_onboarding"
    case entryEditor = "screen_entry_editor"
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

    // Entry creation
    case entryCompositionStarted = "entry_composition_started"
    case entryCreated = "entry_created"
    case entryEdited = "entry_edited"
    case entryDeleted = "entry_deleted"
    case entryDrafted = "entry_drafted"
    case entryDiscarded = "entry_discarded"

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

    // Settings
    case settingsOpened = "settings_opened"
    case privacyPolicyViewed = "privacy_policy_viewed"
    case feedbackSent = "feedback_sent"

    // Session events
    case sessionStarted = "session_started"
    case sessionEnded = "session_ended"
    case appBackgrounded = "app_backgrounded"
    case appForegrounded = "app_foregrounded"

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
    case networkError = "network_error"
    case aiServiceError = "ai_service_error"
}

// MARK: - Analytics Manager

@MainActor
final class AnalyticsManager {

    static let shared = AnalyticsManager()
    private init() {}

    // MARK: - Screen Tracking

    /// Track screen view (auto-called by views via onAppear)
    func trackScreenView(_ screen: AnalyticsScreen, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["screen_name"] = screen.rawValue

        Analytics.logEvent(AnalyticsEvent.sessionStarted.rawValue, parameters: params)

        #if DEBUG
        print("📊 Screen: \(screen.rawValue)")
        #endif
    }

    // MARK: - Event Tracking

    /// Log a custom event with optional parameters
    func logEvent(_ event: AnalyticsEvent, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        params["timestamp"] = ISO8601DateFormatter().string(from: Date())

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

    func trackOnboardingCompleted(totalSteps: Int, duration: TimeInterval) {
        logEvent(.onboardingCompleted, parameters: [
            "total_steps": totalSteps,
            "duration_seconds": Int(duration)
        ])
    }

    func trackVibeSelected(_ vibe: String) {
        logEvent(.onboardingVibeSelected, parameters: ["vibe": vibe])
    }

    // Entry creation
    func trackEntryCompositionStarted(sessionType: String) {
        logEvent(.entryCompositionStarted, parameters: ["session_type": sessionType])
    }

    func trackEntryCreated(
        sessionType: String,
        wordCount: Int,
        hasMood: Bool,
        hasPhoto: Bool,
        hasAI: Bool,
        duration: TimeInterval
    ) {
        logEvent(.entryCreated, parameters: [
            "session_type": sessionType,
            "word_count": wordCount,
            "has_mood": hasMood,
            "has_photo": hasPhoto,
            "has_ai_insights": hasAI,
            "composition_time_seconds": Int(duration)
        ])
    }

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

    func trackEchoAnswered() {
        logEvent(.echoAnswered)
    }

    func trackEchoDismissed() {
        logEvent(.echoDismissed)
    }

    // Pattern
    func trackPatternSurfaced(archetype: String, evidenceCount: Int, noveltyScore: Double) {
        logEvent(.patternSurfaced, parameters: [
            "archetype": archetype,
            "evidence_count": evidenceCount,
            "novelty_score": noveltyScore
        ])
    }

    func trackPatternDismissed() {
        logEvent(.patternDismissed)
    }

    func trackPatternExplored(archetype: String) {
        logEvent(.patternExplored, parameters: ["archetype": archetype])
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
    func trackSessionStarted(daysAfterSignup: Int) {
        logEvent(.sessionStarted, parameters: ["days_after_signup": daysAfterSignup])
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
