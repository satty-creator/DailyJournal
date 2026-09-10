# AI Cost Audit — DailyJournal (Spilr)

Date: 2026-09-06
Scope: every LLM call the product makes, what each one costs, which ones are duplicated or unearned, and what a 14-day trial vs. an unlimited paid tier can each afford.

Sequel to `ai-usage-audit-2026-09-02.md`, which asked whether each call site was *safe*. This one asks whether each call site is *paid for*. Read-only survey of `AIService*.swift`, `MirrorView.swift`, `HintEngine`/`QuestionEngine`, `PatternDetectionService`, `ReadService`, and `functions/index.js`. No code changed.

---

## 0. The headline

| | today | after the cuts in §4 |
|---|---|---|
| Engaged daily user | **$1.49 / month** | **$0.37 / month** (−75%) |
| p95 power user (3 chats + 3 entries/day) | **$2.92 / month** | **$1.50 / month** (−49%) |
| 14-day trial user (median) | ~$0.42 uncapped | **$0.14 capped** |
| Worst case a single account can force | **$130 / month** | **~$3 / month** |

Two conclusions:

1. **"Unlimited for paid" is not safely offerable today.** At $4.99 with a 30% store cut (net $3.49), a p95 user already burns 84% of net revenue on inference, and the only thing stopping a determined account from spending $130/month is a 60-calls-per-hour cap that no cost model was built around. After the cuts, p95 lands at 43% of net at $4.99 and 25% at $6.99 — that is when "unlimited" becomes a defensible promise.
2. **The expensive layer is not the layer users feel.** Chat is 20% of spend and is the product. The profile-intelligence stack (mining, counter-evidence, pattern detection, Mirror cards) is **47%** of spend and runs almost entirely in the background, twice, in two parallel systems that were never merged.

---

## 1. Pricing basis

Model is `gemini-3.5-flash-lite`, pinned server-side (`functions/index.js:193`).

| | per 1M tokens |
|---|---|
| Input | $0.30 |
| Output | $2.50 |
| Cached input | $0.03 |
| Batch API | 50% of the above |

Rates checked 2026-09-06 against [OpenRouter](https://openrouter.ai/google/gemini-3.5-flash-lite) and [BenchLM](https://benchlm.ai/google/api-pricing); caching thresholds from [Google's context-caching docs](https://ai.google.dev/gemini-api/docs/caching). Re-check before committing to a price point.

Output is **8.3× input**. Current spend splits ~49% input / 51% output, so both levers matter, but a token you *ask for* costs eight times a token you *send*. Every `maxTokens` budget in the codebase is a direct cost decision.

**Context caching does not rescue this.** Implicit caching needs a ≥4,096-token matching prefix on the 3.5 generation; almost every prompt here is 1,800–4,000 tokens, and the only ones that clear the bar (the mining corpus) change nightly, so they never hit. `SpilrVoice.system` (1,280 tokens) is prepended to ~11 call sites and is re-billed at full price every single time. The fix is to make prompts smaller and to make fewer calls — not to cache.

Assumptions used throughout: average entry ≈ 200 tokens (~150 words); `cachedPromptContext()` ≈ 150 tokens; engaged user = 1 entry/day, 1 chat session every other day (10 turns), opens the editor 1.5×/day, opens Mirror daily.

---

## 2. Every call site, priced

`SYS` = `SpilrVoice.system` = 1,280 tokens (personality 471 + safetyRules 803). It is in the input column of nearly every row below.

| # | Flow | File | in | out | $/call | fires | $/user/day |
|---|---|---|---|---|---|---|---|
| 1 | Journal insights | `AIService.generateInsights` | 1,810 | 200 | $0.00104 | every save | 0.00104 |
| 2 | Echo extraction | `AIService.extractEcho` | 2,642 | 150 | $0.00117 | every new entry | 0.00117 |
| 3 | Mirror extract (Prompt A) | `AIService+Mirror.analyzeEntry` | 2,089 | 700 | $0.00238 | **every save, incl. edits** | 0.00238 |
| 4 | Hints enrichment | `AIService+Hints.enrichHints` | 2,020 | 450 | $0.00173 | **every editor open** | 0.00260 |
| 5 | Questions enrichment | `AIService+Questions.enrichQuestions` | 1,988 | 550 | $0.00197 | **every editor open** | 0.00296 |
| 6 | Chat turn ×10 | `AIService+Chat.nextChatTurn` | 33,300 | 1,800 | $0.01449 | per session | 0.00724 |
| 7 | Weave to entry | `AIService+Chat.weaveEntry` | 2,301 | 650 | $0.00232 | per session | 0.00116 |
| 8 | Re-extract on woven entry | (1)+(3) again | 3,899 | 900 | $0.00342 | per session | 0.00171 |
| 9 | Today's Read (server) | `functions:generateForUser` | 1,280 | 60 | $0.00053 | daily/user | 0.00053 |
| 10 | Today's Read (client dupe) | `AIService+Read` | 3,143 | 60 | $0.00109 | on server miss | 0.00033 |
| 11 | Mirror card (Prompt D) | `generateMirrorCard` | 3,863 | 800 | $0.00316 | daily | 0.00316 |
| 12 | Mirror guard (Prompt E) | `guardMirrorCard` | 1,200 | 300 | $0.00111 | daily | 0.00111 |
| 13 | **Mirror mine (client)** | `MirrorView.runMiningIfNeeded` | 12,380 | 1,200 | $0.00671 | daily (24h cooldown) | 0.00671 |
| 14 | Pattern detection | `AIService+Patterns.detectPatterns` | 5,843 | 500 | $0.00300 | ~20h throttle | 0.00300 |
| 15 | **Server nightly mine** | `functions:mineHypothesesForUser` | 13,200 | 1,200 | $0.00696 | nightly | 0.00696 |
| 16 | **Counter-evidence ×4** | `functions:buildCounterEvidencePrompt` | 8,960 | 1,600 | $0.00669 | nightly | 0.00669 |
| 17 | Ask (journal Q&A) | `MirrorView.swift:1239` | 5,757 | 400 | $0.00273 | 0.3/day | 0.00082 |
| | | | | | | **TOTAL** | **$0.0496/day = $1.49/mo** |

Row 17 is **not in the previous audit's table** — `MirrorView.swift:1239` builds and sends its own prompt inline rather than going through an `AIService+` extension, so it was missed. It has a bespoke safety block, no `tripsLint`, and no cost ceiling on the entries it renders into the prompt.

`structureVoiceRant` (`AIService.swift:402`, 600 output tokens) is **defined and never called** from anywhere in the app. Dead code carrying a live prompt.

### Where the money actually is

| cluster | $/mo | share |
|---|---|---|
| Profile intelligence (13, 14, 15, 16) | $0.70 | **47%** |
| Chat (6, 7, 8) | $0.30 | 20% |
| Hints / Questions (4, 5) | $0.17 | 11% |
| Entry save (1, 2, 3) | $0.14 | 9% |
| Mirror card (11, 12) | $0.13 | 9% |
| Today's Read (9, 10) | $0.03 | 2% |
| Ask (17) | $0.02 | 2% |

---

## 3. The five structural problems

### 3.1 Pattern mining runs twice, in two independent systems

`MirrorView.runMiningIfNeeded` (client, 24h cooldown, `mirrorLastMiningDate_{uid}` in UserDefaults) and `mineUserInsights` (server, nightly, 4am UTC) both read the same `entryAnalyses` corpus, both send a near-identical prompt, and both write to `users/{uid}/patternHypotheses`. Neither knows the other exists — the client cooldown is per-device UserDefaults, the server gate is `lastMineRunAt` on the user doc.

That is **$0.0067/user/day, or 13.5% of total spend, for a duplicate result.** It is also a correctness problem: two writers minting hypotheses into the same collection is how duplicate identities and re-surfaced closed threads happen, which the server code has a 30-line comment apologising for.

Separately, `PatternDetectionService` (row 14) is a *third* pattern engine — `PatternCallback` — running on a 20h throttle over a 60-day window. `PATTERNS_MERGE_PLAN.md` already exists in this repo and describes merging it into the hypothesis system. That plan is worth $0.09/user/month.

### 3.2 Hints and Questions call the model on view construction

`HintEngine.init` and `QuestionEngine.init` both end with `Task { await self?.enrich() }`. They are `@StateObject`s in `JournalEditorView`, `SpillWriteView`, and `TimedSessionView` — so **opening the editor fires two LLM calls (1,000 output tokens, temperature 0.7) before the user has typed a character or asked for a hint.**

The input is `HintContext(pebbles, personal, mode)` — a tiny, low-cardinality key. Most users have a handful of pebble combinations, and the output is a bundle of writing prompts with no per-user secrets in it at the `.safe` and `.light` personal levels. This is the single most cacheable call in the product and it is currently the least cached. 11% of spend for output that is frequently never seen, because the local bundle is already on screen and the panel may never be opened.

### 3.3 The entry-save path sends the same entry to the model three times

`generateInsights`, `extractEcho`, and `analyzeEntry` each independently re-send `SpilrVoice.system` (1,280 tokens) plus the entry text, from three separate `Task.detached` blocks in `JournalEditorViewModel.save()`. That is 6,541 input tokens to analyse one 200-token entry — 3,840 of which is the same safety block, billed three times.

Worse: the comment at `JournalEditorViewModel.swift:203` says Mirror analysis "runs on every save (new or edited) so re-edited text re-analyses." There is **no content-hash check**. A user who saves, reopens, fixes a typo, and saves again pays for `analyzeEntry` twice on functionally identical text.

And `generateInsights` writes bullets the user has usually already moved past — the local reflection was shown during the session, and the AI version overwrites it in Firestore afterwards. It is a 200-output-token call whose result may never be read.

### 3.4 Today's Read is personalised at great structural expense and no token expense

`buildGeneratorPrompt` receives exactly three variables: `themes` (up to 8 tags), `dayTime` (weekday + "Morning"), and `tonePreference` (one of three words). That is a state space of a few thousand combinations across the entire user base, yet it runs one LLM call per user per day, plus a full client-side fallback path (`ReadService`, up to 3 attempts/day) that re-queries 14 entries and re-generates the same line.

At $0.00053 it is only 2% of spend, so this is not urgent — but it is the clearest example of a per-user call that should be a shared pool, and the client duplicate should be deleted outright.

### 3.5 There is no entitlement layer, and the only cost control is an abuse cap

`geminiProxy` (`functions/index.js:251`) enforces 60 calls/hour/UID, Firestore-backed. That is the entirety of cost control. Nothing in the codebase references StoreKit, RevenueCat, a subscription, an entitlement, a trial, or a paywall — I grepped for all of them.

Two consequences:

- **60 calls/hour = 1,440 calls/day.** At the blended $0.003/call in §2, one account can force **$4.32/day, $130/month.** No alert fires. The rate limiter counts *calls*, not tokens, so a caller who sends 30k-token prompts costs 10× a caller who sends 3k-token prompts and looks identical to it.
- **When entitlements are built, they must be enforced in `geminiProxy`, not in Swift.** Every quota below is a server-side decision keyed on the user doc. A client-side check is a suggestion; the proxy holds the key, so the proxy is the only place a limit is real. This is the single most important architectural note in this document, and it is cheapest to get right *before* the client has quota logic in it.

---

## 4. The cuts, ranked

Ordered by (saving × confidence) ÷ product risk. Percentages are of the $1.49 baseline.

| # | Cut | Saving | Product risk | Effort |
|---|---|---|---|---|
| 1 | **Delete `MirrorView.runMiningIfNeeded`.** The server already mines nightly. | 13.5% | none — duplicate output | 1 line |
| 2 | **Merge the entry-save trio into one call.** One prompt, one `SpilrVoice.system`, one JSON response carrying insights + echo + analysis. Add a content-hash guard so re-saves don't re-analyse. | 6% | none | medium |
| 3 | **Move the merged extract server-side, nightly, on the Batch API.** Nothing on the save path is read before the next session. Batch is 50% off. | +3% | echo latency: same-day echoes become next-day | medium |
| 4 | **Cache hint/question bundles by `(pebbles, personal, mode)` for 7 days, and only enrich when the panel actually opens.** | 10% | none — local bundle already ships first | small |
| 5 | **Merge `PatternDetectionService` into the hypothesis system** per `PATTERNS_MERGE_PLAN.md`. | 6% | consolidation already planned | large |
| 6 | **Mine every 3rd day (or on ≥3 new analyses), not nightly. Cut `ANALYSIS_LOOKBACK` 40 → 20. Run on Batch.** A 4am job has no latency requirement. | 9% | patterns update slightly slower | small |
| 7 | **Counter-evidence: `CE_MAX_HYPOTHESES` 4 → 2, and only audit hypotheses that are new or changed since the last run.** Today it re-audits the same top claims nightly. | 9% | fewer claims audited per run | small |
| 8 | **Trim the chat system instruction.** `scope` (273) + `conversationCore` (1,414) + `chatSafetyRules` (897) + `cbt` (1,061) = up to 3,645 tokens re-sent on **every turn**. Target 1,500. Cap `contents` at the last 12 turns plus a rolling summary. | 7% | needs re-testing against the failure modes in `chatprompt-teardown` | medium, highest care |
| 9 | **Mirror card: cache on the top hypothesis id.** Regenerate only when the top hypothesis changes, not daily. | 5% | none — the card was identical anyway | small |
| 10 | **Mirror guard: run `SpilrVoice.tripsLint` first, call the model only when the lint is borderline.** The deterministic check already exists and is stronger than the prompt. | 2% | none — strictly more enforcement | small |
| 11 | **Today's Read: one shared weekly pool, selected per user by tag overlap. Delete the client fallback path.** | 2% | reads become less individually tailored | medium |
| 12 | **Delete `structureVoiceRant`.** | 0% | none — dead code | 1 line |
| 13 | **Replace the call-count rate limit with a token budget, and add a per-UID daily spend ceiling with graceful degradation to local fallbacks.** | caps the tail | none for real users | small |

**Net: $1.49 → $0.37/user/month.**

Note the asymmetry: the mean drops 75%, the p95 only 49%. That is because a power user's bill is dominated by chat, which is real usage of the actual product and cannot be optimised away — only trimmed (cut 8). This is why "unlimited" needs the fair-use ceiling in cut 13 even after everything else lands.

### One thing not to cut

Every one of these is a *plumbing* change. None of them removes a surface, shortens an output the user reads, or lowers a temperature that was tuned for voice. Do not pay for margin by cutting `maxTokens` on `nextChatTurn` (180) or `generateMirrorNarrative` (500) — those ceilings are already doing double duty as quality constraints, and the `chatprompt-teardown` file documents what happens when chat gets terser.

---

## 5. Trial vs. paid

### 5.1 The tension to design around

The 14-day trial is close to the window in which the expensive layer produces the least value, and the maturity gates already in the code say so precisely:

- `PatternDetectionService.minJournalingDays = 14` — pattern callbacks **cannot fire at all** inside a 14-day trial. You pay for `detectIfNeeded` to be gated out for the entire trial.
- `MIN_ANALYSES = 3` (server mine) and `MirrorMaturity.soft` (3 entries) — the first hedged pattern needs 3 entries, so a trial user reaches it around day 3–5.
- `MirrorMaturity.unlock` (7 entries) — the First Sketch ceremony, the strongest single artefact in the product, lands around day 7–10 for someone journaling most days.
- `MirrorMaturity.deeper` (14 entries) — only reachable inside 14 days by a daily journaler.

So the trial cannot be "everything, for 14 days" — that spends the most on the surfaces that impress the least, and it pays for one engine (`PatternDetectionService`) that is structurally incapable of producing anything before the trial ends. Front-load the surfaces that are cheap and immediately good (chat, echo, reads, hints), and stage two deliberate, expensive payoff moments from the profile layer, positioned as *the thing you lose*.

Trigger those two moments on `MirrorMaturity` transitions (`.soft` at 3 entries, `.unlock` at 7) rather than on calendar day. The payoff then arrives when there is genuinely something to say, which is the whole argument for paying — and a trial user who never reaches 3 entries never costs you a mining run.

### 5.2 Entitlement matrix

Every quota is enforced **in `geminiProxy`**, keyed on an `entitlement` field on the user doc plus a `surface` field the client sends in the request body. Client-side gating is UI only.

| Surface | Trial (14 days) | Paid ("unlimited") | Why |
|---|---|---|---|
| **Daily Chat — Normal** | 3 sessions/day, 20 turns/session | unlimited, 40-turn soft cap per session | The core loop. Generous in trial; the cap exists only to stop a runaway thread. |
| **Daily Chat — CBT / Thought Journal** | 1 session/day | unlimited | The `cbt` prompt block is 1,061 tokens on top of the shared core and runs at 400 output tokens/turn — roughly 2× a normal turn. Natural premium mode. |
| **Weave to entry** | with every session | with every session | Cheap, and it is the payoff of the chat. Never gate this. |
| **Entry insights + sentiment** | on | on | Cheap after cut 2; gating it makes the free experience feel broken. |
| **Echo extraction** | on | on | $0.001. The "it remembered" moment is the best trial hook in the product. |
| **Mirror entry analysis (Prompt A)** | on | on | It is the *substrate* — gating it means the day-7 payoff has nothing to mine. Runs nightly on Batch either way. |
| **Today's Read** | daily, from the shared pool | daily, from the shared pool + tag-matched | Effectively free. Same for both. |
| **Hints / Questions** | cached bundles only | live enrichment on panel open | Trial users get the local + cached ladder, which is already good. |
| **Mirror card** | **2 total** — one per mining run below | daily (regenerated when the top hypothesis changes) | The staged payoff. Two cards, timed. |
| **Pattern mining** | **2 runs** — at the `.soft` and `.unlock` transitions | every 3rd day | Feeds the two cards above. |
| **Counter-evidence pass** | off | on | This is a *quality* feature: it is what stops a claim surviving because nobody looked. "Your patterns get audited against the entries they didn't cite" is a real, honest paid differentiator. |
| **Ask your journal** | **5 questions total** | unlimited, 50/day fair use | High perceived value, high input cost (renders entries into the prompt). A hard, countable trial allowance is legible: "3 of 5 questions left". |
| **Model tier** | Flash-Lite everywhere | Flash-Lite everywhere; **Flash on mine, Mirror card, and Ask** | See §5.4. |

### 5.3 What this costs

| | per user |
|---|---|
| Median trial user (journals ~8 of 14 days, 7 chats) | **$0.137** |
| Trial user who hits every cap, every day | **$0.62** |
| 10,000 trial signups/month | **~$1,400** |
| Paid engaged user | **$0.434 / month** |
| Paid p95 power user | **$1.50 / month** |

Against net revenue after the store cut:

| price | store cut | net | AI as % of net (engaged) | (p95) |
|---|---|---|---|---|
| $4.99 | 30% | $3.49 | 12.4% | 43% |
| $4.99 | 15% | $4.24 | 10.2% | 35% |
| $6.99 | 30% | $4.89 | 8.9% | 31% |
| $6.99 | 15% | $5.94 | 7.3% | 25% |
| $9.99 | 15% | $8.49 | 5.1% | 18% |

At $6.99 with the Small Business Program rate, inference is 7% of net for a typical subscriber and 25% for the heaviest. That is a healthy structure and it makes "unlimited" an honest word.

For contrast, **without the §4 cuts**, the same p95 user is 84% of net at $4.99/30% — which is the number that says the current architecture cannot carry an unlimited tier at a consumer price point.

Trial cost is dominated by chat (65% of it). If trial CAC needs to come down further, the lever is chat sessions/day (3 → 2), not the profile layer.

### 5.4 Model tier as the paid differentiator

Everything currently runs on Flash-Lite, including the mining prompt — which is the one call in the product whose entire job is to produce a non-obvious, specific, quoted insight, and which the `SPECIFICITY CONTRACT` in `buildMinePrompt` spends 300 tokens begging for. Flash-Lite is a reasonable place to *start* that call and a poor place to leave it.

Running Flash ($1.50/$9.00) on just three surfaces for paid users — the nightly mine, the Mirror card, and Ask — adds roughly **$0.28/paid user/month** (mine 10 runs, card ~8, Ask ~9). That takes the paid user from $0.43 to $0.71 — still 12% of net at $6.99/15% — and buys the thing the paid tier is actually selling. It is a better use of margin than any of the copy on a paywall screen.

Trial users stay on Flash-Lite throughout. The upgrade is then a real change in output quality, not a counter that stops moving.

### 5.5 Guardrails "unlimited" needs

1. **Token budget, not call count.** Replace the 60/hour call limit with a rolling per-UID token budget (e.g. 400k input + 60k output per day for paid — roughly 8× the p95 user). Count tokens returned in `usageMetadata`, which the proxy already receives and currently discards.
2. **Degrade, never 429.** Over budget → fall through to the local engines (`LocalAI`, `HintLadder.localBundle`, `LocalPatternDetector`, `localNextTurn`) that already exist for every surface. The user sees a slightly plainer app, not an error. This is the reason the local-fallback discipline in `CLAUDE.md` is worth money as well as uptime.
3. **Per-surface ceilings inside the budget**, so one runaway surface cannot eat the whole allowance.
4. **Log `usageMetadata` per call with `uid` + `surface`.** None of this is measurable today — every number in this document is modelled from prompt lengths and `maxTokens` ceilings, not from billing. That is fine for prioritising; it is not fine for operating. This is the first thing to build, because it is what tells you which of the estimates in §2 are wrong.

---

## 6. Suggested order

1. Instrument first — log `usageMetadata` per `(uid, surface)` in `geminiProxy`. One day of real data replaces every estimate here.
2. Cuts 1 and 12 (delete the duplicate mine, delete the dead prompt). Two lines, 13.5%.
3. Cuts 4, 6, 7, 9, 10 — the caching and cadence changes. No product surface moves. ~35%.
4. Cuts 2 and 3 — merge the entry-save trio and move it to nightly Batch. ~9%.
5. Cut 13 — the token budget and graceful degradation. This is the prerequisite for shipping any "unlimited" claim.
6. Build the entitlement layer in `geminiProxy` per §5.2.
7. Cut 8 — the chat prompt trim. Last, because it is the one that can regress voice, and it needs a live re-test against `chatprompt-teardown-2026-09-02.md`.
8. Cut 5 — the pattern merge, per the existing plan.

---

## 7. Where these numbers could be wrong

- **Average entry length.** I assumed 200 tokens. If real entries average 500, rows 1–3 and 17 roughly double and the entry-save cluster overtakes hints/questions.
- **Realistic output vs. `maxTokens`.** I estimated actual output at 50–70% of each ceiling. If the model routinely saturates its budgets — likely for the JSON-schema calls (3, 15) — total spend is 20–30% higher and the output-side cuts get correspondingly more valuable.
- **Chat session length.** Modelled at 10 turns. This is the assumption the whole chat cluster pivots on, and it is measurable today from existing analytics.
- **Trial conversion behaviour.** §5.3 assumes a median trial user journals 8 of 14 days. Your onboarding funnel data should replace this.
- Nothing here is measured. §6 step 1 exists for that reason.
