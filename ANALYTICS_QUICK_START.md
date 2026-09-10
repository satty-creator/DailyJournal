# Analytics Quick Start (5-Minute Setup)

## What You're Getting

Three levels of analytics tracking:

1. **Automatic (no code):** App launches, screens, crashes
2. **Simple events:** User actions (entry created, mood logged, AI toggled)
3. **Rich context:** Session duration, latency, word count, feature adoption

**Result:** You'll know exactly which features users love, where they drop off, and why people leave.

---

## Step 1: Verify Firebase Analytics is Enabled (2 min)

Firebase Analytics comes **free and automatic** with Firebase. Just verify:

1. Open [Firebase Console](https://console.firebase.google.com)
2. Select your DailyJournal project
3. Go to **Analytics** (left sidebar)
4. You should see: **"Google Analytics is enabled for this app"**

If not, enable it:
1. Click **Setup** → **Get started with Google Analytics**
2. Accept defaults and enable

✅ **Done.** Firebase now tracks: app launches, screens, crashes, events.

---

## Step 2: Add Analytics Code to Your App (3 min)

### File 1: Create `/DailyJournal/Analytics/AnalyticsManager.swift`
Copy the full file from this repo's Analytics directory. This is your event SDK.

### File 2: Create `/DailyJournal/Analytics/ScreenTrackingModifier.swift`
Copy this to auto-log screen views.

### File 3: Create `/DailyJournal/Analytics/SessionManager.swift`
Copy this to track app lifecycle (when user launches/closes the app).

### File 4: Update `DailyJournalApp.swift`
Add these lines:

```swift
import FirebaseAnalytics  // Add this import

@main
struct DailyJournalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = SessionManager.shared  // ADD THIS

    init() {
        AppCheck.setAppCheckProviderFactory(NinetyAppCheckProviderFactory())
        FirebaseApp.configure()
        
        // Optional: record signup date (for retention analysis)
        if Auth.auth().currentUser == nil {
            sessionManager.recordSignupDate()
        }
        
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

✅ **Done.** Basic tracking is live.

---

## Step 3: Add Screen Tracking to Views (30 sec per view)

Add `.trackScreen()` to your main views:

```swift
// HomeView.swift
struct HomeView: View {
    var body: some View {
        ZStack { /* your UI */ }
            .trackScreen(.home)  // Add this line
    }
}

// JournalListView.swift
struct JournalListView: View {
    var body: some View {
        NavigationStack { /* your UI */ }
            .trackScreen(.journal)  // Add this line
    }
}

// MirrorView.swift
struct MirrorView: View {
    var body: some View {
        ZStack { /* your UI */ }
            .trackScreen(.mirror)  // Add this line
    }
}

// AuthContainerView.swift
struct AuthContainerView: View {
    var body: some View {
        VStack { /* your UI */ }
            .trackScreen(.authLogin)  // Add this line
    }
}

// OnboardingView.swift
struct OnboardingView: View {
    var body: some View {
        VStack { /* your UI */ }
            .trackScreen(.onboarding)  // Add this line
    }
}
```

✅ **Screen tracking live.** Firebase now logs every time a user visits Home, Journal, Mirror, etc.

---

## Step 4: Add Key Event Tracking (Optional but Recommended)

Track these high-impact events in your ViewModels:

### In `AuthViewModel`:
```swift
func completeSignup(email: String, password: String) async {
    // ... signup logic
    AnalyticsManager.shared.trackSignupCompleted(provider: "email")
}

func toggleAIConsent(_ enabled: Bool) {
    UserDefaults.standard.aiConsentGranted = enabled
    if enabled {
        AnalyticsManager.shared.trackAIConsentGranted()
    } else {
        AnalyticsManager.shared.trackAIConsentDenied()
    }
}
```

### In `JournalEditorViewModel`:
```swift
func saveEntry(userId: String, sessionType: SessionType) {
    let wordCount = content.split(separator: " ").count
    let duration = Date().timeIntervalSince(startTime)
    
    // Save to Firestore...
    JournalService().createEntry(entry)
    
    // Track
    AnalyticsManager.shared.trackEntryCreated(
        sessionType: sessionType.rawValue,
        wordCount: wordCount,
        hasMood: mood != nil,
        hasPhoto: photoURL != nil,
        hasAI: !entry.aiSummaryBullets.isEmpty,
        duration: duration
    )
    
    SessionManager.shared.recordEntryWritten()
}
```

### In `HomeViewModel`:
```swift
func handleEchoAnswered() {
    AnalyticsManager.shared.trackEchoAnswered()
}

func handlePatternSurfaced(pattern: PatternHypothesis) {
    AnalyticsManager.shared.trackPatternSurfaced(
        archetype: pattern.archetype.rawValue,
        evidenceCount: pattern.evidence.count,
        noveltyScore: pattern.noveltyScore
    )
}
```

### In `AIService`:
```swift
func generate(prompt: String, ...) async throws -> Data {
    let startTime = Date()
    do {
        let response = try await callGemini(prompt)
        let latency = Date().timeIntervalSince(startTime)
        AnalyticsManager.shared.trackAIInsightsGenerated(
            entryType: "freeWrite",
            bulletCount: 3,
            hasQuestion: true,
            latency: latency
        )
        return response
    } catch {
        AnalyticsManager.shared.trackAIInsightsFailed(error: error.localizedDescription)
        throw error
    }
}
```

✅ **Event tracking live.** You'll see: signups, entries created, AI usage, echo interactions, pattern detection.

---

## Step 5: Check Your Dashboard (Immediate)

1. Run the app and perform some actions (write entry, toggle AI, view screens)
2. Wait 5-10 seconds
3. Open [Firebase Console → Analytics → Real-time](https://console.firebase.google.com)
4. You should see:
   - **Active users now:** >0
   - **Top screens:** Your screens listed
   - **Top events:** Your events listed

📊 **You're live!**

---

## What Data You'll See (Next 24 Hours)

After a day of real usage:

### **Real-Time Tab**
- How many users active right now
- Which screens they're on
- Which events firing

### **Dashboard Tab**
- Daily active users (DAU)
- Session duration
- Events per session
- Screen view distribution

### **Retention Tab**
- Day 1 retention (% of day-0 users who return)
- Day 7, 30 retention
- Trends

### **Funnels Tab** (create manually)
- Signup → Onboarding → First Entry
- Today's Read → Hint Ladder → Entry
- Echo Surfaced → Echo Answered

---

## Key Metrics to Monitor (Daily)

| Metric | Target | Why |
|--------|--------|-----|
| **DAU** | Growing | Users are returning |
| **D1 Retention** | >50% | Most users like the app |
| **D7 Retention** | >30% | Product-market fit indicator |
| **Entry Creation Rate** | >50% of sessions | Core feature working |
| **AI Consent Rate** | >60% | Users trust AI |
| **Echo Answer Rate** | >40% | Echoes are relevant |
| **Session Duration** | >5 min | Engagement |
| **Crash Rate** | <1% | Stability |

---

## Top 3 Questions to Ask After One Week

1. **"What % of users who sign up actually write their first entry?"**
   - Answer: Firebase → Funnels → Create "Signup → First Entry"
   - Red flag: <30% means onboarding is too hard

2. **"Are users who enable AI more likely to keep using the app?"**
   - Answer: Compare cohorts (AI enabled vs AI disabled) retention curves
   - Firebase → Cohorts → Create

3. **"Where do users drop off?"**
   - Answer: Firebase → Funnels → Check each step completion rate
   - Red flag: >30% drop at any step

---

## Next: Deep Dives (Optional)

Once you have baseline data (1 week), dig into:

1. **Cohort analysis:** Compare AI users vs non-AI users
2. **Funnel analysis:** Where do users abandon?
3. **Retention curves:** When do users leave?
4. **Session flows:** HomeView → JournalView → Mirror, or what?

See `ANALYTICS_SETUP.md` for detailed guides.

---

## Troubleshooting

### **"I don't see any data in Analytics"**
- Wait 24 hours (new apps take time to populate)
- Check real-time tab (data appears there first)
- Verify Firebase is initialized in `DailyJournalApp`
- Check Xcode console for errors

### **"Events aren't showing up"**
- Verify `AnalyticsManager.shared.logEvent()` calls exist in your code
- Check Firebase console → Events tab (not all events show in dashboard)
- In debug mode, print statements in `AnalyticsManager` should appear in Xcode console

### **"Screen views aren't being logged"**
- Verify `.trackScreen()` modifier is added to view
- Check that view is actually appearing (not inside a condition that's false)

---

## Privacy Reminder

✅ **You're collecting:**
- Screen names, event names
- Aggregated counts (not individual data)
- Session duration

❌ **You should never collect:**
- Entry content
- User exact queries
- Personal user information

✅ **Update your Privacy Policy to disclose:**
- You use Google Firebase Analytics
- How long data is retained (90 days default)
- That data is anonymized and aggregated

---

## One-Line Summary

**You now have:** Automatic real-time visibility into which features users love, where they drop off, and what drives retention — no external tools needed.

---

## Next Actions

- [ ] Copy 3 analytics files to `/DailyJournal/Analytics/`
- [ ] Update `DailyJournalApp.swift`
- [ ] Add `.trackScreen()` to 5 main views
- [ ] Add event tracking to `AuthViewModel` + `JournalEditorViewModel`
- [ ] Run app → perform actions → check Firebase real-time tab
- [ ] Set up Slack alert for crash rate (optional)
- [ ] Monitor metrics daily for 1 week
- [ ] Create funnels in Firebase (signup, onboarding, entry)

---

**Ready?** Start with Step 1. You'll be live in 10 minutes.

Questions? See `ANALYTICS_SETUP.md` (comprehensive guide) or `ANALYTICS_INTEGRATION_EXAMPLES.md` (copy-paste code).
