# Today's Read — Feature PRD

**Last updated:** 2026-06-09
**Status:** Core slice + share surface + push notifications shipped (models, local engine, card, Home wiring, overnight generator, share card, FCM push). Card simplified 2026-06-09: shown directly (no sealed/tap-to-reveal), no in-card feedback loop, "receipts" relabelled.

---

## What it is

Today's Read is the daily hook: a single, sharp, evidence-backed line ("tenderly brutal") generated from the user's own recent entries, surfaced once per day on Home. The read line is shown directly (the old "tap to reveal" sealed gate was removed — it only worked once per launch and added friction), alongside the evidence it's "drawn from your entries" (tiny word chips lifted from the user's actual words, formerly labelled "receipts") and a 90-second reply door.

It replaces the today's-prompt card as the primary daily vehicle. The plain prompt card is now only the fallback for brand-new users (no entries) or a held-back read. The River becomes the retrospective weekly reward rather than the daily hook.

The point: ninety has been reading. The Read proves it with one specific, grounded observation — never poetic fluff, therapy-speak, or horoscope generality.

---

## Product loop

Read line shown directly → evidence ("drawn from your entries") → reply door (90s).

> **Changed 2026-06-09:** the sealed "tap to reveal" gate and the in-card feedback row (felt true / too sharp / not me) were removed from the card UI for a calmer, friction-free surface. The feedback *engine* (`ReadSettings` / `ReadService` recalibration) and the server's feedback-derived tone preference are unchanged and still drive future reads; the card simply no longer renders the manual feedback affordances. "Receipts" is relabelled "drawn from your entries" for clarity.

---

## Data model

**File:** `DailyJournal/Hints/DailyReadModels.swift`

### ReadTone

The flavour the *generated* read lands in (a property of the read, chosen by the engine).

| Value | Raw |
|---|---|
| `.soft` | `soft` |
| `.direct` | `direct` |
| `.funny` | `funny` |
| `.spicy` | `spicy` |

### ReadSharpness

The user-facing "how hard should it hit?" dial. **Distinct from `ReadTone`.** `funny` is a flavour the engine reaches for opportunistically, but the sharpness LADDER the "too sharp" loop walks down is strictly `soft ↔ direct ↔ spicy` (per spec: "spicy → direct, or direct → soft"). The local engine maps this preference onto a tone. **As of 2026-06-09 the local engine no longer selects `funny`** (its lines read as loud/gimmicky); it stays observational — `.soft` → soft, `.direct` → direct, `.spicy` → mostly direct with occasional spicy. The `funny` `ReadLine`s remain defined for the server generator.

`ladder = [soft, direct, spicy]`; `.softer` steps one gentler, with `.soft` as the floor.

### ReadFeedback

`felt_true` · `not_me` · `too_sharp` · `more_like_this`.

### ReadRejectionCode ("not me" micro-menu)

`too_dramatic` · `wrong_topic` · `too_vague` · `close_but_not_quite`.

### ReadSafetyLevel

`none` · `mild_distress` · `high_distress`. Only `none` is surfaceable — client gate on top of the server guard.

### DailyRead fields

| Field | Type | Notes |
|---|---|---|
| `id` | String | Doc id == `localDate` key (`yyyy-MM-dd`) |
| `userId` | String | Firebase UID |
| `localDate` | Date | Start of the local day this read belongs to |
| `readText` | String | The line (one of six formulas) |
| `receiptChips` | [String] | 2–4 tokens lifted from the user's words |
| `replyPrompt` | String | Low-friction reply question |
| `shareSafeText` | String | Clean, context-free line for a share card |
| `notificationCopy` | String | Push body (≤ 45 chars); curiosity line, never the read. Default-safe |
| `tone` | ReadTone | Generated flavour |
| `sharpnessLevel` | ReadSharpness | Preference at generation time |
| `safetyLevel` | ReadSafetyLevel | `none` to surface |
| `confidence` | Double | 0–1 |
| `shouldShow` | Bool | False → Home falls back to prompt card |
| `doNotShowReason` | String? | Why a read was held back |
| `sourceEntryIds` | [String] | Tracing |
| `sourcePatternIds` | [String] | Tracing; rewarded on "felt true" |
| `sourceRiverMarkIds` | [String] | Tracing |
| `userFeedback` | ReadFeedback? | Set by feedback loop |
| `detailedFeedbackCode` | ReadRejectionCode? | Set by "not me" menu |
| `modelProvider` / `modelName` / `promptVersion` | String | Telemetry |
| `createdAt` | Date | Creation time |

---

## Firestore schema

Collection path: `users/{uid}/dailyReads/{localDate}` where `{localDate}` is `yyyy-MM-dd`.

One doc per user per local date — the doc id makes the per-user-per-day uniqueness constraint structural (mirrors the SQL `idx_user_date_active` unique index). Timestamps use `FirebaseFirestore.Timestamp`.

---

## The six structural formulas

All `read_text` must use exactly one of:

1. "You keep calling it X, but it sounds like Y."
2. "The problem is not X. It is Y."
3. "X is taking more space than it deserves."
4. "You are trying to X before Y."
5. "Your words say X. Your pattern says Y."
6. "Stop asking X. Ask Y."

## Tone matrix scenarios

The local engine carries the spec's three first-class scenarios — **Avoidance & Messaging**, **Over-Availability**, **Burnout & Rest** — each with a soft / direct / funny / spicy variant, plus a generic formula-driven floor.

---

## Local engine (fallback)

**File:** `DailyJournal/Hints/LocalReadEngine.swift`

Always-available, offline, never-throws. Reads coarse signals off the last 14 entries, detects the best-fit scenario, lifts receipt chips from the user's actual words/tags, and emits a read at the user's sharpness in one of the six formulas.

- Honours recent rejection codes: `too_vague` → most concrete formulas; `too_dramatic` → never the spiciest line; `wrong_topic` → deprioritises the strongest scenario.
- Returns `shouldShow == false` (with `doNotShowReason`) when there is too little signal (< 60 chars of corpus), so Home falls back to the prompt card.
- Local reads carry `confidence = 0.55`, `modelProvider = "local"`, `promptVersion = "local-read-v1"`.

---

## Feedback engine

**Files:** `DailyJournal/Hints/ReadSettings.swift`, `ReadService.swift`

On-device `UserDefaults` store, namespaced by user id (mirrors `PatternSettings`).

| Loop | Action | Recalibration |
|---|---|---|
| **felt true** | Card → `.replied`; CTA becomes "more like this" | `reward(patternIds:)` — +0.25 multiplier (cap 2.0) on each `sourcePatternId` |
| **too sharp** | Inline confirm "softening future reads" | `softenSharpness()` — steps `sharpnessPreference` one gradient gentler (spicy → direct → soft) |
| **not me** | Opens 4-option micro-menu | `recordRejection(readId:code:)` — appends to last-20 rejection history; codes feed the next local payload |

The local store recalibrates the local engine immediately; the overnight server pass reads the persisted feedback fields back off each read doc and derives `tone_preference` from them.

---

## ReadService

**File:** `DailyJournal/Hints/ReadService.swift`

| Method | Description |
|---|---|
| `fetchRead(for:date:)` | Cache-first read of `users/{uid}/dailyReads/{date}`; nil on miss |
| `todayRead(for:date:)` | Get-or-build: server read if surfaceable, else build a local read and persist it (fire-and-forget). Nil only when even local has nothing → prompt-card fallback |
| `save(_:)` | Fire-and-forget write |
| `recordFeedback(_:on:)` | Writes `userFeedback` + applies local recalibration |
| `recordRejection(_:on:)` | Writes `userFeedback = not_me` + `detailedFeedbackCode`, records to `ReadSettings` |

---

## UI

### TodayReadCardView

**File:** `DailyJournal/Home/TodayReadCardView.swift`

Calm, light card (2026-06-09 restyle — the old loud dark-`ink` / 25 pt bold-cream
treatment was toned down). `AppTheme.cream` surface with a hairline
`inkSoft` border and soft shadow. Shown directly — no sealed gate. Layout:

- "today's read" label (muted inkSoft) + share button (header).
- Read line: 22 pt **serif, regular weight**, `AppTheme.ink`, generous line
  spacing — readable and quiet rather than shouty.
- Evidence row labelled "drawn from your entries" (terracotta mono chips joined
  by " · ") — formerly "receipts".
- "reply in 90s" soft `rose2` capsule with ink text. After tapping, it swaps to
  a quiet inkSoft confirmation ("you took it to the page.").

The card's only outbound closure is `onReply`. The felt-true / too-sharp / not-me affordances and the sealed/revealed/replied state machine were removed (2026-06-09). `ReadRejectionCode` / `ReadFeedback` and the recalibration methods remain in the model/service layer for the server feedback loop.

### Home wiring

**File:** `DailyJournal/Home/HomeView.swift`

- `HomeViewModel.todayRead` is fetched once per session in `load()` (guarded by `if todayRead == nil`) so the sealed/revealed state and feedback survive pull-to-refresh.
- `promptCard` now renders `TodayReadCardView` when a read exists, else `fallbackPromptCard` (the original today's-prompt card).
- `onReply` opens the 90-second session directly via `NinetySecondSessionView` (`showingNinetySecond = true`). The separate `PebblePickerView` gating step was removed — pebbles are now chosen inline on the writing screen.
- Home also shows an always-visible "Write something" CTA (`writeCTASection`) independent of the read/prompt card, plus a "start with a hint" secondary that opens the 90-second session.
- The `vm.readFeltTrue()/readTooSharp()/readNotMe(_:)` methods remain on `HomeViewModel` for the server feedback loop but are no longer wired to the card UI.

---

## Overnight generation (Cloud Function)

**File:** `functions/index.js` → `generateDailyReads`

Scheduled `onSchedule` job, `0 5 * * *` UTC, region `us-central1`, secret `GEMINI_KEY`.

1. Iterate `users`. Skip a user if a read for today already exists (idempotent) or there are no substantial entries in the last 14 days.
2. Assemble an engine payload (entry summaries, previous reads, previous feedback, derived `tone_preference`).
3. **Stage 1 — generator** (`gemini-2.5-flash`, temp 0.8): produces the read against the six-formula contract and the output schema mirroring `DailyRead`.
4. Hold back if `should_show == false`, `safety_level != none`, or fewer than 2 receipt chips.
5. **Stage 2 — quality guard** (temp 0.0): scores specificity / grounding / sharp-but-kind / privacy / anti-spiral 1–5. Rejects unless `approved == true` **and every score ≥ 4**.
6. Write the approved read to `users/{uid}/dailyReads/{yyyy-MM-dd}`.

`PROMPT_VERSION = "read-gen-v1"`. Bump on any prompt/schema change.

### Timezone (known limitation)

`local_date` is currently derived from server (UTC) time. A future refinement should store a per-user timezone and key the doc on the user's local midnight so the read flips over at the right local hour.

---

## Share surface

**File:** `DailyJournal/Components/ReadShareCard.swift`

The viral loop. `ReadShareCard` is a 405×720 (9:16) dark gradient card for Instagram Stories / TikTok: a lowercase "today's read" eyebrow, the line in large editorial display, and a "✦ made with ninety / get your read" footer. `ShareReadButton` renders it to a `UIImage` via `ImageRenderer` and hands it to a SwiftUI `ShareLink` — same pattern as `ShareableInsightCard`.

**Privacy:** the card renders ONLY `read.shareSafeText`. It never shows receipt chips, source entries, mood, dates, or any private metadata — the share-safe line is a clean, de-contextualised restatement produced specifically for export.

**Surfacing:** `TodayReadCardView` shows the share button in its header once the card is no longer `.sealed` (revealed or replied). Never offered while sealed.

---

## Push notifications

Firebase Cloud Messaging (FCM) over APNs.

### Client

**Files:** `DailyJournal/Notifications/PushNotificationManager.swift`, `App/DailyJournalApp.swift`, `Home/HomeView.swift`

- `AppDelegate` (bridged via `@UIApplicationDelegateAdaptor`) forwards the APNs device token to `Messaging.messaging().apnsToken` and calls `PushNotificationManager.shared.configure()` on launch. `FirebaseApp.configure()` still runs in `DailyJournalApp.init` first.
- `PushNotificationManager` (`MessagingDelegate` + `UNUserNotificationCenterDelegate`) requests permission, registers for remote notifications, and persists the FCM token at `users/{uid}/pushTokens/{token}`. Foreground reads still present a banner.
- Permission is requested from `HomeView.task` (post-auth), so the token is always saved against a signed-in uid. iOS shows the system prompt only once.

### Server

**File:** `functions/index.js` → `sendReadPush(...)`, called from `generateDailyReads` right after a read is written.

- Reads every token in `users/{uid}/pushTokens`, sends via `admin.messaging().sendEachForMulticast`, and prunes tokens FCM reports as `registration-token-not-registered` / `invalid-argument`.
- Title is always `"ninety"`. Body is `read.notificationCopy`, chosen by `notificationCopyForTone(tone, modelCopy)`: the model's `notification_copy` if ≤ 45 chars, else the manifest mapping — soft → "One thing is ready.", funny/spicy → "You've been clocked, kindly.", default → "ninety has a read for you."
- **The read text is never in the payload** — the curiosity gap lives behind the sealed card. Delivery failure never fails the read write.

### Firestore rules

**File:** `firestore.rules` — added owner-only `match` blocks for both `dailyReads/{readId}` (the client reads + writes feedback / local fallbacks) and `pushTokens/{token}`. The Admin SDK in the function bypasses rules.

### One-time console / project setup (not code)

1. Upload an **APNs Auth Key (.p8)** to Firebase → Project Settings → Cloud Messaging.
2. Add the **Push Notifications** capability and the **Background Modes → Remote notifications** option to the app target in Xcode.
3. `FirebaseMessaging` is already added to `Package.swift` and the Xcode project; run a package resolve on first build.

---

## Still deferred

Per the agreed core scope, the client-side Gemini generator and quality guard remain server-only (in the Cloud Function). Per-user-timezone scheduling (see Timezone note) and richer notification actions (e.g. reply from the lock screen) are future work.

---

## What constitutes an update to this PRD

Add or update the relevant section whenever you:
- Add a `daily_reads` / `dailyReads` field or change the doc-id / collection path
- Change the tone-engine thresholds or the soft/direct/funny/spicy constraints
- Edit any of the six structural formulas or the tone-matrix scenarios
- Change the Stage-2 quality-guard score cutoffs (currently ≥ 4 on all axes)
- Change the local engine's signal thresholds, confidence, or no-show rule
- Change the feedback recalibration (reward multiplier, sharpness step, rejection history size)
- Alter the push-notification manifest mapping (`notificationCopyForTone`) or what data the payload carries
- Change the share-card layout, dimensions, or the privacy rule (share-safe text only)
- Change the `pushTokens` / `dailyReads` Firestore rules or token storage path
- Change `PROMPT_VERSION`, the schedule, or the model
