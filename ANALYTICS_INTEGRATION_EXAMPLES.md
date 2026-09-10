# Analytics Integration: Code Examples

Copy-paste examples for integrating analytics throughout the app.

---

## Example 1: Screen Tracking in Views

### HomeView.swift
```swift
struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            // ... your existing UI
        }
        .trackScreen(.home, parameters: ["tab": "today"])
    }
}
```

### JournalListView.swift
```swift
struct JournalListView: View {
    var body: some View {
        NavigationStack {
            List {
                // ... entries list
            }
        }
        .trackScreen(.journal)
    }
}
```

### MirrorView.swift
```swift
struct MirrorView: View {
    var body: some View {
        ZStack {
            // ... hypotheses UI
        }
        .trackScreen(.mirror)
    }
}
```

---

## Example 2: Auth Tracking

### AuthViewModel.swift
```swift
@MainActor
final class AuthViewModel: ObservableObject {
    
    func completeSignup(email: String, password: String) async {
        do {
            // ... Firebase signup logic
            
            // Track signup completion
            AnalyticsManager.shared.trackSignupCompleted(provider: "email")
            
            // Set user ID for analytics segmentation
            AnalyticsManager.shared.setUserId(user.uid)
            
            // Record signup date for retention analysis
            SessionManager.shared.recordSignupDate()
            
        } catch {
            AnalyticsManager.shared.trackError(error, context: "signup_failed")
        }
    }
    
    func loginWithGoogle() async {
        do {
            // ... Google sign-in logic
            
            AnalyticsManager.shared.trackLoginCompleted(provider: "google")
            AnalyticsManager.shared.setUserId(user.uid)
            
        } catch {
            AnalyticsManager.shared.trackError(error, context: "google_login_failed")
        }
    }
    
    func toggleAIConsent(_ enabled: Bool) {
        UserDefaults.standard.aiConsentGranted = enabled
        
        if enabled {
            AnalyticsManager.shared.trackAIConsentGranted()
            AnalyticsManager.shared.setUserProperty("true", forName: "ai_consent_granted")
        } else {
            AnalyticsManager.shared.trackAIConsentDenied()
            AnalyticsManager.shared.setUserProperty("false", forName: "ai_consent_granted")
        }
    }
}
```

---

## Example 3: Entry Creation Tracking

### JournalEditorViewModel.swift
```swift
@MainActor
final class JournalEditorViewModel: ObservableObject {
    
    @Published var startTime: Date?
    @Published var content: String = ""
    @Published var mood: Mood?
    @Published var photoURL: String?
    
    func startComposing(sessionType: SessionType) {
        startTime = Date()
        
        // Track composition started
        AnalyticsManager.shared.trackEntryCompositionStarted(
            sessionType: sessionType.rawValue
        )
    }
    
    func saveEntry(userId: String, sessionType: SessionType) {
        guard let startTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let wordCount = content.split(separator: " ").count
        
        let entry = JournalEntry(
            userId: userId,
            content: content,
            mood: mood,
            sessionType: sessionType,
            photoURL: photoURL
        )
        
        // Save to Firestore (fire-and-forget)
        JournalService().createEntry(entry)
        
        // Track entry creation with rich context
        AnalyticsManager.shared.trackEntryCreated(
            sessionType: sessionType.rawValue,
            wordCount: wordCount,
            hasMood: mood != nil,
            hasPhoto: photoURL != nil,
            hasAI: false,  // Will be true after AI insights generated
            duration: duration
        )
        
        // Record for session-end metrics
        SessionManager.shared.recordEntryWritten()
    }
    
    func discardEntry(sessionType: SessionType) {
        let wordCount = content.split(separator: " ").count
        
        // Track discard (useful for identifying friction)
        AnalyticsManager.shared.trackEntryDiscarded(
            sessionType: sessionType.rawValue,
            wordCount: wordCount
        )
    }
}
```

---

## Example 4: AI Feature Tracking

### AIService.swift
```swift
final class AIService {
    
    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> Data {
        let startTime = Date()
        
        guard isAIAvailable else {
            throw AIError.consentNotGranted
        }
        
        do {
            let response = try await callGemini(prompt, maxTokens: maxTokens, temperature: temperature)
            
            let latency = Date().timeIntervalSince(startTime)
            
            // Track successful AI call
            AnalyticsManager.shared.logEvent(.aiInsightsGenerated, parameters: [
                "latency_ms": Int(latency * 1000),
                "model": "gemini-3.5-flash-lite"
            ])
            
            return response
            
        } catch let error as AIError {
            AnalyticsManager.shared.trackAIInsightsFailed(error: error.localizedDescription)
            throw error
        }
    }
}

// Extension for entry insights
extension AIService {
    func generateInsights(for entry: JournalEntry) async throws -> JournalInsights {
        let startTime = Date()
        
        do {
            let insights = try await callGeminiForInsights(entry)
            
            let latency = Date().timeIntervalSince(startTime)
            
            AnalyticsManager.shared.trackAIInsightsGenerated(
                entryType: entry.sessionType.rawValue,
                bulletCount: insights.bullets.count,
                hasQuestion: insights.question.isEmpty == false,
                latency: latency
            )
            
            return insights
        } catch {
            AnalyticsManager.shared.trackAIInsightsFailed(error: error.localizedDescription)
            throw error
        }
    }
}
```

---

## Example 5: Echo System Tracking

### EchoService.swift
```swift
final class EchoService {
    
    func surfaceNextEcho(for userId: String) async -> Echo? {
        let echo = try? await fetchPendingEcho(userId: userId)
        
        if let echo {
            AnalyticsManager.shared.trackEchoSurfaced(
                type: echo.type.rawValue,
                confidence: echo.confidence
            )
        }
        
        return echo
    }
}

// In HomeViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    
    @Published var pendingEcho: Echo?
    
    func userAnsweredEcho() {
        AnalyticsManager.shared.trackEchoAnswered()
    }
    
    func userDismissedEcho() {
        AnalyticsManager.shared.trackEchoDismissed()
    }
    
    func userExploredTheme() {
        AnalyticsManager.shared.trackEchoThemeExplored()
    }
}
```

---

## Example 6: Pattern/Mirror Tracking

### PatternDetectionService.swift
```swift
final class PatternDetectionService {
    
    func detectPatterns(for userId: String, window: Int = 60) async -> [PatternHypothesis] {
        do {
            let patterns = try await mineHypotheses(userId: userId, windowDays: window)
            
            for pattern in patterns {
                AnalyticsManager.shared.trackPatternSurfaced(
                    archetype: pattern.archetype.rawValue,
                    evidenceCount: pattern.evidence.count,
                    noveltyScore: pattern.noveltyScore
                )
            }
            
            return patterns
        } catch {
            AnalyticsManager.shared.logEvent(.patternDetectionFailed, parameters: [
                "error": error.localizedDescription
            ])
            throw error
        }
    }
}

// In MirrorView
struct MirrorView: View {
    var body: some View {
        List(hypotheses) { hypothesis in
            Button {
                AnalyticsManager.shared.trackPatternExplored(
                    archetype: hypothesis.archetype.rawValue
                )
                selectedHypothesis = hypothesis
            } label: {
                HypothesisRow(hypothesis)
            }
        }
        .trackScreen(.mirror)
    }
}
```

---

## Example 7: Journal Interactions Tracking

### JournalListView.swift
```swift
struct JournalListView: View {
    @State private var searchText = ""
    @State private var selectedFilter: MoodFilter?
    
    var body: some View {
        NavigationStack {
            List(filteredEntries) { entry in
                NavigationLink(destination: EntryDetailView(entry: entry)) {
                    EntryRow(entry)
                }
                .onTapGesture {
                    let age = Date().timeIntervalSince(entry.createdAt)
                    AnalyticsManager.shared.trackEntryViewed(
                        sessionType: entry.sessionType.rawValue,
                        age: age
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search entries")
            .onChange(of: searchText) { newValue in
                if !newValue.isEmpty {
                    AnalyticsManager.shared.trackJournalSearched(query: newValue)
                }
            }
            .onChange(of: selectedFilter) { newFilter in
                if let filter = newFilter {
                    AnalyticsManager.shared.trackJournalFiltered(
                        filterType: filter.rawValue
                    )
                }
            }
        }
        .trackScreen(.journal)
    }
}
```

---

## Example 8: Hint Ladder Tracking

### HintLadderView.swift
```swift
struct HintLadderView: View {
    @State private var startTime: Date?
    
    var body: some View {
        VStack {
            if currentStep == 0 {
                BlankPrompt(onStart: {
                    startTime = Date()
                    AnalyticsManager.shared.logEvent(.hintLadderStarted)
                })
            } else if currentStep < totalSteps {
                HintStep(hint: hints[currentStep])
            } else {
                // User reached free-write (completed ladder)
                if let startTime {
                    let duration = Date().timeIntervalSince(startTime)
                    AnalyticsManager.shared.logEvent(
                        .hintLadderCompleted,
                        parameters: ["duration_seconds": Int(duration)]
                    )
                }
            }
        }
    }
}
```

---

## Example 9: Mood Tracking

### MoodLogView.swift
```swift
struct MoodLogView: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Mood.allCases, id: \.self) { mood in
                Button {
                    AnalyticsManager.shared.trackMoodLogged(mood: mood.rawValue)
                    selectedMood = mood
                } label: {
                    Text(mood.emoji)
                        .font(.system(size: 32))
                }
            }
        }
    }
}
```

---

## Example 10: Settings/Theme Tracking

### ThemePickerView.swift
```swift
struct ThemePickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        List(Theme.allCases) { theme in
            Button {
                themeManager.selectTheme(theme)
                AnalyticsManager.shared.logEvent(.themeChanged, parameters: [
                    "theme": theme.rawValue
                ])
            } label: {
                HStack {
                    Text(theme.name)
                    Spacer()
                    if themeManager.currentTheme == theme {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .trackScreen(.settings)
    }
}
```

---

## Example 11: Session Lifecycle (in AppDelegate)

Already implemented in `SessionManager.swift`, but here's how it works:

```swift
// When app launches
func application(_ application: UIApplication, 
                 didFinishLaunchingWithOptions: ...
) -> Bool {
    // SessionManager automatically logs session_started with days_after_signup
    return true
}

// When app enters background
func applicationDidEnterBackground(_ application: UIApplication) {
    // SessionManager automatically logs session_ended with duration + entries_written
}
```

---

## Example 12: Error Tracking Throughout the App

### Any ViewModel or Service
```swift
do {
    try await performSomeTask()
} catch {
    AnalyticsManager.shared.trackError(
        error,
        context: "journal_list_fetch"  // Specific context
    )
}
```

---

## Real-Time Monitoring Checklist

After integrating analytics, monitor these in Firebase Console:

### **Daily**
- [ ] Real-time active users (should be >0)
- [ ] Crash rate (should be <1%)
- [ ] Top screens (Home should be highest)
- [ ] Top events (entry_created should appear regularly)

### **Weekly**
- [ ] Entry creation trend (should be stable or growing)
- [ ] AI consent rate (target: >60%)
- [ ] Echo answer rate (target: >40%)
- [ ] DAU/MAU ratio (target: >30%)

### **Monthly**
- [ ] D1/D7/D30 retention (target: >50% / >30% / >15%)
- [ ] Average entries per user (target: >5/month)
- [ ] AI feature adoption trend
- [ ] New user funnel completion

---

## Common Pitfalls to Avoid

❌ **Don't:** Log raw entry content or query strings
✅ **Do:** Log hashed queries or just event counts

❌ **Don't:** Log personally identifiable information in parameters
✅ **Do:** Use Firebase's setUserID() instead

❌ **Don't:** Create too many custom events (>100)
✅ **Do:** Reuse parameters to segment existing events

❌ **Don't:** Log every single interaction (too noisy)
✅ **Do:** Log key decision points and conversions only

❌ **Don't:** Ignore errors in analytics calls
✅ **Do:** Catch exceptions so analytics failures don't crash the app

✅ **Do:** Test analytics locally with Firebase emulator or debug logs
✅ **Do:** Review Firebase limits (events, properties, etc.)
