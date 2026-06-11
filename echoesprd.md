# Echoes — Feature PRD

**Last updated:** 2026-06-07

---

## What it is

An Echo is a single AI-extracted moment from a past journal entry, resurfaced on the Home screen as a gentle callback. At most one Echo appears per session. It is always dismissable. It is never a list.

The point: ninety has been reading. An Echo proves it — not by summarising, but by holding up one specific thing the user said and asking whether anything moved.

---

## Data model

**File:** `DailyJournal/Echo/Echo.swift`

### EchoType

| Value | Raw string | Meaning | Display label | Action label |
|---|---|---|---|---|
| `.intention` | `intention` | User said they'd do a specific, concrete action | "stated intention" | "done ✓" |
| `.openLoop` | `open_loop` | User mentioned a future event with emotional weight | "open loop" | "it happened" |
| `.theme` | `theme` | A specific person/fear/situation that recurs across entries | "recurring theme" | "read them" |
| `.moodMarker` | `mood_marker` | A specific emotional state stated as fact with intensity | "mood callback" | "noted" |

### EchoStatus

| Value | Meaning |
|---|---|
| `.pending` | Waiting to be surfaced; surface gate not yet passed |
| `.answered` | User responded positively |
| `.dismissed` | Skipped ≥ 2 times — never resurfaces |
| `.expired` | Not acted on within 7 days — decayed by background job |

### Echo fields

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `userId` | String | Firebase UID |
| `sourceEntryId` | String | Firestore doc ID of the originating entry |
| `sourceEntryCreatedAt` | Date | Used to compute "time ago" label on the card |
| `type` | EchoType | One of the four types above |
| `quote` | String | **Exact** user words — never paraphrased |
| `surfaceAfterDate` | Date | Computed from `surfaceAfterHours`; don't show before this |
| `confidence` | Double | 0.0–1.0; must be ≥ 0.8 to persist (enforced twice) |
| `status` | EchoStatus | Lifecycle state |
| `skipCount` | Int | Increments on skip; at 2 → auto-dismiss |
| `createdAt` | Date | When the Echo document was created |
| `answeredAt` | Date? | Set when user confirms |
| `themeKeyword` | String? | Only for `.theme` — the 1–3 word recurring subject |
| `line` | String? | Ninety's framing voice line shown above the quote |

### Surface-after delays (hours)

| Type | Delay |
|---|---|
| `.intention` | 36 h |
| `.openLoop` | 72 h |
| `.theme` | 168 h (7 days) |
| `.moodMarker` | 336 h (14 days) |

---

## Extraction pipeline

**File:** `DailyJournal/Echo/EchoExtractionService.swift`

Called fire-and-forget after every entry save from both `NinetySecondViewModel.saveEntry()` and `JournalEditorViewModel`. Never throws into the UI.

### Steps

1. **Guard:** `AIService.shared.isAIAvailable` (user signed in) and entry > 30 chars.
2. **Context fetch:** Pull up to 4 recent entries, exclude the just-saved one. Used as context-only for the AI — the model must not extract from them.
3. **AI extraction:** `AIService.shared.extractEcho(from:recentEntries:)` — conservative, low-temperature (0.2) prompt. Returns `nil` when the model correctly decides there's nothing to echo.
4. **Confidence gate:** Belt-and-suspenders check: `result.confidence >= 0.8`. Below threshold → silent drop.
5. **Line fallback:** If the model returned no `line`, generate one locally via `NinetyVoice.localEchoLine(type:quote:daysAgo:)` so the card never resurfaces as a bare quote.
6. **Persist:** `EchoService.createEcho(_:)` — fire-and-forget write to Firestore.

---

## AI prompt

**File:** `DailyJournal/Home/AIService.swift` → `buildEchoPrompt(entryText:recentContext:recurrenceSeed:)`

- System persona: `NinetyVoice.system` — injected at the top of every prompt.
- Memory context: `MemoryProfileService.shared.cachedPromptContext()` — injected at the bottom for personalisation.
- Recurrence seed: known recurring themes from MemoryProfile injected to improve `.theme` detection.
- Temperature: **0.2** (conservative).
- Max tokens: **350**.
- Returns one of two JSON shapes:
  - `{"echo": null, "reason": "…"}` — the common, correct case.
  - `{"echo": {"type": …, "quote": …, "surface_after_hours": …, "confidence": …, "theme_keyword": …, "line": …}}`

Hard rules enforced in the prompt:
- `confidence < 0.8` → return null.
- Vague intentions ("I should exercise more") do not qualify.
- Generic emotions ("tired") do not qualify.
- `quote` must be **exact user words**, never paraphrased.
- `line` must frame the quote with a perspective or question — never restate it.

---

## Firestore schema

Collection path: `users/{uid}/echoes/{echoId}`

All fields listed in the data model section are persisted. Timestamps use `FirebaseFirestore.Timestamp`.

---

## CRUD — EchoService

**File:** `DailyJournal/Echo/EchoService.swift`

| Method | Description |
|---|---|
| `createEcho(_:)` | Fire-and-forget write. |
| `fetchTopPendingEcho(for:)` | Queries `status == pending`, `surfaceAfterDate <= now`, ordered by `surfaceAfterDate asc` then `confidence desc`, `limit(1)`. Also triggers background decay. |
| `fetchAll(for:limit:)` | Returns pending + answered echoes ordered by `sourceEntryCreatedAt desc` — used by the Echoes/Memories feed (not the surface gate). |
| `skipEcho(id:userId:currentSkipCount:)` | Increments `skipCount`. If new count ≥ 2, sets `status = dismissed`. |
| `markAnswered(id:userId:)` | Sets `status = answered`, `answeredAt = now`. |
| `decayExpiredEchoes(for:)` | Private. Batches `status = expired` on any pending echo older than 7 days. Runs detached/background, never awaited. |

---

## Surfacing logic (HomeViewModel)

**File:** `DailyJournal/Home/HomeView.swift`

- `pendingEcho` is fetched once per session load (first `vm.load()` call).
- `if pendingEcho == nil` guard prevents re-fetching on pull-to-refresh after the user has dismissed/answered.
- Both `skipEcho()` and `answerEcho()` clear `pendingEcho` with `.easeOut(0.25)` animation.

---

## UI

### EchoCardView

**File:** `DailyJournal/Echo/EchoCardView.swift`

Shown in `HomeView.echoSection`, above the prompt card.

| Element | Description |
|---|---|
| Type tag | Pulsing terracotta dot + "an echo · {displayLabel}" in mono uppercase |
| Skip button | Top-right, "skip" in mono uppercase, instant dismiss |
| Ninety's line | `echo.line` — the framing voice line shown first, larger (18pt editorial medium) |
| Quote | `echo.quote` in curly quotes, italic editorial body, 15pt |
| Time ago label | "From your entry · {relative time}" in mono 9pt |
| Action row | Differs by type (see below) |

Action row variants:
- **Non-theme types:** "not yet" (outline capsule, calls `onNotYet`) + primary action button (filled capsule, calls `onAnswer`).
- **Theme type:** Single full-width "read them together →" button, calls `onThemeTap`.

Card styling: `AppTheme.paperWarm` background, 16pt rounded rect, 2px hard shadow (x:2 y:2), terracotta stroke 0.2 opacity.

### EchoAnsweredView

**File:** `DailyJournal/Echo/EchoAnsweredView.swift`

Presented as a sheet when the user confirms (taps primary action). Shown after a `sheet(item: $activeEchoForAnswer, onDismiss: { vm.answerEcho() })` — the Firestore write happens on dismiss, not inside the view.

| Section | Content |
|---|---|
| Glyph header | `✺` in terracotta, "An echo, closed" label |
| Resolved card | Past quote in faded italic, date stamp above |
| Response area | Optional free-text field "How did it go?" — never required |
| "You said" card | Appears when response is non-empty; editable in-place |
| Ninety's closing note | Dark card with a type-keyed closing line |
| Close button | Outline, full-width, triggers `dismiss()` |

No celebration, no streak counter, no green checkmark. Deliberately quiet.

Closing notes by type:
- **intention:** "Most of the things you dread doing, you do…"
- **openLoop:** "The things you wait on with dread usually turn out to be just events…"
- **theme:** "The thread is still there. That's not a problem…"
- **moodMarker:** "Two weeks changes more than it feels like it will…"

### ThemeCompilationView

**File:** `DailyJournal/Echo/ThemeCompilationView.swift`

Presented as a sheet when the user taps "read them together" on a `.theme` Echo.

- Fetches **all** entries for the user (`JournalService.fetchAllEntries`), filters by `themeKeyword` (case-insensitive contains).
- Renders each matching entry as a card with date stamp + 220-char snippet.
- Keyword is highlighted terracotta inline using `Text` concatenation (no `AnyView`).
- Shows entry count in the header: "A pattern, {n} entries".
- "Ninety noticed" dark card at the bottom: fixed copy, no AI call.
- Dismissing the sheet triggers `vm.answerEcho()` — viewing the compilation counts as engaging.

---

## Local fallback voice lines

**File:** `DailyJournal/Home/NinetyVoice.swift` → `localEchoLine(type:quote:daysAgo:)`

Used when the AI returns no `line`. Framed with the time delta ("the other day", "yesterday", "{n} days ago") and a type-appropriate observation + question. Never a restatement of the quote.

---

## What constitutes an update to this PRD

Add a section or update the relevant section whenever you:
- Add a new EchoType or EchoStatus value
- Change surface-after delay values
- Change the confidence threshold
- Modify the AI prompt (temperature, token budget, rules, schema)
- Add fields to the Echo data model
- Change Firestore collection path or query structure
- Add/change EchoService methods
- Change card UI layout, actions, or copy
- Add new views in the Echo flow
- Change the decay window (currently 7 days)
- Change skip-to-dismiss threshold (currently 2 skips)
