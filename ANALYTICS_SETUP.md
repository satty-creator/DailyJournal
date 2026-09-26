# Analytics Implementation Guide

This document outlines the complete analytics strategy for the DailyJournal app to measure user engagement, identify drop-off points, and drive product decisions.

---

## Quick Start

### 1. Firebase Analytics is Already Enabled
Firebase Analytics is bundled with Firebase and requires **no additional setup**. It automatically tracks:
- App installs
- Crashes
- App opens
- In-app purchases (if applicable)

### 2. Initialize Session Manager in AppDelegate
Add this to track app lifecycle:

```swift
// DailyJournalApp.swift
@main
struct DailyJournalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionManager = SessionManager.shared  // Add this

    init() {
        AppCheck.setAppCheckProviderFactory(NinetyAppCheckProviderFactory())
        FirebaseApp.configure()
        
        sessionManager.recordSignupDate()  // On first app launch
        
        // ... rest of init
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(themeManager)
                .environmentObject(sessionManager)  // Add this
        }
    }
}
```

### 3. Add Screen Tracking to Views
Wrap each major view with `.trackScreen()`:

```swift
struct HomeView: View {
    var body: some View {
        ZStack {
            // ... your UI
        }
        .trackScreen(.home)  // Auto-logs when screen appears
    }
}
```

### 4. Log Events When Things Happen
```swift
// When user creates an entry
AnalyticsManager.shared.trackEntryCreated(
    sessionType: "freeWrite",
    wordCount: 250,
    hasMood: true,
    hasPhoto: false,
    hasAI: true,
    duration: 125.5
)

// When user answers an echo
AnalyticsManager.shared.trackEchoAnswered()

// When user grants AI consent
AnalyticsManager.shared.trackAIConsentGranted()
```

---

## What to Track: Complete Event Map

### **Authentication & Onboarding** (Signup Funnel)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `signup_started` | User taps "Sign up" | - | Measure top-of-funnel |
| `signup_completed` | User completes signup | `provider` (email/Google/Apple) | Measure conversion; which provider works? |
| `login_completed` | User logs in | `provider` | Returning user behavior |
| `onboarding_started` | Onboarding screen appears | - | Measure completion rate |
| `onboarding_vibe_selected` | User picks a vibe | `vibe` (calm/energetic/reflective/etc) | Product preference data |
| `onboarding_completed` | User finishes onboarding | `total_steps`, `duration_seconds` | Measure friction; time to first meaningful step |

**Funnel analysis:** `signup_started` → `signup_completed` → `login_completed` → `onboarding_completed` → `entry_created`

**Drop-off questions:**
- What % of signups complete signup?
- What % of onboarders reach first entry?
- How long is onboarding taking? (should be <3 min)

---

### **Entry Creation** (Core Product Flow)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `entry_composition_started` | User opens compose sheet | `session_type` | Measure interest; which format? |
| `entry_created` | Entry saved | `session_type`, `word_count`, `has_mood`, `has_photo`, `has_ai`, `composition_time_seconds` | **Key metric:** are entries getting written? What's the distribution? |
| `entry_discarded` | User exits composer without saving | `session_type`, `word_count` | Identify friction (e.g., did they write but leave?) |
| `entry_drafted` | User saves draft (if implemented) | `session_type` | Measure intent-to-return |

**Retention analysis:**
- Day 1 entry rate (% of signups who write day 1)
- Day 7 entry rate (% still writing after a week)
- Entry velocity (entries per day per user)
- Session type distribution (% timed vs free-write vs chat)

**Questions:**
- Are users dropping off before writing first entry? (big red flag)
- Which session type gets highest completion?
- What's typical word count? (indicates depth of engagement)

---

### **Mood Logging**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `mood_clicked` | User opens mood picker | - | Measure feature awareness |
| `mood_logged` | User selects + logs mood | `mood` (amazing/good/neutral/bad/terrible) | Measure adoption; do users feel it's useful? |

**Questions:**
- % of entries that include mood?
- Mood distribution (mostly positive/negative?)
- Are mood trends correlated with entry frequency?

---

### **AI Features**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `ai_consent_granted` | User enables AI in onboarding/settings | - | **Critical:** how many users opt in? |
| `ai_consent_denied` | User declines AI consent | - | Measure consent friction |
| `ai_consent_toggled` | User toggles AI on/off in settings | - | Measure regret/adoption |
| `ai_insights_generated` | Gemini call succeeds | `entry_type`, `bullet_count`, `has_question`, `latency_ms` | Track: success rate, performance, quality hints |
| `ai_insights_failed` | Gemini call fails | `error` | Track: reliability issues |
| `ai_insights_viewed` | User reads the AI summaries | `entry_type` | Do users care about insights? |

**User property:** Set `ai_consent_granted = true/false` so you can segment all other metrics by AI users vs non-AI users.

**Questions:**
- What % of users enable AI?
- What % of entries get AI insights?
- Average latency (should be <2s)?
- Failure rate (should be <5%)?
- Do AI users have higher retention?

---

### **Echo System** (Memory Callbacks)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `echo_surfaced` | Echo card appears on Home | `echo_type` (intention/openLoop/theme/moodMarker), `confidence` | Measure feature utility; are echoes high quality? |
| `echo_answered` | User responds to echo | - | **Engagement metric:** do people interact? |
| `echo_dismissed` | User dismisses echo | - | Measure engagement (swipe away = disengagement) |
| `echo_expired` | Echo expired (not answered) | - | Track lifecycle |
| `echo_theme_explored` | User clicks "show all entries for this theme" | - | Measure deep engagement |

**Retention correlation:** Do users who answer echoes return more often?

**Questions:**
- Echo answer rate (% of surfaced that are answered)?
- Average confidence of surfaced echoes?
- Do high-confidence echoes get higher answer rate?

---

### **Pattern System** (Deep Insights)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `pattern_surfaced` | Pattern card appears on Home | `archetype`, `evidence_count`, `novelty_score` | Measure: are patterns being detected? Quality? |
| `pattern_dismissed` | User dismisses pattern card | - | Engagement; relevance |
| `pattern_explored` | User opens pattern detail | `archetype` | Deep engagement |
| `pattern_evidence_viewed` | User opens "evidence drawer" | - | Engagement with insights |
| `pattern_detection_failed` | Pattern mining failed (Gemini error or safety gate) | - | Track reliability |

**Questions:**
- Pattern surface rate (how often are patterns available)?
- What archetypes are most common?
- Do users engage with patterns or dismiss them?
- Correlation: pattern engagement → retention?

---

### **Mirror/Self-Model**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `mirror_hypothesis_viewed` | User opens hypothesis detail | - | Engagement with self-insights |
| `mirror_hypothesis_edited` | User updates/accepts hypothesis | - | Measure validation + ownership |
| `mirror_graph_viewed` | User opens graph visualization | - | Feature adoption |

**Questions:**
- % of users who ever visit Mirror tab?
- Do Mirror users have higher retention?

---

### **Hints & Daily Read** (Guidance System)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `today_read_viewed` | User opens Today's Read card | - | Feature awareness + engagement |
| `hint_ladder_started` | User starts hint ladder | - | Measure guidance adoption |
| `hint_ladder_completed` | User completes ladder → writes entry | - | **Success metric:** does guidance lead to writing? |
| `question_answered` | User responds to daily question | - | Engagement |
| `question_skipped` | User skips question | - | Disengagement signal |

**Funnel:** `today_read_viewed` → `hint_ladder_started` → `hint_ladder_completed` → `entry_created`

**Questions:**
- % of users who use the hint ladder?
- Hint ladder → entry conversion rate (should be high)?
- Which hints get skipped most?

---

### **Chat Features**

Thought Journal (`.cbt`) is the default chat mode from Home; Casual Vent (`.normal`)
is opt-in via the in-chat pill (and is pinned for onboarding's first-ever session).
`daily_chat_started`/`_completed` fire on every chat open/save regardless of mode,
carrying a `mode` parameter (`"normal"` or `"cbt"`); `cbt_mode_started`/`_completed`
additionally fire only for Thought Journal, kept as their own event for continuity
with data from before the default flip.

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `daily_chat_started` | User opens Daily Chat, any mode | `mode` | Feature adoption |
| `daily_chat_completed` | Chat woven into entry, any mode | `mode` | Completion rate |
| `cbt_mode_started` | User opens/switches to Thought Journal | - | Feature adoption (legacy series) |
| `cbt_mode_completed` | Thought Journal snapshot saved | - | Completion rate (legacy series) |

**Questions:**
- % of entries created via chat?
- Chat vs free-write engagement?

---

### **Journal List Interactions**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `journal_searched` | User searches entries | `query` (hashed for privacy) | Feature usage |
| `journal_filtered` | User filters (by mood/date/tags) | `filter_type` | Feature usage |
| `journal_sorted` | User sorts (date/mood/etc) | - | Feature usage |
| `entry_viewed` | User opens old entry | `session_type`, `age_days` | Measure re-reading behavior |

**Questions:**
- Do users re-read old entries?
- How old are the entries they view?

---

### **Tab Navigation** (Screen Views)

| Screen | Event | Parameters | Why |
|--------|-------|-----------|-----|
| Home | `screen_home_today` | - | Measure: daily active users |
| Journal | `screen_journal_list` | - | Navigation pattern |
| Mirror | `screen_mirror_view` | - | Feature adoption |
| Auth | `screen_auth_login`, `screen_auth_signup` | - | Funnel tracking |
| Onboarding | `screen_onboarding` | - | Onboarding funnel |
| Entry editor | `screen_entry_editor` | - | Composition flow |

**Analysis:**
- Session paths (Home → Compose → dismiss? Or Home → Compose → Journal?)
- Tab switching patterns
- Screen time distribution (where do users spend time?)

---

### **Session Lifecycle**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `session_started` | App opens | `days_after_signup` | Daily active users; retention curve |
| `session_ended` | App closes (enters background) | `session_duration_seconds`, `entries_written` | Session length; productivity |
| `app_foregrounded` | App returns from background | - | Re-engagement |
| `app_backgrounded` | App goes to background | - | Lifecycle tracking |

**Retention analysis:** DAU/MAU, D1/D7/D30 retention curves.

---

### **Settings & Preferences**

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `theme_changed` | User switches theme | `theme_name` | Product preference |
| `settings_opened` | User opens settings | - | Feature discoverability |
| `privacy_policy_viewed` | User opens privacy policy | - | Trust/safety engagement |
| `feedback_sent` | User sends feedback | - | Engagement signal |

---

### **Errors** (Technical Monitoring)

| Event | When | Parameters | Why |
|-------|------|-----------|-----|
| `firebase_error` | Firestore/Auth error | `error_code`, `error_domain`, `context` | Reliability tracking |
| `network_error` | Network request fails | - | Connectivity issues |
| `ai_service_error` | Gemini/proxy error | - | AI reliability |

---

## Integration Points: Where to Add Tracking

### **In Views** (Screen tracking)
```swift
struct HomeView: View {
    var body: some View {
        ZStack { /* ... */ }
            .trackScreen(.home)  // Auto-logs on appear
    }
}
```

### **In ViewModels** (Event tracking)
```swift
@MainActor
final class HomeViewModel: ObservableObject {
    func saveEntry(_ entry: JournalEntry) {
        // ... save logic
        
        // Track
        AnalyticsManager.shared.trackEntryCreated(
            sessionType: entry.sessionType.rawValue,
            wordCount: entry.content.count,
            hasMood: entry.mood != nil,
            hasPhoto: entry.photoURL != nil,
            hasAI: !entry.aiSummaryBullets.isEmpty,
            duration: timeSpentComposing
        )
    }
}
```

### **In Services** (Background tasks)
```swift
final class AIService {
    func generate(prompt: String, ...) async throws -> Data {
        let startTime = Date()
        
        do {
            let result = try await callGemini(prompt)
            
            let latency = Date().timeIntervalSince(startTime)
            AnalyticsManager.shared.trackAIInsightsGenerated(
                entryType: "freeWrite",
                bulletCount: bullets.count,
                hasQuestion: question != nil,
                latency: latency
            )
            
            return result
        } catch {
            AnalyticsManager.shared.trackAIInsightsFailed(
                error: error.localizedDescription
            )
            throw error
        }
    }
}
```

### **In Auth** (User properties)
```swift
final class AuthViewModel: ObservableObject {
    func completeSignup() async {
        // ... signup logic
        
        AnalyticsManager.shared.setUserId(user.id)
        AnalyticsManager.shared.trackSignupCompleted(provider: "email")
        SessionManager.shared.recordSignupDate()
    }
    
    func toggleAIConsent(_ enabled: Bool) {
        UserDefaults.standard.aiConsentGranted = enabled
        
        if enabled {
            AnalyticsManager.shared.trackAIConsentGranted()
        } else {
            AnalyticsManager.shared.trackAIConsentDenied()
        }
    }
}
```

---

## Firebase Console: What to Monitor

### **Real-Time Dashboard**
- Active users (now)
- Top screens
- Top events
- Crash rate

**URL:** Firebase Console → DailyJournal project → Analytics → Realtime

### **User Properties**
- `ai_consent_granted` (segment by consent)
- `theme_preference`
- `days_after_signup` (cohort analysis)

**URL:** Analytics → User Properties

### **Funnels** (Pre-built)
Create these funnels in Firebase:

1. **Signup → Onboarding → First Entry**
   - `signup_started` → `onboarding_completed` → `entry_created`

2. **Today's Read → Hint Ladder → Entry**
   - `today_read_viewed` → `hint_ladder_started` → `entry_created`

3. **Echo Surfaced → Answered**
   - `echo_surfaced` → `echo_answered`

4. **Pattern Surfaced → Explored**
   - `pattern_surfaced` → `pattern_explored`

**URL:** Analytics → Funnel Analysis → Create Funnel

### **Retention Curves**
- D0, D1, D3, D7, D14, D30 retention
- Segment by: AI consent, session type, onboarding vibe

**URL:** Analytics → Retention

### **Cohort Analysis**
- Compare: AI users vs non-AI users (entry rate, session duration, return rate)
- Compare: Onboarding vibes (which vibe has best retention?)
- Compare: Entry types (timed vs free-write vs chat retention)

**URL:** Analytics → Cohorts

### **Events Over Time**
Track trends:
- Entries per day (trending up/down?)
- Mood logging rate
- AI usage
- Echo answer rate
- Pattern engagement

**URL:** Analytics → Events → Select event → Trend over time

---

## Example Dashboard Questions to Answer

### **Week 1 Questions**
1. How many users signed up?
2. What % completed onboarding?
3. What % wrote their first entry?
4. How long is onboarding taking?
5. What % enabled AI?
6. Average time to first entry?

### **Monthly Questions**
1. DAU vs MAU ratio (engagement)?
2. D1, D7, D30 retention rates?
3. Average entries per user per day?
4. What % of entries include mood?
5. Echo answer rate?
6. Pattern surface rate?
7. Session duration trend?
8. Top drop-off points in each funnel?
9. AI users: higher retention than non-AI users?
10. Which onboarding vibe → best retention?

### **Product Decision Questions**
1. Should we promote hint ladder more? (low usage → low completion)
2. Is the pattern system working? (low surface rate or low engagement?)
3. Which session type is most popular?
4. Should we re-design the hint ladder? (high start, low complete)
5. Do echoes drive engagement? (compare retention: answered vs dismissed)
6. Is Mirror feature worth the complexity? (low tab visits?)

---

## Privacy & GDPR Considerations

✅ **What Firebase Analytics tracks by default:**
- App installs, opens, crashes
- Screen views, events, user properties

✅ **What we're tracking (anonymized):**
- Event names (no user input logged)
- Aggregated metrics (counts, latencies)
- Hashed query strings (for journal search)

⚠️ **What NOT to track:**
- Entry content (ever)
- Exact queries (log hashed queries only, or counts only)
- User IDs in event parameters (Firebase handles via `setUserID`)

✅ **Compliance:**
- Firebase stores data in US by default (can be configured)
- GDPR: Users can request data deletion (Firebase supports this)
- Privacy Policy: Disclose that you use Firebase Analytics

---

## Checklist: Integration Steps

- [ ] Add `AnalyticsManager.swift` to `/Analytics/` directory
- [ ] Add `ScreenTrackingModifier.swift` to `/Analytics/` directory
- [ ] Add `SessionManager.swift` to `/Analytics/` directory
- [ ] Initialize `SessionManager` in `DailyJournalApp`
- [ ] Add `.trackScreen()` to: `HomeView`, `JournalListView`, `MirrorView`, `AuthContainerView`, `OnboardingView`
- [ ] Add event tracking to `AuthViewModel` (signup, login, AI consent)
- [ ] Add event tracking to `HomeViewModel` (entry creation, echo, pattern)
- [ ] Add event tracking to `JournalEditorViewModel` (composition, discard)
- [ ] Add event tracking to `AIService` (insights generation, failures)
- [ ] Add event tracking to `EchoService` (surface, answer, dismiss)
- [ ] Add event tracking to `PatternDetectionService` (surface, explore)
- [ ] Create funnels in Firebase Console (signup, onboarding, entry)
- [ ] Create retention curves in Firebase Console
- [ ] Set up alerts for anomalies (crash rate, latency spikes)
- [ ] Document baseline metrics (Day 1 numbers to compare against)

---

## What to Do With Insights

### **High Priority Signals**
- **Low Day 1 completion:** Too hard to write first entry? → Simplify hint ladder
- **Low onboarding completion:** Onboarding friction → run A/B test
- **High entry start → abandon rate:** Compose UI too hard? → Test simpler composer
- **Low AI adoption:** Consent friction? → Test skipping consent, ask later
- **Low echo answer rate:** Echoes not relevant? → Review extraction logic
- **Low pattern engagement:** Patterns not valuable? → Review detection accuracy

### **Optimization Opportunities**
- Compare onboarding vibes: pick the one with best D7 retention
- Compare session types: promote the one with highest completion rate
- A/B test hint ladder: current vs simplified version
- A/B test hint ladder timing: now vs after first entry
- Analyze: which questions get highest answer rate? Promote those.

### **Feature Prioritization**
- If Mirror has <10% tab visit rate: deprioritize
- If echoes don't drive retention: reconsider the feature
- If chat has low completion rate: fix UX before promoting

---

## Resources

- **Firebase Analytics docs:** https://firebase.google.com/docs/analytics
- **Setting up custom events:** https://firebase.google.com/docs/analytics/ios/start
- **Funnels in Firebase:** https://support.google.com/firebase/answer/9048308
- **GDPR with Firebase:** https://firebase.google.com/support/privacy
