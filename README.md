# Spilr

A quiet, private iOS journaling app. No streaks, no badges, no gamification — a
space to think, with AI that reflects rather than rates.

> Codename in the repo/bundle is `DailyJournal` ("ninety" historically); the
> user-facing brand is **Spilr**.

---

## What it is

Spilr is **local-first**: writing, saving and browsing always work offline and
without AI. AI enriches silently in the background and never blocks the user; when
it can't produce something safe and grounded, the surface shows nothing rather
than a canned line (see CLAUDE.md → "No local text in Spilr's voice").

The app has **three tabs** (`AppTab` in `App/AppRouter.swift`):

- **Today** — the home screen. Entry points to write: Daily Chat, a free/timed
  "spill" write, and guided templates. Surfaces one Echo and the day's hook.
- **Journal** — the searchable entry list with mood, tags, sentiment and
  future-self letters.
- **Mirror** — the reflection surface: the daily reading, the Person Model
  ("what Spilr thinks it knows", with evidence and corrections), the First Sketch
  ceremony, and the weekly letter.

### Core features

- **Daily Chat** — an interactive CBT-style conversation that weaves into a
  journal entry (`Chat/`).
- **Spill / timed write** — open-ended or timed writing from Home (`Home/SpillWriteView.swift`, `TimedSessionViewModel`).
- **Templates** — structured guided prompts woven into one entry (`Home/`).
- **Echoes** — a single follow-up surfaced from a past entry: an intention, open
  loop, recurring theme or mood marker (`Echo/`).
- **Mirror / Person Model** — server-assembled hypotheses about the user, each
  evidence-backed and user-correctable; a daily reading grounded in counted
  observations; a dated weekly letter (`Mirror/`).
- **Future-self letters** — schedule an entry to "arrive" on a future date.
- **Themes** — selectable palettes via `Theme/AppTheme.swift` + `ThemeManager`.
- **Onboarding** — vibe picker and a guided first entry (`Onboarding/`).

Access to AI features is gated by `Auth/EntitlementService.swift` (a free preview
window + budget, then subscription).

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI |
| Language | Swift, structured concurrency (`async/await`, `Task.detached`) |
| Auth | Firebase Auth — email/password, Google, Sign in with Apple |
| Database | Cloud Firestore with a local persistent cache (cache-first reads) |
| AI | Gemini `gemini-3.5-flash-lite`, server-side only via the `geminiProxy` Cloud Function (plain `URLSession` + `JSONSerialization`, no SDK, no API key on device) |
| Local derivation | `Home/LocalAI.swift` — on-device sentiment + topic tags (data, not voice) |
| Backend | `functions/` — `geminiProxy` plus nightly jobs (facts, observations, Person Model, weekly letter) |
| Architecture | MVVM — `@MainActor` `ObservableObject` ViewModels, callbacks over direct service calls |

No third-party UI libraries.

---

## AI

All model calls go through the `geminiProxy` Cloud Function with a Firebase ID
token — the API key never lives on the device. Client prompts begin with
`SpilrVoice.system` and carry a safety block; nightly reflection runs server-side.

The full list of live AI surfaces — client and server-internal, each with its
prompt location, model and safety block — is in **`ai-surfaces.md`**. The working
rules for the AI layer (fallback discipline, safety blocks, enrichment listeners)
are in **CLAUDE.md**.

---

## Project structure

```
DailyJournal/
├── Analytics/     AnalyticsManager, SessionManager, screen tracking
├── App/           DailyJournalApp (@main), RootView, AppRouter, FirestoreSchema
├── Auth/          Sign-in (email/Google/Apple), EntitlementService
├── Calendar/      Calendar view + service
├── Chat/          Daily Chat (ChatPrompts, ChatSession, AIService+Chat, DailyChatView)
├── Components/    Shared UI (SpeechManager, FlowLayout, FutureSelfSheet, …)
├── Echo/          Echo model, EchoService, extraction, card views
├── Hints/         HintEngine, StarterQuestionBank
├── Home/          HomeView(+VM), AIService, SpilrVoice, LocalAI, SpillWriteView, templates
├── Journal/       JournalEntry, JournalService, editor, list, cards, RollupService, photos
├── Memory/        MemoryProfile(+Service)
├── Mirror/        MirrorView, SelfModel(+View/Service), Person Model, DerivedService,
│                  MirrorFacts/Score, AskView, FirstSketchView, WeeklyLetterView
├── Notifications/ PushNotificationManager
├── Onboarding/    OnboardingView + steps
├── Pattern/       PatternDetectionService (crisis-corpus safety gate only; callback engine cut)
└── Theme/         AppTheme (all colours/fonts), ThemeManager, ThemePickerView
functions/         Firebase Cloud Functions: geminiProxy + nightly reflection jobs
```

---

## Firestore

Per-user data lives under `users/{userId}/…` (entries, echoes, derived facts,
observations, readings, personModel, selfModel, chatSessions, and more — the full
list is `FirestoreSchema.userSubcollections`). Security rules grant the owner
**read** recursively but enumerate **writes**: server-owned collections
(`derived`, `observations`, `readings`, `personModel`, hypotheses) are Admin-SDK
truth and only accept narrow client feedback updates (see `firestore.rules`).
Account deletion runs server-side in the `deleteAccount` Cloud Function.

Composite indexes are in `firestore.indexes.json`.

---

## Conventions

See **CLAUDE.md** for the full working rules. In short: ViewModels are
`@MainActor final class … ObservableObject`; views pass callbacks rather than
calling services; all Firestore writes are fire-and-forget; background work uses
`Task.detached`; all colours/fonts come from `AppTheme.swift`.

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files
dropped into a group folder are picked up automatically, no `.pbxproj` edits.
