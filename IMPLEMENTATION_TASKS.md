# Spilr — Implementation Task Plan

**Source:** `Spilr_Product_AI_Strategy.pdf` (Aug 2026 teardown), cross-checked line-by-line against the shipping SwiftUI + Firebase codebase (107 app-source Swift files + `functions/index.js`).
**Scope of this plan:** everything the strategy recommends for the **existing code**, broken into actionable tasks. **Thought Drop / Thought Journal is explicitly excluded** here (tracked separately in `thoughtjournalprd.md`). Net-new capture surfaces (widgets, Watch, App Intents) are included but quarantined into later phases and clearly marked as net-new.
**How to read effort:** XS ≈ hours · S ≈ 1–2 days · M ≈ 3–8 days · L ≈ 2–4 weeks.

---

## 0 · Verified ground truth (audit confirmation)

Before planning, I re-verified the PDF's claims against the actual code. All of them hold. This table is the factual base every task below rests on.

| Claim in strategy | Verified? | Evidence in code |
|---|---|---|
| `analyzeEntry` (Prompt A) has **zero callers** | ✅ Confirmed | Defined at `Mirror/AIService+Mirror.swift:19`; no call site anywhere in the app source. |
| Save paths fire echo + river + per-entry insights but **not** analysis | ✅ Confirmed | `Journal/JournalEditorViewModel.swift:113` (`save`) fires `generateInsights`, `EchoExtractionService.extractAndStore`, `RiverService().generateMark` — no `analyzeEntry`. Same in `Home/NinetySecondSessionView.swift:633` and `Chat/DailyChatView.swift:141`. |
| Mirror engine is built but **inert** (17 files) | ✅ Confirmed | `Mirror/` has 17 files. `AIService+Mirror.swift` implements Prompt A (`analyzeEntry`), B (`minePatternHypotheses:117`), D (`generateMirrorCard:63`), E (`guardMirrorCard:136`) — all client-side, all starve with no `EntryAnalysis` input. |
| `SelfModelService` is **CRUD-only, never fed** | ✅ Confirmed | Callers are only `MirrorView` (load) and `SelfModelView` (`markHypothesis`/`hideHypothesis`/`submitCorrection`). Nothing ever writes a populated Self-Model. |
| Mirror tab attempts client-side mining/card-gen on open, and starves | ✅ Confirmed | `MirrorView.swift:load()` calls `runMiningIfNeeded` + `loadOrGenerateMirrorCard` over `loadRecentAnalyses(limit:14)` — which returns nothing because no analyses exist. |
| Mood log **built but unreachable** | ✅ Confirmed | `Mood/MoodBlobView.swift:70` is defined but **never instantiated** (`MoodBlobView(` appears nowhere). `MoodLogService` is referenced in `HomeView.swift:43` / `PatternsView.swift:17` but no check-in UI is surfaced. |
| Chat opener is **static, 5 lines, cycles every 5 days** | ✅ Confirmed | `Chat/AIService+Chat.swift:56` hardcoded `openers` array, indexed `day % openers.count` (line 64). |
| Chat "readiness" is a **turn count**, weave offered too early | ✅ Confirmed | `readyToWeave = userTurns >= 3` (`AIService+Chat.swift:131`); but `canWeave = readyToWeave || userTurnCount >= 1` (`DailyChatView.swift:45`). Weave throws `textTooShort` under 12 words (`AIService+Chat.swift:162`) and the caller falls back to a raw transcript stitch. |
| Chat has **no streaming**; reveal is theatre | ✅ Confirmed | `DailyChatView.swift:87-109`: the network call is not streamed; a client-side per-word reveal (~0.7s artificial delay) runs over already-received text. |
| Chat transcript is **discarded**, no cross-session memory | ✅ Confirmed | No persistence of chat summaries; each session rebuilds from a fresh opener. `MemoryProfile` exists but is not used to seed the opener. |
| Only **two** Cloud Functions exist | ✅ Confirmed | `functions/index.js`: `geminiProxy` (`:30`, on-demand proxy) and `generateDailyReads` (`:383`, nightly `onSchedule`). No mining / Self-Model / counter-evidence jobs. |
| Notification permission requested **cold**, before first entry | ✅ Confirmed | `Home/HomeView.swift:298` calls `PushNotificationManager.shared.requestAuthorization()` inside the Home `.task` on load. |
| Nightly read runs on a **fixed UTC cron** (wrong local hour) | ✅ Confirmed | `functions/index.js:383` `schedule: "0 5 * * *"`, `timeZone: "Etc/UTC"`, with an inline `NOTE` that per-user timezone is unimplemented. |
| **`ninety` → `Spilr` naming drift** in shipping code | ✅ Confirmed | 34 files reference `ninety`/`Ninety` (87 occurrences) vs 73 `Spilr` references. Some are legitimate type names (`NinetySecondSessionView`, `NinetyVoice`); many are user-facing copy. |
| Legacy pattern callbacks are a **separate, older system** from Mirror | ✅ Confirmed | `PatternCallback` / `PatternDetectionService` / `PatternCallbackService` wired into `HomeView.swift:35/44/45`, `River/NoticedView.swift`, `Memory/MemoryProfileService.swift:25` — parallel to the richer `Mirror/` engine. |

**Bottom line the audit is right about:** this is not an early MVP. It is a mature app whose single most differentiated system (Mirror / Self-Model) is one wiring call away from switching on, and whose "between-sessions" surfaces (ambient capture, smart nudges, a chat that remembers) barely exist.

---

## 1 · Do I need a backend? Database? — direct answers

**Do I need a backend?** **Yes — but only more of the backend you already have, not a new one.** The in-the-moment work (per-entry reflection, chat turns, daily card render) should stay local-first on device exactly as it is. The *cross-time* cognition — hypothesis mining (Prompt B), the Self-Model updater (SM-1), counter-evidence and blind-spot passes — must move into **scheduled Cloud Functions**, for four reasons the audit is right about: (1) it can reason over the full corpus, not just the last 14 entries the client loads; (2) it runs once per user per night instead of burning tokens on every Mirror-tab visit; (3) it produces consistent output; (4) it keeps heavy latency off the device. You already have the exact pattern to clone: `generateDailyReads` is a clean, idempotent, two-stage nightly job.

**Do I need a new database?** **No.** Firestore is sufficient and already holds the right shape. No new datastore, no relational DB, no vector DB required for any task in this plan.

**Do I need to change Firestore security rules?** **No.** `firestore.rules` is already a recursive, owner-scoped rule (`match /users/{userId}/{document=**}`), and the Admin SDK used by Cloud Functions bypasses rules entirely. New per-user subcollections are already permitted — the team already fixed the earlier "missing permissions" bug that starved the AI.

**Do I need new database indexes?** **Yes, a few.** `firestore.indexes.json` currently defines only `echoes` and `entries` composite indexes. New nightly queries will need composite indexes — at minimum:
- `entryAnalyses` by `(userId implicit)` + `createdAt` (mining reads recent analyses in order).
- `patternHypotheses` by `salienceScore DESC` (already read "top-20 by salienceScore" in `MirrorGraphService`; a single-field descending index or composite may be required at scale).
- Any collectionGroup query the nightly job runs across users.

**Privacy invariant that constrains the backend design (non-negotiable, from `privacyprd.md`):** nightly functions must mine **structured `EntryAnalysis` only — never raw decrypted entry text server-side**, and must persist **chat summaries, not transcripts**. The Self-Model must remain separately deletable. This is a selling point; design the jobs to honour it from day one.

### New Firestore collections this plan introduces
| Collection (under `users/{uid}/`) | Written by | Read by | Notes |
|---|---|---|---|
| `entryAnalyses/{entryId}` | **NEW:** `analyzeEntry` on every save (Phase 0) | nightly mining, Mirror | Structured signal (emotions, episodes, protective moves, open loops). Already modelled by `EntryAnalysis` / `EpisodeFrame`. |
| `patternHypotheses/{id}` | **Move to** nightly mining fn (Phase 1); today attempted client-side | Mirror, Self-Model | Schema exists (`Pattern/PatternHypothesis.swift`) incl. `counterEvidence`. |
| `selfModel/{doc}` | **NEW:** nightly SM-1 updater (Phase 1) | Mirror, chat opener, NBQ | Today read by `SelfModelService` but never populated. |
| `chatSummaries/{sessionId}` (or fold into `entryAnalyses`) | **NEW:** end-of-chat distiller (Phase 1) | next chat opener | Structured summary only — open loops, what shifted, one follow-up. **No raw transcript.** |

---

## 2 · Phased task breakdown

Sequenced by leverage. **Phase 0 is deliberately small and disproportionately valuable** — it converts already-built work into felt product. Each task lists the files to touch (verified), effort, dependencies, whether it needs backend, and acceptance criteria.

### PHASE 0 — "Switch on what's built" (0–4 weeks)

Goal: turn dormant code into live product with minimal new code. No new surfaces.

---

#### T0.1 — Wire `analyzeEntry` into every save path ⭐ highest ROI in the codebase
- **What:** Call `analyzeEntry(entryId:userId:text:)` as a detached background task in all three save paths, exactly as echo/river generation is already wired. Persist the result to `users/{uid}/entryAnalyses/{entryId}`.
- **Why:** This one missing call starves the entire Mirror/Self-Model chain: no `EntryAnalysis` → no hypothesis mining (needs ≥3 analyses) → no Mirror card → no Self-Model → "First Sketch" never unlocks. It converts ~17 dormant files and 5 written prompts into a live product.
- **Files:** `Journal/JournalEditorViewModel.swift:113` (free write), `Home/NinetySecondSessionView.swift:633` (90-second), `Chat/DailyChatView.swift:141` (chat weave). Reuse `Mirror/AIService+Mirror.swift:19`. Add a persistence method (mirror `RiverService.generateMark`'s fire-and-forget shape).
- **Backend?** No — device-side detached task, same as today's enrichment. (Backend comes in Phase 1 to move the *heavy* mining off-device.)
- **Effort:** XS (a few lines per save path + one persistence helper).
- **Depends on:** nothing. **Do this first.**
- **Acceptance:** After saving any entry, a document appears at `entryAnalyses/{entryId}` within seconds; saving 3+ entries makes `loadRecentAnalyses` return data and the Mirror tab begins forming hypotheses instead of placeholders.
- **PRD to update:** `mirrorprd.md`, `profileintelligenceprd.md`.

#### T0.2 — Make the mood log reachable on Home
- **What:** Surface the one-tap mood/energy check-in on Home by instantiating `MoodBlobView` (currently never rendered) and wiring it to the existing `MoodLogService` (one-doc-per-day).
- **Why:** First real "small log," instantly — a genuine bug-fix win. `MoodBlobView` and the one-tap service already exist; they're just never shown. Establishes credibility that "small logs" work ahead of the deeper micro-capture work.
- **Files:** `Mood/MoodBlobView.swift:70` (the unused view), `Mood/MoodLogService.swift`, `Home/HomeView.swift` (already holds `moodService` at line 43 — add the surface).
- **Backend?** No.
- **Effort:** XS.
- **Depends on:** nothing (independent of T0.1).
- **Acceptance:** A mood/energy tap is visible on Home, writes one `moodLogs` doc/day, and reflects the already-logged state on return.
- **PRD to update:** `journalprd.md` (or a new `moodprd.md` if you want mood tracked as its own feature).

#### T0.3 — Fix nudge timing + timezone; move the permission ask to post-first-entry
- **What:** Two changes: (a) move `requestAuthorization()` out of the cold Home `.task` to fire **after the user's first entry is written**; (b) fix the fixed-UTC scheduling so the daily read/nudge lands at a sensible local hour (per-user timezone), and add the first journaling reminders (learned from the user's own entry timestamps).
- **Why:** Cheapest retention available, and a materially better opt-in rate. Today permission is requested cold on first Home load (`HomeView.swift:298`) before the user has any reason to say yes, and the only push is a fixed `0 5 * * *` UTC cron (`functions/index.js:383`) that lands at the wrong local hour for most users.
- **Files:** `Home/HomeView.swift:298`, `Notifications/PushNotificationManager.swift:48`, `functions/index.js:383` (`generateDailyReads` schedule/`local_date`).
- **Backend?** Partial — the timezone fix touches the nightly function; storing a per-user timezone/quiet-hours field is a small Firestore addition.
- **Effort:** S.
- **Depends on:** nothing.
- **Acceptance:** Permission prompt only appears after entry #1; a test user in a non-UTC timezone receives their read at the intended local hour; at least one learned journaling reminder fires.
- **PRD to update:** `todaysreadprd.md` (Timezone section it already flags), plus a notifications note.

#### T0.4 — Resolve the `ninety` → `Spilr` naming drift (user-facing copy)
- **What:** Rename user-facing strings and comments from "ninety" to "Spilr." **Do not** blindly rename type identifiers — `NinetySecondSessionView`, `NinetyVoice`, `NinetySecondSession` are legitimate symbols; renaming those is a separate, larger mechanical refactor (see §3).
- **Why:** A split-brain name quietly costs trust and App Store clarity.
- **Files:** 34 files contain `ninety`/`Ninety` (87 occurrences). Start with user-visible copy strings; leave symbol renames for the cleanup pass.
- **Backend?** No.
- **Effort:** XS for copy; the symbol rename is S–M and optional.
- **Depends on:** nothing.
- **Acceptance:** No user-visible "ninety" copy remains; a grep audit distinguishes remaining occurrences as intentional symbol names.

> **Excluded from Phase 0 by your instruction:** the "thought drop" one-line capture. The strategy lists it in this block, but it is the thought-journal primitive tracked in `thoughtjournalprd.md` and handled separately.

---

### PHASE 1 — "Make the intelligence real and felt" (1–3 months)

Goal: move heavy cognition to the backend, hold the quality bar, and make the intelligence *felt* through moments and a chat that remembers.

---

#### T1.1 — Nightly Cloud Functions: hypothesis mining (B), Self-Model updater (SM-1), counter-evidence pass
- **What:** Add scheduled Cloud Functions that run once nightly over each user's structured `entryAnalyses` (never raw text): mine `PatternHypothesis` records (Prompt B), update the Self-Model (SM-1), and run the counter-evidence pass. Clone the idempotent two-stage shape of `generateDailyReads`.
- **Why:** Full-corpus reasoning, cheaper (one run/user/night vs. per-tab), and consistent. The PRDs already assume server-side nightly jobs; the code just never got them.
- **Files:** `functions/index.js` (new `onSchedule` exports beside `generateDailyReads:383`). Port the prompt logic from `Mirror/AIService+Mirror.swift` (`minePatternHypotheses:117`, guard `:136`) to server JS. New indexes in `firestore.indexes.json`.
- **Backend?** **Yes — this is the backend task.** New nightly functions + indexes. No new datastore.
- **Effort:** L.
- **Depends on:** **T0.1** (needs `entryAnalyses` flowing).
- **Acceptance:** Overnight, a user with ≥3 analyses gets fresh `patternHypotheses` and a populated `selfModel`; a second run is idempotent (no duplicates/overwrites of same-day output).
- **PRD to update:** `profileintelligenceprd.md`, `mirrorprd.md`, `patternsprd.md`.

#### T1.2 — Move client-side mining/card-writing off the device (deprecate the on-tab-open heavy path)
- **What:** Once T1.1 runs, retire the client-side `runMiningIfNeeded` / `loadOrGenerateMirrorCard` heavy path in `MirrorView.load()`. The Mirror tab should **read** server-produced hypotheses/cards, not generate them on open. Keep the local card *render* and per-entry reflection on device.
- **Why:** The current on-open generation is slow, token-burning, corpus-limited, and fragile. This is a deprecation, not a rewrite.
- **Files:** `Mirror/MirrorView.swift:load()`, `Mirror/MirrorGraphService.swift`, `Mirror/AIService+Mirror.swift` (`minePatternHypotheses`, `generateMirrorCard`, `guardMirrorCard` become server-side; keep client parse/read).
- **Backend?** Yes (consumes T1.1 output).
- **Effort:** M.
- **Depends on:** **T1.1.**
- **Acceptance:** Opening Mirror makes no generation LLM calls; it renders server output instantly; token spend per tab-open drops to ~0.

#### T1.3 — Hold the quality bar (counter-evidence, exception-first, hedged language, one-at-a-time, correctable)
- **What:** Ship the differentiation the PRDs already specify: every surfaced claim carries 2–3 verbatim receipts **and** ≥1 counter-example; make exception hypotheses top-priority; keep the deterministic banned-phrase lint (no identity/clinical language); enforce "one Mirror card per day, never a list"; surface "This is me / Almost / Not me / Too intense" and make corrections outrank inference (rule PI-010).
- **Why:** This is why an insight feels like a good therapist instead of a horoscope — and the corrected labels are the labelled-data moat.
- **Files:** counter-evidence pass in T1.1's functions; lint + correction handling in `Mirror/SelfModelView.swift` (`submitCorrection` already exists) and `Pattern/PatternHypothesis.swift` (`counterEvidence` field already exists). `MirrorScore.swift` for exception-first prioritisation.
- **Backend?** Yes (counter-evidence runs server-side); client enforces lint + correction UI.
- **Effort:** M.
- **Depends on:** **T1.1.**
- **Acceptance:** No surfaced hypothesis lacks receipts + a counter-example; a banned phrase never ships; a user correction visibly outranks inferred claims on the next render.

#### T1.4 — Ship the First Sketch ceremony + weekly pattern digest
- **What:** At ~7 entries, deliver the First Sketch as a genuine ceremony (the first evidence-backed reflection of the person to themselves). Add a once-weekly digest: one recognized pattern with receipts, one exception, one question to carry.
- **Why:** First Sketch is the "wow" that converts a curious downloader into a believer; the weekly digest is the between-sessions cadence and a natural Sunday-evening ritual + share moment.
- **Files:** `Mirror/FirstSketchView.swift` (exists; needs the engine on + ceremony polish), `Mirror/MirrorMaturity.swift` (gates 1/3/7/14/30/90), weekly digest render + a scheduled trigger.
- **Backend?** Yes for digest generation/scheduling; client for the ceremony.
- **Effort:** M.
- **Depends on:** **T0.1 + T1.1.**
- **Acceptance:** A 7-entry test user hits the First Sketch ceremony; a weekly digest arrives with exactly one pattern + one exception + one question.
- **PRD to update:** `mirrorprd.md`, `patternsprd.md`.

#### T1.5 — Chat: personalized opener + privacy-safe rolling memory + readiness/weave fix
- **What:** Three linked upgrades. (a) Generate the opener from `MemoryProfile` + today's mood log + most recent open loop, with the static five as an offline floor. (b) At end of each chat, distil a short **structured summary** (open loops, what shifted, one follow-up) into the `EntryAnalysis`/Self-Model store — **not** the transcript — and feed it into the next session. (c) Gate readiness on emotional material rather than turn count, make the ≥12-word floor gate the weave *button* (not fail after it), and when a chat is thin, escalate with one more good question instead of a premature passthrough weave.
- **Why:** Turns the chat from a clever, forgetful text box into continuity of care ("last time you were dreading Monday's call — how did it go?"), while respecting the "woven narrative only" privacy decision.
- **Files:** `Chat/AIService+Chat.swift` (openers `:56`, readiness `:131`, weave floor `:162`), `Chat/DailyChatView.swift` (`canWeave:45`), `Memory/MemoryProfileService.swift`.
- **Backend?** Mostly device-side; the rolling summary persists to Firestore (structured only).
- **Effort:** M.
- **Depends on:** **T0.1** (shared analysis store); opener personalization benefits from **T1.1** but doesn't strictly require it.
- **Acceptance:** Opener references something the user actually said; the next session recalls a prior open loop; the weave button never appears before there's enough to weave, and never silently returns raw text mislabeled as "woven."
- **PRD to update:** `dailychatprd.md`, `memoryprd.md`, `privacyprd.md`.

#### T1.6 — Route micro-logs through the `EntryAnalysis` / `EpisodeFrame` pipeline
- **What:** Treat each micro-capture (mood tap, energy check) as a **one-episode analysis** flowing through the same `EntryAnalysis`/`EpisodeFrame` structure as full entries — not a separate analytics silo. A 7am "wired, couldn't sleep" and a 3pm "calmer after a walk" become two episodes on the same day.
- **Why:** This is what lets the engine notice things a human wouldn't ("mornings run tense, soften by mid-afternoon on days you move"). Time-of-day rhythm (`timeRhythm`) is already a defined pattern type; ambient logs make it real.
- **Files:** `Mood/MoodLogService.swift`, `Mirror/EpisodeFrame.swift`, `Mirror/EntryAnalysis.swift`, the mining function from T1.1.
- **Backend?** Yes (mining reads the episodes).
- **Effort:** M.
- **Depends on:** **T0.1 + T0.2 + T1.1.**
- **Acceptance:** Two mood logs on one day produce two episodes; a `timeRhythm` hypothesis can form from ambient logs alone.

#### T1.7 — Home + lock-screen widgets; actionable "reply from lock screen" *(net-new surface, but low-effort and high-leverage)*
- **What:** WidgetKit home/lock-screen widgets for a mood tap; make the daily-read notification actionable so a person can reply from the lock screen (your own PRD lists this as deferred).
- **Why:** Ambient capture → frequency → better patterns. This is the difference between "I'll journal later" (never) and a tap at a red light. Zero widgets exist today.
- **Files:** new WidgetKit target; `Notifications/PushNotificationManager.swift` for actionable categories; `functions/index.js` payload for the reply action.
- **Backend?** Minor (notification payload/handling).
- **Effort:** M.
- **Depends on:** **T0.2** (mood surface), **T0.3** (notification hygiene).
- **Note:** This is a **net-new surface**, included here because it directly fuels Pillar 1's data supply.

---

### PHASE 2 — "Compound the moat" (3–6 months) — mostly net-new surfaces

Goal: maximise capture frequency, ground nudges in the user's own words, and put depth behind premium.

| Task | What | Net-new? | Effort | Depends on |
|---|---|---|---|---|
| **T2.1 — NBQ engine** | Pattern-aware personalized prompts & nudges grounded in the user's own words ("yesterday you wrote 'reset' again — reset day or rest day?") | Extends existing | M | Self-Model live (T1.1) |
| **T2.2 — Apple Watch complication + App Intents / Siri Shortcuts** | Highest-frequency, lowest-friction capture ("Hey Siri, tell Spilr I'm wired"; a wrist tap for energy) | **Net-new** | L | T0.2, T1.6 |
| **T2.3 — Voice-first "talk it out" mode + streaming** | True voice-first chat; stream tokens as they arrive instead of the artificial reveal delay. Dictation is already wired (`SpeechManager`). | Extends existing | M | T1.5 |
| **T2.4 — Premium tier** | Full Self-Model + evidence drawer, weekly/monthly Mirror digests, blind-spot cards, unlimited pattern history, voice mode. Keep capture + daily read + basic reflection free forever. | Net-new (billing) | M | T1.1–T1.5 |
| **T2.5 — Monthly / 90-entry milestone Mirror** | Deeper-insight formula applied across the whole person, always ending in a question. | Extends existing | M | T1.1 |

---

## 3 · Cleanup, deprecation & removal

Grouped by risk. **Nothing here should be deleted before its replacement is live** — most of this is "deprecate after," not "delete now." A `git grep` audit should accompany each.

### 3A · Deprecate (remove *after* the replacement ships)

| Item | Current state | Action | Trigger to remove | Risk |
|---|---|---|---|---|
| **Client-side heavy Mirror path** — `runMiningIfNeeded`, `loadOrGenerateMirrorCard` in `MirrorView.load()`; server-eligible prompts `minePatternHypotheses`/`generateMirrorCard`/`guardMirrorCard` in `AIService+Mirror.swift` | Attempted on every Mirror-tab open; starves and burns tokens | Move generation server-side (T1.1), make the tab read-only for hypotheses/cards (T1.2) | After T1.1 nightly jobs verified in production | Medium — keep local *render* + per-entry reflection on device |
| **Static chat openers** — `AIService+Chat.swift:56` hardcoded array + `day % count` | Same 5 lines for every user, cycling every 5 days | Replace with memory-grounded opener; keep the 5 as the offline floor only (T1.5) | After T1.5 | Low |
| **Turn-count "readiness"** — `readyToWeave = userTurns >= 3` (`:131`) and `canWeave = … || userTurnCount >= 1` (`DailyChatView.swift:45`) | Offers weave after a single reply; silent raw-text passthrough | Gate on emotional material + ≥12-word floor on the button (T1.5) | After T1.5 | Low |
| **Artificial chat reveal delay** — `DailyChatView.swift:90-109` (~0.7s client-side per-word reveal over already-received text) | Adds latency theatre on top of real latency; not streaming | Replace with real token streaming (T2.3) | After T2.3 | Low |

### 3B · Consolidate (resolve duplication — decision required)

**Legacy pattern-callback system vs. the Mirror engine.** There are two parallel "pattern" systems: the older client-side `PatternCallback` / `PatternDetectionService` / `PatternCallbackService` (wired into `HomeView.swift:35/44/45`, `River/NoticedView.swift`, `Memory/MemoryProfileService.swift:25`) and the richer `Mirror/` engine. Running both indefinitely is confusing and doubles the surface area for safety and copy bugs.
- **Recommendation:** keep legacy callbacks as the working fallback **until** the Mirror engine is live and quality-gated (through T1.3), then migrate `Home` and `River/NoticedView` to consume Mirror hypotheses and retire `PatternDetectionService` / `PatternCallbackService`. **Preserve the dual safety gate** (`PatternSafety.corpusHasCrisisSignal` + model `safety_flag`) in whichever system survives — this is table stakes and must not be weakened by the refactor.
- **Trigger to remove legacy:** Mirror hypotheses shipping with receipts + counter-evidence and passing the safety gate in production.
- **Effort:** M. **Risk:** Medium (safety-adjacent — do it carefully, behind a flag).

### 3C · Wire, don't remove (dormant but wanted)

- **`Mood/MoodBlobView.swift`** — never instantiated, but the plan *wants* it surfaced (T0.2). Wire, don't delete.
- **`Mirror/SelfModelService.swift`** — CRUD-only and unfed, but it's the read side of the Self-Model; feed it from T1.1 rather than removing it.

### 3D · Symbol / naming refactor (optional, mechanical)

- `ninety`/`Ninety` appears in 34 files (87 occurrences). Phase 0 (T0.4) handles **user-facing copy** only. The remaining **type identifiers** — `NinetySecondSessionView`, `NinetyVoice`, `NinetySecondSession` — are a separate mechanical rename (Xcode "Rename" refactor, one symbol at a time, compile between each). **Effort:** S–M. **Do this in a dedicated PR** so the diff is reviewable and doesn't hide behind feature work.

### 3E · Repo hygiene (not shipped code — low risk)

The project root carries prototyping artifacts and overlapping planning docs that predate the current PRD set and can confuse a new contributor:
- **Static HTML prototypes:** `preview.html`, `patterns_preview.html`, `echoes_memories_preview.html`. Move to a `docs/prototypes/` folder or delete if superseded.
- **Overlapping planning docs:** `MIRROR_IMPLEMENTATION_PLAN.md`, `NINETY_River_and_Gap_Analysis.md`, `PROJECT_SUMMARY.md`, `INDEX.md`, `QUICKSTART.md`, `SETUP.md` — reconcile against the 13 canonical PRDs and `README.md`; archive the stale ones. **Risk:** none (docs only). Keep the PRDs — `CLAUDE.md` mandates they stay current.
- `.firebaserc.bak` — stray backup; delete.

---

## 4 · Sequencing & dependency graph

```
T0.1 analyzeEntry wiring ─┬─────────────────────────────────────────► (unlocks everything AI)
                          │
T0.2 mood log reachable ──┼──► T1.6 micro-logs → episodes
                          │
T0.3 nudge timing/tz ─────┼──► T1.7 widgets / actionable reply
                          │
T0.4 naming (copy) ───────┘

T0.1 ─► T1.1 nightly CFs (mining B / SM-1 / counter-evidence)
             │
             ├─► T1.2 deprecate client-side heavy path
             ├─► T1.3 quality bar (counter-evidence, lint, corrections)
             ├─► T1.4 First Sketch + weekly digest
             └─► T1.6 micro-logs → episodes

T0.1 ─► T1.5 chat (opener + rolling memory + readiness fix)

Phase 2 (T2.*) depends on T1.1–T1.5 being live.
```

**Critical path:** `T0.1 → T1.1 → {T1.2, T1.3, T1.4}`. T0.1 is XS and unblocks the entire moat, so it should merge in week 1.

---

## 5 · Risks, guardrails & success metrics (carry-over from the strategy)

**Guardrails to hold through every task:**
- **No horoscope effect:** never surface an insight without the user's own words as receipts + a counter-example; keep the deterministic banned-phrase lint (no identity/clinical language).
- **Safety is table stakes:** keep the dual gate (deterministic crisis filter *before* any LLM call + a temp-0.0 guard *after*). A refactor must not weaken it. Never claim to replace therapy.
- **Privacy = product:** mine structured `EntryAnalysis` server-side, never raw text; persist chat *summaries*, not transcripts; keep the Self-Model separately deletable.
- **One thing at a time on the output side**, even as input surfaces multiply. "Eager to receive, sparing to speak."
- **Cost:** nightly batch beats per-tab calls; keep local-first fallbacks for everything so the app is fully usable — and cheap — with zero API calls.

**Metrics that tell you it's working:**
- **Activation:** % of new users reaching the 7-entry First Sketch, and ceremony completion rate (target > 70%).
- **Insight resonance:** "This is me" + "Almost" as a share of Mirror feedback (target > 65%); evidence-drawer open rate (> 25%).
- **Capture frequency:** micro-captures per active day (leading indicator for pattern quality).
- **Correction rate:** % of users who ever teach the model (the bond & moat signal).
- **Return without streaks:** D7 / D30 retention; "bridge" return rate after a gap.
- **Chat depth:** median turns/session & weave-completion rate after the readiness fix.

---

## 6 · Decisions I need from you

1. **Legacy pattern system (§3B):** confirm the "keep as fallback, then migrate to Mirror" plan vs. running both permanently. This is the one real architectural fork.
2. **Timezone storage (T0.3):** OK to add a per-user `timezone` field written on app launch, so the nightly function schedules per local hour?
3. **Chat summary location (T1.5):** fold the rolling chat summary into `entryAnalyses`, or give it its own `chatSummaries` collection? (Both honour "no transcript.")
4. **Naming refactor (T0.4 / §3D):** do you want the full symbol rename (`NinetyVoice` → `SpilrVoice`, etc.) now, or copy-only now and symbols later?
5. **Premium (T2.4):** is monetization in scope for this cycle, or plan-only for now?

---

*Grounded in a full audit of the shipping SwiftUI + Firebase codebase (107 app-source files + `functions/index.js`) and the 13 feature PRDs, cross-checked against `Spilr_Product_AI_Strategy.pdf` (Aug 2026). Thought Drop / Thought Journal is excluded per instruction and tracked in `thoughtjournalprd.md`.*

