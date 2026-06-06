# ninety — DailyJournal

A quiet iOS journaling app. No streaks. No badges. No gamification. Just a space to think.

---

## What it does

**ninety** gives users a structured but gentle way to journal daily. The name refers to the 90-second timed session — the minimum viable moment of reflection. Every feature is designed to feel like it's on the user's side, not pushing them toward a metric.

### Core features

**90-second sessions** — A timed prompt with a countdown. The entry auto-saves when the timer ends. Users can tap any of the daily prompts or just write to the timer; it never punishes them for stopping early.

**Free write** — Open-ended editor, no timer, no constraints. Invoked from the same home screen as the 90-second mode. Saving just saves — it no longer forces any follow-up sheet.

**Daily mood check-in** — A journal-free way to log how today feels, surfaced on Home below the prompt card. An interactive "mood blob" maps a 7-band slider onto the app's 5-point mood scale and writes a `MoodLog`. Once today is logged the widget collapses to a compact summary row with a single "Change" action, so it never dominates the screen; the logged mood feeds straight into Patterns analytics.

**Future self letters** — Any entry can be scheduled to "arrive" on a future date. This is now opt-in: tap the **paper-plane button** in the editor toolbar to save and choose a delivery date (2 weeks → 1 year), which also schedules a local notification. Arrived letters appear as a horizontal card row near the top of Home, styled as sealed envelopes. Opening one marks it read and removes it from the inbox.

**Pattern callbacks ("ninety noticed")** — A rarer, weightier sibling of Echoes. A background detector scans a 60-day window (throttled to ~once/20h) and, when a cross-entry pattern is salient enough, surfaces a single callback card on Home stitched from multiple entries. Responses ("not now", "stop watching…", "I needed that") tune future salience. A hard safety gate runs first: if a crisis signal is detected anywhere in the window, **no callback is ever created** — instead a soft, opt-in resource card is shown.

**AI insights (Gemini 2.5 Flash)** — After saving an entry, the app calls Gemini in a background task to generate 2–3 emotional summary bullets, one reflective follow-up question, and a sentiment label. If no API key is configured, `LocalAI` handles these locally with keyword scoring. Either way, the save flow never blocks on the AI call.

**Echoes** — The app's most distinctive feature. After each save, a second background AI call runs to detect whether the entry contains something worth following up on: a stated intention ("I'll call my mum tonight"), an open loop ("the interview next week"), a recurring theme (a person or fear that keeps surfacing), or a mood marker ("I feel completely stuck"). If confidence is ≥ 0.8, the result is stored as an Echo in Firestore. On the next Home load, at most one Echo surfaces — a card above the prompt with the user's original words and a single action. Theme-type echoes link to a full compilation view of every entry mentioning that keyword. Echoes decay automatically: 2 skips dismiss them permanently; anything unanswered after 7 days expires silently.

**Patterns tab** — Shows a resilience score (unique days journaled in the last 30), mood distribution, top tags, and a sentiment timeline. No streak counter — the score reframes consistency as resilience, not obligation.

**Search** — Filters the full entry list by keyword in real time.

**Mood + tags** — Each entry can carry a 5-point mood on a pleasant ↔ unpleasant valence scale (Very pleasant → Very unpleasant, shown with face emoji) and free-text tags laid out with a flow layout.

**Voice input (live)** — `SpeechManager` wraps `SFSpeechRecognizer` for dictation in the editor. Transcription is now **live**: words appear in the editor as you speak (composed onto whatever text was already there) rather than only after you stop. Tapping stop simply ends the session — the text is already in place.

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (iOS 17+) |
| Language | Swift 5, structured concurrency (`async/await`, `Task.detached`) |
| Auth | Firebase Auth — email/password + Google Sign-In |
| Database | Cloud Firestore with 100 MB local cache |
| AI | Gemini 2.5 Flash via plain `URLSession` + `JSONSerialization` (no SDK) |
| Local AI | `LocalAI.swift` — keyword-based sentiment, bullet generation, daily prompts |
| Architecture | MVVM — `@StateObject` ViewModels, `@Published` state, callbacks over closures |

No third-party UI libraries. No Combine. State flows through SwiftUI's native property wrappers.

---

## Project structure

```
DailyJournal/
├── App/
│   ├── DailyJournalApp.swift      — @main, Firebase init, Firestore cache config
│   └── RootView.swift             — Auth gate: routes to Home or Auth based on session
│
├── Auth/
│   ├── AuthViewModel.swift        — Publishes currentUser, handles sign-in/out
│   ├── AuthService.swift          — Firebase Auth wrappers
│   ├── AuthContainerView.swift    — Switches between Login and Signup
│   ├── LoginView.swift
│   ├── SignupView.swift
│   └── VerificationView.swift     — Email-verification gate after signup
│
├── Home/
│   ├── HomeView.swift             — Main screen: header, letters, echo card, prompt, recents
│   ├── NinetySecondSessionView.swift — Timed 90s session UI + ViewModel
│   ├── AIService.swift            — Gemini 2.5 Flash: insights + echo extraction
│   └── LocalAI.swift              — Offline fallback: sentiment, bullets, 30 daily prompts
│
├── Echo/
│   ├── Echo.swift                 — Data model + EchoType + EchoStatus enums
│   ├── EchoService.swift          — Firestore CRUD: create, fetch, skip, answer, decay
│   ├── EchoExtractionService.swift — Pipeline: fetch context → call AI → gate → store
│   ├── EchoCardView.swift         — The home screen card; callbacks only, no service calls
│   ├── EchoAnsweredView.swift     — Sheet shown after user confirms an echo
│   └── ThemeCompilationView.swift — Lists all entries matching a theme keyword
│
├── Journal/
│   ├── JournalEntry.swift         — Data model: content, mood, tags, AI fields, future-self fields
│   ├── JournalService.swift       — Firestore CRUD for entries
│   ├── JournalEditorView.swift    — Entry editor (create + edit)
│   ├── JournalEditorViewModel.swift — Save logic: Firestore + AI insights + echo extraction
│   ├── JournalListView.swift      — Searchable entry list
│   ├── JournalListViewModel.swift
│   └── JournalCardView.swift      — Entry card used in Home recent list
│
├── Patterns/
│   └── PatternsView.swift         — Resilience score, mood chart, top tags
│
├── Mood/
│   ├── MoodLog.swift              — Daily mood-log model + day-key helper
│   ├── MoodLogService.swift       — Firestore CRUD for daily mood logs (cache-first reads)
│   └── MoodBlobView.swift         — Home mood widget: interactive blob + compact logged state
│
├── Pattern/
│   ├── PatternCallback.swift          — Callback model + archetype/evidence types
│   ├── PatternDetectionService.swift  — 60-day detection orchestration + safety gate
│   ├── PatternCallbackService.swift   — Firestore CRUD + surface/frequency gating
│   ├── LocalPatternDetector.swift     — Offline fallback detector
│   ├── AIService+Patterns.swift       — Gemini pattern-detection call
│   ├── PatternSafety.swift            — Crisis-signal detection (hard safety gate)
│   ├── PatternSettings.swift          — Per-user frequency, scope, mutes, throttle
│   ├── PatternCallbackCardView.swift  — Home "ninety noticed" card
│   ├── PatternStitchedView.swift      — Tap-through stitched evidence view
│   └── PatternResourceCardView.swift  — Soft, opt-in safety resource card
│
├── Components/
│   ├── CustomTextField.swift
│   ├── PrimaryButton.swift
│   ├── ErrorBanner.swift
│   ├── DividerWithText.swift
│   ├── FlowLayout.swift           — Wrapping tag layout
│   ├── FutureSelfSheet.swift      — Date picker for scheduling future-self letters
│   ├── GoogleSignInButton.swift
│   └── SpeechManager.swift        — AVFoundation speech recognition wrapper
│
└── Theme/
    └── AppTheme.swift             — Color palette, semantic aliases, typography helpers
```

---

## Design system

All visual constants live in `AppTheme`. The palette is warm and analogue — no pure whites or blacks.

| Token | Hex | Use |
|---|---|---|
| `paper` | `#F2EBDE` | Screen backgrounds |
| `paperWarm` | `#EAE0CE` | Card backgrounds (echo card) |
| `cream` | `#FBF7EE` | Entry cards, input areas |
| `ink` | `#1A1614` | Primary text, filled buttons |
| `inkSoft` | `#3A332D` | Secondary text, borders |
| `terracotta` | `#C8472F` | Primary accent: labels, highlights, CTAs |
| `moss` | `#5C6F4A` | Calm/happy mood accent |
| `dusk` | `#6B5B8A` | Sad mood accent |
| `gold` | `#C9973A` | Excited/amazing mood accent |
| `slate` | `#8B8B7A` | Neutral mood, muted UI |

**Typography** uses two system font styles — no custom font files required:
- `editorialDisplay(size:)` — `.system(design: .serif)` for headings and quotes
- `editorialBody(size:)` — `.system(design: .serif)` for body text
- `mono(size:)` — `.system(design: .monospaced)` for labels, timestamps, metadata

---

## Data model (Firestore)

```
users/{userId}
  ├── entries/{entryId}
  │     id, userId, title, content, mood, tags
  │     createdAt, updatedAt, sessionType
  │     futureSelfDeliveryDate?, futureSelfOpened
  │     aiSummaryBullets[], aiQuestion?, sentimentLabel?
  │
  └── echoes/{echoId}
        id, userId, sourceEntryId, sourceEntryCreatedAt
        type (intention | open_loop | theme | mood_marker)
        quote, surfaceAfterDate, confidence
        status (pending | answered | dismissed | expired)
        skipCount, createdAt, answeredAt?
        themeKeyword?
```

Firestore security rules restrict all reads and writes to the authenticated owner (`request.auth.uid == userId`).

---

## Echo feature — how it works

1. Entry saved → `EchoExtractionService.extractAndStore` runs in a detached background task (never blocks the save UI).
2. Fetches up to 3 recent entries for context, excludes the one just saved.
3. Calls Gemini 2.5 Flash with a conservative extraction prompt (temperature 0.2). Most entries return `{"echo": null}` — that is the correct and expected outcome.
4. Gates on `confidence ≥ 0.8` before writing to Firestore.
5. On next HomeView load, `EchoService.fetchTopPendingEcho` queries: `status == pending AND surfaceAfterDate <= now`, ordered by confidence descending, limit 1.
6. At most one Echo is set per session — `HomeViewModel.load()` only assigns `pendingEcho` when it's currently nil, so pull-to-refresh doesn't re-surface a dismissed card.
7. Decay runs as a background task on every fetch: skips ≥ 2 → dismissed, age > 7 days → expired.

> **Firestore index required:** The `fetchTopPendingEcho` query uses a composite index on `status + surfaceAfterDate + confidence`. Firestore will log a clickable link to create it the first time this query runs.

---

## AI setup

AI insights are powered by Gemini when an API key is present in `UserDefaults` under `"gemini_api_key"` (read via `AIService`). There is **no in-app UI to enter the key** — the Profile screen was deliberately stripped to just Account + Sign out. When no key is set (the default), all AI features fall back to `LocalAI` (local keyword scoring) and Echo / Pattern extraction run on the on-device detector.

> **Architectural note:** Storing the API key client-side is a shortcut. The correct long-term approach is a Firebase Cloud Function that accepts the entry text, calls Gemini server-side, and returns the result — so the key never lives on the device. Provisioning the key (remote config, build-time injection, or the Cloud Function) is a future task.

**Pattern callbacks are always-on.** Frequency/scope are no longer user-configurable — `PatternSettings.frequency` is hardcoded to `.whenever` and cadence is governed entirely by the detection throttle (~once/20h) and the surface gates.

---

## Sign in with Apple

The app supports email/password, Google, and **Sign in with Apple** (`AppleSignInButton` on both Login and Signup). The flow uses Apple's `SignInWithAppleButton` with a CryptoKit-generated nonce (`AuthService.randomNonceString` / `sha256`), exchanged for a Firebase credential via `OAuthProvider.appleCredential(withIDToken:rawNonce:fullName:)` in `AuthService.signInWithApple`. `AuthViewModel.prepareAppleRequest` / `handleAppleSignIn` own the request and result handling.

Code and the `DailyJournal.entitlements` file (with `com.apple.developer.applesignin`) are committed and `CODE_SIGN_ENTITLEMENTS` is wired into both build configs. **Two switches still require your accounts:**

1. **Apple Developer portal** — on the App ID `com.satakshi.DailyJournal`, enable the "Sign in with Apple" capability. (In Xcode: Target → Signing & Capabilities → + Capability → Sign in with Apple, with automatic signing, does this for you.)
2. **Firebase console** — Authentication → Sign-in method → enable **Apple** as a provider. For email relay you may also configure the Apple private-email return path; for a basic iOS-only app the default is enough.

Until both are on, the button will render but sign-in will fail at the Firebase exchange.

## What's new in this iteration

- **AI model bumped to `gemini-2.5-flash`** — the previous `gemini-2.0-flash` was retired by Google (Mar 2026) and was silently failing into the LocalAI fallback.
- **Live voice transcription** in the editor; **one-time mic hint** on the 90-second screen.
- **Mood blob** logs a per-day `MoodLog`, collapses to a compact summary once logged, and adds a haptic + bounce + gentle affirmation on log. Labels are a pleasant ↔ unpleasant valence scale with face emoji.
- **Mascot empty states** (`MascotView` / `FriendlyEmptyState`) on Home recents and the Journal list.
- **Draft autosave** — unsaved free-write text persists locally and restores on reopen ("Draft restored"), cleared on save.
- **Simplified Home CTA** — one primary "Start writing", 90-second mode secondary.
- **Shareable insight card** (`ShareableInsightCard`) and **weekly "ninety wrapped" recap** (`WeeklyWrappedCard`), both rendered to images via `ImageRenderer` and shared through `ShareLink`.
- Profile stripped to Account + Sign out; pattern callbacks are always-on.

## Key patterns and decisions

**Fire-and-forget writes** — Firestore writes go to the local cache instantly and sync in the background. The UI never `await`s a write.

**Cache-first reads** — Firestore persistence is enabled explicitly via `PersistentCacheSettings` (100 MB) in `DailyJournalApp`. Read paths in `JournalService` and `MoodLogService` query `source: .cache` first and only fall back to the network (`.default`) when the cache is cold, so Home, Patterns and the entry list paint instantly instead of waiting on a server round-trip. Pull-to-refresh re-runs the same load. This is the fix for the earlier slow-load behaviour.

**`sheet(item:onDismiss:)`** — Echo sheets use `sheet(item:)` instead of `sheet(isPresented:)`. The echo is captured at tap time into a stable `@State` variable so sheet content never flickers if `vm.pendingEcho` is cleared during the dismiss animation. The parent's `onDismiss` handles the Firestore state update; child views only call `dismiss()`.

**MVVM callback pattern** — `EchoCardView` receives all actions as closures (`onSkip`, `onAnswer`, `onThemeTap`). It never calls a service directly. `HomeViewModel` is the single source of truth for echo state.

**No badges on the echo section** — `sectionLabel("an echo", count: nil)` explicitly passes `nil` for the count, omitting the terracotta count pill. The echo is not a notification.

**Xcode 15+ file sync** — The project uses `PBXFileSystemSynchronizedRootGroup`. New `.swift` files dropped into any group folder are picked up automatically — no `.pbxproj` edits needed.
