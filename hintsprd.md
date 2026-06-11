# Hints — Question Bank PRD

**Last updated:** 2026-06-09
**Status:** Replacement PRD — supersedes the previous Hint Ladder direction

---

## 2026-06-09 update — live writing-screen changes (shipped against the Hint* path)

The `Question*` system below is still the target direction, but the **live**
90-second writing screen (`NinetySecondSessionView`) continues to use the
`Hint*` files (`HintEngine`, `HintLadder`, `AIService+Hints`). The migration to
`QuestionEngine` remains TODO. The following user-facing fixes shipped against
the live Hint* path and the writing flow:

- **Pebble picker is no longer a separate gating screen.** `PebblePickerView` is
  no longer presented. The 90-second session opens directly (`HomeView` presents
  `NinetySecondSessionView` in a `fullScreenCover`), and pebbles are chosen
  **inline** on the writing screen via an optional horizontal pebble strip in
  `promptArea`. Selecting a pebble updates the starter prompt and what gets saved
  as tags, without leaving the page.
- **Write/Talk toggle removed from the entry flow.** With the picker gone, the
  session defaults to `.write` (mic still available for dictation). The `.talk`
  code paths remain for callers that pass an explicit talk context.
- **"How personal?" control removed** from the pre-write flow (it lived on the
  picker). The inline pebble strip excludes the personal-locked pebbles
  (`Sunday dread`, `after gym`); personal level defaults to `.safe`/`.light`.
- **Reroll now shuffles.** `gentler` / `more direct` / `weirder` previously
  returned one fixed string forever. `HintLadder.starterPrompt` now takes a
  `variant:` index and `HintEngine.restyledStarter` advances a per-style counter,
  so re-tapping the same control yields a new question each time
  (`HintLadder.styledPool`).
- **Voice transcript no longer lost on mic-stop.** The session now mirrors
  `SpeechManager.liveText` into `vm.content` in real time (the proven editor
  approach), so stopping the mic — or hitting Save mid-recording — keeps the
  spoken text.

---

## Product thesis

A user who has "no words" does not need words from the app. They need one kind, specific question that makes their own words easier to find.

The product promise changes from **"Make it smaller."** to **"Ask me something I can actually answer."**

A good hint question is:
- specific enough to unlock memory
- soft enough to answer badly
- short enough to use immediately
- personal only when the user has allowed personalization
- useful even when the user writes only one sentence

---

## What changed from the old direction

**Deprecated:** `HintLadder`, `PebblePickerView`, `HintPanelView`, `AIService+Hints.swift`, `HintEngine`

**New:** `QuestionBank.swift`, `UniversalQuestionBank.swift`, `QuestionMixer.swift`, `QuestionEngine.swift`, `AIService+Questions.swift`, `QuestionPickerView.swift`, `QuestionPanelView.swift`

Old direction gave users smaller writing starts ("Write 3 words", "Finish this…", "body / room / thought").

New direction gives users direct questions they can answer in their own words. The question is shown as the prompt — it is **not inserted into the journal entry** unless the user explicitly copies it.

---

## The 50 universal questions

File: `DailyJournal/Hints/UniversalQuestionBank.swift`

50 fixed questions across 5 categories. Always available offline. Always personalLevel = .safe.

| Category | IDs | Example |
|---|---|---|
| Blank-page friendly | UQ001–UQ010 | "What part of today is easiest to tell?" |
| Body, energy, and mood | UQ011–UQ020 | "What did your body ask for today?" |
| People and messages | UQ021–UQ030 | "Who affected the shape of your day?" |
| Work, pressure, and avoidance | UQ031–UQ040 | "What did you avoid, and was it trying to protect you?" |
| Home, world, and tiny details | UQ041–UQ050 | "What felt beautiful for half a second?" |

---

## Core models

File: `DailyJournal/Hints/QuestionBank.swift`

| Type | Purpose |
|---|---|
| `QuestionMode` | `.write` or `.talk` |
| `QuestionPersonal` | `.safe`, `.light`, `.me` — controls how personal questions may get |
| `QuestionSource` | `.universal`, `.localContext`, `.personal`, `.gemini` |
| `QuestionCategory` | `.blank`, `.body`, `.people`, `.work`, `.home`, `.personal` |
| `QuestionAnswerStyle` | `.open`, `.choice`, `.tapOnly`, `.trace` |
| `QuestionRung` | Ladder: `.specificQuestion` → `.gentleQuestion` → `.choiceQuestion` → `.tapOnlyQuestion` → `.traceOnly` → `.blankDrop` |
| `QuestionTab` | `.gentle`, `.specific`, `.choice`, `.mine` (hidden until personal history exists) |
| `QuestionRerollStyle` | Reroll pills inside session |
| `QuestionCard` | Replaces `HintCard`. `question` is displayed as prompt, never auto-inserted. |
| `QuestionBundle` | Full set for one session: starterWrite, starterTalk, gentle[3], specific[3], choice[3], mine[3] |
| `QuestionContext` | Passed from picker → session → engine. Has pebbles, personal, mode, explicitQuestion, source. |
| `QuestionOutcome` | Outcome recorded every time a question is shown — drives startedness score. |
| `QuestionBank` | Static pebble bank, maxPebbles = 3, personalPebbles, feelingWords, pebbleTagMap |

---

## Local selection logic

File: `DailyJournal/Hints/QuestionMixer.swift`

Scoring system (no network required):

| Signal | Effect |
|---|---|
| Matches selected pebbles | +3 |
| Prior session saved after this question | +2 |
| Not shown recently | baseline |
| Shown recently | −2 |
| Dismissed | −1.5 per dismiss |

`QuestionMixer.localBundle(for:)` — builds a full `QuestionBundle` synchronously.
`QuestionMixer.rungQuestion(_:pebbles:mode:)` — returns the question for a specific ladder rung.
`QuestionMixer.reroll(style:current:pebbles:mode:excluding:)` — instant reroll from local bank.
`QuestionMixer.recordOutcome(_:)` / `loadOutcomes()` — outcome persistence in UserDefaults (rolling 200).

---

## QuestionEngine

File: `DailyJournal/Hints/QuestionEngine.swift`

`@MainActor final class QuestionEngine: ObservableObject`

Lives inside `NinetySecondSessionView` as `@StateObject private var questions: QuestionEngine`.

**On init:**
1. Build local `QuestionBundle` synchronously — UI never blank.
2. Show starter question immediately.
3. Fire-and-forget AI enrichment.
4. Swap in enriched bundle with animation if valid.
5. Keep local bundle silently if AI fails.

**Key methods:**

```swift
func useQuestion(_ card: QuestionCard)          // sets prompt, records outcome
func makeEasier() -> QuestionCard               // descend one ladder rung
func reroll(style: QuestionRerollStyle)         // instant swap, local bank
func dismissQuestion(_ card: QuestionCard)
func lessLikeThis(_ card: QuestionCard)
func quietForToday()
func recordSessionSaved(wordCount:)
func recordBlankDrop()
func recordFirstInput(timeInterval:)
```

---

## AI enrichment

File: `DailyJournal/Hints/AIService+Questions.swift`

Trigger: `AIService.shared.isAIAvailable` (user signed in + network).

**AI output schema:**
```json
{
  "starter_write":       { "question": "≤120 chars", "category": "string", "tags": ["string"] },
  "starter_talk":        { "question": "≤90 chars",  "category": "string", "tags": ["string"] },
  "gentle":              [ { "question": "string", "category": "string", "tags": ["string"] } ],
  "specific":            [ { "question": "string", "category": "string", "tags": ["string"] } ],
  "choice":              [ { "question": "string", "category": "string", "tags": ["string"] } ],
  "personal_candidates": [ { "question": "string", "category": "string", "tags": ["string"],
                             "personal_level": "safe|light|me", "seed_question_ids": ["string"] } ]
}
```

**Validation rules:**
- `starter_write` and `starter_talk` must be non-empty.
- `gentle`, `specific`, `choice` must each contain exactly 3 questions.
- Every question must end with `?`.
- No question exceeds 140 characters.
- Talk questions ≤ 90 characters.
- `personal_candidates`: 0–10 entries.
- Invalid responses are rejected; local bundle stays unchanged.

**AI non-negotiable prompt rules:**
- Questions only. No sentence stems. No "write 3 words." No "talk for 90 seconds."
- No advice, diagnosis, shame, guilt, productivity pressure, or fake intimacy.
- No private phrase unless `personal == .me`.
- No lock-screen-facing personal content.
- Questions answerable in 90 seconds.
- "Why" used sparingly — prefer "what made that harder?" over "why did you avoid that?"

---

## Pebbles

File: `DailyJournal/Hints/QuestionBank.swift` — `QuestionBank` enum

Pebbles still matter. Their job is now to help the app choose better questions (not generate word-based hints).

```
maxPebbles = 3
personalPebbles = ["Sunday dread", "after gym"]
```

Personal pebbles only influence questions when `QuestionPersonal == .me`. Never in lock-screen, notification, or widget contexts.

---

## Question tabs

| Tab | Title | Intent |
|---|---|---|
| `.gentle` | "Ask me gently" | Soft, low-pressure questions |
| `.specific` | "Ask about today" | Pebble-aware, contextual questions |
| `.choice` | "Give me a choice" | Either/or questions for blank moments |
| `.mine` | "Mine" | Personalized questions — hidden until history exists |

Each visible tab renders exactly 3 `QuestionCard` objects.

---

## Question ladder

The ladder controls how easy the question is to answer:

| Rung | Description |
|---|---|
| `.specificQuestion` | Sharp question grounded in today's context |
| `.gentleQuestion` | Softer question with less emotional demand |
| `.choiceQuestion` | Either/or question |
| `.tapOnlyQuestion` | User answers with one tap |
| `.traceOnly` | Save chosen pebbles or feeling words |
| `.blankDrop` | Save a blank drop — river still gets a mark |

Button copy: **"Make it easier"** (not "Make it smaller"). Floor copy: "This is the easiest start."

---

## Reroll styles

Write mode pills: "gentler", "more specific", "give me a choice", "surprise me"

Talk mode pills: "shorter", "easier", "give me a choice"

Reroll is instant when local questions are available. Reroll is hidden when the session was opened with an explicit question from a pattern callback or notification.

---

## Blank rescue banner

Appears after `vm.secondsBlank >= 15` when `!rescueDismissed && !vm.isRecording && !questions.questionsQuietedToday`.

Copy: **"Want one question?"**

Actions: "ask me" → opens `QuestionPanelView` | "save a blank drop" → trace + exit | ✕ → dismiss for session.

---

## Entry point copy

CTA: **"No words yet? Pick a question"**

---

## Using a question

The question is shown as the displayed prompt. **It is never auto-inserted into the journal body.** Tapping a card updates the prompt above the editor and focuses the field. Existing user content is never overwritten.

---

## Personalized question bank

File: `DailyJournal/Hints/QuestionPersonalizationService.swift` (stub, full implementation TODO)

AI generates personal candidates after ≥5 sessions and ≥10 outcomes. Merge logic validates schema, removes duplicates and near-duplicates, rejects personal-level violations, and archives lowest-performing questions when bank exceeds 50.

Active personal bank: up to 50 questions.
Archived: up to 100 questions.
Universal bank: never removed.

---

## Privacy rules

- Universal questions are always safe.
- AI personalization uses summaries by default, not raw journal entries.
- User-confirmed phrases only when `personal == .me`.
- Personal questions are in-app only — never lock screen, notification, or widget.
- User can reset personal question bank at any time.

---

## File map

| File | Purpose |
|---|---|
| `Hints/QuestionBank.swift` | Core models, enums, constants |
| `Hints/UniversalQuestionBank.swift` | Fixed 50-question set |
| `Hints/QuestionMixer.swift` | Local scoring and question selection |
| `Hints/QuestionEngine.swift` | Session-level question state (`@MainActor ObservableObject`) |
| `Hints/AIService+Questions.swift` | Gemini enrichment and personal question generation |
| `Hints/QuestionPickerView.swift` | Entry sheet replacing `PebblePickerView` |
| `Hints/QuestionPanelView.swift` | In-session panel replacing `HintPanelView` |
| `Home/NinetySecondSessionView.swift` | Session integration (migration TODO) |

**Deprecated (kept for reference, do not use in new code):**
`HintLadder.swift`, `HintEngine.swift`, `HintPanelView.swift`, `PebblePickerView.swift`, `AIService+Hints.swift`

---

## What triggers a PRD update

- Add, remove, or edit the 50 universal questions
- Change question categories or tags
- Change `maxPebbles`
- Change `QuestionMode` or `QuestionPersonal`
- Change question tabs or ladder rungs
- Change the blank rescue threshold (currently 15 seconds)
- Change AI output schema or prompt rules
- Change personalization merge logic or bank size
- Add or remove user controls
- Change trace or blank-drop behavior
