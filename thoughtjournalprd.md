# Thought Journal — Feature PRD

**Status:** Proposed (design spec — no code yet).
**Author:** Product.
**Depends on:** the Mirror `EntryAnalysis` / `EpisodeFrame` pipeline being wired into save paths (see `mirrorprd.md`); the Daily Chat weave engine (`Chat/AIService+Chat.swift`); `PatternSafety`; `MemoryProfileService`.

---

## What it is

A **capture-first, silent-by-default** way to log thoughts as they happen across the
day — one line, no title, no timer, no reply expected. It is the "small logs
throughout the day" surface that the rest of the app has been missing, and it is
the primary fuel for pattern recognition (`timeRhythm`, within-day episode
structure) that a once-a-day entry can never provide.

The Thought Journal is defined by what it is **not**:

- It is **not the Journal** (which is *reflection* — a considered entry you keep and revisit).
- It is **not Daily Chat / Spilr** (which is *conversation* — you talk, Spilr replies, turn by turn).

It is the third point of an intent spectrum:

```
        DUMP IT                    TALK IT OUT                 KEEP IT
   ┌──────────────┐            ┌──────────────┐          ┌──────────────┐
   │   THOUGHT     │  ── take ─▶│  DAILY CHAT  │          │   JOURNAL    │
   │  (this PRD)   │   further  │   (Spilr)    │          │   (entry)    │
   │ capture-first │◀── seed ───│ conversation │          │  reflection  │
   │ silent default│            └──────┬───────┘          └──────▲───────┘
   └──────┬────────┘                   │ weave                   │
          │  weave the day             └─────────────────────────┘
          └──────────────────────────────────────────────────────┘
                        (all three write the SAME analysis signal)
```

The capture unit is a **Thought** (`Thought` model). In River-flavoured copy it is
a "drop" — many drops across a day flow into the River, consistent with the
existing water metaphor (`riverprd.md`). Spilr remains the persona but is **silent
in this surface by default**.

---

## The decision: shared engine, three modes, two bridges

> **Q: Does the thought journal merge into Daily Chat, or stand separate?**
> **A: Separate front-end surface, shared back-end, with two explicit bridges.**

**Why not merge into Daily Chat.** Capture and conversation have *opposite
defaults*. Capture wants **silence and speed** — the moment Spilr feels obligated
to reply, every log costs a round trip, a typing indicator, and a decision about
whether to respond to the response. Conversation wants **presence and turn-taking**
— which is friction you *want* when you've decided to go deep, and friction you
must not pay when you're catching a thought at a red light. Fusing them makes
capture slower and chat noisier. So they stay two surfaces.

**Why not fully separate, either.** A totally standalone thought log would waste
two engines we already have: the chat's depth (`nextChatTurn`, anti-fabrication
grounding) and the weave (`weaveEntry`). And splitting the data would blind the
pattern engine. So the surfaces are separate; the **pipeline is one**.

| | **Thought Journal** | **Daily Chat (Spilr)** | **Journal (entry)** |
|---|---|---|---|
| Intent | dump / notice | talk it out | reflect / keep |
| Default AI behaviour | **silent** | replies every turn | reflects on save |
| Friction | ~2 s, one tap | a conversation | a sitting |
| Volume | many per day | ~1 per session | ~1 per day |
| Stored as | `Thought` (own collection) | woven `JournalEntry` | `JournalEntry` |
| Feeds pattern engine | ✅ (1 episode each) | ✅ | ✅ |

**The two bridges** connect the surfaces so intent can escalate without the user
re-typing:

1. **Thought → Chat ("take it further").** Any thought can be opened into Spilr,
   pre-seeded with that thought as the first user turn. This is also the fix for
   Daily Chat's static opener problem on this path — the opener is *generated from
   the thought*, not picked from the hardcoded five.
2. **Thoughts → Entry ("weave the day").** A day's thoughts can be woven into one
   reflective `JournalEntry` using the existing weave engine. This is the
   deliberate graduation from fragments to a kept reflection — never automatic.

---

## Entry points (no new tab)

The tab bar is already five deep (Today / Journal / River / Mirror / Patterns).
Adding a sixth for a *capture* surface is the wrong trade — capture should be
everywhere, not one more place to navigate to. Instead:

1. **Home capture bar** — a persistent, always-focusable "Catch a thought…" bar on
   the Today screen, above the fold. Type or dictate, hit return, it's saved. The
   bar never navigates away; you can drop three thoughts in a row.
2. **Ambient surfaces (the un-quittable part)** — Home-screen & Lock-screen
   **widgets**, an Apple Watch complication, and an **App Intent / Siri Shortcut**
   ("Hey Siri, tell Spilr I'm wired"). These are the highest-frequency inputs and
   the reason the thought journal actually gets used. (See `Spilr_Product_AI_Strategy`
   Pillar II.)
3. **Thoughts stream** — lives **inside the Journal tab** as a segmented control
   (`Entries | Thoughts`), because the Journal is already the "written record"
   home. Chronological, grouped by day, collapsible. Keeps the entry list clean.
4. **Interjection ripple** — the only place Spilr may appear (opt-in, rate-limited;
   see below).

---

## Relationship to Daily Chat — the interjection & escalation logic

### When Spilr speaks in the Thought Journal

**Default: never.** A thought is a place to put something down, not start a
conversation. Unsolicited replies are OFF by default.

If the user turns on **Reflective mode** (a single toggle in the Thoughts stream,
default off), Spilr may surface **at most one** optional micro-response, and only
when **all** of these hold:

- the thought passed the **`PatternSafety` deterministic gate** (no crisis signal), **and**
- a **cooldown** has elapsed since the last interjection (≥ 3 new thoughts *or* ≥ 3 hours), **and**
- the thought has **substance** (≥ ~25 characters — mirrors the chat's own thresholds), **and**
- `AIService.shared.isAIAvailable` (else stay silent — no local guessing here).

The response is **one hedged line or one question**, reusing the chat's
`CONCRETE / TENSION / UNDERNEATH / ABSENCE / REFRAME` moves and the full
anti-fabrication grounding (only reference what the person actually wrote; reuse
their exact words; no advice, no diagnosis, no invented second party). It renders
as a **dismissible ripple** attached to the thought — **not** a chat bubble that
demands a reply. One-thing-at-a-time is preserved: never a list, never more than
one open ripple.

Tapping the ripple **escalates to full Daily Chat**, seeded with the thought and
the ripple as the first exchange.

### Thought → Chat escalation (bridge 1)

"Take it further" on any thought opens `DailyChatView` with:

- the thought text injected as the first `.user` `ChatMessage`,
- a **generated opener** from `AIService.chatOpener(seededWith:)` grounded in the
  thought (replaces the static rotation for this path),
- `sourceThoughtIds` carried through so a subsequent weave links back to the origin thoughts.

Everything downstream is unchanged: the woven result is a normal `JournalEntry`
(`sessionType: .dailyChat`), the transcript is still discarded, only the entry is kept.

### Why the surfaces don't share a screen

Chat's word-by-word reveal, typing indicator, and per-turn round trip are correct
*for chat* and wrong *for capture*. Keeping them separate lets each optimise its
own default (capture = instant + silent; chat = present + responsive) while the
bridges let a user move along the spectrum in one tap.

---

## Relationship to Journal, River, and Mood

- **Thoughts are their own collection, not `JournalEntry`.** They are fragmentary
  and high-volume; forcing them into the entry list (with titles, tags, mood UI)
  would clutter the Journal and pollute streak/resilience maths. They graduate into
  entries only via an explicit weave.
- **Weave → `JournalEntry`** with a new `sessionType: .thoughtWeave`, tag
  `"thoughts"`, `sourceThoughtIds` set. Source thoughts are **preserved** (not
  deleted) so the day's raw record survives alongside the reflection.
- **River:** each thought generates a **lightweight `RiverMark`** (a small droplet,
  lower intensity than an entry's) via `RiverService`, so a day of thoughts shows
  as ripples feeding the current. "Cute is the wrapper, meaning is the engine"
  (`riverprd.md`) holds.
- **Mood:** the previously-unwired one-tap mood check-in (`MoodLogService`,
  `MoodBlobView`) becomes an **attribute of a thought** (optional mood/energy chip)
  *and* supports a **mood-only thought** (empty text + mood) for the fastest
  possible log. This gives `MoodLog` a real home and unifies "small logs."

---

## Data model

**File (proposed):** `Thought/Thought.swift`

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `userId` | String | Firebase UID |
| `text` | String | The raw thought (may be empty for a mood-only log) |
| `createdAt` | Date | Capture time — the whole point; drives `timeRhythm` |
| `source` | Enum | `.bar` / `.widget` / `.lockScreen` / `.watch` / `.siri` / `.voice` |
| `mood` | `Mood?` | Optional one-tap mood/energy chip |
| `unpack` | `ThoughtUnpack?` | Optional CBT structure (see below); nil for a raw drop |
| `escalatedToChat` | Bool | Set when the thought was taken into Daily Chat |
| `wovenIntoEntryId` | String? | Set when a weave consumed this thought |
| `analysisId` | String? | Link to the `EntryAnalysis`-compatible doc produced from it |
| `rawTextEncrypted` | String | Base64 AES-GCM; not sent server-side for mining (privacy parity with entries) |

**`ThoughtUnpack`** (optional, progressive CBT thought-record — never forced):

| Field | Type | Notes |
|---|---|---|
| `situation` | String? | "What was happening?" |
| `automaticThought` | String | The raw thought itself |
| `feeling` | String? | Named feeling + optional 0–100 intensity |
| `reframeQuestion` | String? | A gentle question Spilr offered (not an answer) |
| `reframe` | String? | The user's own re-read, if they wrote one |

---

## Analysis & pattern-engine integration

The rule that makes the pattern AI "top class": **a thought is analysed by the
exact same pipeline as an entry, at the episode level.** No parallel analytics path.

- On save, a detached task runs `analyzeEntry`-equivalent extraction, producing a
  **single `EpisodeFrame`** (situation / emotion / bodySignal / protectiveStrategy /
  need / outcome) wrapped in an `EntryAnalysis`-compatible document keyed by
  `thoughtId`, with `source: .thought`.
- The nightly miner (Prompt B / SM-1, once server-side per `mirrorprd.md` /
  `profileintelligenceprd.md`) reads **entries and thoughts uniformly**. Thoughts
  are what make within-day and time-of-day patterns real:
  *"mornings run tense and soften by mid-afternoon on days you move your body"*,
  *"the word 'reset' shows up on Sunday evenings"* — insight a daily entry cannot yield.
- Thoughts respect the same **confidence and maturity gates** as entries. A single
  thought never triggers a pattern claim; it accretes.

---

## AI layer

All calls route through `AIService.generate(...)` via `geminiProxy`
(`gemini-3.5-flash-lite`), begin with `NinetyVoice.system`, and end with
`MemoryProfileService.shared.cachedPromptContext()` — per project convention.

| Call | Tokens | Temp | When | Fallback |
|---|---|---|---|---|
| *(silent capture)* | — | — | default | **none needed — zero AI on the hot path** |
| `analyzeThought(text:)` | 800 | 0.2 | detached, on save (if AI available) | `EntryAnalysis.local(...)` single-episode |
| `thoughtInterjection(thought:)` | 120 | 0.5 | only in Reflective mode, gated | silent (no interjection) |
| `chatOpener(seededWith:)` | 90 | 0.5 | on "take it further" | first line = the thought itself |
| `weaveDay(thoughts:)` | 700 | 0.3 | on "weave the day" | `localWeaveEntry` over the day's thoughts |

**Non-negotiable prompt rules** (inherited from Daily Chat, `dailychatprd.md`):
no fabrication, reuse the person's exact words, no advice/diagnosis/reassurance,
one line only, banned clichés ("how did that make you feel", "that sounds
difficult", "I hear you"). The interjection is an *observation or question*, never
a verdict.

**The hot path uses no AI.** Dropping a thought is a fire-and-forget Firestore
write + local save; analysis and any interjection are detached and optional. The
feature is fully usable offline and with AI consent off.

---

## Optional CBT structure — "Unpack"

A thought can be **unpacked** into a light thought-record: `situation →
automatic thought → feeling → reframe question`. This is the therapeutic teeth
("therapy is 50% journaling") but it is **progressive and optional**:

- Default capture is a raw one-liner. Unpack is a secondary tap, never a gate.
- Spilr may *offer* to unpack only when a thought looks like a stuck/negative loop
  (recurring self-critical phrasing, cognitive-distortion markers already modelled
  in `EntryAnalysis.cognitivePatterns`) **and** it passes the safety gate.
- Spilr supplies the **reframe question**, never the reframe. The user writes their
  own re-read, or skips it. Unpacked thoughts are the highest-value learning signal
  and feed the Self-Model's `whatHelps` / `exception` sections.

---

## Capture UX

1. Tap the Home bar (or a widget) → keyboard/dictation is already up.
2. Type/say one line → **return saves instantly** with a soft haptic; the bar clears and stays focused for the next.
3. Optional: tap a mood/energy chip; optional: "Unpack."
4. No reply, no reveal animation, no waiting. (In Reflective mode, a ripple *may* appear later, dismissibly.)

**Speed target:** thought → saved in **under 2 seconds**, no navigation. Anything
slower defeats the purpose.

---

## Firestore schema

```
users/{uid}/thoughts/{thoughtId}            // the Thought
users/{uid}/entryAnalyses/{thoughtId}       // shared analysis doc, source: thought
```

`firestore.rules`: add an owner-only `match` block for `thoughts/{thoughtId}`
(mirrors the entries/moodLogs rules). The nightly miner (Admin SDK) bypasses rules.

---

## Volume, retention, performance

- High write volume is fine: fire-and-forget `setData`, one doc per thought, no UI
  wait (project convention). Analysis is detached `.background`.
- **Stream pagination:** load the last ~14 days; older days lazy-load. Thoughts
  never expire but collapse under "Earlier."
- **Optional auto-archive:** a user setting to auto-fold thoughts older than 90
  days out of the stream (still mined, still deletable).

---

## Privacy

Thoughts are as sensitive as entries and inherit the same posture (see
`privacyprd.md`): `rawTextEncrypted` at rest, **structured-only** mining
server-side (never raw text), and thoughts are **separately deletable** — per
thought, "delete today's thoughts," and included in full export/delete.

**Lock-screen constraint:** widgets and lock-screen surfaces are **capture-only** —
they must never render prior thought text (no read-back of sensitive content on a
locked device). Same rule the Hints PRD applies to personal questions.

---

## Safety

Every thought runs the deterministic **`PatternSafety.corpusHasCrisisSignal`** gate
**before** any interjection, unpack offer, or escalation is generated. On a crisis
signal: no interjection, no offer; route to the existing
`HomeViewModel.showResourceCard` / `PatternResourceCardView` flow. Thoughts also
join the corpus the pattern-safety check runs over, so a run of distressing
micro-logs is caught the same way a distressing entry is.

---

## Local-first fallback

- **Capture:** never needs AI — always works.
- **Analysis:** `EntryAnalysis.local(...)` single-episode heuristic when AI is off.
- **Interjection:** simply absent without AI (no local guessing — silence is the safe default).
- **Weave:** `localWeaveEntry` over the day's thoughts (same as Daily Chat's offline weave).

---

## Files (proposed)

| File | Purpose |
|---|---|
| `Thought/Thought.swift` | `Thought` + `ThoughtUnpack` models, `sessionType.thoughtWeave` |
| `Thought/ThoughtService.swift` | Firestore CRUD, fire-and-forget save, stream fetch/pagination |
| `Thought/AIService+Thought.swift` | `analyzeThought`, `thoughtInterjection`, `weaveDay`, `chatOpener(seededWith:)` |
| `Thought/LocalThought.swift` | Local single-episode analysis + offline weave |
| `Thought/ThoughtCaptureBar.swift` | The Home capture bar |
| `Thought/ThoughtStreamView.swift` | The `Entries \| Thoughts` segment + ripple + Unpack sheet |
| `Widget/…` (new target) | Home/Lock-screen widgets + App Intent for capture |
| Wiring | `Home/HomeView.swift` (bar), `Journal/JournalListView.swift` (segment), `River/RiverService.swift` (light mark), `Chat/DailyChatView.swift` (seeded open), Mirror analyze pipeline |

---

## Success metrics

| Metric | Why |
|---|---|
| Thoughts per active day | The leading indicator for pattern quality |
| % of active users who capture ≥1 thought via an ambient surface (widget/Watch/Siri) | Proves the friction floor is low enough |
| Thought → Chat escalation rate | Are the bridges discovered/valued |
| "Weave the day" usage | Fragments graduating to reflection |
| Interjection dismiss vs. escalate ratio (Reflective mode) | Is Spilr's one line welcome or noise |
| Unpack completion rate | Depth of therapeutic engagement |

---

## Open decisions (flagged for review)

1. **Interjection default** — proposed **off** (Reflective mode opt-in). Alternative: on with a hard 1/day cap. *Recommendation: ship off; earn the right to speak.*
2. **Stream location** — proposed **segment inside Journal**. Alternative: a lightweight sheet from the Home bar. *Recommendation: segment; keeps navigation at five tabs.*
3. **Name** — unit is a **Thought** ("drop" in River copy). Alternatives considered: Sparks, Static, Threads. *Recommendation: keep "thought" — literal beats cute for a capture primitive.*
4. **Mood merge** — proposed to **subsume** the standalone mood log as a thought attribute. Alternative: keep both. *Recommendation: subsume; one "small log" concept.*

---

## What triggers a PRD update

- Change the `Thought` / `ThoughtUnpack` schema, the `thoughts` collection path, or the `.thoughtWeave` session type
- Change the interjection gate (safety, cooldown, substance threshold, Reflective-mode default) or its prompt (rules, tokens, temperature)
- Change the escalation seeding (Thought → Chat) or the weave inputs (Thoughts → Entry)
- Change how thoughts feed the analysis/pattern pipeline (episode mapping, `source` discriminator, maturity gates)
- Add/remove a capture surface (bar, widget, lock screen, Watch, Siri) or change the capture flow/speed target
- Change the River mark weighting for thoughts, or the mood-attribute behaviour
- Change privacy behaviour (retention/archive, lock-screen read-back rule, deletion granularity)
