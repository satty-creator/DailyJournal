# CLAUDE.md — DailyJournal Project Instructions

This file tells Claude how to work in this codebase.

---

## PRD maintenance rule (mandatory)

**Every time you add a new feature or edit an existing one, you must add or update the corresponding PRD file before considering the task done.**

The PRDs live at the root of the project:

| Feature | PRD file |
|---|---|
| Echoes (AI callbacks from past entries) | `echoesprd.md` |
| Hints / Hint Ladder / Pebble Picker | `hintsprd.md` |
| Today's Read (daily hook + receipts + feedback engine) | `todaysreadprd.md` |
| Journal (list, filters, sorting, streak, topical tags + sentiment) | `journalprd.md` |

When you add a feature that doesn't have a PRD yet, create one at the project root named `{featurename}prd.md` and add it to the table above.

### What counts as "edit an existing feature"

- Changing a data model field, enum value, or Firestore schema
- Changing an AI prompt (rules, temperature, token budget, JSON schema)
- Changing a surfacing threshold, timer, or delay value
- Adding or removing UI elements, copy, or user-facing actions
- Adding a new service method or changing an existing one's behaviour
- Changing any logic that is described in a PRD

When in doubt: if a PRD section describes the thing you changed, update that section.

---

## Project overview

**ninety** — a private iOS journaling app. SwiftUI, Firebase (Firestore + Auth + Cloud Functions), Gemini 2.0 Flash via a server-side proxy.

Key design principles:
- Local-first: every feature works offline or without AI; AI enriches silently.
- Fire-and-forget writes: the UI never waits on Firestore saves.
- One thing at a time: one Echo, one Pattern Callback, one hint — never lists.
- AI never blocks the user: all LLM calls run detached, fail silently, degrade to local fallbacks.

---

## Project structure

```
DailyJournal/
├── App/            DailyJournalApp.swift, RootView.swift
├── Auth/           Auth flow (email/Google/Apple sign-in)
├── Components/     Shared UI (SpeechManager, MascotView, FlowLayout, …)
├── Echo/           Echo data model, EchoService, EchoExtractionService, card views
├── Hints/          HintLadder, HintEngine, AIService+Hints, PebblePickerView
├── Home/           HomeView, HomeViewModel, AIService, NinetyVoice, LocalAI, NinetySecondSessionView
├── Journal/        JournalEntry, JournalService, editor, list, card views
├── Memory/         MemoryProfile, MemoryProfileService
├── Mood/           MoodLog, MoodLogService, MoodBlobView
├── Pattern/        PatternCallback, PatternDetectionService, PatternCallbackService, card views
├── Patterns/       PatternsView (tab), WeeklyWrappedCard
├── River/          River, RiverMark, RiverService, AIService+River, RiverView
├── Theme/          AppTheme.swift (all colours, fonts, markers)
functions/          Firebase Cloud Functions (geminiProxy)
```

---

## AI layer

- **Backend:** Gemini 2.0 Flash via `geminiProxy` Cloud Function at `us-central1-dailyjournal-12a35.cloudfunctions.net/geminiProxy`.
- **Auth:** Firebase ID token in `Authorization: Bearer {token}` header — no API key in the app.
- **Available when:** `AIService.shared.isAIAvailable` == `Auth.auth().currentUser != nil`.
- **All prompts** begin with `NinetyVoice.system` and end with `MemoryProfileService.shared.cachedPromptContext()`.
- **Local fallbacks** exist for every AI feature: `LocalAI`, `NinetyVoice.localReflection`, `NinetyVoice.localEchoLine`, `LocalRiver`, `LocalPatternDetector`.

---

## Safety

- Pattern detection has a hard safety gate: `PatternSafety.corpusHasCrisisSignal(_:)` runs before any LLM call. If it triggers, no callbacks are created and `HomeViewModel.showResourceCard` is set to `true`.
- The model also self-reports a `safety_flag` in the pattern detection response; this is checked in addition to the local gate.
- Echo extraction has no safety gate (single entry, low risk), but the confidence threshold (0.8) and conservative temperature (0.2) act as quality gates.

---

## Coding conventions

- ViewModels are `@MainActor final class … ObservableObject`.
- Views use callback closures rather than calling services directly — the ViewModel is the single source of truth for mutations.
- All Firestore writes are fire-and-forget (`setData` / `updateData` without `try await`).
- Background tasks use `Task.detached(priority: .background)` or `.utility`.
- No third-party networking SDK — plain `URLSession + JSONSerialization` for all AI calls.
- Themes: all colours and fonts come from `AppTheme.swift`. Never use hardcoded values.
