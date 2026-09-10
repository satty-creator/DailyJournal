# Spilr Mirror — Implementation Plan

**Status:** Proposed (planning only — no code written yet)
**Author:** drafted 2026-06-15 · **rev 2** adds the Self Model layer (§§1.1, 2.5–2.9, 3.x, Phases 8–11, §10)
**Decision inputs:** Deliverable = phased engineering plan. Migration = **replace / rebrand** (Patterns → Mirror, Today's Read → Today's Mirror). Positioning = self-reflection & pattern recognition, **not** diagnosis, treatment, or therapy.

> **rev 2 — the next leap.** The rev-1 pipeline (entry → signals → patterns → mirror card) still only *builds insights*. It does not maintain a coherent, living, **correctable** model of the person. Rev 2 adds a brain layer — the **Self Model** — and closes the loop: *entry → signals → episodes → patterns → Self Model → mirror card → user correction → Self Model updates.* The Self Model is not a diagnosis or a personality label; it is "what Spilr is learning about how I operate," with evidence, counter-evidence, a confidence lifecycle, and the user holding the eraser.

---

## 0. The core finding

The product does **not** need a greenfield rebuild. The current codebase already contains working prototypes of almost every piece the Mirror Engine spec calls for. The work is mostly **unify + extend + rebrand**, plus three genuinely new things (a persisted per-entry analysis object, a richer pattern hypothesis, and at-rest encryption).

| Spec concept | What already exists today | Gap to close |
|---|---|---|
| Entry analysis JSON (Prompt A) | `AIService.generateInsights` (bullets/question/sentiment), `extractEcho` → `EchoExtractionResult`, `extractRiverMarkSignals` → `RiverMarkSignals` | These are **three separate, partly-discarded** extractions. Unify into one persisted `EntryAnalysis` doc. |
| Pattern hypothesis | `PatternCallback` (archetype, evidence[], confidence, salienceScore, status, feedback) | Extend: add protection / cost / counter-evidence / novelty / emotional-weight / tiny-experiment / callback-question. |
| Pattern mining (Prompt B) | `AIService.detectPatterns` (60-day window, 6 archetypes, dedup, salience) | Feed it structured `EntryAnalysis` instead of raw text; add co-occurrence / sequence / lag / exception mining. |
| Today's Mirror card (Prompt D) | `generateDailyReads` Cloud Fn (Stage-1 generator) + `DailyRead` + `TodayReadCardView` | Rebrand; expand the read into the 5-part structure (pattern/protection/cost/evidence/experiment). |
| Evidence drawer ("show me the proof") | `DailyRead.sourceEntryIds`, `receiptChips`, `sourcePatternIds` already traced | Build the drawer UI; surface counts, first-seen, exception days, confidence. |
| Insight feedback loop | `ReadFeedback` / `ReadRejectionCode` + `ReadSettings` recalibration engine (was removed from the card UI on 2026-06-09, engine intact) | Re-add the buttons as "This is me / Almost / Not me / Too intense / Show proof / Ask tomorrow". |
| Mirror Seeds | `SpillWriteView` prompt chips + `HintLadder` starters | Replace chips with the 8 psychological seed lenses. |
| Safety reviewer (Prompt E) | `generateDailyReads` Stage-2 quality guard (temp 0.0, rejects if any score < 4 or safety ≠ none) + `PatternSafety.corpusHasCrisisSignal` hard gate | Extend the guard's reject criteria to the spec's full list (diagnosis, certainty, shame, trauma-inference, medical advice). |
| Memory / pattern graph | `MemoryProfile` (themes, entities, emotional vocab, coping, cadence) in UserDefaults | Promote to a durable, Firestore-backed graph that accumulates the signals from `EntryAnalysis`. |
| Navigation | Today / Journal / River / **Patterns** | Rename Patterns → **Mirror**; add Blind Spots / Loops / Exceptions / First Mirror sections. |
| At-rest encryption | **None** — `JournalEntry.content` is stored as plaintext in Firestore | New. Highest-priority trust/compliance gap. |
| **Self Model** (rev 2) | `MemoryProfile` is a flat signal warehouse, recomputed from scratch | **Genuinely new — the brain layer.** A versioned, evidence-backed, user-correctable model of core rules, protective strategies, inner parts, values, contradictions, relationship roles, vocabulary, and what-helps. |
| **EpisodeFrame** (rev 2) | Each entry is treated as one emotional event | New. Split an entry into multiple episodes so complexity isn't flattened. |
| **LifeContext / known facts** (rev 2) | None — AI reads entries with no stable grounding | New, optional, skippable onboarding (season, likely people, focus, no-go topics) stored apart from entries. |
| **Profile correction ("Teach Spilr")** (rev 2) | `ReadFeedback` rates a card | New. Structured correction that edits the Self Model, not just the card. |

**Architectural fit:** every AI call already routes through `AIService.generate` → `geminiProxy` (Firebase-token auth, JSON-only responses), every call injects `NinetyVoice.system` + `MemoryProfileService.cachedPromptContext()`, and every feature has a local fallback. The Mirror Engine slots cleanly into this pattern. Keep all four invariants from `CLAUDE.md`: local-first, fire-and-forget writes, one-thing-at-a-time surfacing, AI never blocks.

---

## 1. Target architecture (the pipeline)

```
Spill saved (JournalService, fire-and-forget)
   │
   ├─▶ Step 1  Ingest + ENCRYPT raw text at rest                [NEW: EntryCrypto]
   │
   ├─▶ Step 2  Per-entry extraction (Prompt A)  → EntryAnalysis  [UNIFY: AIService.analyzeEntry]
   │            replaces generateInsights + extractEcho + extractRiverMarkSignals
   │            persisted to users/{uid}/entryAnalyses/{entryId}
   │
   ├─▶ Step 3  Mirror Graph update                              [EXTEND: MirrorGraphService]
   │            accumulate emotions, needs, strategies, body signals,
   │            avoidance markers, values conflicts, exceptions, tracked phrases
   │
   ├─▶ Step 4  Pattern mining (Prompt B, daily, server)         [EXTEND: detectPatterns]
   │            recurrence · co-occurrence · sequence · contrast · lag · exception
   │            → PatternHypothesis  (users/{uid}/patternHypotheses/{id})
   │
   ├─▶ Step 5  Insight generation (Prompts C + D)               [EXTEND: generateDailyReads]
   │            gated by entry-count maturity (1/3/7/14/30/90)
   │            Mirror Score ranks candidates; only the top passes
   │
   └─▶ Step 6  Safety + claims review (Prompt E)                [EXTEND: Stage-2 guard]
                deterministic crisis gate (PatternSafety) ALWAYS runs first
                then LLM claims-review; rejects → safer_version or suppress
```

**Maturity gates** (spec §5) become a single `MirrorMaturity` helper read off `MemoryProfile.cadence.totalEntries`:

| Entries | Surface |
|---|---|
| 1 | Today's Mirror (light, single-entry read) |
| 3 | Soft pattern (low-confidence hypothesis, hedged) |
| 7 | **First Mirror** unlock ceremony |
| 14 | Deeper pattern |
| 30 | Monthly Mirror |
| 90 | Identity / rhythm insights |

### 1.1 The rev-2 pipeline (with the Self Model loop)

```
Spill saved
   │
   ├─▶ Step 1  Ingest + ENCRYPT raw text                         [EntryCrypto]
   │
   ├─▶ Step 2a EntryAnalysis (Prompt A)                          [AIService.analyzeEntry]
   ├─▶ Step 2b EpisodeFrame split (Prompt A2 / same call)        [NEW]
   │            one entry → 1..n episodes (situation, emotion, body,
   │            strategy, need, outcome) so complexity isn't flattened
   │
   ├─▶ Step 3  Pattern mining over episodes (Prompt B)           [detectPatterns, extended]
   │
   ├─▶ Step 4  SELF MODEL UPDATE (Prompt SM-1)                   [NEW: SelfModelService]
   │            folds analyses + episodes + patterns + corrections
   │            into a versioned, evidence-backed person model;
   │            every hypothesis carries scope + stability + lifecycle
   │
   ├─▶ Step 5  Retrieve relevant past entries (semantic)         [NEW: MirrorRetrieval]
   │            similar · contradictory · first-seen · most-intense ·
   │            most-recent · exception-day  → grounds the insight
   │
   ├─▶ Step 6  Insight candidate (Prompts C + D / Profile-Mirror)
   │            ranked by Mirror Score; gated by maturity
   │
   ├─▶ Step 7  COUNTER-EVIDENCE pass (Prompt CE) — MANDATORY     [NEW]
   │            "what would make this untrue?" → weaken/reword
   │
   ├─▶ Step 8  Safety + claims review (Prompt E)                 [Stage-2 guard, extended]
   │
   ├─▶ Step 9  Mirror card / Self Model card shown
   │
   └─▶ Step 10 USER CORRECTION ("Teach Spilr")                   [NEW]
                "missing something" → structured correction →
                back to Step 4 (corrections outrank AI inference)
```

The two loops that make it a *living* model: corrections feed back into the Self Model (Step 10 → 4), and the Next-Best-Question engine (Prompt NBQ) reads unresolved Self Model hypotheses to choose tomorrow's seed — so the app asks the question most likely to confirm, reject, or deepen what it's tentatively learning.

---

## 2. New & changed data models

### 2.1 `EntryAnalysis` (NEW) — `DailyJournal/Mirror/EntryAnalysis.swift`
Persisted Codable struct, Firestore `users/{uid}/entryAnalyses/{entryId}`. Mirrors Prompt A's schema: `surfaceSummary`, `lifeDomains[]`, `explicitEmotions[]`, `inferredEmotions[{emotion, confidence, evidenceQuote}]`, `needs[]`, `protectiveStrategies[{strategy, protectsAgainst, confidence, evidence}]`, `avoidanceMarkers[{type, phrase, function}]`, `cognitivePatterns[]`, `valuesPresent[]`, `valuesConflict[]`, `bodySignals[]`, `relationshipRoles[]`, `openLoops[]`, `phrasesToTrack[]`, `possibleTinyAct`, `safetyFlags{...}`. Confidence on every inference.
*Why new:* today the three extractions overlap and most of their output is thrown away after rendering. This is the canonical signal record everything downstream reads.

### 2.2 `PatternHypothesis` (EXTEND `PatternCallback`) — `DailyJournal/Pattern/`
Keep: `id, userId, archetype, evidence[], status, salienceScore, feedback`. Add: `patternType` (protective_loop / avoided_subject / identity_rule / relationship_role / body_signal / values_conflict / exception / time_rhythm / vocabulary_fingerprint), `userFacingTitle`, `coreHypothesis`, `protection` (why it makes sense), `cost` (what it quietly takes), `counterEvidence[]`, `noveltyScore`, `emotionalWeight`, `actionabilityScore`, `shameRisk`, `diagnosticRisk`, `tinyExperiment`, `callbackQuestion`, `firstSeenAt`, `timesSeen`. Firestore `users/{uid}/patternHypotheses/{id}` (rename collection or alias the existing `patternCallbacks`).

### 2.3 `MirrorCard` (EXTEND `DailyRead`) — `DailyJournal/Mirror/`
Keep all `DailyRead` fields + the per-day doc-id pattern (`users/{uid}/mirrors/{yyyy-MM-dd}`). Add the 5-part body: `headline`, `mirrorSentence`, `whyThisCameUp`, `patternName`, `receipts[{quote, whyItMatters}]`, `possibleRead`, `tinyExperiment`, `tomorrowCallbackQuestion`, `shareSafeSummary`, `confidence`. Keep `ReadFeedback`/`ReadRejectionCode` and remap to the new button set.

### 2.4 `MirrorGraph` (PROMOTE `MemoryProfile`) — the raw accumulator
Today `MemoryProfile` lives in UserDefaults and is recomputed from scratch. Promote to a Firestore-backed accumulator (`users/{uid}/mirrorGraph/current`) that folds in each `EntryAnalysis`: recurring emotions, repeated phrases, recurring people, triggers, coping strategies, body signals, values conflicts, unresolved loops, tiny acts attempted, **and exceptions where the loop broke**. Keep `cachedPromptContext()` as the synchronous prompt-injection read so no AI call site changes.
*Rev-2 clarification:* the MirrorGraph stays the **signal warehouse** (counts, frequencies, raw co-occurrences). The **Self Model (2.6) is the coherent, interpreted layer above it** — the warehouse holds the bricks, the Self Model is the house. Insights are written from the Self Model; the graph feeds it.

### 2.5 `EpisodeFrame` (NEW) — `DailyJournal/Mirror/EpisodeFrame.swift`
A single entry often contains several emotional moments ("work was stressful → dinner felt better → spiralled about tomorrow" = three episodes). Persisted as `users/{uid}/entryAnalyses/{entryId}.episodes[]` (sub-array, no extra doc). Each: `episodeId`, `situation`, `emotion[]`, `bodySignal[]`, `protectiveStrategy`, `need`, `outcome`. Pattern mining and the Self Model operate on **episodes**, not whole entries — this is what keeps the app from flattening a mixed day into one mood.

### 2.6 `SelfModel` (NEW) — the brain — `DailyJournal/Mirror/SelfModel.swift`
Versioned Codable doc at `users/{uid}/selfModel/current` (with `version` + `updated_at`; keep a short version history for audit/rollback). Sections, each an array of evidence-backed, revisable hypotheses:
`coreRules[]` (hidden if/then beliefs — "rest has to be earned"), `protectiveStrategies[{strategy, protectsAgainst, shortTermBenefit, possibleCost, confidence}]`, `innerParts[{name, description, commonTriggers[], commonLanguage[], confidence}]`, `values[]`, `contradictions[]` (wants calm → chooses stimulation), `whatHelps[]` (levers, **not only problems**), `relationshipRoles[]` (per-context: with family = peacekeeper, with work = fixer), `vocabulary[]` (word → personal meaning: "reset" = shame + control).
Each hypothesis carries: `id`, `title`, `hypothesis`, `confidence`, `evidenceEntryIds[]`, `counterEvidenceEntryIds[]`, `userStatus` (unrated / this_is_me / half_true / not_me), the **scope/stability/lifecycle** fields (2.9), and `lastTestedAt`. Plus a top-level `profileMaturity` block and a hard `doNotInfer: ["diagnosis","trauma_origin","attachment_style"]` guard echoed into every prompt.

### 2.7 `LifeContext` / known facts (NEW) — `users/{uid}/lifeContext`
Optional, skippable, privacy-sensitive onboarding stored **separately from journal entries**: `currentSeason` (student / building career / burned out / healing / new parent / between things), `primaryFocus[]`, `peopleLikelyToAppear[]`, `sensitiveTopicsDisabled[]` (the AI must not analyze these), `preferredDepth`. Grounds inference ("mum texted again" ≠ relationship stress if mum texts daily) without making onboarding heavy. Honored by every extraction/mining/insight prompt; `sensitiveTopicsDisabled` is enforced deterministically, not just asked of the model.

### 2.8 `ProfileCorrection` (NEW) — structured training data
Emitted by the "Teach Spilr" flow (Phase 10). Beyond card-level `ReadFeedback`, captures: `feedbackType` (this_is_me / half_true / not_me / missing_context), `patternId`/`hypothesisId`, `userCorrection` (free text), `correctionCategory` (e.g. guilt / control / fear-of-wasting-time / disappointing-someone), `shouldUpdateSelfModel`. Stored at `users/{uid}/profileCorrections/{id}` and fed into the Self Model updater as **higher-priority truth than AI inference** (PI-010).

### 2.9 Scope / stability / lifecycle (applies to every hypothesis in 2.2 & 2.6)
The single biggest over-claim risk is the AI seeing 7 tired entries and concluding "you are a tired person." Mandatory fields separate **state** from **trait** from **season** from **identity**:
- `scope`: `today` / `this_week` / `this_month` / `recurring` / `user_confirmed`
- `stability`: `temporary` / `emerging` / `stable` / `retired`
- `lastSeenAt`, `decayAfterDays` (default 45 — unconfirmed hypotheses fade)
- lifecycle: `observed_once → emerging → recurring → user_confirmed → weakened → retired`, with `timesSeen`, `userConfirmations`, `userRejections`, `counterexamples`.
User-facing language is bound to scope: never "you are someone who avoids conflict" (identity) but "*this week*, conflict often appears indirectly — that may be temporary, or worth watching" (state).

---

## 3. Prompt work

All five prompts ship in the existing prompt-assembly style: prefixed with `NinetyVoice.system`, suffixed with `cachedPromptContext()`, `responseMimeType: application/json`, parsed by `parseGeminiResponse`. Version each with a `PROMPT_VERSION` bump (`mirror-extract-v1`, `mirror-mine-v1`, `mirror-blindspot-v1`, `mirror-write-v1`, `mirror-guard-v1`).

| Prompt | Where it runs | Replaces / extends | Temp |
|---|---|---|---|
| **A** Entry extraction | Client, on save (`AIService.analyzeEntry`) | `generateInsights` + `extractEcho` + `extractRiverMarkSignals` | 0.2 |
| **B** Pattern mining | Server, daily (`functions/index.js`) | `detectPatterns` logic, now over `EntryAnalysis` | 0.3 |
| **C** Blind-spot detector | Server, daily | NEW — the highest-value prompt | 0.3 |
| **D** Mirror writer | Server, daily | `generateDailyReads` Stage-1 generator | 0.6 |
| **E** Safety + claims reviewer | Server, daily, last | `generateDailyReads` Stage-2 guard | 0.0 |

The spec's prompt bodies (§10 A–E) are production-ready; lift them verbatim, keeping the existing JSON-only + careful-language ("may/might/seems") constraints already present in `NinetyVoice.system`.

### 3.1 Rev-2 prompts (the Self Model loop)

| Prompt | Where | Role | Temp |
|---|---|---|---|
| **A2** Episode split | Client, same call as A | Split entry into `EpisodeFrame[]` | 0.2 |
| **SM-1** Self Model updater | Server, daily after mining | Folds analyses + episodes + patterns + **corrections** into the Self Model; returns `profile_updates[]` with `operation` (add/strengthen/weaken/retire/no_change), `scope`, `confidence_delta`, evidence + counter-evidence, `user_visible_summary`; also emits `next_best_question`. Rules: prefer "emerging pattern" over fixed identity; every strong hypothesis needs counter-evidence or an explicit note that none was found; **preserve user corrections over model guesses**; no trauma/disorder/attachment/childhood inference. | 0.3 |
| **NBQ** Next Best Question | Server / client | Picks tomorrow's seed to confirm/reject/deepen an unresolved hypothesis. Answerable in 90s, never clinical, never interrogating; returns `question`, `target_hypothesis_id`, `seed_chip_label`, `risk_level`. | 0.5 |
| **CE** Counter-evidence pass | Server, before any insight shows — **mandatory** | "Search recent entries for evidence that contradicts this hypothesis." Returns `supporting_evidence[]`, `counter_evidence[]`, `should_weaken_claim`, `safer_wording`. Turns "you *always* avoid hard conversations" into "you don't always — but you often delay them until the feeling has built up." | 0.0 |
| **PM** Profile-Mirror writer | Server, at maturity milestones | The bigger "I learned something about me" card (distinct from daily Today's Mirror). Returns `title`, `main_reflection`, `what_it_may_protect`, `what_it_may_cost`, `evidence_receipts[]`, `exception`, `question_to_carry`, `tiny_experiment`, `confidence`. Ends with a question, never a verdict. | 0.6 |

All five carry the `doNotInfer` guard and `LifeContext` grounding. Version: `mirror-selfmodel-v1`, `mirror-nbq-v1`, `mirror-counter-v1`, `mirror-profilemirror-v1`.

---

## 4. Mirror Score (NEW) — gating which insight surfaces

A deterministic Swift scorer (`MirrorScore.swift`) over `PatternHypothesis` fields, so the LLM proposes but the device disposes:

```
score = evidenceStrength + emotionalWeight + noveltyScore + actionabilityScore
        − shameRisk − diagnosticRisk − repetitionFatigue
```
`repetitionFatigue` = decay on `timesSeen` / `lastShownAt`. Only the top-scoring hypothesis above a floor becomes Today's Mirror; the rest stay in the graph. This is what keeps the app from saying "you felt tired today" and pushes it toward "tiredness arrives with guilt, not low energy."

### 4.1 The deeper-insight formula (the shape every strong mirror should take)
```
When [trigger],
you often [protective move],
which may help you [short-term benefit],
but may cost you [long-term cost].
The exception is [when it softened].
A useful question is [next question].
```
This is enforced as the structural contract for the Profile-Mirror writer (Prompt PM) — the analogue of the six formulas the daily read already uses. It is what makes the output "deeper than 'you seem stressed about productivity.'"

---

## 5. Phased rollout

Each phase is independently shippable, preserves local fallbacks, and **updates the relevant PRD before it's considered done** (per `CLAUDE.md`).

### Phase 0 — Trust foundation (do first; unblocks everything sensitive)
- **At-rest encryption** for `JournalEntry.content` and `EntryAnalysis.rawText`. Per-user key via Keychain; `raw_text_encrypted` in Firestore (spec §4 Entry, §16). Decrypt only on-device before an AI call.
- **Privacy screen + AI-depth controls** (Gentle / Balanced / Deep), "use exact quotes" on/off, "track people names" on/off, full export + full delete (spec §16).
- **PRD:** new `privacyprd.md`; update `journalprd.md` (content now encrypted).
- *Why first:* journal text is special-category data (ICO/UK-GDPR); the FTC Health Breach Notification Rule now covers non-HIPAA health apps. Encryption + delete/export are table stakes before deepening analysis.

### Phase 1 — Unified entry analysis
- Build `EntryAnalysis` model + `AIService.analyzeEntry` (Prompt A); persist to Firestore. Local fallback = current `LocalAI` heuristics mapped into the new shape.
- Migrate `EchoExtractionService` and `AIService+River` to read from `EntryAnalysis` rather than re-extracting.
- **PRD:** new `mirrorprd.md` (§ Entry analysis); update `echoesprd.md`, `riverprd.md`.

### Phase 2 — Mirror Graph + pattern mining
- Promote `MemoryProfile` → `MirrorGraph` (Firestore-backed accumulator, incl. exceptions).
- Extend `PatternCallback` → `PatternHypothesis`; rewrite `detectPatterns` (Prompt B) over structured signals; add co-occurrence / sequence / lag / exception mining.
- **PRD:** update `patternsprd.md` → fold into `mirrorprd.md`; update `memoryprd.md`.

### Phase 3 — Today's Mirror (rebrand Today's Read)
- Rename `DailyRead` → `MirrorCard`; expand generator (Prompt D) to the 5-part body; bump `PROMPT_VERSION`.
- Rebuild `TodayReadCardView` → `TodayMirrorCardView`: pattern → possible read → receipts → tiny experiment → tomorrow callback.
- **Re-add the feedback buttons** (engine already exists): This is me / Almost / Not me / Too intense / Show proof / Ask tomorrow. Wire to existing `ReadSettings` recalibration + `sourcePatternIds` reward.
- Build the **evidence drawer** ("Why Spilr thinks this": seen-N-times, first-seen, nearby words, supporting quotes, when-it-softened, confidence).
- Add the "checking today against your older words…" generation animation (spec §14).
- **PRD:** `mirrorprd.md` (Today's Mirror, evidence drawer, feedback); supersede `todaysreadprd.md`.

### Phase 4 — Blind spots + First Mirror
- Prompt C (blind-spot detector) server-side; surface under the Mirror tab.
- `MirrorMaturity` gating; **First Mirror unlock ceremony** at 7 entries (loop → protection → cost → exception → next-week question), spec §12.
- **PRD:** `mirrorprd.md` (Blind Spots, First Mirror); update `onboardingprd.md` (7-day promise → First Mirror payoff).

### Phase 5 — Richer input (Mirror Seeds + templates)
- Replace `SpillWriteView` prompt chips with the 8 **Mirror Seeds** (Body / Avoided / People / Pattern / Want / Mask / Loop / Exception), spec §8.
- Add the 5 **templates** as optional "lenses" (Loop Finder, Relationship Mirror, Body Knows First, Hidden Rule, Exception), spec §9. The Exception template feeds Step-3 exception tracking — high priority so the app learns what *helps*, not only what hurts.
- **PRD:** `mirrorprd.md` (Seeds, templates); update `hintsprd.md`.

### Phase 6 — Navigation rebrand + River geography
- Rename **Patterns tab → Mirror** (`MainTabView` in `App/RootView.swift`): Today's Mirror / First / Weekly / Monthly / Blind Spots / Loops / Exceptions.
- River → emotional geography (streams = domains, intensity = charge, stones = tiny acts, bends = loop-changes, bright pools = exception days), spec §15. Share card stays share-safe text only (already enforced).
- **PRD:** update `riverprd.md`, `themesprd.md` if labels/colours move; finalize `mirrorprd.md` navigation section.

### Phase 7 — Safety hardening (cross-cutting, lands alongside Phases 3–6)
- Extend the Stage-2 guard (Prompt E) reject list to the full spec §5/§6 set: no diagnosis, no certainty about hidden motives, no trauma/attachment/disorder inference, no medical advice, no shame amplification, no therapy-replacement claims. Provide `safer_version` fallback.
- Keep `PatternSafety.corpusHasCrisisSignal` as the **deterministic gate that always runs before any LLM call** on the Mirror path (it currently guards only pattern detection — extend to the Mirror generator path too). On a crisis signal: suppress all insight, route to `PatternResourceCardView`.
- **PRD:** `mirrorprd.md` (safety) + a short `SAFETY.md` describing the dual gate.

> **Phases 8–11 are the rev-2 Self Model work.** They sit on top of Phases 1–3 (they consume `EntryAnalysis` and the pattern layer) and deliver the "Spilr is learning how I operate, and I can correct it" moment.

### Phase 8 — EpisodeFrame + Self Model core
- Add `EpisodeFrame` split to Prompt A (one entry → 1..n episodes); retarget pattern mining to episodes.
- Build `SelfModel` schema + `SelfModelService` + Prompt SM-1 (daily updater). Implement scope/stability/lifecycle (2.9) and the `doNotInfer` guard. Local fallback: a deterministic accumulator that can only *strengthen* recurring signals, never invent rules.
- **PRD:** new `profileintelligenceprd.md` (PI-001…010, §10); update `memoryprd.md`.

### Phase 9 — Counter-evidence + grounding
- Prompt CE as a **mandatory** gate before any insight surfaces; wire `should_weaken_claim` → `safer_wording`.
- `LifeContext` known-facts onboarding (optional, skippable) + deterministic enforcement of `sensitiveTopicsDisabled`.
- Semantic retrieval (`MirrorRetrieval`): similar / contradictory / first-seen / most-intense / most-recent / exception-day. (Start with on-device embeddings or a keyword+recency heuristic; upgrade later.)
- **PRD:** `profileintelligenceprd.md` (counter-evidence, known facts); update `privacyprd.md` (LifeContext stored apart from entries).

### Phase 10 — "My Self Model" screen + "Teach Spilr" correction loop
- **My Self Model** screen under the Mirror tab: Rules I may be living by / Protective moves / Parts that show up / What helps me soften / Words that mean something here / People patterns / Questions still open. Each card shows confidence (emerging/recurring/user-confirmed), 3 proof receipts, last-seen, and **edit / hide / not-me** controls.
- `ProfileCorrection` flow ("missing something?" → category chips → free text) feeding SM-1 as higher-priority truth. Weekly **calibration ritual** (3 taps, 30s).
- Delete-Self-Model separately from entries (PI-008).
- **PRD:** `profileintelligenceprd.md` (My Self Model, correction, calibration).

### Phase 11 — First Sketch + Next-Best-Question + ask-from-profile
- **"Spilr's first sketch of you"** at 7 entries: a rule + a protective move + a part + a thing that helped + one question for next week (the fastest "wow"; supersedes the generic First Mirror ceremony from Phase 4 — they merge).
- **Next-Best-Question** engine (Prompt NBQ) drives Mirror Seeds from unresolved hypotheses; prompts become personal ("you often write 'reset' when you feel behind — was today a reset day or a rest day?") instead of generic.
- Profile-Mirror writer (Prompt PM) for the milestone "I learned something about me" cards at 14/30/90.
- **PRD:** `profileintelligenceprd.md` (First Sketch, NBQ, profile-driven prompts); update `onboardingprd.md`, `hintsprd.md`.

---

## 6. Positioning & compliance guardrails (apply to every phase)

These are product-level, not fine print:
- **Language:** self-reflection, pattern recognition, journaling support. Never diagnosis, treatment, or therapy. The APA has cautioned that AI wellness apps alone should not be relied on as mental-health care.
- **Claims:** always "may / might / seems"; always paired with a gentler alternative interpretation and the user's own evidence; always a *testable* experiment, never a verdict. ("You may go quiet when a feeling is too expensive to explain" — not "you are avoidant.")
- **No identity labels, no disorder names, no trauma inference.** Enforced by Prompt E + a deterministic lint on output strings.
- **Data:** special-category-grade handling (encrypt at rest, separate identity from content, no model-training on entries by default, full export/delete, log every AI analysis event). Avoiding diagnosis/treatment also keeps the product clear of FDA device-software oversight.

---

## 7. Success metrics to instrument (spec §20)

Activation: % completing first spill, % viewing Today's Mirror, % opening evidence drawer, % rating an insight. Insight quality: % "This is me" / "Almost" / "Not me" / "Too intense", % saved-or-shared, % returning for the tomorrow callback. Retention: D1/D7/D30, entries per activated user, 7-entry unlock completion, Weekly Mirror open rate. Safety/trust: % flagged "too intense", % hidden/deleted, AI-discomfort tickets, export/delete completion. Add an `analytics` event per AI step (also satisfies the "log every AI analysis event" requirement).

---

## 8. Recommended sequencing

**Milestone 1 — prove the mirror.** Phase 0 → 1 → 3: "The Thing You Didn't Notice" (spec §21) on an encrypted, unified-analysis foundation with the feedback loop. Smallest slice that proves the daily mirror.

**Milestone 2 — prove the *living profile* (rev 2).** This is where the app stops being a journal and becomes a mirror. Build in this order (the user's stated order, mapped to phases):
1. `SelfModel` schema (Phase 8)
2. `EpisodeFrame` extraction (Phase 8)
3. Self Model update prompt SM-1 (Phase 8)
4. Counter-evidence pass CE (Phase 9)
5. **My Self Model** screen (Phase 10)
6. User correction / "Teach Spilr" (Phase 10)
7. Next-Best-Question engine (Phase 11)
8. **First Sketch** unlock (Phase 11)

**The fastest "wow":** at 7 entries, ship *"Spilr's first sketch of you"* — 4 evidence-backed hypotheses (a rule, a protective move, a part, a thing that helped) + one question for next week. Prioritize a thin vertical slice of Phases 8→9→11 that reaches this screen before building the full My Self Model surface (Phase 10).

Phases 2, 4, 5, 6 deepen the daily side; Phase 7 (safety) and Phase 9's counter-evidence gate ride alongside everything that surfaces text. Each phase keeps the four `CLAUDE.md` invariants and updates its PRD before close.

---

## 9. Risks & open questions

- **Cost / latency:** Prompts A–E are 5 LLM calls. A and the daily server pass (B+C+D+E) are already mostly mirrored by today's architecture; confirm the daily Cloud Function budget tolerates the extra mining/blind-spot calls per active user.
- **Encryption vs. server-side mining:** if raw text is encrypted at rest, the daily server pass needs either (a) the structured `EntryAnalysis` (no raw text) to be sufficient for mining — preferred — or (b) a server-decrypt path, which weakens the privacy story. **Recommendation: mine over `EntryAnalysis` only; never decrypt server-side.** This is a real design constraint to confirm in Phase 1.
- **Collection rename:** `patternCallbacks` → `patternHypotheses` and `dailyReads` → `mirrors` need a migration/alias and Firestore-rules update. Cheapest path: keep existing collection names internally, rebrand only user-facing copy. Decide in Phase 2/3.
- **Timezone:** the existing per-day doc-id uses UTC midnight (known limitation in `todaysreadprd.md`); the maturity/daily cadence inherits it. Fix when convenient, not blocking.

**Rev-2 additions:**
- **More LLM calls per day:** rev 2 adds SM-1, CE (mandatory), and sometimes NBQ/PM to the nightly server pass. Confirm the Cloud Function budget per active user; CE can run at temp 0.0 cheaply, and SM-1 only needs the *delta* (new analyses + episodes), not the whole history, each night.
- **Self Model write contention / versioning:** SM-1 is the single writer of `selfModel/current`; corrections (Step 10) and the nightly pass must not race. Use the `version` field for optimistic concurrency and apply corrections as queued ops the next SM-1 run consumes (corrections always win — PI-010).
- **Retrieval cost:** semantic retrieval (Phase 9) is the heaviest new infra. Ship the keyword+recency heuristic first; only add embeddings if insight specificity demands it. Keep retrieval on `EntryAnalysis`/episodes, never raw decrypted text server-side (consistent with the encryption constraint above).
- **Over-claiming is the core product risk, not a footnote:** the scope/stability/lifecycle fields, the mandatory CE pass, and scope-bound wording are the three guardrails that keep a "living profile" from becoming an unearned diagnosis. None is optional.

---

## 10. Profile Intelligence — PRD requirements (rev 2)

To live in new `profileintelligenceprd.md`. **Goal:** a private, editable, evidence-backed Self Model that helps users understand recurring rules, protective strategies, values, contradictions, relationship roles, and what helps them. **User value:** "Spilr is not summarizing me — it is learning how I work, and letting me correct it."

| ID | Requirement |
|---|---|
| PI-001 | Maintain a private `SelfModel` per user. |
| PI-002 | Separate temporary state from recurring pattern (scope/stability fields). |
| PI-003 | Attach evidence **and** counter-evidence to every hypothesis. |
| PI-004 | Let users confirm, reject, edit, or hide any profile hypothesis. |
| PI-005 | Generate personalized prompts from unresolved profile hypotheses (NBQ). |
| PI-006 | Track exceptions and helpful levers, not only problems. |
| PI-007 | Never present hypotheses as diagnosis or fixed identity. |
| PI-008 | Allow deleting the `SelfModel` separately from journal entries. |
| PI-009 | Maintain lifecycle states: emerging → recurring → confirmed → weakened → retired. |
| PI-010 | Treat user corrections as higher-priority truth than AI inference. |

These map to the phases as: PI-001/002/007/009 → Phase 8; PI-003/006 → Phase 9; PI-004/008/010 → Phase 10; PI-005 → Phase 11.
```
