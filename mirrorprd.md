# Mirror Engine PRD

## Overview

Mirror replaces and extends the Patterns tab. Its purpose is self-reflection and pattern recognition — never diagnosis or therapy. The engine helps users notice recurring emotional structures in their own words, with evidence they can verify, in language that stays tentative and correctable.

**Core invariants (inherited from project-wide principles)**

- Local-first: every Mirror feature works offline or without AI; AI enriches silently.
- Fire-and-forget writes: no UI element waits on a Firestore save.
- One thing at a time: one Today's Mirror card surfaces per day — never a list of insights.
- AI never blocks the user: all LLM calls run detached, fail silently, and degrade to local fallbacks.

**Pipeline**

```
Entry saved
  → Prompt A (EntryAnalysis, client-side, temp 0.2)
  → MirrorGraph updated (local + Firestore)
  → Prompt B (PatternHypothesis mining, server, nightly)
  → MirrorScore gate (deterministic Swift scorer)
  → Prompt D (MirrorCard writer, server, temp 0.6)
  → Prompt E (Safety guard, server, temp 0.0)
  → Today's Mirror card shown
```

If any step fails the pipeline degrades gracefully: local fallback copy is shown or the card is suppressed for the day.

---

## Entry Analysis (Phase 1)

**Purpose**

Prompt A runs client-side immediately after the user saves an entry. It replaces the three separate legacy extractions (`generateInsights`, `extractEcho`, `extractRiverMarkSignals`) with a single structured pass. Downstream services (EchoService, RiverService) read from the resulting EntryAnalysis document rather than re-extracting from raw text.

**Prompt version:** `mirror-extract-v1`  
**Temperature:** 0.2  
**Execution:** detached background task on the device immediately after save  
**Storage:** `users/{uid}/entryAnalyses/{entryId}`

**EntryAnalysis schema**

| Field | Type | Notes |
|---|---|---|
| `entryId` | String | Matches the JournalEntry id |
| `surfaceSummary` | String | One sentence, factual — what happened or was written about |
| `lifeDomains` | [String] | work / relationship / body / self / finances / creative / other |
| `explicitEmotions` | [String] | Emotions the user named directly |
| `inferredEmotions` | [{emotion, confidence, evidenceQuote}] | Confidence on every inference; include the verbatim phrase that led to it |
| `needs` | [String] | Unmet or met needs apparent in the entry |
| `protectiveStrategies` | [{strategy, protectsAgainst, confidence}] | Behaviours that seem to serve a protective function |
| `avoidanceMarkers` | [{type, phrase, function}] | Phrasing patterns that circle around something rather than naming it |
| `cognitivePatterns` | [String] | e.g. catastrophising, minimising, all-or-nothing |
| `valuesPresent` | [String] | Values the user is living or honouring |
| `valuesConflict` | [{valueA, valueB, evidenceQuote}] | Where two values appear to pull against each other |
| `bodySignals` | [String] | Physical sensations mentioned or strongly implied |
| `relationshipRoles` | [{role, person, evidenceQuote}] | e.g. caretaker, peacekeeper, outsider |
| `openLoops` | [String] | Unresolved situations or decisions mentioned |
| `phrasesToTrack` | [String] | Distinctive phrasing worth watching across entries |
| `possibleTinyAct` | String? | One small actionable experiment, or null |
| `episodes` | [EpisodeFrame] | Sub-array; see EpisodeFrame section |
| `rawTextEncrypted` | String | Base64 AES-GCM; not sent server-side for mining |
| `promptVersion` | String | `mirror-extract-v1` |
| `createdAt` | Timestamp | |

Every inferred field carries a `confidence` value (0.0–1.0). Fields with confidence below 0.5 are omitted from downstream consumers unless the user has set AI depth to Deep.

**Downstream consumers**

- `EchoService` reads `phrasesToTrack` and `inferredEmotions` instead of calling its own extraction prompt.
- `RiverService` reads `lifeDomains`, `valuesPresent`, and `bodySignals` instead of calling `extractRiverMarkSignals`.
- `PatternDetectionService` reads `protectiveStrategies`, `avoidanceMarkers`, and `episodes` for hypothesis mining.

---

## EpisodeFrame

One entry often contains several distinct emotional moments — a tense morning meeting, a quiet lunch that helped, and an anxious evening. Collapsing them into a single mood loses the structure. EpisodeFrame preserves each moment separately.

**Storage:** sub-array at `entryAnalyses/{entryId}.episodes[]`

**EpisodeFrame schema**

| Field | Type | Notes |
|---|---|---|
| `episodeId` | String | UUID, stable across app restarts |
| `situation` | String | Brief factual description of the moment |
| `emotion` | [String] | Emotions present in this episode |
| `bodySignal` | [String] | Physical sensations in this episode |
| `protectiveStrategy` | String? | Strategy deployed in this episode, if any |
| `need` | String? | Apparent need in this episode |
| `outcome` | String? | How this episode resolved or didn't |

**Why this matters**

Pattern mining and Self Model inference operate on episodes, not whole entries. This prevents a mixed day (tense morning / good afternoon / anxious evening) from being flattened into one ambiguous mood signal. A user who consistently has tense mornings that soften by afternoon is showing something meaningful — but only if episodes are tracked separately.

---

## Pattern Hypotheses (Phase 2)

**Purpose**

Extends the existing PatternCallback system with richer hypothesis types and metadata. PatternHypothesis supersedes PatternCallback for Mirror-aware clients; legacy PatternCallback fields are retained for backward compatibility.

**Storage:** `users/{uid}/patternHypotheses/{id}`

**New `patternType` values**

| Type | What it captures |
|---|---|
| `protectiveLoop` | A recurring move that protects against a feared outcome |
| `avoidedSubject` | A topic the user circles around but rarely names directly |
| `identityRule` | An implicit rule about who the user is allowed to be |
| `relationshipRole` | A role the user consistently occupies with other people |
| `bodySignal` | A physical pattern that precedes or accompanies an emotional state |
| `valuesConflict` | Two values that repeatedly pull against each other |
| `exception` | A moment when the usual pattern softened — highest-priority learning signal |
| `timeRhythm` | Energy, mood, or behaviour patterns tied to time of day/week |
| `vocabularyFingerprint` | Distinctive phrasing that recurs and may carry meaning |

**New PatternHypothesis fields**

| Field | Type | Notes |
|---|---|---|
| `userFacingTitle` | String | Short, plain-language label shown in UI |
| `coreHypothesis` | String | The hypothesis in one or two sentences |
| `protection` | String | Why this pattern makes sense — what it is protecting against |
| `cost` | String | What the pattern quietly takes from the user |
| `counterEvidence` | [String] | Entries or episodes where this pattern did NOT appear |
| `noveltyScore` | Float 0–1 | How new or surprising this is relative to what has been surfaced before |
| `emotionalWeight` | Float 0–1 | Estimated emotional significance |
| `actionabilityScore` | Float 0–1 | How much a user can actually do with this insight |
| `shameRisk` | Float 0–1 | Risk that surfacing this insight triggers shame |
| `diagnosticRisk` | Float 0–1 | Risk that the wording implies a clinical diagnosis |
| `tinyExperiment` | String? | One small, low-stakes experiment the user could try |
| `callbackQuestion` | String | A question to carry forward |
| `firstSeenAt` | Timestamp | When this pattern was first detected |
| `timesSeen` | Int | Number of entries/episodes supporting it |
| `scope` | Enum | `today` / `this_week` / `this_month` / `recurring` / `user_confirmed` |
| `stability` | Enum | `temporary` / `emerging` / `stable` / `retired` |
| `evidenceEntryIds` | [String] | Entry IDs that support this hypothesis |
| `counterEvidenceEntryIds` | [String] | Entry IDs that contradict or soften this hypothesis |

**Prompt version:** `mirror-mine-v1`  
**Temperature:** 0.3  
**Execution:** server-side, nightly Cloud Function

---

## MirrorScore (Phase 2)

**Purpose**

A deterministic Swift scorer that selects which hypothesis surfaces as Today's Mirror. Only the top-scoring hypothesis above a minimum floor is shown; all others remain in the MirrorGraph for future surfacing.

**Formula**

```
MirrorScore =
    evidenceStrength        // 0–3, based on timesSeen and evidenceEntryIds count
  + emotionalWeight         // 0–1, from PatternHypothesis
  + noveltyScore            // 0–1, from PatternHypothesis
  + actionabilityScore      // 0–1, from PatternHypothesis
  + seenBonus               // +0.5 if timesSeen >= 3, +1.0 if >= 7
  − shameRisk               // 0–1, from PatternHypothesis
  − diagnosticRisk          // 0–1, from PatternHypothesis
  − repetitionFatigue       // +0.5 per time this hypothesis was the top card in last 14 days
```

**Floor:** 2.5. Hypotheses scoring below this are not surfaced today regardless of ranking.

**Effect on language quality**

The scorer pushes toward structurally interesting insights. "You felt tired today" scores low on noveltyScore and actionabilityScore. "Tiredness arrives with guilt, not with low energy" scores higher on both because it distinguishes a trigger from a state — giving the user something to watch for.

---

## The Deeper-Insight Formula

Every strong Mirror output must follow this structural contract. Prompt D is instructed to produce output that maps to these parts; Prompt E verifies the structure is maintained.

```
When [trigger or situation],
you often [protective move],
which may help you [short-term benefit],
but may cost you [long-term cost].
The exception is [when it softened or was absent].
A useful question is [next question].
```

This formula is:

- Non-diagnostic: framed as observation, not assessment.
- Evidence-anchored: each clause must trace back to actual entry content.
- Exception-aware: always names a time the pattern did not hold.
- Forward-looking: ends with a question, never a verdict.

---

## Today's Mirror (Phase 3)

**Purpose**

Today's Mirror is the primary daily surface. It replaces Today's Read. One card per day, one hypothesis, structured evidence, user feedback.

**Storage:** `users/{uid}/mirrors/{yyyy-MM-dd}`

**Card structure (5 parts)**

| Part | Content |
|---|---|
| `headline` | Short label — what pattern this is about |
| `mirrorSentence` | The deeper-insight formula rendered as natural prose |
| `whyThisCameUp` | Why today's entry(s) triggered this hypothesis |
| `patternName` | The `userFacingTitle` from the hypothesis |
| `receipts` | Array of {quote, whyItMatters} — verbatim or paraphrased depending on user setting |
| `possibleRead` | Alternative interpretation — "or, it might be…" |
| `tinyExperiment` | One low-stakes action the user can take |
| `tomorrowCallbackQuestion` | Question to carry into the next entry |
| `shareSafeSummary` | De-identified one-liner safe for sharing externally |

**Feedback options**

- This is me
- Almost
- Not me
- Too intense
- Ask tomorrow

Feedback is written to `mirrors/{date}.feedback` and consumed by SM-1 as a correction signal.

**Evidence drawer ("Show proof")**

Tapping "Show proof" expands a drawer containing:

- Seen N times
- First seen: [date]
- When it softened: [date or "not yet"]
- Supporting quotes (up to 3)
- Exception days (entry dates where the pattern did not appear)
- Confidence: low / medium / high (never a percentage)
- Counter-evidence: entries that cut against the hypothesis

**Generation animation**

While Prompt D is running, the card shows: "checking today against your older words…"

**Prompt version:** `mirror-write-v1`  
**Temperature:** 0.6

---

## Mirror Seeds (Phase 5)

Mirror Seeds replace the old generic prompt chips in SpillWriteView. They are 8 lenses — short, evocative, personally grounded writing invitations.

| Label | Description | Personal prompt |
|---|---|---|
| Body | Tension, fatigue, fog, restlessness | "Where did your body react before your mind had words?" |
| Loop | What felt familiar today? | "What did you try to solve instead of feel?" |
| People | The person you keep carrying | "Who took up more space in your head than expected?" |
| Exception | What softened the loop? | "When did today feel 5 percent lighter?" |
| Avoided | The thing you circled around | "What did you almost write about, then didn't?" |
| Pattern | Something recurring | "What are you doing again that you've done before?" |
| Want | Under the doing | "What did you actually want today, underneath everything else?" |
| Mask | What you showed vs felt | "What were you performing today, even just a little?" |

Seeds are shown in `SpillWriteView` as horizontal chips. Tapping a seed inserts the personal prompt string as a starting line and sets the `seedLabel` on the resulting entry (for analytics and hypothesis targeting).

When the Next-Best-Question engine (NBQ, see Profile Intelligence PRD) produces a personalised question, it replaces the most generic seed for that session.

---

## Templates (Phase 5)

Templates are optional structured lenses available from the write screen. They scaffold a longer entry around a known reflective pattern.

| Template | Structure |
|---|---|
| Loop Finder | Trigger → Move → Cost → Need |
| Relationship Mirror | Person → My role → What I wanted → What I did → How it felt |
| Body Knows First | Signal → Moment that preceded it → Underlying need |
| Hidden Rule | "I am only allowed to [X] if [Y]" — fill in the blanks |
| Exception | What softened the loop today? When? What was different? |

The Exception template is highest priority for learning. Entries written with the Exception template feed directly into `exception`-type PatternHypotheses and the `whatHelps` section of the Self Model. They are the primary learning signal for what actually shifts the pattern.

---

## Mirror Tab / Navigation (Phase 6)

The Patterns tab is renamed Mirror. `PatternsView` is replaced by `MirrorView`.

**MirrorView sections**

| Section | Content |
|---|---|
| Today's Mirror | Today's card (or "nothing to show yet" if below maturity gate) |
| First Sketch | Visible after 7 entries; shows the 4 evidence-backed hypotheses from Phase 11 |
| Blind Spots | Cards from Prompt C (Blind Spot Detector) |
| Loops | List of active PatternHypotheses by type, sorted by MirrorScore |
| Exceptions | List of exception-type hypotheses — what has helped, with evidence |

Navigation within MirrorView uses a tab-strip or segmented control at the top. Today's Mirror is always the default visible section.

---

## Blind Spot Detector (Phase 4)

**Purpose**

A separate daily pass that asks: "What is this person not noticing?" Surfaces as a distinct card type in the Blind Spots section of MirrorView — never conflated with Today's Mirror.

**Prompt version:** `mirror-blindspot-v1`  
**Temperature:** 0.3  
**Execution:** server-side, daily Cloud Function  
**Input:** last 14 days of EntryAnalysis documents (structured fields only, no raw text)

**Output schema**

| Field | Notes |
|---|---|
| `blindSpotHypothesis` | What the user may not be seeing |
| `evidence` | Specific fields from EntryAnalysis that support this |
| `gentlePointer` | A question that points toward the blind spot without naming it directly |
| `confidence` | 0.0–1.0 |

Blind Spot cards are suppressed if `confidence < 0.6` or if Prompt E flags them.

---

## First Sketch / First Mirror (Phase 4 + 11)

**Trigger:** 7 entries saved.

**Content:** 4 evidence-backed hypotheses plus one question for next week.

| Slot | Content |
|---|---|
| A rule | "You seem to hold a rule that [X]" — an identityRule hypothesis |
| A protective move | The highest-scoring protectiveLoop hypothesis |
| A part that shows up | A relationshipRole or inner-part hypothesis |
| A thing that helped | The highest-confidence exception hypothesis (what softened the loop) |
| One question | The best callbackQuestion from the top hypothesis |

**Unlock ceremony**

At 7 entries, a full-screen animation plays before the First Sketch is shown. The animation text: "You've written enough for a first sketch." The user taps to reveal each of the 4 hypotheses in sequence, then the question.

First Sketch and First Mirror (referenced in Profile Intelligence PRD) are the same screen — they merge into one unlock event.

---

## Maturity Gates

Mirror features unlock progressively as the user builds a corpus. This prevents the system from over-claiming on thin evidence.

| Entries | Unlock |
|---|---|
| 1 | Daily Mirror card (light — surface-level observations only, no pattern claims) |
| 3 | Soft pattern hypotheses (hedged language: "might be", "seems like") |
| 7 | First Sketch unlock ceremony; Blind Spot Detector activates |
| 14 | Deeper pattern hypotheses; counter-evidence pass enabled |
| 30 | Monthly Mirror milestone card |
| 90 | Identity and rhythm-level insights (valuesConflict, timeRhythm) |

Language gets firmer as maturity increases — but never crosses into diagnostic territory regardless of entry count.

---

## Safety (Phase 7)

**Dual gate — both must pass before any Mirror card is shown.**

**Gate 1 (deterministic, runs first)**

`PatternSafety.corpusHasCrisisSignal(_:)` runs on the EntryAnalysis corpus before any LLM call. If it fires:

- All Mirror output is suppressed.
- `PatternResourceCardView` is shown instead.
- No hypothesis is written to Firestore for this run.

This gate cannot be bypassed by any LLM output.

**Gate 2 (Prompt E, runs last)**

Prompt E (`mirror-guard-v1`, temp 0.0) is the final check before the card is written to Firestore. It rejects the output and triggers fallback if the card:

- Makes a diagnostic claim (names a disorder, condition, or clinical construct).
- Asserts certainty about hidden motives or childhood origin.
- Infers trauma, attachment style, or mental disorder.
- Offers medical advice.
- Amplifies shame.
- Claims to replace therapy.

On rejection, Prompt E returns either a `safer_version` (rewritten card at lower inference depth) or a `suppress` signal. If `suppress`, no card is stored and the user sees nothing for today.

---

## Language Rules

These rules apply to all Mirror output — enforced by Prompt E and by a deterministic output lint function that runs after Prompt D.

**Always:**

- Use hedged language: "may", "might", "seems", "often".
- Include a state/season frame: "this week, X appears frequently — that may be temporary, or worth watching."
- Pair every observation with a gentler alternative interpretation.
- Anchor every claim in the user's own words (receipts).
- Offer a testable experiment.

**Never:**

- Assert fixed identity: "you are someone who avoids conflict."
- Name a disorder, condition, or clinical construct.
- Infer trauma origin, attachment style, or childhood cause.
- Use certainty language: "you always", "you never", "this is why you…"
- Amplify shame.
- Claim to replace or supplement therapy.

The output lint function scans for banned phrases before the card is passed to Prompt E. If banned phrases are found, the card is sent back to Prompt D with a correction instruction.

---

## Prompt Version Table

| Prompt | Version tag | Purpose | Temp | Execution |
|---|---|---|---|---|
| A | `mirror-extract-v1` | Entry Analysis extraction | 0.2 | Client-side, on save |
| B | `mirror-mine-v1` | Pattern Hypothesis mining | 0.3 | Server, nightly |
| C | `mirror-blindspot-v1` | Blind Spot Detector | 0.3 | Server, daily |
| D | `mirror-write-v1` | Today's Mirror card writer | 0.6 | Server, on demand |
| E | `mirror-guard-v1` | Safety guard | 0.0 | Server, after D |

All prompts begin with `NinetyVoice.system` and end with `MemoryProfileService.shared.cachedPromptContext()`, per project-wide convention.

---

## Success Metrics

| Metric | Target |
|---|---|
| % of active users viewing Today's Mirror | > 60% on days a card is generated |
| % opening the evidence drawer ("Show proof") | > 25% of views |
| % rating an insight (any feedback option) | > 40% of views |
| Distribution: This is me / Almost / Not me / Too intense | "This is me" + "Almost" > 65% combined |
| D1 retention | Baseline + 5pp vs pre-Mirror |
| D7 retention | Baseline + 8pp |
| D30 retention | Baseline + 12pp |
| 7-entry First Sketch unlock completion rate | > 70% of users who reach 7 entries |

---

## Service Layer (Phase 1–3 Implementation)

Three Swift service files implement the Mirror Engine client-side:

### `Mirror/AIService+Mirror.swift`

Extension on `AIService`. All methods are non-throwing — failures degrade to local fallbacks or nil.

| Method | Prompt | Temp | Max tokens | Returns |
|---|---|---|---|---|
| `analyzeEntry(entryId:userId:text:)` | mirror-extract-v1 | 0.3 | 1200 | `EntryAnalysis` (never nil — local fallback on failure) |
| `generateMirrorCard(userId:topHypothesis:recentAnalyses:)` | mirror-write-v1 | 0.6 | 800 | `MirrorCard?` |
| `fetchLatestMirrorCard(userId:)` | — | — | — | `MirrorCard?` from `users/{uid}/mirrors/{yyyy-MM-dd}` |
| `saveMirrorCard(_:userId:)` | — | — | — | Fire-and-forget write |

`analyzeEntry` fires-and-forgets a Firestore write to `users/{uid}/entryAnalyses/{entryId}` after a successful AI analysis.

Guards: `isAIAvailable` and `text.count > 30` — both fall back to `EntryAnalysis.local(...)`.

### `Mirror/MirrorGraphService.swift`

`@MainActor final class MirrorGraphService: ObservableObject` — the signal accumulator.

| Method | Behaviour |
|---|---|
| `loadHypotheses(for:)` | Fetches top-20 from `users/{uid}/patternHypotheses` ordered by `salienceScore` desc, filters `isSurfaceable == true` |
| `topScoringHypothesis(for:)` | Returns `hypotheses.max(MirrorScore)` where score > 0.5 |
| `saveHypothesis(_:userId:)` | Fire-and-forget setData |
| `markShown(_:userId:)` | Updates `shownAt` + increments `timesSeen` locally and in Firestore |
| `recordFeedback(hypothesisId:userId:status:)` | Updates `status` + `respondedAt` locally and in Firestore |
| `loadRecentAnalyses(for:limit:)` | Fetches from `users/{uid}/entryAnalyses` ordered by `createdAt` desc |

### `Mirror/SelfModelService.swift`

`@MainActor final class SelfModelService: ObservableObject` — the self-model owner.

| Method | Behaviour |
|---|---|
| `load(for:)` | Fetches `users/{uid}/selfModel/current` + `users/{uid}/profileCorrections` (limit 20) concurrently |
| `save(_:userId:)` | Fire-and-forget setData to `selfModel/current` |
| `submitCorrection(_:userId:)` | Persists to `profileCorrections/{id}` and prepends to local array |
| `markHypothesis(id:userStatus:userId:)` | Updates `userStatus` across all hypothesis sections; writes back |
| `hideHypothesis(id:userId:)` | Sets `stability = .retired` on matching hypothesis; writes back |
| `deleteModel(userId:)` | Deletes `selfModel/current`, batch-deletes all `profileCorrections`, resets local state |
| `lifeContext(for:)` | Fetches `users/{uid}/lifeContext/current`; fallback to `LifeContext.empty` |
| `saveLifeContext(_:userId:)` | Fire-and-forget setData to `lifeContext/current` |

Hypothesis search covers: `coreRules`, `values`, `contradictions`, `whatHelps` (`SelfModelHypothesis`), `protectiveStrategies` (`ProtectiveHypothesis`), and `innerParts` (`InnerPart`). Mutations copy-and-reassign since `SelfModel` is a struct.

---

## Performance: tab pre-warming *(Updated 2026-06-17)*

`MirrorViewModel` and `PatternsViewModel` were previously `@StateObject` properties
**inside** `MirrorView`/`PatternsView`, so they were created lazily on the first
tab tap — causing a full-screen spinner every cold open.

**Fix:** Both VMs are now `@StateObject` properties of `MainTabView` in
`RootView.swift`. `MainTabView` kicks off `mirrorVM.load(showSpinner: false)` and
`patternsVM.load()` in its `.task` modifier as soon as the tab bar appears (i.e.
right after authentication, before the user touches anything). By the time the user
taps Mirror or Patterns the Firestore fetch is already in-flight or complete.

`MirrorView` and `PatternsView` now accept an optional pre-built VM via their
`init(userId:viewModel:)` parameter and use `@ObservedObject` instead of
`@StateObject`. When called without a VM (previews, deep links) they fall back
to creating their own.

`MirrorViewModel.hasLoaded` already prevented re-showing the spinner on
back-navigation. The same guard was added to `PatternsViewModel`.
