# Analytics Implementation: Complete Overview

This folder contains everything you need to implement comprehensive product analytics for the DailyJournal app.

---

## 📚 Documentation Files

| File | Purpose | Read Time |
|------|---------|-----------|
| **ANALYTICS_QUICK_START.md** | 5-minute setup guide | 5 min ⭐ START HERE |
| **ANALYTICS_SETUP.md** | Comprehensive event reference | 20 min 📖 Deep dive |
| **ANALYTICS_INTEGRATION_EXAMPLES.md** | Copy-paste code for each feature | 15 min 💻 Implementation |
| **METRICS_DASHBOARD_GUIDE.md** | How to interpret Firebase dashboards | 10 min 📊 Analysis |
| **ANALYTICS_README.md** | This file (overview) | 5 min 👈 You are here |

---

## 🎯 What This Gives You

After implementing, you'll have **automatic, real-time visibility** into:

### **User Behavior**
- Which pages users visit most
- How long they spend on each page
- When they drop off
- Feature adoption rates
- Engagement patterns

### **Product Health**
- Daily active users (DAU)
- Retention curves (Day 1, 7, 30)
- Session duration
- Entry creation rate
- Feature usage distribution

### **Technical Metrics**
- App crashes
- AI call latency
- Error rates
- Network issues

### **Business Insights**
- Funnel conversion rates (signup → first entry)
- Feature engagement (echoes, patterns, mirror)
- AI consent adoption
- Cohort comparisons

---

## 🚀 Implementation Path

### Phase 1: Basic Tracking (Today — 10 min)
```
1. Copy 3 analytics files to /DailyJournal/Analytics/
2. Update DailyJournalApp.swift to initialize SessionManager
3. Add .trackScreen() to 5 main views
4. Verify Firebase is enabled
→ Now tracking: screen views, app launches, crashes
```

### Phase 2: Event Tracking (Next 1 hour)
```
1. Add event logging to AuthViewModel (signup, login)
2. Add event logging to JournalEditorViewModel (entry creation)
3. Add event logging to HomeViewModel (echo, pattern interactions)
4. Add event logging to AIService (AI call latency/failures)
→ Now tracking: all user actions and feature usage
```

### Phase 3: Dashboard & Analysis (Next 1 day)
```
1. Create funnels in Firebase (signup, onboarding, entry)
2. Set up retention curves
3. Create cohort analysis (AI users vs non-AI users)
4. Set up alerts for crashes, DAU drops
→ Now have: actionable insights for product decisions
```

---

## 📁 Code Structure

```
DailyJournal/Analytics/
├── AnalyticsManager.swift
│   └─ Central event tracking SDK
│      • Pre-built event enums (50+ events)
│      • Convenience methods (trackEntryCreated, trackEchoAnswered, etc)
│      • User properties (for segmentation)
│
├── ScreenTrackingModifier.swift
│   └─ Auto-log screen views
│      • Usage: MyView().trackScreen(.home)
│      • Logs on every view appearance
│
└── SessionManager.swift
    └─ App lifecycle tracking
       • Tracks app launch/background/close
       • Logs session duration
       • Logs entries written per session
```

---

## 📊 Events You'll Collect (50+)

Organized by feature:

| Category | Events | Examples |
|----------|--------|----------|
| **Auth** | 5 | signup_started, signup_completed, login_completed, signout_completed, account_deleted |
| **Onboarding** | 4 | onboarding_started, onboarding_completed, vibe_selected, onboarding_skipped |
| **Entries** | 5 | entry_composition_started, entry_created, entry_edited, entry_deleted, entry_discarded |
| **AI Features** | 4 | ai_consent_granted, ai_consent_denied, ai_insights_generated, ai_insights_failed |
| **Echoes** | 5 | echo_surfaced, echo_answered, echo_dismissed, echo_expired, echo_theme_explored |
| **Patterns** | 5 | pattern_surfaced, pattern_dismissed, pattern_explored, pattern_evidence_viewed, pattern_detection_failed |
| **Mirror** | 3 | mirror_hypothesis_viewed, mirror_hypothesis_edited, mirror_graph_viewed |
| **Hints** | 4 | today_read_viewed, hint_ladder_started, hint_ladder_completed, question_answered |
| **Chat** | 4 | daily_chat_started, daily_chat_completed, cbt_mode_started, cbt_mode_completed |
| **Journal** | 4 | journal_filtered, journal_searched, journal_sorted, entry_viewed |
| **Settings** | 3 | theme_changed, settings_opened, feedback_sent |
| **Session** | 4 | session_started, session_ended, app_foregrounded, app_backgrounded |
| **Errors** | 3 | firebase_error, network_error, ai_service_error |

---

## 🔍 Key Metrics to Monitor

### **Daily**
- Active Users Now (real-time)
- Crash Rate (should be <1%)
- Top screens visited
- Latest events

### **Weekly**
- DAU (Daily Active Users)
- Entry creation rate
- D1 Retention (% who return next day)
- Session duration
- Feature adoption

### **Monthly**
- D7 Retention (% who return after 1 week)
- D30 Retention (% who return after 1 month)
- Funnel conversions (signup → first entry)
- Feature engagement (echo answer rate, pattern exploration)
- AI adoption rate

---

## 📈 Critical Funnels to Track

### Funnel 1: Acquisition
```
signup_started → signup_completed → login_completed
Target conversion: >80%
```

### Funnel 2: Onboarding
```
onboarding_started → onboarding_completed → entry_created
Target conversion: >50%
```

### Funnel 3: Today's Read
```
today_read_viewed → hint_ladder_started → entry_created
Target conversion: >40%
```

### Funnel 4: Echoes
```
echo_surfaced → echo_answered (+ echo_dismissed)
Target: >40% answer rate
```

### Funnel 5: Patterns
```
pattern_surfaced → pattern_explored → pattern_evidence_viewed
Target: >25% exploration rate
```

---

## ✅ Integration Checklist

### Files to Add
- [ ] Copy `AnalyticsManager.swift` to `/DailyJournal/Analytics/`
- [ ] Copy `ScreenTrackingModifier.swift` to `/DailyJournal/Analytics/`
- [ ] Copy `SessionManager.swift` to `/DailyJournal/Analytics/`

### Code Changes
- [ ] Import `FirebaseAnalytics` in `DailyJournalApp.swift`
- [ ] Initialize `SessionManager.shared` in `DailyJournalApp`
- [ ] Add `.trackScreen(.home)` to `HomeView`
- [ ] Add `.trackScreen(.journal)` to `JournalListView`
- [ ] Add `.trackScreen(.mirror)` to `MirrorView`
- [ ] Add `.trackScreen(.authLogin)` to `AuthContainerView`
- [ ] Add `.trackScreen(.onboarding)` to `OnboardingView`

### Event Tracking (by feature)
- [ ] `AuthViewModel`: `trackSignupCompleted()`, `trackLoginCompleted()`, `trackAIConsentGranted()`
- [ ] `JournalEditorViewModel`: `trackEntryCreated()`, `trackEntryDiscarded()`
- [ ] `HomeViewModel`: `trackEchoAnswered()`, `trackPatternSurfaced()`
- [ ] `AIService`: `trackAIInsightsGenerated()`, `trackAIInsightsFailed()`
- [ ] `EchoService`: `trackEchoSurfaced()`, `trackEchoDismissed()`
- [ ] `PatternDetectionService`: `trackPatternSurfaced()`, `trackPatternExplored()`

### Firebase Setup
- [ ] Verify Firebase Analytics is enabled
- [ ] Set `proxyURLString` in `AIService` to your Gemini proxy URL
- [ ] Create funnels in Firebase Console (signup, onboarding, echo)
- [ ] Create retention cohort
- [ ] Set up crash alert

### Documentation
- [ ] Update Privacy Policy to mention Firebase Analytics
- [ ] Document baseline metrics (Day 1 DAU, signup rate, etc.)
- [ ] Schedule weekly metrics review

---

## 🎓 How to Use These Docs

### "I just want to get started ASAP"
→ Read **ANALYTICS_QUICK_START.md** (5 min) and implement

### "I want comprehensive event tracking"
→ Read **ANALYTICS_SETUP.md** and **ANALYTICS_INTEGRATION_EXAMPLES.md**

### "I want to understand how to read the dashboards"
→ Read **METRICS_DASHBOARD_GUIDE.md**

### "I need copy-paste code for my feature"
→ Search **ANALYTICS_INTEGRATION_EXAMPLES.md** for your view/service

---

## 🔑 Key Concepts

### **Screen View** (Automatic)
Logged every time a user navigates to a screen. Shows which screens are used most.

```swift
.trackScreen(.home)  // Logs: user_engagement event with screen_name=screen_home_today
```

### **Event** (Manual)
Logged when specific user actions happen. Shows what users do on screens.

```swift
AnalyticsManager.shared.trackEntryCreated(...)  // Logs: entry_created with parameters
```

### **User Property** (Segmentation)
Assigns a characteristic to a user (e.g., "ai_consent_granted=true"). Lets you compare cohorts.

```swift
AnalyticsManager.shared.setUserProperty("true", forName: "ai_consent_granted")
// Later: Compare retention of users where ai_consent_granted=true vs false
```

### **Funnel** (Conversion)
A sequence of events showing drop-off points (e.g., how many signup → complete onboarding → write entry).

### **Cohort** (Segmentation)
A group of users with a shared characteristic or time period (e.g., "users who signed up this week").

### **Retention** (Engagement)
Percentage of users from Day 0 who return on Day 1, 7, 30, etc.

---

## 🛠️ Firebase Analytics Basics

### Where to Check Data
1. **Real-time**: Firebase Console → Analytics → Realtime (updates every 5 sec)
2. **Dashboard**: Firebase Console → Analytics → Dashboard (next day)
3. **Events**: Firebase Console → Analytics → Events (all event occurrences)
4. **Funnels**: Firebase Console → Analytics → Funnel Analysis (create new)
5. **Retention**: Firebase Console → Analytics → Retention (cohort curves)
6. **Cohorts**: Firebase Console → Analytics → Cohorts (compare user groups)

### How Data Flows
```
App logs event via AnalyticsManager
    ↓
Firebase SDK (already in app via Firestore dependency)
    ↓
Firebase Analytics backend (Google's servers)
    ↓
Firebase Console dashboard (displays data, usually 24h delay for Dashboard)
    ↓
Realtime view shows immediately (<5 min)
```

### Retention Window
- Real-time data: Available in 5-10 min
- Dashboard updates: Once per day (usually early morning)
- Custom reports: Can be run on historical data

---

## ⚠️ Common Mistakes to Avoid

❌ **Don't log personally identifiable information**
- No entry content
- No exact search queries
- Firebase explicitly forbids this

✅ **Do log aggregated/hashed data**
- Log "user searched" (not "searched for 'anxiety'")
- Log event counts (not individual queries)

❌ **Don't spam with too many events**
- Firebase has limits; be intentional
- Log key decision points only

✅ **Do make event names consistent**
- Use PascalCase or snake_case consistently
- Keep names short but descriptive
- Examples: `entry_created`, `echo_answered`, `pattern_explored`

❌ **Don't forget to handle errors**
- Analytics failures should not crash the app
- Wrap in try-catch or use Task { @MainActor in }

✅ **Do test locally**
- Enable Firebase debug mode to see events locally
- Check Xcode console for debug logs

---

## 📞 Support & Questions

### "How do I track [specific feature]?"
→ See **ANALYTICS_INTEGRATION_EXAMPLES.md** for your feature

### "Which events should I log?"
→ See **ANALYTICS_SETUP.md** Events table

### "How do I interpret my dashboard?"
→ See **METRICS_DASHBOARD_GUIDE.md**

### "Firebase Analytics isn't showing data"
→ Common: Takes 24 hours for data to appear in Dashboard tab
→ Check: Real-time tab first (updates in 5-10 min)
→ Verify: `AnalyticsManager.shared.logEvent()` is being called

### "I want to build a custom dashboard"
→ Export to BigQuery (Firebase Console → Settings → BigQuery linking)
→ Then query with SQL: `SELECT event_name, COUNT(*) FROM analytics_events GROUP BY event_name`

---

## 🎯 Success Criteria (After 1 Month)

✅ **You can answer these questions:**
1. How many daily active users do we have?
2. What % of new users write their first entry?
3. What % of users return on Day 7?
4. Which feature has the highest engagement?
5. What % of users have AI enabled?
6. Where do users drop off in onboarding?
7. Do AI users have higher retention?
8. What's our crash rate?
9. How long do sessions last?
10. Which session type (timed/free-write/chat) is most popular?

✅ **You have:**
- [ ] Real-time dashboard showing active users
- [ ] Daily metrics spreadsheet tracking DAU, entries, retention
- [ ] Weekly report template
- [ ] 3-5 key funnels to monitor
- [ ] Alerts for crash rate and DAU drops

✅ **You're using insights to:**
- [ ] Prioritize features based on adoption
- [ ] Identify friction points (high drop-off)
- [ ] A/B test improvements
- [ ] Make data-driven product decisions

---

## 📅 Next Steps

**This week:**
1. Add analytics files to project
2. Update `DailyJournalApp.swift`
3. Add `.trackScreen()` to main views
4. Run app and verify Firebase is receiving data

**Next week:**
1. Add event tracking to ViewModels and Services
2. Create funnels in Firebase
3. Build weekly metrics report
4. Share first report with team

**Month 1:**
1. Establish baseline metrics
2. Identify top 3 product improvements based on data
3. Run A/B test on highest-friction point
4. Monthly retro: "What did we learn from analytics?"

---

## 📖 Additional Resources

- [Firebase Analytics Docs](https://firebase.google.com/docs/analytics/ios/start)
- [Creating Funnels in Firebase](https://support.google.com/firebase/answer/9048308)
- [Firebase Cohort Analysis](https://support.google.com/firebase/answer/9048312)
- [Setting User Properties](https://firebase.google.com/docs/analytics/ios/start#set_user_properties)
- [Firebase Best Practices](https://firebase.google.com/docs/best-practices/analytics)

---

**Ready to go?** Start with **ANALYTICS_QUICK_START.md** (5 minutes) → implementation → dashboard review.

You'll have production-grade analytics live by end of day.
