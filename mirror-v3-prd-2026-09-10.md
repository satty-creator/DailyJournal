# Mirror v3 — product requirements and UX

**For:** Satakshi · Spilr (ninety) · 2026-09-10
**Status:** proposal. Supersedes the daily-card sections of `mirrorprd.md` and the Self Model surfaces in `profileintelligenceprd.md`; does not touch extraction (Prompt A) or the encryption/rules work in `engineering-decisions-ai-architecture-2026-09-09.md`.
**Inputs:** the 13 screenshots from 2026-09-09 (Patterns list, My Mirror, First Sketch, Home), `functions/index.js`, `Mirror/*.swift`, the Rosebud teardown, and the research in §2 (each claim verified against the source; corrections noted where the common paraphrase overstates).

---

## 0. The one-paragraph version

Mirror today shows the user **nineteen hypotheses, eighteen of them seen once, six of them the same hypothesis reworded**, each carrying a taxonomy label, a lifecycle chip, a confidence caption, an evidence caveat, and four buttons. It is the output of a pattern engine displayed as if it were the product. Mirror v3 inverts the order: **the product is the user's own data, read back precisely** — counts, dates, verbatim phrases, and comparisons between days — and interpretation is a thin layer that appears only when the numbers already support it. Almost everything in v3 is deterministic; the language model writes at most one sentence a day. That is what makes it accurate, cheap, and — because true specifics about yourself are the only thing that reliably feels uncanny — the thing people screenshot.

---

## 1. What is on screen now, and why

Every failure below is visible in the screenshots and traced to its cause.

| What the user sees | Cause | Where |
|---|---|---|
| Six versions of one pattern: "translating empty hours into engineering problems", "treating empty hours as an engineering puzzle", "Converting empty hours into an engineering puzzle", "Turning free hours into an output equation", "turning unmanaged hours into an engineering puzzle", "turning open time into engineering problems" | Hypothesis identity is resolved by *evidence-entry containment within the same `patternType`* only. A rewording that cites a different entry, or lands in a different type (`protectiveLoop` vs `valuesConflict` vs `bodySignal`), mints a new id. Nothing compares meaning. | `functions/index.js:1207–1240` (`IDENTITY_OVERLAP`, `resolveHypothesisId`) |
| "19 patterns", 18 of them "Seen 1×" | `MAX_HYPOTHESES = 6` caps each *run*, not the total; nothing retires n=1 items except the 45-day decay. One-off observations are rendered with the same chrome as a pattern. | `functions/index.js:716`, `:744` |
| "1 entry" and "recurring" on the same card | Legacy docs default `scope` to `"recurring"` when the field is missing, and the UI trusts the field. | `functions/index.js:1750` |
| "A hunch · Not checked against other entries yet" on 17 of 19 cards | The counter-evidence pass audits only the top 2 hypotheses per run (`CE_MAX_HYPOTHESES = 2`); the UI then prints the *absence* of QA as a caption on everything else. | `functions/index.js:739`; `SelfModel.swift:104–110` |
| "What softens it" section full of cards labelled "RULE YOU MAY CARRY" | Exceptions are bucketed into `whatHelps` server-side, but the card label is derived from `patternType`, which for those items resolves to `.identityRule`. | `functions/index.js:1799–1800`; `MirrorView.swift:30` |
| First Sketch: "Your question for the next 7 days: *translating empty hours into engineering problems?*" | The question card appends "?" to whatever string it receives; the NBQ fallback passes a hypothesis title. | `FirstSketchView.swift:154–160` |
| First Sketch body cut mid-word: "maybe to fend o" | `String(prefix(120))` | `FirstSketchView.swift:23–35` |
| "Warding off the quiet terror of unstructured space", "the ledger of fairness against quietude", "letting the physical environment drop its armor", "Keeps the nervous system revved up" | The writer prompt bans metaphor and demands 8th-grade English, but nothing enforces it; the lint checks banned clinical terms only. "Nervous system" is not on the list. | `ai-prompts-verbatim §3.2`; `functions/index.js` `BANNED_SUBSTRINGS` |
| "What's shifting" with two arrows, from 7 entries | Trend requires a baseline; at n=7 the arrows are noise presented as signal. | `MirrorView.swift:104–145` |
| Four feedback buttons × 19 cards = 76 buttons on one screen | Feedback is attached to every hypothesis rather than to the one thing being asked about today. | `SelfModelView.swift` |
| Two label systems for the same items (Patterns: "PROTECTIVE LOOP / VALUES IN TENSION / BODY SIGNAL / EXCEPTION — WHAT HELPED"; My Mirror: "PROTECTIVE MOVE / RULE YOU MAY CARRY") plus a maturity ring ("Sprouting") | Internal ontology rendered as UI, twice, differently. | `MirrorView.swift:20–37`; `SelfModelView.swift` |

The one thing on screen that works is the "Story so far" paragraph — because it quotes the user: *"heavy sadness"*, *"lucky and loved"*, *"To get moving"*. Everything in v3 is built from that observation.

---

## 2. The research the design is built on

Each principle below names the finding it rests on. Where the popular paraphrase overstates, the accurate version is used.

**R1 — Insight comes from comparing data streams, not from prose about one entry.** Li, Dey & Forlizzi's stage model of personal informatics (CHI 2010) puts *integration* — combining data — before *reflection*, and shows barriers cascade: a reflection surface built on un-integrated data fails. Bentley et al. (ACM TOCHI 2013, "Health Mashups") computed correlations across sleep, steps, mood, calendar and weather and rendered only significant ones as sentences — "You are happier on days when you sleep more" — in a 90-day, 60-person study; relationships were highly individual, and the sentences supported self-understanding that led to focused behaviour change. Choe et al. (CHI 2014) found quantified-selfers' pitfalls were tracking too many things, not tracking context/triggers, and lacking rigour — and that they collect multiple streams precisely to find relationships.

**R2 — Generic statements feel accurate; that is the trap.** Forer (1949): 39 students rated an identical, horoscope-derived personality sketch 4.26/5 for accuracy. A Mirror line that could be about anyone will *feel* fine and teach nothing. The antidote is a specificity the user can check: a number, a date, their own words.

**R3 — One idea at a time.** Cowan (BBS 2001): short-term capacity is about four chunks when rehearsal is blocked. Xiao et al. (CHI 2020): one open question at a time elicited higher-quality responses than several presented together. Rosebud's interactive turn is one perspective plus one question; its "For You" slot is one item per day.

**R4 — Distance, don't immerse.** Kross, Ayduk & Mischel (Psych. Science 2005) and Kross & Ayduk (Adv. Exp. Soc. Psych. 2017): analysing a negative experience from a self-distanced perspective reduces emotional reactivity and rumination relative to an immersed one, and the effect persists. Design consequence: Mirror speaks in observations about days and words — "on the days you wrote…" — never in second-person character claims ("you are someone who…").

**R5 — Reflection without insight is rumination.** Grant, Franklin & Langford (2002, SRIS): self-reflection and insight are separable; reflection correlates with anxiety and stress, insight with lower psychopathology and better self-regulation. Nolen-Hoeksema, Wisco & Lyubomirsky (2008): rumination predicts onset of depression. Design consequence: Mirror never restates a negative and stops; every surfaced item ends in an exception, a comparison, or one forward question.

**R6 — Exceptions are the material.** Solution-focused brief therapy (de Shazer 1985/1988; Iveson 2002): "however serious, fixed or chronic the problem there are always exceptions and these exceptions contain the seeds of the client's own solution." A core early-SFBT technique, not the only one — but for a *passive* surface it is the safest high-value thing to say. Design consequence: when an exception and a problem compete for the day, the exception wins.

**R7 — Causal and insight language is the mechanism of expressive writing.** Pennebaker, Mayne & Francis (JPSP 1997): rising use of causal and insight words across writing days predicted improved *physical* health (not mental health, in that reanalysis). Design consequence: Mirror should make it easy to write a *because* — the callback question is always about a mechanism the user can see.

**R8 — Conversational reflection works when it references the user's actual data.** Kocielnik et al. (IMWUT 2018, "Reflection Companion"): daily mini-dialogues tied to the user's own activity graph increased awareness and produced concrete plans; generic follow-ups drew complaints. (Qualitative; the pre/post understanding change was p = .07.)

**R9 — Product evidence for thresholds.** WHOOP shows a behaviour's effect on recovery only after at least five "yes" and five "no" days within 90 days, as a percentage-point difference between yes-days and no-days. Exist.io needs about three weeks of data before showing a correlation, refreshes weekly, shows strength and confidence separately, and disclaims causation. Rosebud gates its in-depth weekly report at 1,500 words. All three tell the user how far they are from the next unlock.

---

## 3. Product principles for v3

1. **Facts first, interpretation last.** A number, a date or a verbatim phrase is always on screen before any sentence that interprets it. (R1, R2)
2. **A pattern is n ≥ 3 distinct entries with a contrast set.** Below that it is an observation, and observations are not shown as patterns. (R1, R9)
3. **One line a day. Silence is a valid line.** (R3)
4. **Observational voice.** "On the 4 evenings you wrote about work…" — never "you are", "you always", "you tend to". (R4)
5. **Never end on the negative.** Every item closes with an exception, a comparison, or one question. (R5, R6, R7)
6. **Exceptions outrank problems.** (R6)
7. **Tell the user what would unlock the next thing.** "2 more evening entries and Spilr can compare your mornings and evenings." (R9)
8. **The user holds the eraser, with two taps.** Correction is on the one item being asked about, not on every card. (Rosebud Learned Preferences; existing `ProfileCorrection`)
9. **The model phrases; it does not decide.** Selection, thresholds, dedup, and lint are code. (engineering doc §3)

---

## 4. Data model: three tiers

### Tier 0 — Facts (no model; computed from what already exists)

| Fact | Source | Already captured? |
|---|---|---|
| Entry timestamp → weekday, time-of-day band (morning / afternoon / evening / late) | `entries.createdAt` | yes |
| Word count, entry mode (blank / chat-woven / template / voice) | `entries` | yes (mode: verify field) |
| Explicit emotion words the user typed | `EntryAnalysis.explicitEmotions` | yes |
| People named, with role | `EntryAnalysis.relationshipRoles[{person, role}]` | yes |
| Life domains | `EntryAnalysis.lifeDomains` | yes |
| Distinctive phrases | `EntryAnalysis.phrasesToTrack` | yes |
| Body signals | `EntryAnalysis.bodySignals` | yes |
| Episodes (situation → emotion → outcome) | `EntryAnalysis.episodes[]` | yes |
| Mood chip (if logged) | `moodLogs` | yes, sparse |
| Template before/after intensity (CBT thought record) | prototype's `before`/`after` scale steps | **new field** `entries.templateDeltas{before, after}` |
| Chat session: mode, turns, duration | `chatSessions` | yes |
| Unlock progress counters (entries by band, days with contrast) | derived | **new** |

Everything in this tier is stored on a per-user derived doc `users/{uid}/derived/facts` recomputed nightly from `entryAnalyses` (server) — the engineering doc's §5.4 replacement for the on-device `MemoryProfile`.

### Tier 1 — Observations (deterministic statistics)

An observation is a *comparison* between two sets of entries. Types, with the minimum data each needs (30-day rolling window unless stated):

| Type | Shape | Minimum |
|---|---|---|
| **Co-occurrence** | "On the {n} days you wrote about {A}, '{B}' appeared in {k}. On the other {m} days: {j}." | n ≥ 3, m ≥ 3, lift ≥ 1.5 |
| **Time band** | "{k} of your {n} entries with '{phrase}' were written after 9pm." | n ≥ 3, k/n ≥ 0.67 |
| **Weekday** | "Sunday entries are {x}% longer than the rest." | ≥ 3 Sundays, ≥ 6 other days |
| **Lag** | "The day after you write about {person}, entries are {x}% shorter." | ≥ 3 lag pairs |
| **Callback (then / now)** | "{date}: '{quote A}'. Today: '{quote B}'. {N} days apart." | same `phrasesToTrack` or same person + same emotion, ≥ 14 days apart |
| **Exception** | "{date} is the only day this month you wrote about {A} without '{B}'." | the co-occurrence exists (n ≥ 3) and exactly 1–2 exceptions |
| **Delta** | "Thought record: {before} → {after}. That's your {k}th drop in a row." | template entries with both scales |
| **Streak / first / last** | "First time 'calm' has appeared since 12 Aug." | phrase history ≥ 2 |

Rules:

- Computed nightly, server-side, zero model tokens. Templated natural language; the model is not involved.
- Every observation stores `{type, n, m, k, j, lift, entryIds[], contrastEntryIds[], quotes[], computedAt, window}` at `users/{uid}/observations/{id}` — client read-only.
- Ranked by a deterministic `ObservationScore = lift × log(n) × recency × novelty × exceptionBonus − shownPenalty`, where `novelty` is Jaccard distance from anything shown in the last 14 days and `exceptionBonus` = 1.5 for exception/delta types (R6).
- Correlation ≠ cause: the copy never says "because"; the *user* is invited to (R7).

### Tier 2 — Readings (the only model call)

A reading is one sentence the model writes **on top of one observation** — the Line from the earlier blueprint, now with a guaranteed factual base.

- Input: one observation (numbers + quotes), the user's `LifeContext`, `StylePreferences`. Not the raw entries, not the hypothesis list.
- Output: `{line ≤ 140 chars, move ∈ {TENSION, UNDERNEATH, ABSENCE, REFRAME, PATTERN}, question?}`.
- Lint (code): length; ≤ 1 hedge; contains a quote from the observation; Flesch-Kincaid grade ≤ 8; no metaphor list hits (`armor`, `terror`, `ledger`, `landscape`, `journey`, `navigate`, `hold space`, `nervous system`…); no trait grammar (`you are (a|someone)`, `you always`, `you tend`); banned clinical list. Any failure → show the observation alone. The observation is already a good line.
- At most one reading per day; none if no observation clears the floor.

### Tier 3 — Threads (the Self Model, made legible)

A thread is a reading that has **recurred** — the same observation type over the same terms on ≥ 3 distinct entries with a contrast set — **and passed the counter-evidence audit**, or that the user confirmed. Cap: **3 active threads**. Everything else stays in the store as an observation.

- Identity: `sha(type + sorted terms)` for observations; for model-worded hypotheses, an embedding (`gemini-embedding-001`) with cosine ≥ 0.82 across *all* `patternType`s, then evidence-containment as a second key. Merge = union of evidence, `timesSeen` = distinct entries. This alone collapses the six "empty hours" variants into one thread with n = 9.
- Labels: derived from `timesSeen` and audit state only. `once` (1) · `twice` (2) · `recurring` (≥ 3) · `confirmed` (user). Delete the `scope || "recurring"` fallback. The phrase "not checked against other entries yet" is never shown; unaudited items are not shown.
- Retirement: 45-day decay stays; also retire any thread the user marks "Not quite" twice.

---

## 5. Surfaces

### 5.1 The Mirror tab (one scroll, four things)

```
Mirror
─────────────────────────────────────────
TODAY                                            ← §5.2
  'She'd do it for me' is the third yes this month
  written on a day you were already behind.
  ┌ "Said yes to covering Priya's shift again…" · 2 days ago
  [That's me]  [Not quite]  more…

THIS WEEK, IN YOUR WORDS                          ← §5.3
  4 entries · 3 after 9pm
  'heavy' — 3 times, all on work days
  Priya 2 · Dan 1

THREADS (3)                                       ← §5.4
  Empty hours become projects          n 9 · since 3 Aug · ●●○●●●○●●
  Yes before the report is done        n 4 · since 21 Aug · ○●○○●●
  Heavy days you let land              n 3 · since 30 Aug · exception ✓

Your weekly letter · Sunday                       ← §5.5
Your profile · what Spilr thinks it knows         ← §5.6
```

Removed from the tab: the Patterns list, the "Go deeper" rows with counts, the maturity ring, "What's shifting" until n ≥ 14 with a baseline, the subtitle, the First Sketch banner after first open.

### 5.2 Today

One card. Content is chosen by code in this order:

1. An **exception** or **delta** observation, if one is new today (R6).
2. A **callback** observation, if today's entry echoes an older one (this is the "it remembers" moment Rosebud users praise and Spilr's provenance makes exact).
3. The top-scoring observation with a reading, if the reading passes lint.
4. The top-scoring observation alone.
5. **Silence**: "Nothing new to show today. {unlock hint}." plus one Mirror Seed question.

Anatomy: the line (≤ 140 chars, editorial ~20pt), one receipt (quote + relative date), two taps. "more…" opens the proof sheet: the numbers behind it (n, m, k, j as a two-row comparison), up to 3 quotes with dates, the exception if any, the counter-evidence if any, "Ask Spilr about this" (Daily Chat with `seedContext`), and "Teach Spilr" (free text → `ProfileCorrection`).

Feedback semantics: **That's me** → `thisIsMe` on the underlying observation/thread. **Not quite** → `almost`; twice on the same thread retires it; also writes `StylePreferences.sharpness -= 1` if the user picks "too much" in the follow-up chip row (Too much · Wrong · Already knew).

### 5.3 This week, in your words

Three Tier-0 facts, no model, always available from the first entry. Chosen by a fixed rotation so the strip is never empty: cadence (entries, time band), the most-repeated emotion word with its count and where it clustered, the people count. Each row taps through to the entries it counts. On a week with one entry it says so: "1 entry · Tuesday, late. Two more and Spilr can compare days."

### 5.4 Threads

Maximum three rows. Each: a plain-English title rewritten from the hypothesis in the observational voice (lint-enforced, ≤ 45 chars), `n` distinct entries, first-seen date, a 30-day dot strip (one dot per day; filled = the thread appeared), and — when an exception exists — "softened {date}". No type label, no lifecycle chip, no confidence caption, no buttons. Tap → the same proof sheet as Today, with the two taps at the bottom.

Why the dot strip: it is the single most information-dense, least interpretive element available. It shows recurrence *and* exceptions at a glance, it is the user's own calendar, and it is what makes "n 9" credible.

### 5.5 Weekly letter (Sunday, notified)

Replaces "The story so far" with a dated artefact, ≤ 80 words: the week's dominant word and the day it broke, one observation with its numbers, one question. Quotes only; no interpretation beyond the observation. Archived, so a user can read last month's letters — this is the Rosebud weekly report, in Spilr's register. Delivered only when the week has ≥ 3 entries; otherwise the notification is the unlock hint.

### 5.6 Your profile

The Self Model, visible on demand only. Sections renamed in plain English: **What you do when it gets hard** (protective strategies), **Rules you seem to run on** (core rules), **What helps** (exceptions), **People and the part you play** (relationship roles), **Your words** (vocabulary). Each item is a thread-style row; the four-button row is gone; tap → proof sheet with the two taps. Items shown only if `timesSeen ≥ 3` and audited, or user-confirmed. At 7 entries most sections are empty, and the empty state says what would fill them.

### 5.7 Your first seven (replaces First Sketch)

Fires once at 7 entries. Three Tier-0 facts with real numbers ("1,140 words in 7 days", "'lucky' — 3 times, every time after 8pm", "3 people, one of them in 5 entries"), one thread *if* one has reached n ≥ 3 (else the strongest observation, labelled as such), and one question generated by NBQ **only if it ends in a question mark and contains no hypothesis title**; otherwise the card is omitted. No truncation: text wraps.

---

## 6. Copy contract (enforced in code, not asked of the model)

| Rule | Check |
|---|---|
| Contains a number, a date, or a quoted phrase from the user | regex + quote match against observation |
| ≤ 140 chars (Today), ≤ 45 chars (thread title), ≤ 80 words (letter) | length |
| Observational voice | reject `you are (a|an|someone)`, `you always`, `you never`, `you tend`, `your (need|inability|fear)` |
| ≤ 1 hedge | count of may/might/seems/perhaps |
| Reading level | Flesch-Kincaid grade ≤ 8 |
| No metaphor | word list (`armor`, `terror`, `ledger`, `landscape`, `journey`, `navigate`, `space` as noun, `hold`, `nervous system`, `revved`, `warding`) — extend from lint-reject logs |
| No clinical or pop-psych label | existing `BANNED_SUBSTRINGS` + `BANNED_LABELS` |
| Never ends on the negative | last clause must be an exception, a comparison, or a question |
| Sentence case | existing `sentenceCased` — fixes the mixed-case titles |

A line that fails any check is not softened and retried; the observation is shown alone. The lint log (rule, term, prompt version) is the prompt-quality dashboard.

---

## 7. What the user sees at each stage (the unlock ladder)

| Entries | Available | The unlock hint shown until then |
|---|---|---|
| 1 | This week, in your words (1 row) · Today = seed question | "Two more entries and Spilr can compare days." |
| 3 | Time-band and co-occurrence observations if contrast exists · Today = observation | "One more evening entry and Spilr can compare your mornings and evenings." |
| 7 | Your first seven · first callback possible · reading with lint | "Three more and a thread can form." |
| 10 | First thread (n ≥ 3 with contrast + audit) · weekly letter | — |
| 14 | Lag observations · "What's shifting" with a baseline | — |
| 30 | Monthly letter · profile sections populate | — |

For the account in the screenshots (7 entries, one day of writing for most): the correct v3 state is **one reading or observation today, three fact rows, zero threads** ("None yet — threads need the same thing on three different days"), and no Patterns list at all. That is not less product; it is the first honest state, and honesty at n = 7 is what earns belief at n = 30.

---

## 8. Pipeline changes (server, nightly)

```
entryAnalyses (existing)
  → FactsJob        deterministic  → derived/facts
  → ObservationsJob deterministic  → observations/*  (types in §4, thresholds enforced here)
  → DedupJob        embeddings     → merge hypotheses across types; timesSeen = distinct entries
  → AuditJob        LLM (CE)       → only for candidates that could become threads (n ≥ 3); cap 3/run
  → ReadingJob      LLM (1 line)   → for the top observation only; lint; else observation-only
  → LetterJob       LLM (≤ 80 w)   → Sundays, weeks with ≥ 3 entries
```

The miner (`mineHypothesesForUser`) keeps running but its input becomes **observations, not raw analyses** — it names and interprets structures the statistics already found, so it cannot invent a pattern from one entry. `MAX_HYPOTHESES` becomes irrelevant: the cap is three active threads.

Cost: Tier 0/1 are free. Tier 2 is one ~200-token call per active user per day plus the weekly letter, and the audit runs only on thread candidates. This is strictly less than today's per-hypothesis deck writer.

---

## 9. Requirements list

**Must (v3.0)**

- M1 Observations job with the eight types and thresholds in §4; stored client-read-only.
- M2 Embedding-based hypothesis identity across all types; merge with `timesSeen` = distinct entries; delete `scope || "recurring"`.
- M3 Threads capped at 3; shown only when n ≥ 3 + contrast + audit, or user-confirmed; labels derived from counts.
- M4 Today card with the 5-step selection order; silence state with unlock hint; two-tap feedback; proof sheet.
- M5 "This week, in your words" strip from Tier 0.
- M6 Copy lint (§6) applied to readings, thread titles, letters, and First-seven text; lint-reject logging.
- M7 Remove: Patterns list, Go-deeper counted rows, maturity ring, four-button rows, "A hunch / Not checked" captions, "What's shifting" below n = 14.
- M8 First seven: facts + at most one thread + NBQ question only if it is a question; no truncation.
- M9 Unlock hints at every threshold in §7.

**Should (v3.1)**

- S1 Weekly letter with archive and push.
- S2 Profile sections renamed and gated per §5.6.
- S3 Template deltas captured as a Tier-0 fact (CBT thought record before/after); Delta observation type live.
- S4 Callback observation using `phrasesToTrack` + people; Then/Now proof layout.

**Could (later)**

- C1 Opt-in HealthKit sleep as a Tier-0 stream — the single addition that would make Health-Mashups-grade observations ("on nights under 6h, 'heavy' appears 3× more") possible.
- C2 Monthly letter at 30 entries.

---

## 10. Metrics

Per surface: shown → expanded (proof) rate; That's-me rate; Not-quite rate and its follow-up split (Too much / Wrong / Already knew); time on Today card (target median < 8s); silence-day rate (healthy 15–35%); lint-reject histogram by rule; thread count per user over time (target: reaches 1 by entry 10 for ≥ 60% of users); 14-day repeat rate of Today lines (target < 5%); weekly-letter open rate.

The single success metric: **That's-me rate rises while time-on-card falls.** A mirror that is right and quick is the one people keep opening.

---

## 11. Sequence

1. **Week 1 — subtraction and bug fixes.** M7, M8, the `scope` fallback, the label mapping, truncation. Cap the Patterns list at threads with n ≥ 3 (it will show zero for most users; that is correct). Ship.
2. **Week 2 — Tier 0 and the strip.** FactsJob + M5 + unlock hints (M9). The tab now has true numbers on it from entry one.
3. **Week 3 — Tier 1.** ObservationsJob with co-occurrence, time-band, exception, streak types; Today selects from observations (M4 without readings).
4. **Week 4 — identity and threads.** M2, M3, audit gating.
5. **Week 5 — readings and lint.** M6; the model's one sentence a day; proof sheet complete.
6. **Week 6 — letter, callback, deltas.** S1, S3, S4.

---

## Sources

Li, Dey & Forlizzi, "A stage-based model of personal informatics systems," CHI 2010 — https://www.ianli.com/publications/2010-ianli-chi-stage-based-model.pdf
Bentley et al., "Health Mashups: Presenting statistical patterns between wellbeing data and context in natural language to promote behavior change," ACM TOCHI 20(5), 2013 — https://frankbentley.com/wp-content/uploads/2021/12/a30-bentley.pdf
Choe, Lee, Lee, Pratt & Kientz, "Understanding quantified-selfers' practices in collecting and exploring personal data," CHI 2014 — https://depts.washington.edu/chilllab/research/quantified-self/
Kocielnik, Xiao, Avrahami & Hsieh, "Reflection Companion," IMWUT 2(2), 2018 — https://faculty.washington.edu/garyhs/docs/kocielnik-UBICOMP2018-reflection.pdf
Forer, "The fallacy of personal validation," J. Abnormal & Social Psychology 44(1), 1949 — https://www.oxfordreference.com/display/10.1093/oi/authority.20110810104425651
Cowan, "The magical number 4 in short-term memory," BBS 24(1), 2001 — https://www.cambridge.org/core/journals/behavioral-and-brain-sciences/article/magical-number-4-in-shortterm-memory-a-reconsideration-of-mental-storage-capacity/44023F1147D4A1D44BDC0AD226838496
Xiao et al., "Tell me about yourself," CHI 2020 — https://research.ibm.com/publications/tell-me-about-yourself
Kross, Ayduk & Mischel, "When asking 'why' does not hurt," Psychological Science 16(9), 2005; Kross & Ayduk, "Self-distancing: Theory, research, and current directions," Adv. Exp. Soc. Psych. 55, 2017 — https://www.sciencedirect.com/science/article/pii/S0065260116300338
Grant, Franklin & Langford, "The Self-Reflection and Insight Scale," Social Behavior and Personality 30(8), 2002 — https://www.sbp-journal.com/index.php/sbp/article/view/1219
Nolen-Hoeksema, Wisco & Lyubomirsky, "Rethinking rumination," Perspectives on Psychological Science 3(5), 2008 — https://drsonja.net/wp-content/themes/drsonja/papers/NWL2008.pdf
Iveson, "Solution-focused brief therapy," Advances in Psychiatric Treatment 8(2), 2002 (on de Shazer 1985/1988) — https://www.cambridge.org/core/journals/advances-in-psychiatric-treatment/article/solutionfocused-brief-therapy/B8198B18DDEE77F9D39A09FDBCC0CE15
Pennebaker, Mayne & Francis, "Linguistic predictors of adaptive bereavement," JPSP 72(4), 1997
Baumer, "Reflective informatics," CHI 2015 — https://ericbaumer.com/2015/06/08/reflective-informatics-conceptual-dimensions-for-designing-technologies-of-reflection/
WHOOP Journal thresholds — https://support.whoop.com/hc/en-us/articles/360040883074 ; Exist.io correlations — https://kb.exist.io/article/18-how-long-does-it-take-to-find-correlations ; Rosebud weekly report — https://help.rosebud.app/ai-analysis/weekly-report
Spilr code: `functions/index.js` (lines cited inline), `Mirror/MirrorView.swift`, `Mirror/SelfModel.swift`, `Mirror/SelfModelView.swift`, `Mirror/FirstSketchView.swift`.
