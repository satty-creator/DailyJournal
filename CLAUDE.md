# CLAUDE.md — DailyJournal Project Instructions

This file tells Claude how to work in this codebase.

---

## PRD maintenance rule (mandatory)

> **⏸️ PAUSED (2026-08-11):** PRD updates are temporarily **skipped**. Do NOT update or
> create PRD files when changing features for now — focus on the code changes only.
> Re-enable this rule when the pause note is removed.



The PRDs live at the root of the project:

| Feature | PRD file |
|---|---|
| Echoes (AI callbacks from past entries) | `echoesprd.md` |
| Hints / Hint Ladder | `hintsprd.md` |
| Today's Read (daily hook + receipts + feedback engine) | `todaysreadprd.md` |
| Journal (list, filters, sorting, streak, topical tags + sentiment) | `journalprd.md` |
| Patterns (resilience, activity grid, AI insight cards, mood/stats) | `patternsprd.md` |
| Themes (selectable vibes, ThemeManager, theme picker) | `themesprd.md` |
| Onboarding (vibe picker, 7-day promise, first-entry celebration, feedback) | `onboardingprd.md` |
| Memory layer (recurring themes, entities, emotional vocab, coping patterns) | `memoryprd.md` |
| Privacy & Trust (encryption, AI controls, export/delete) | `privacyprd.md` |
| Mirror (Today's Mirror, evidence drawer, seeds, blind spots, First Sketch, navigation) | `mirrorprd.md` |
| Profile Intelligence (Self Model, episodes, NBQ, corrections, First Sketch) | `profileintelligenceprd.md` |
| Daily Chat (interactive chat → woven journal entry, home entry point) | `dailychatprd.md` |
| Thought Journal (throughout-the-day thought capture, silent-by-default, bridges to Daily Chat + woven entries, feeds pattern engine) | `thoughtjournalprd.md` |

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

**ninety** — a private iOS journaling app. SwiftUI, Firebase (Firestore + Auth + Cloud Functions), Gemini 2.5 Flash Lite via a server-side proxy.

Key design principles:
- Local-first: writing, saving and browsing always work offline or without AI; AI enriches silently. Reflection is the exception — see "No local text in Spilr's voice" below.
- Fire-and-forget writes: the UI never waits on Firestore saves.
- One thing at a time: one Echo, one Pattern Callback, one hint — never lists.
- AI never blocks the user: all LLM calls run detached, fail silently, degrade to local fallbacks.

---

## Project structure

```
DailyJournal/
├── Analytics/      AnalyticsManager, SessionManager, ScreenTrackingModifier
├── App/            DailyJournalApp.swift, RootView.swift, AppRouter, FirestoreSchema
├── Auth/           Auth flow (email/Google/Apple sign-in), EntitlementService
├── Chat/           Daily Chat (ChatPrompts, ChatSession, AIService+Chat, DailyChatView)
├── Components/     Shared UI (SpeechManager, MascotView, FlowLayout, FutureSelfSheet, …)
├── Echo/           Echo data model, EchoService, EchoExtractionService, card views
├── Hints/          HintLadder, HintEngine, ReadService, AIService+Read, UniversalQuestionBank
├── Home/           HomeView, HomeViewModel (in HomeView.swift), AIService, SpilrVoice, LocalAI,
│                   TimedSessionViewModel, SpillWriteView
├── Journal/        JournalEntry, JournalService, editor, list, card views, RollupService
├── Memory/         MemoryProfile, MemoryProfileService
├── Mirror/         MirrorView (tab), SelfModel, PatternHypothesis-driven pattern surfacing,
│                   EvidenceDrawerView, FirstSketchView, SelfModelView
├── Notifications/  PushNotificationManager
├── Onboarding/     OnboardingView
├── Pattern/        PatternDetectionService (crisis-corpus safety gate only — the
│                   PatternCallback engine was cut, see PATTERNS_MERGE_PLAN.md)
├── Theme/          AppTheme.swift (all colours, fonts, markers), ThemeManager, ThemePickerView
functions/          Firebase Cloud Functions (geminiProxy)
```

---

## AI layer

- **Backend:** Gemini via `geminiProxy` Cloud Function at `us-central1-spilr-100f7.cloudfunctions.net/geminiProxy`. Model `gemini-3.5-flash-lite` (see `functions/index.js`). Project migrated from `dailyjournal-12a35` → `spilr-100f7`.
- **Auth:** Firebase ID token in `Authorization: Bearer {token}` header — no API key in the app.
- **Available when:** `AIService.shared.isAIAvailable` == `Auth.auth().currentUser != nil`.
- **All prompts** begin with `SpilrVoice.system` and end with `MemoryProfileService.shared.cachedPromptContext()`.
- **No local text in Spilr's voice.** Anything presented as an observation, insight, reflection or question must come from the model. When the call fails or AI is unavailable the surface renders *nothing* — an empty section is honest, a canned sentence is not. Do not add a heuristic template to "fill the gap": `SpilrVoice.localReflection` and `SpilrVoice.localEchoLine` were removed for exactly this reason. They shipped the same handful of sentences to every user, and because composers wrote them into the entry at save time they were indistinguishable from real insight everywhere downstream — on cards, in the editor, and on share cards.
  - Composers (`JournalEditorViewModel`, `TimedSessionViewModel`, `TemplateRunnerViewModel`, `DailyChatView`) leave `aiSummaryBullets` / `aiQuestion` unset. `EntryEnrichment` patches them in via `updateEntryInsights` when Gemini answers.
  - Consumers must degrade on their own: `JournalCardView` and `CollageTileView` fall back to `displayTitle`, `InsightShareCard` to an excerpt of the entry, and the editor's `aiSummarySection` is gated on non-empty.
  - An `extractEcho` result with no `line` is dropped rather than saved as a bare quote.
- **Local derivation is fine** — it's data, not voice. `LocalAI.detectSentiment` and `LocalAI.extractTopics` still run synchronously on every save to populate `sentimentLabel` and tags, which feed filters, cards and the pattern engine.
- **Surfaces already on screen need a listener, not a re-fetch.** Enrichment lands *after* a composer dismisses, so anything displaying a just-saved entry holds a stale value type. `JournalService.observeEntry` returns a live snapshot listener for this; `EntryInsightsObserver` (OnboardingView) is the reference use — placeholder while waiting, real bullets on arrival, nothing after a timeout.
- **Two carve-outs, both about data loss rather than fake voice:**
  - Daily Chat's turn-by-turn reply has no local fallback at all — a canned question in Spilr's mouth reads as a non-sequitur mid-conversation, so a failed turn surfaces an inline "couldn't reach Spilr" retry (`DailyChatViewModel.requestNextTurn`/`retryLastTurn`).
  - Its weave step *does* fall back locally (`AIService.localWeaveEntry`), because that fallback is a plain stitch of the user's own transcript — no invented voice — and the alternative is losing a finished conversation.
- **Every prompt must contain a safety block.** Two exist and they are not interchangeable:
  - `SpilrVoice.safetyRules` — for the **reflection** surfaces (Echo, River, Mirror, Reads, Patterns). Its rules 8 and 10 instruct the model to return an *empty result* when it can't produce something safe and grounded. Prompts built on `SpilrVoice.system` inherit it automatically.
  - `SpilrVoice.chatSafetyRules` — for **live conversation** (Daily Chat, plus its weave). Same prohibitions, but the fallback is "ask a plain question", not silence — in chat the user is waiting on a reply. Injected by `ChatPrompts.systemPrompt`.

  A prompt that uses neither must paste the appropriate one in explicitly. The server mirror is `SAFETY_RULES` in `functions/index.js`; keep it in sync with `safetyRules`.

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
