# Analytics Implementation Checklist

Use this checklist to implement analytics systematically. Estimated total time: **2-3 hours** for full implementation.

---

## ✅ Phase 1: Foundation Setup (10 minutes)

### Already Done
- [x] `AnalyticsManager.swift` created in `/DailyJournal/Analytics/`
- [x] `ScreenTrackingModifier.swift` created in `/DailyJournal/Analytics/`
- [x] `SessionManager.swift` created in `/DailyJournal/Analytics/`

### You Need to Do

#### Step 1: Update DailyJournalApp.swift
```swift
// 1. Add import at top
import FirebaseAnalytics

@main
struct DailyJournalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = SessionManager.shared  // ADD THIS

    init() {
        AppCheck.setAppCheckProviderFactory(NinetyAppCheckProviderFactory())
        FirebaseApp.configure()
        
        // Optional: record first app launch for cohort analysis
        sessionManager.recordSignupDate()
        
        // ... rest of init
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(themeManager)
                .environmentObject(sessionManager)  // ADD THIS
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
```

**Checklist:**
- [ ] Add `import FirebaseAnalytics`
- [ ] Add `@StateObject private var sessionManager = SessionManager.shared`
- [ ] Call `sessionManager.recordSignupDate()` in init
- [ ] Pass `sessionManager` to `.environmentObject()`

#### Step 2: Verify Firebase Analytics is Enabled
- [ ] Open Firebase Console
- [ ] Select DailyJournal project
- [ ] Go to Analytics → Overview
- [ ] Confirm "Google Analytics is enabled"

**If not enabled:**
- [ ] Click "Setup" → "Get started with Google Analytics"
- [ ] Accept defaults

---

## ✅ Phase 2: Screen Tracking (5 minutes)

Add `.trackScreen()` to your main views. Each takes ~30 seconds.

### HomeView.swift
```swift
struct HomeView: View {
    var body: some View {
        ZStack {
            // ... your existing UI
        }
        .trackScreen(.home)  // ADD THIS LINE
    }
}
```
- [ ] Added `.trackScreen(.home)` to HomeView

### JournalListView.swift
```swift
struct JournalListView: View {
    var body: some View {
        NavigationStack {
            // ... your existing UI
        }
        .trackScreen(.journal)  // ADD THIS LINE
    }
}
```
- [ ] Added `.trackScreen(.journal)` to JournalListView

### MirrorView.swift
```swift
struct MirrorView: View {
    var body: some View {
        ZStack {
            // ... your existing UI
        }
        .trackScreen(.mirror)  // ADD THIS LINE
    }
}
```
- [ ] Added `.trackScreen(.mirror)` to MirrorView

### AuthContainerView.swift
```swift
struct AuthContainerView: View {
    var body: some View {
        VStack {
            // ... your existing UI
        }
        .trackScreen(.authLogin)  // ADD THIS LINE
    }
}
```
- [ ] Added `.trackScreen(.authLogin)` to AuthContainerView

### OnboardingView.swift
```swift
struct OnboardingView: View {
    var body: some View {
        VStack {
            // ... your existing UI
        }
        .trackScreen(.onboarding)  // ADD THIS LINE
    }
}
```
- [ ] Added `.trackScreen(.onboarding)` to OnboardingView

### Optional: Add to More Views
- [ ] `EntryDetailView.swift`: `.trackScreen(.entryDetail)`
- [ ] `JournalEditorView.swift`: `.trackScreen(.entryEditor)`

---

## ✅ Phase 3: Event Tracking in ViewModels (60 minutes)

### AuthViewModel.swift

```swift
// Add to signup completion
func completeSignup(email: String, password: String) async {
    do {
        // ... your existing signup logic
        
        // ADD THESE LINES:
        AnalyticsManager.shared.setUserId(user.uid)
        AnalyticsManager.shared.trackSignupCompleted(provider: "email")
        SessionManager.shared.recordSignupDate()
        
    } catch {
        AnalyticsManager.shared.trackError(error, context: "signup_failed")
        throw error
    }
}

// Add to login completion
func loginWithGoogle() async {
    do {
        // ... your existing Google login logic
        
        // ADD THESE LINES:
        AnalyticsManager.shared.setUserId(user.uid)
        AnalyticsManager.shared.trackLoginCompleted(provider: "google")
        
    } catch {
        AnalyticsManager.shared.trackError(error, context: "google_login_failed")
    }
}

// Add to AI consent toggle
func toggleAIConsent(_ enabled: Bool) {
    UserDefaults.standard.aiConsentGranted = enabled
    
    // ADD THESE LINES:
    if enabled {
        AnalyticsManager.shared.trackAIConsentGranted()
    } else {
        AnalyticsManager.shared.trackAIConsentDenied()
    }
}
```

**Checklist:**
- [ ] Added `trackSignupCompleted()` to signup completion
- [ ] Added `setUserId()` after signup
- [ ] Added `trackLoginCompleted()` to login completion
- [ ] Added `trackAIConsentGranted()` / `trackAIConsentDenied()` to consent toggle
- [ ] Added `recordSignupDate()` after first signup

### JournalEditorViewModel.swift

```swift
@Published var startTime: Date?

func startComposing(sessionType: SessionType) {
    startTime = Date()
    
    // ADD THIS LINE:
    AnalyticsManager.shared.trackEntryCompositionStarted(sessionType: sessionType.rawValue)
}

func saveEntry(userId: String, sessionType: SessionType) {
    guard let startTime else { return }
    
    let duration = Date().timeIntervalSince(startTime)
    let wordCount = content.split(separator: " ").count
    
    let entry = JournalEntry(...)
    
    // ... save to Firestore
    JournalService().createEntry(entry)
    
    // ADD THESE LINES:
    AnalyticsManager.shared.trackEntryCreated(
        sessionType: sessionType.rawValue,
        wordCount: wordCount,
        hasMood: mood != nil,
        hasPhoto: photoURL != nil,
        hasAI: false,  // Will be true after AI generates insights
        duration: duration
    )
    
    SessionManager.shared.recordEntryWritten()
}

func discardEntry(sessionType: SessionType) {
    let wordCount = content.split(separator: " ").count
    
    // ADD THIS LINE:
    AnalyticsManager.shared.trackEntryDiscarded(
        sessionType: sessionType.rawValue,
        wordCount: wordCount
    )
}
```

**Checklist:**
- [ ] Added `trackEntryCompositionStarted()` to compose start
- [ ] Added `trackEntryCreated()` to save
- [ ] Added `recordEntryWritten()` to session manager on save
- [ ] Added `trackEntryDiscarded()` to discard handler

### HomeViewModel.swift

```swift
func userAnsweredEcho() {
    // ADD THIS LINE:
    AnalyticsManager.shared.trackEchoAnswered()
}

func userDismissedEcho() {
    // ADD THIS LINE:
    AnalyticsManager.shared.trackEchoDismissed()
}

func load() async {
    // ... existing load logic
    
    if let callback = pendingCallback {
        // ADD THIS LINE:
        AnalyticsManager.shared.trackPatternSurfaced(
            archetype: callback.archetype.rawValue,
            evidenceCount: callback.evidence.count,
            noveltyScore: 0.5  // Use actual score if available
        )
    }
}
```

**Checklist:**
- [ ] Added `trackEchoAnswered()` to echo answer handler
- [ ] Added `trackEchoDismissed()` to echo dismiss handler
- [ ] Added `trackPatternSurfaced()` when pattern appears

### OnboardingView.swift (Optional)

```swift
@State private var startTime = Date()

var body: some View {
    VStack {
        // ... your onboarding UI
    }
    .onAppear {
        startTime = Date()
        AnalyticsManager.shared.trackOnboardingStarted()  // ADD THIS
    }
    .onDisappear {
        if completed {
            let duration = Date().timeIntervalSince(startTime)
            // ADD THESE LINES:
            AnalyticsManager.shared.trackOnboardingCompleted(
                totalSteps: totalSteps,
                duration: duration
            )
        }
    }
}

func selectVibe(_ vibe: String) {
    // ADD THIS LINE:
    AnalyticsManager.shared.trackVibeSelected(vibe)
}
```

**Checklist:**
- [ ] Added `trackOnboardingStarted()` on appear
- [ ] Added `trackOnboardingCompleted()` on completion
- [ ] Added `trackVibeSelected()` when vibe is selected

---

## ✅ Phase 4: Service-Level Tracking (30 minutes)

### AIService.swift

```swift
func generateInsights(for entry: JournalEntry) async throws -> JournalInsights {
    let startTime = Date()
    
    do {
        let insights = try await callGeminiForInsights(entry)
        
        let latency = Date().timeIntervalSince(startTime)
        
        // ADD THESE LINES:
        AnalyticsManager.shared.trackAIInsightsGenerated(
            entryType: entry.sessionType.rawValue,
            bulletCount: insights.bullets.count,
            hasQuestion: !insights.question.isEmpty,
            latency: latency
        )
        
        return insights
        
    } catch {
        // ADD THESE LINES:
        AnalyticsManager.shared.trackAIInsightsFailed(
            error: error.localizedDescription
        )
        throw error
    }
}
```

**Checklist:**
- [ ] Added `trackAIInsightsGenerated()` after successful call
- [ ] Added `trackAIInsightsFailed()` in error handler
- [ ] Tracking latency in milliseconds

### EchoService.swift

```swift
func surfaceNextEcho(for userId: String) async -> Echo? {
    let echo = try? await fetchPendingEcho(userId: userId)
    
    if let echo {
        // ADD THESE LINES:
        AnalyticsManager.shared.trackEchoSurfaced(
            type: echo.type.rawValue,
            confidence: echo.confidence
        )
    }
    
    return echo
}
```

**Checklist:**
- [ ] Added `trackEchoSurfaced()` when echo appears
- [ ] Passing echo type and confidence

### PatternDetectionService.swift

```swift
func detectPatterns(for userId: String) async -> [PatternHypothesis] {
    do {
        let patterns = try await mineHypotheses(userId: userId)
        
        for pattern in patterns {
            // ADD THESE LINES:
            AnalyticsManager.shared.trackPatternSurfaced(
                archetype: pattern.archetype.rawValue,
                evidenceCount: pattern.evidence.count,
                noveltyScore: pattern.noveltyScore
            )
        }
        
        return patterns
    } catch {
        // ADD THESE LINES:
        AnalyticsManager.shared.logEvent(.patternDetectionFailed, parameters: [
            "error": error.localizedDescription
        ])
        throw error
    }
}
```

**Checklist:**
- [ ] Added `trackPatternSurfaced()` for each pattern
- [ ] Added `logEvent(.patternDetectionFailed)` in error handler

---

## ✅ Phase 5: Optional Feature Tracking (30 minutes)

### JournalListView.swift

```swift
List(filteredEntries) { entry in
    NavigationLink {
        EntryDetailView(entry: entry)
    } label: {
        EntryRow(entry)
    }
    .onTapGesture {
        // ADD THESE LINES:
        let age = Date().timeIntervalSince(entry.createdAt)
        AnalyticsManager.shared.trackEntryViewed(
            sessionType: entry.sessionType.rawValue,
            age: age
        )
    }
}
.searchable(text: $searchText)
.onChange(of: searchText) { newValue in
    // ADD THESE LINES:
    if !newValue.isEmpty {
        AnalyticsManager.shared.trackJournalSearched(query: newValue)
    }
}
```

**Checklist:**
- [ ] Added `trackEntryViewed()` on entry tap
- [ ] Added `trackJournalSearched()` on search

### MoodLogView.swift

```swift
HStack(spacing: 12) {
    ForEach(Mood.allCases) { mood in
        Button {
            // ADD THIS LINE:
            AnalyticsManager.shared.trackMoodLogged(mood: mood.rawValue)
            selectedMood = mood
        } label: {
            Text(mood.emoji)
        }
    }
}
```

**Checklist:**
- [ ] Added `trackMoodLogged()` on mood selection

---

## ✅ Phase 6: Firebase Console Setup (30 minutes)

### Verify Data Collection
- [ ] Run app locally
- [ ] Perform actions: sign in, write entry, toggle AI, view echo
- [ ] Open Firebase Console → Analytics → Realtime
- [ ] Verify events appear within 5-10 seconds

### Create Funnels

**Funnel 1: Signup → Entry**
1. Go to Firebase Console → Analytics → Funnel Analysis
2. Click "Create Funnel"
3. Name: "Signup to First Entry"
4. Add steps:
   - Step 1: `signup_completed`
   - Step 2: `onboarding_completed`
   - Step 3: `entry_created`
5. Save
- [ ] Created signup → onboarding → entry funnel

**Funnel 2: Echo Surfaced → Answered**
1. Click "Create Funnel"
2. Name: "Echo Engagement"
3. Add steps:
   - Step 1: `echo_surfaced`
   - Step 2: `echo_answered`
4. Save
- [ ] Created echo funnel

**Funnel 3: Today's Read → Entry**
1. Click "Create Funnel"
2. Name: "Today's Read Conversion"
3. Add steps:
   - Step 1: `today_read_viewed`
   - Step 2: `entry_created`
4. Save
- [ ] Created today's read funnel

### Create Retention Cohorts
1. Go to Firebase Console → Analytics → Retention
2. Select your app
3. Default retention curve should appear (Day 0, 1, 7, 14, 30)
4. This shows % of users from Day 0 who return each day
- [ ] Retention curves visible

### Create User Properties
1. Go to Firebase Console → Analytics → User Properties
2. Verify these appear:
   - `ai_consent_granted` (true/false)
   - Any custom properties you set
- [ ] User properties visible

### Set Up Alerts (Optional)
1. Go to Firebase Console → Analytics → Reporting → Alerts
2. Create alert: "Crash rate exceeds 1%"
3. Create alert: "DAU drops 30% vs previous day"
4. Get Slack notifications when alerts trigger
- [ ] Created 2-3 alerts

---

## ✅ Phase 7: Documentation & Monitoring (30 minutes)

### Create Weekly Metrics Tracking Sheet
Create a Google Sheet with these columns:

| Date | DAU | D1 Ret | D7 Ret | Entries/Day | AI Adoption | Echo Answer % | Pattern Surface % | Notes |
|------|-----|--------|--------|-------------|-------------|---------------|--------------------|-------|
| Aug 22 | 150 | 55% | 28% | 180 | 65% | 45% | 12% | — |

- [ ] Created tracking sheet

### Document Baseline
- [ ] Record Day 1 metrics (DAU, retention, crash rate)
- [ ] Share with team
- [ ] Set targets for Month 1

### Set Up Weekly Review
- [ ] Schedule weekly 30-min standup to review metrics
- [ ] Assign someone to pull data each Monday
- [ ] Create template for presenting findings

### Broadcast to Team
- [ ] Share ANALYTICS_README.md with team
- [ ] Share METRICS_DASHBOARD_GUIDE.md
- [ ] Show Firebase Console dashboard
- [ ] Explain key metrics and funnels

- [ ] Team understands analytics setup
- [ ] Weekly review process scheduled

---

## ✅ Validation Checklist

### App Running & Event Collection
- [ ] Run app locally
- [ ] Perform actions:
  - [ ] Sign up with email
  - [ ] View Home, Journal, Mirror screens
  - [ ] Write an entry
  - [ ] Enable/disable AI consent
  - [ ] Return to app (check session tracking)
- [ ] Check Firebase Real-time dashboard
- [ ] Verify events appear: signup_completed, entry_created, screen views, etc.

### Firebase Console
- [ ] Real-time tab shows active users >0
- [ ] Top screens populated
- [ ] Top events populated
- [ ] Funnels created and showing data
- [ ] Retention curves visible
- [ ] Crash rate visible (should be 0% in dev)

### No Errors
- [ ] Xcode console shows no AnalyticsManager errors
- [ ] App doesn't crash during analytics calls
- [ ] Firebase SDK initializes without errors

---

## 🎯 Success Criteria (After 1 Day)

**You know if analytics is working if:**

✅ Firebase Real-time shows:
- `signup_completed` events
- `entry_created` events
- Screen views from your app
- Session duration data

✅ You can create a funnel showing:
- `signup_completed` → `onboarding_completed` → `entry_created`
- Conversion % for each step

✅ You have a retention curve showing:
- % of users returning Day 1, 7, 30

✅ Your team can answer:
- "How many users signed up today?"
- "What % wrote their first entry?"
- "What's our crash rate?"

---

## 📞 Troubleshooting

### No data appearing in Firebase
**Check:**
- [ ] Firebase Console: is Analytics enabled?
- [ ] Did you run the app? (need real activity to generate events)
- [ ] Wait 5-10 minutes (realtime has latency)
- [ ] Check Xcode console for errors

**Fix:**
- [ ] Restart app
- [ ] Perform more actions (more events = easier to see)
- [ ] Refresh Firebase Console

### Events not showing up
**Check:**
- [ ] Is `.trackScreen()` modifier actually added to view?
- [ ] Is AnalyticsManager.shared.logEvent() being called?
- [ ] Xcode console: any errors?

**Fix:**
- [ ] Add print statements to verify code is executing
- [ ] Check that view is appearing (not hidden behind condition)

### Funnel showing 0 users
**Check:**
- [ ] Are the events happening? (check real-time first)
- [ ] Are event names spelled correctly? (case-sensitive)
- [ ] Did you wait 24 hours? (funnels take time to populate)

**Fix:**
- [ ] Create funnel again with correct event names
- [ ] Perform actions manually to generate events
- [ ] Wait 24 hours for data to appear

---

## 🚀 You're Done!

Once this checklist is complete, you have:

✅ Screen view tracking (all major tabs logged)
✅ Event tracking (50+ events across all features)
✅ Session lifecycle tracking (duration, entries written)
✅ Firebase console set up with funnels and retention
✅ Team aware of analytics capability
✅ Weekly review process scheduled

**Next:**
- Monitor daily (5 min)
- Review weekly (30 min)
- Make data-driven decisions on features

**Questions?** See ANALYTICS_SETUP.md or ANALYTICS_INTEGRATION_EXAMPLES.md

---

**Estimated total time: 2-3 hours for full implementation**

**Good luck! 🚀**
