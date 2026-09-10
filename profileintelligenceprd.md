# Profile Intelligence (Self Model) PRD — rev 2

## Goal

"Spilr is not summarizing me — it is learning how I work, and letting me correct it."

Profile Intelligence builds a private, editable, evidence-backed Self Model of the user. Unlike a summary (which flattens), a Self Model accumulates hypotheses, tracks their lifecycle, and lets the user correct them. The system gets smarter over time without ever asserting fixed identity.

The goal is for the app to stop being a journal and become a mirror — one that reflects the user's recurring emotional structures back to them in language they can recognize, correct, and use.

---

## Self Model Schema

**Storage:** `users/{uid}/selfModel/current` — a single versioned document, replaced on each SM-1 run.

**Top-level fields**

| Field | Type | Notes |
|---|---|---|
| `version` | Int | Incremented on every SM-1 write; used for optimistic concurrency |
| `generatedAt` | Timestamp | When SM-1 last ran |
| `entryCount` | Int | Number of entries in corpus at generation time |
| `doNotInfer` | [String] | Hard exclusions: `["diagnosis","trauma_origin","attachment_style","mental_disorder"]` — echoed verbatim in every prompt |
| `nextBestQuestion` | String? | Emitted by SM-1; used by NBQ engine |

**Hypothesis sections** — each is an array of SelfModelHypothesis:

| Section | What it captures |
|---|---|
| `coreRules` | Implicit rules the user seems to live by ("I am only safe when I am useful") |
| `protectiveStrategies` | Moves the user makes to protect against a feared outcome |
| `innerParts` | Recurring emotional sub-selves or modes ("the part that manages everything", "the part that disappears") |
| `values` | What the user seems to care about, including conflicts |
| `contradictions` | Places where the user's behaviour and stated values diverge |
| `whatHelps` | Things that have demonstrably softened a loop or shifted a state |
| `relationshipRoles` | Roles the user occupies with specific people or relationship types |
| `vocabulary` | Phrases with personal weight — recurring words that carry more meaning than their surface reading |

**SelfModelHypothesis schema**

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID, stable across runs |
| `title` | String | Short plain-language label |
| `hypothesis` | String | Full hypothesis in 1–3 sentences |
| `confidence` | Float 0–1 | Internal; shown to user as low/medium/high |
| `scope` | Enum | `today` / `this_week` / `this_month` / `recurring` / `user_confirmed` |
| `stability` | Enum | `temporary` / `emerging` / `stable` / `retired` |
| `lifecycle` | Enum | `observed_once` → `emerging` → `recurring` → `user_confirmed` → `weakened` → `retired` |
| `evidenceEntryIds` | [String] | Entry IDs supporting the hypothesis |
| `counterEvidenceEntryIds` | [String] | Entry IDs that contradict or soften it |
| `userStatus` | Enum | `unrated` / `this_is_me` / `half_true` / `not_me` |
| `lastSeenAt` | Timestamp | Most recent entry that triggered this hypothesis |
| `decayAfterDays` | Int | Default 45 — unconfirmed hypotheses age out and move to `retired` |
| `timesSeen` | Int | Number of entries/episodes that activated this hypothesis |
| `userConfirmations` | Int | Times user tapped "This is me" |
| `userRejections` | Int | Times user tapped "Not me" |
| `counterexamples` | Int | Times user tapped "Half true" or provided a correction |
| `lastTestedAt` | Timestamp? | When NBQ last generated a question targeting this hypothesis |

---

## Scope, Stability, and Lifecycle

The biggest over-claim risk in self-model systems is inferring fixed identity from thin evidence: "you are a tired person" from 7 tired entries. The scope, stability, and lifecycle fields prevent this.

**Scope — user-facing language bound to scope**

| Scope | User-facing framing |
|---|---|
| `today` | "Today you seemed to…" |
| `this_week` | "This week, X has appeared a few times…" |
| `this_month` | "Over the past month, X seems to show up when…" |
| `recurring` | "This has appeared across many entries — it may be a recurring pattern, or worth watching." |
| `user_confirmed` | "You've confirmed this feels true for you." |

Identity-level language ("you are someone who…") is never used. Always state/season framing.

**Lifecycle transitions**

```
observed_once → (seen again) → emerging → (seen 5+ times) → recurring
recurring → (user confirms) → user_confirmed
recurring → (decayAfterDays exceeded with no new evidence) → weakened → retired
user_confirmed → (user rejects or contradictions accumulate) → weakened
weakened → retired
```

A retired hypothesis is preserved in the document for audit (soft delete — never hard-deleted from the schema) but is not shown to the user unless they view history.

**Decay**

Hypotheses with `userStatus == unrated` and no new supporting evidence within `decayAfterDays` (default 45) are automatically moved to `weakened` by SM-1. This prevents the Self Model from accumulating stale claims about who the user was six months ago.

---

## EpisodeFrame

Pattern mining and Self Model inference operate on EpisodeFrames, not whole entries. This is inherited from the Mirror Engine PRD and is a shared data structure.

**Storage:** sub-array at `entryAnalyses/{entryId}.episodes[]`

See Mirror Engine PRD for full EpisodeFrame schema. The key constraint: SM-1 must never flatten a mixed-emotion day into a single mood signal. It reads at the episode level to preserve the within-day structure.

---

## LifeContext

Optional, skippable onboarding. Grounds AI inference in the user's current season without requiring heavy setup.

**Storage:** `users/{uid}/lifeContext` — separate from entries and Self Model; separately deletable.

**Fields**

| Field | Type | Notes |
|---|---|---|
| `currentSeason` | Enum | `student` / `building_career` / `burned_out` / `healing` / `new_parent` / `between_things` |
| `primaryFocus` | [String] | 1–3 areas the user is focused on right now |
| `peopleLikelyToAppear` | [String] | First names or roles (partner, manager, sibling) — used for entity linking |
| `sensitiveTopicsDisabled` | [String] | Topics the user does not want analysed |
| `preferredDepth` | Enum | `gentle` / `balanced` / `deep` |

**sensitiveTopicsDisabled enforcement**

This is not a preference passed to the model — it is enforced deterministically in code before any prompt is assembled. If a topic appears in `sensitiveTopicsDisabled`, all EntryAnalysis fields related to that topic are stripped before being included in any prompt context. The LLM never sees the content, not merely "asked not to analyse it."

**LifeContext in prompts**

SM-1 and Prompt A receive LifeContext as structured context, not as part of the system prompt narrative. This grounds inference ("this user is in a new-parent season — exhaustion signals may be situational, not structural") without requiring the model to reason about it explicitly.

---

## Prompt SM-1 (Self Model Updater)

**Prompt version:** `mirror-selfmodel-v1`  
**Temperature:** 0.3  
**Execution:** server-side, nightly Cloud Function  
**Input:** new EntryAnalysis documents + new episodes + new PatternHypotheses + ProfileCorrections since last run + current selfModel/current document

**Output schema**

```json
{
  "profile_updates": [
    {
      "operation": "add | strengthen | weaken | retire | no_change",
      "hypothesisId": "string (existing) or null (new)",
      "section": "coreRules | protectiveStrategies | ...",
      "scope": "today | this_week | ...",
      "confidenceDelta": 0.0,
      "evidence": ["entryId or episodeId"],
      "counterEvidence": ["entryId or episodeId"],
      "userVisibleSummary": "one sentence in hedged language"
    }
  ],
  "nextBestQuestion": "string"
}
```

**SM-1 rules (hard constraints)**

- Prefer "emerging pattern" language over fixed identity at all lifecycle stages below `user_confirmed`.
- Every `add` or `strengthen` operation must include at least one item in `counterEvidence`, or an explicit note that none was found in the corpus.
- User corrections (ProfileCorrections) outrank AI inference — if a correction says "not me", that hypothesis moves to `weakened` regardless of evidence count (PI-010).
- The `doNotInfer` list is echoed verbatim at the start of SM-1's output schema prompt. No inference about diagnosis, trauma origin, attachment style, or mental disorder may appear in any field.
- SM-1 is the single writer of `selfModel/current`. No other service writes to this document.

---

## Prompt CE (Counter-Evidence Pass)

Counter-evidence review is a mandatory gate before any insight surfaces to the user. It runs on every hypothesis before it is included in a MirrorCard or My Self Model screen.

**Prompt version:** `mirror-counter-v1`  
**Temperature:** 0.0  
**Execution:** server-side, called by Mirror card generation pipeline  
**Input:** hypothesis text + 60-day EntryAnalysis corpus (structured fields only)

**Output schema**

```json
{
  "supportingEvidence": ["quote or field reference"],
  "counterEvidence": ["quote or field reference"],
  "shouldWeakenClaim": true,
  "saferWording": "rewritten hypothesis in hedged language"
}
```

If `shouldWeakenClaim` is true, the `saferWording` replaces the original hypothesis in the card. This is what turns "you always avoid hard conversations" into "you don't always — but you often delay them until the feeling has built up."

This pass is **non-optional**. No insight is shown to the user without passing through Prompt CE.

---

## My Self Model Screen (Phase 10)

A dedicated screen (accessible from the Mirror tab) where the user can view, correct, and manage their Self Model.

**Sections**

- Rules I may be living by (`coreRules`)
- Protective moves (`protectiveStrategies`)
- Parts that show up (`innerParts`)
- What helps me soften (`whatHelps`)
- Words that mean something here (`vocabulary`)
- People patterns (`relationshipRoles`)
- Questions still open (unresolved hypotheses with `callbackQuestion`)

**Hypothesis card**

Each SelfModelHypothesis renders as a card with:

- Title (bold, plain language)
- Hypothesis text (hedged language, CE-pass applied)
- Status pill: `emerging` / `recurring` / `user-confirmed`
- Confidence indicator: low / medium / high (never a percentage)
- 3 proof receipts (verbatim quotes or paraphrases depending on quote-controls setting)
- Last-seen date
- Action buttons: **Correct** / **Hide** / **Not me**

Tapping **Correct** opens the ProfileCorrection flow. Tapping **Not me** immediately moves the hypothesis to `userStatus: not_me` and schedules a `weaken` operation in the next SM-1 run. Tapping **Hide** suppresses the card from this screen without writing a correction.

**Delete Self Model**

A separate "Delete my Self Model" option appears in settings. This clears `selfModel/current` and the entire `profileCorrections` collection but preserves all journal entries. This satisfies PI-008.

---

## ProfileCorrection Flow ("Teach Spilr")

Accessible via the "Correct" button on any hypothesis card, or via "missing something?" on any Mirror card.

**Flow**

1. Category chips: `guilt` / `control` / `fear` / `disappointing-someone` / `other`
2. Free-text field: "What's closer to the truth?"
3. Optional toggle: "Update my profile with this"

**Storage:** `users/{uid}/profileCorrections/{id}`

**ProfileCorrection schema**

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `targetHypothesisId` | String? | Hypothesis being corrected, or null if it's a new insight |
| `category` | String | From the chip selection |
| `userText` | String | Free-text correction |
| `updateProfile` | Bool | Whether user opted in to profile update |
| `createdAt` | Timestamp | |
| `consumedAt` | Timestamp? | Set when SM-1 processes this correction |

**Priority rule (PI-010)**

ProfileCorrections are consumed by SM-1 with higher priority than AI inference. A correction saying "not me" on a hypothesis will move it to `weakened` regardless of how many entries support it. User corrections are ground truth.

**Weekly calibration ritual**

The app surfaces a "Teach Spilr" prompt once per week: 3 taps, 30 seconds. Shows 2–3 hypotheses the system is least confident about and asks for a rating. This feeds SM-1 without requiring active correction sessions.

---

## Next-Best-Question Engine (Prompt NBQ)

**Purpose**

Generates personalised writing prompts (Mirror Seeds) from unresolved Self Model hypotheses. "You often write 'reset' when you feel behind — was today a reset day or a rest day?" instead of a generic "What felt familiar today?"

**Prompt version:** `mirror-nbq-v1`  
**Temperature:** 0.5  
**Execution:** client-side or server, on session start or after SM-1 run

**Input:** SelfModel hypotheses with `userStatus: unrated` or `userStatus: half_true`, sorted by most actionable and least recently tested.

**Output schema**

```json
{
  "question": "string",
  "targetHypothesisId": "string",
  "seedChipLabel": "string (short label for the chip UI)",
  "riskLevel": "low | medium"
}
```

**NBQ rules**

- Question must be answerable in 90 seconds of writing.
- Never clinical or interrogating.
- Always grounded in the user's own language (uses `vocabulary` entries and `phrasesToTrack` from EntryAnalysis).
- If `riskLevel` is `medium`, the question is reviewed by Prompt E before being surfaced.
- NBQ output replaces the most generic default Mirror Seed for the current write session.

`lastTestedAt` on the hypothesis is updated when NBQ generates a question for it, preventing the same hypothesis from being questioned every session.

---

## First Sketch Unlock (Phase 11)

**Trigger:** 7 entries saved.

The First Sketch is the earliest "wow" moment — the first time the app shows the user something real about themselves, backed by evidence.

**Content**

| Slot | Source |
|---|---|
| A rule | Highest-confidence `coreRules` hypothesis |
| A protective move | Highest-scoring `protectiveStrategies` hypothesis |
| A part that shows up | Highest-confidence `innerParts` or `relationshipRoles` hypothesis |
| A thing that helped | Highest-confidence `whatHelps` hypothesis (exception-type) |
| One question for next week | `nextBestQuestion` from the SM-1 run that produced these hypotheses |

Each slot is shown sequentially with a reveal animation. The user taps to advance through the 4 hypotheses, then sees the question on a final screen.

This screen merges the "First Mirror" concept from the Mirror Engine PRD. Both features reference the same 7-entry unlock and the same output — they are one screen, not two.

**Implementation priority**

The thinnest vertical slice that reaches this screen as fast as possible: Phase 8 (Self Model schema) → Phase 9 (counter-evidence pass) → Phase 11 (First Sketch screen). Unblock this path before building the full My Self Model screen.

---

## Profile-Mirror Writer (Prompt PM)

Milestone cards shown at 14, 30, and 90 entries. Applies the deeper-insight formula (from Mirror Engine PRD) at the Self Model level — across the whole user, not a single day.

**Prompt version:** `mirror-profilemirror-v1`  
**Temperature:** 0.4  
**Execution:** server, triggered when entry count crosses milestone

**Output schema**

| Field | Notes |
|---|---|
| `title` | Short label for the milestone card |
| `mainReflection` | The deeper-insight formula applied to a Self Model hypothesis |
| `whatItMayProtect` | Why this pattern might make sense |
| `whatItMayCost` | What it quietly takes |
| `evidenceReceipts` | [{quote, whyItMatters}] — 2–3 anchors in the user's own words |
| `exception` | When this pattern softened or was absent |
| `questionToCarry` | The question to sit with |
| `tinyExperiment` | One low-stakes action |
| `confidence` | low / medium / high |

Every Profile-Mirror card ends with a question, never a verdict. The `exception` field is mandatory — no milestone card may be generated without identifying at least one exception.

---

## PI Requirements Table

| ID | Requirement | Phase |
|---|---|---|
| PI-001 | Maintain a private SelfModel document per user | Phase 8 |
| PI-002 | Separate temporary state (scope: today/this_week) from recurring pattern (scope: recurring/user_confirmed) | Phase 8 |
| PI-003 | Attach evidence AND counter-evidence to every hypothesis before surfacing | Phase 9 |
| PI-004 | Let users confirm, reject, edit, or hide any hypothesis | Phase 10 |
| PI-005 | Generate personalised prompts from unresolved hypotheses via NBQ engine | Phase 11 |
| PI-006 | Track exceptions and helpful levers (whatHelps), not only problems | Phase 9 |
| PI-007 | Never present hypotheses as diagnosis or fixed identity | Phase 8 |
| PI-008 | Allow deleting SelfModel separately from journal entries | Phase 10 |
| PI-009 | Maintain lifecycle states: observed_once → emerging → recurring → user_confirmed → weakened → retired | Phase 8 |
| PI-010 | Treat user corrections (ProfileCorrections) as higher-priority truth than AI inference | Phase 10 |

---

## Phase Grouping

| Phase | Requirements addressed |
|---|---|
| Phase 8 | PI-001, PI-002, PI-007, PI-009: Self Model schema, lifecycle, scope/stability, doNotInfer |
| Phase 9 | PI-003, PI-006: Counter-evidence pass (Prompt CE), exception tracking, whatHelps section |
| Phase 10 | PI-004, PI-008, PI-010: My Self Model screen, ProfileCorrection flow, delete option |
| Phase 11 | PI-005: NBQ engine, First Sketch screen, personalised Mirror Seeds |

---

## Write Contention

SM-1 is the **single writer** of `selfModel/current`. No other service writes to this document.

**Race condition prevention**

- The `version` field is incremented on every SM-1 write.
- ProfileCorrections and Mirror feedback are written to separate collections (`profileCorrections/`, `mirrors/`) and consumed by SM-1 on the next nightly run — they never write directly to `selfModel/current`.
- If two SM-1 invocations overlap (e.g., a triggered run and the nightly run), the one with the higher input `version` wins. The other run discards its output.
- User-triggered profile corrections queue immediately to `profileCorrections/` but take effect on the next SM-1 run — corrections always win over AI inference (PI-010), but they do not race with the current write.

---

## Retrieval Strategy

Self Model mining reads from EntryAnalysis and episodes — never from raw decrypted journal text server-side. This is a hard privacy constraint (see Privacy PRD).

**Retrieval modes (by phase)**

| Mode | When used | Implementation |
|---|---|---|
| Recency + keyword | Phase 8–9 | Sort EntryAnalysis by createdAt; keyword match on surfaceSummary and phrasesToTrack |
| Similar | Phase 9+ | Find EntryAnalysis docs where inferredEmotions or protectiveStrategies overlap with a target hypothesis |
| Contradictory | Phase 9+ | Find EntryAnalysis docs where opposite patterns appear — feeds counterEvidence |
| First-seen | Phase 9+ | Query by earliest entryId in a hypothesis's evidenceEntryIds |
| Most-intense | Phase 9+ | Query on emotionalWeight from EntryAnalysis |
| Exception-day | Phase 9+ | Query exception-type PatternHypotheses; cross-reference with whatHelps entries |

Embeddings-based semantic retrieval is deferred. The keyword + recency heuristic is sufficient for Phases 8–11. Upgrade to embeddings if insight specificity degrades at scale.
