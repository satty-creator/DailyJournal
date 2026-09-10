# Spilr AI architecture — engineering decisions

**For:** Satakshi · Spilr (ninety) · 2026-09-09
**Stance:** staff-engineer review of the AI layer, storage, and chat reliability. Read-only; no code changed.
**Inputs:** `functions/index.js` (2,918 lines), `AIService*.swift`, `Chat/*`, `Mirror/*`, `Journal/EntryEncryption.swift`, `Components/KeychainHelper.swift`, `firestore.rules`, `ai-cost-audit-2026-09-06.md`, `chatprompt-teardown-2026-09-02.md`, git history.
**Companion to:** `rosebud-teardown-mirror-redesign-2026-09-09.md` (product) — this is the engineering half.

Every decision below is written as: **evidence** (file and line), **decision**, **why**, **cost or risk**, **effort**. The sequencing at the end is the part to argue with.

---

## 0. Where the codebase actually is

Credit where due: since the Sept 6 audit, the cheap cuts have landed. Mining is server-side and the client only bootstraps once (`MirrorView.swift:342–392`, gated on `users/{uid}.lastMineRunAt`); the Mirror card is written once per mine cycle, not daily; the 60-calls/hour limiter is replaced by token budgets with a per-surface share cap (`functions/index.js:223–301`); hint/question enrichment no longer fires on editor open (`HintEngine.swift:27`); chat has a 12-turn window, an anti-repetition block, a lint retry, and `systemInstruction` in the right place (`AIService+Chat.swift:244–360`); `cachedContentTokenCount` is logged so cache behaviour is measurable.

What has not changed, and what the audit did not look at:

| Finding | Status | Where |
|---|---|---|
| Entry save still sends the entry to the model three times, no content-hash guard | **open** (audit cut #2) | `JournalEditorViewModel.swift:191–225` |
| Prompts are split across the iOS binary and the Cloud Function; the proxy is a transparent relay | **not in audit** | `functions/index.js:303–487`; every `AIService+*.swift` |
| Entry encryption key is device-local, non-synchronised, non-recoverable | **not in audit** | `EntryEncryption.swift:16–27`, `KeychainHelper.swift:17` |
| Server-owned state (`patternHypotheses`, `selfModel`, `lastMineRunAt`) is client-writable | **not in audit** | `firestore.rules:43–47` |
| Chat forgets everything before turn 12 by instruction, with no summary to replace it | **partially addressed** | `AIService+Chat.swift:274–281` |
| Zero tests (no XCTest target, no functions tests); two git commits, last one 11 June | **not in audit** | repo root, `functions/` |
| `functions/index.js` is one 2,918-line file with 13 prompt bodies inline | **not in audit** | `functions/index.js` |

The rest of this document is eleven decisions that address those, ordered by leverage rather than by area.

---

## 1. The structural decision: server-owned AI operations

**Evidence.** `geminiProxy` forwards `{contents, systemInstruction, generationConfig}` verbatim after auth and budget checks (`functions/index.js:391–420`). Prompt text is assembled on the client in nine Swift extensions plus an inline prompt in `MirrorView.swift:1239`; five more prompts live server-side. `SpilrVoice.safetyRules` and `SAFETY_RULES` (`functions/index.js:563`) are hand-synchronised copies with a comment asking future editors to keep them aligned. `SpilrVoice.system` (1,280 tokens) is prepended client-side to ~11 call sites.

**What this costs you today.**

- *Prompt changes ship on the App Store review cycle.* A bad line in `conversationCore` is a 1–3 day fix plus whatever fraction of users update. The `chatprompt-teardown` failures (fabricated empathy, third-party verdicts, apology loops) were prompt bugs; with server prompts they are a redeploy.
- *The proxy is an authenticated open relay.* Any signed-in user with a jailbroken phone or a MITM proxy can send arbitrary `contents` to Gemini on your key, within their token budget. The budget bounds cost, not use. App Check is soft-enforced (`functions/index.js:322–334`).
- *You cannot route models per surface.* `MODEL` is one constant (`functions/index.js:193`). Chat — the product — runs on the same lite model as tag extraction because the proxy has no idea which is which beyond a client-supplied string.
- *You cannot cache, batch, or evaluate centrally.* Context caching needs a byte-stable prefix the server controls; the Batch API needs the server to own the job; an eval harness needs the prompt in one place with fixtures.
- *Two safety blocks drift.* They already differ in wording (`SPILR_VOICE` on the server insists on sentence case; the Swift personality says "lowercase-friendly").

**Decision.** Replace the relay with a small set of named operations. The client sends *structured inputs*, never prompt text:

```
POST /ai/chatTurn         { sessionId, mode, newMessage }            → { reply, suggestions, readyToWeave }
POST /ai/analyzeEntry     { entryId, text, contentHash }             → { insights, echo, analysis }   (one call, was three)
POST /ai/weave            { sessionId }                              → { entryText }
POST /ai/ask              { question }                               → { answer, citations[] }
POST /ai/enrichHints      { pebbles, personal, mode }                → { bundle }   (server-cached by key)
```

The server assembles the prompt from a **prompt registry** (§3), picks the model per operation, applies the deterministic lint, records usage, and returns typed JSON. `geminiProxy` stays for one release as a fallback and is then deleted.

**Why not keep client prompts for privacy?** The privacy posture is "the server never *stores* plaintext" — and that is already the truth, not "the server never *sees* it." Every chat turn and every entry already transits the proxy in plaintext on its way to Gemini. Server-side operations keep the same posture: process in memory, persist only derived signals, never log bodies. Write that sentence into `privacyprd.md` because it is the accurate one.

**Cost / risk.** One release where both paths coexist. The chat operation needs the transcript server-side for the duration of the call — pass the window in the request (as now) rather than reading the encrypted `chatSessions` doc; the server cannot decrypt it and should not be able to.

**Effort.** Medium-large; ~2 weeks including the registry. It is the prerequisite for decisions 2, 3, 4, 5 and 8, which is why it is first.

---

## 2. AI efficiency: where the ROI actually is

The audit priced calls. These are the *architectural* levers, in order of return.

### 2.1 One call on save, guarded by a content hash

**Evidence.** `JournalEditorViewModel.save()` launches three detached tasks — `generateInsights`, `extractEcho`, `analyzeEntry` — each re-sending `SpilrVoice.system` plus the entry (`:191–225`). The comment at `:211` says analysis runs "on every save (new or edited)"; there is no hash check. A typo fix re-analyses the whole entry.

**Decision.** One `analyzeEntry` operation returning `{insights, echo, analysis}` from one prompt; skip entirely when `sha256(normalised text)` matches `entryAnalyses/{entryId}.contentHash`. Store the hash on the analysis doc.

**Why.** 6,541 → ~2,300 input tokens per save (audit §3.3), and edits become free. `EntryAnalysis` already contains everything `JournalInsights` and `EchoExtractionResult` need — `phrasesToTrack`, `inferredEmotions`, `surfaceSummary` — so the two smaller extractions are strictly redundant.

**Effort.** Small once §1 exists; medium as a client-only change.

### 2.2 Decide caching with the number you are already logging

**Evidence.** `cachedContentTokenCount` is logged per call (`functions/index.js:440–452`). The audit assumed implicit caching never engages because prompts are under the threshold.

**Decision.** Pull two weeks of that log by `surface`. If `cachedContentTokenCount / promptTokenCount` for `chat_turn` is under 20%, create an **explicit** context cache for the chat system instruction per session (instruction is ~3,600 tokens, byte-stable across turns after §1) with a 30-minute TTL refreshed on each turn. If it is already above 50%, do nothing.

**Why.** Chat is 20% of spend and the only surface where the same large prefix is resent many times in minutes. Explicit caching charges storage per hour, so it only pays inside an active session — which is exactly the shape of chat. Do not cache the reflection surfaces; they run once.

**Effort.** Small. Decision gated on data you already have.

### 2.3 Route models per operation

**Evidence.** One model for everything (`functions/index.js:193`). The chat teardown documents quality failures that are partly a lite-model ceiling (fabricated detail at low evidence, template lock-in at 0.7).

**Decision.** In the registry, each operation names its model. Start with: chat turn and weave on `gemini-3.5-flash` (non-lite); extraction, mining, counter-evidence, guard, hints on `flash-lite`; Ask on `flash`. Re-run the cost model — chat input roughly doubles in price, so expect +25–35% on the p95 user *before* §2.2 and §4.1, roughly neutral after.

**Why.** Chat is the product and the only surface where a user is waiting and reading every word. Spend quality there; spend nothing extra on nightly extraction nobody reads.

**Effort.** Trivial once §1 exists; impossible before it.

### 2.4 Nightly work on the Batch API, on a schedule tied to evidence, not the clock

**Evidence.** `mineHypothesesForUser`, counter-evidence, `updateSelfModel`, and Mirror card writing run nightly per user through Cloud Tasks (`functions/index.js:69–185, 1536, 1982, 2511`). `MIN_NEW_ANALYSES_TO_MINE = 3` and `MINE_MAX_STALENESS_HOURS = 72` already gate on evidence — good.

**Decision.** Move the four nightly LLM calls to Gemini's Batch API (50% off, per the audit's pricing). Keep the evidence gates. Move the merged `analyzeEntry` from §2.1 to the same batch *only* for entries older than the current session (an entry written at 11pm can wait until 4am; the Echo for it appears next day — Rosebud's users tolerate exactly this with the weekly report).

**Why.** 47% of spend is this background stack. Halving it is the single largest line item left after the duplicate mining was deleted.

**Risk.** Same-day Echo becomes next-day for late entries. Keep the on-save path for entries written before ~8pm local if that matters; measure Echo tap rate by hour first.

**Effort.** Medium — batch job submission plus a result-collection function.

### 2.5 Output-token discipline as a registry field, not a per-call literal

**Evidence.** Output is 8.3× input in price. `maxTokens` is a literal at each call site (180, 400, 700, 1000, 1200…).

**Decision.** Every operation in the registry declares `maxOutputTokens`, a `responseSchema` (Gemini structured output), and whether the result is read synchronously by a human. Lint rejects any operation without all three. Anything not read synchronously gets the smallest schema that downstream code actually consumes — `EntryAnalysis` has 16 top-level fields plus episodes; check which ones `MirrorGraphService`, `EchoService` and mining actually read, and drop the rest from the schema.

**Effort.** Small; mostly deletion.

---

## 3. Prompts as versioned, tested artefacts

**Evidence.** Prompt versions exist as strings (`mirror-extract-v1`, `mirror-mine-v3`, `mirror-write-v2`, `read-gen-v4`) and are stamped on derived docs — that is the right instinct. But there is no place where a version maps to a prompt body, no changelog, and no test. The verbatim dump in `ai-prompts-verbatim-2026-09-02.md` was produced by hand because nothing produces it automatically. There are no tests in the repo at all — no XCTest target, no `functions/*.test.js`.

**Decision — a prompt registry with three parts.**

1. **`functions/prompts/{operation}/{version}.js`** exporting `{ system, build(inputs), model, temperature, maxOutputTokens, responseSchema, lint }`. `index.js` shrinks to routing and budgets. The safety block becomes one module imported by every prompt — the "keep in sync" comment disappears.
2. **Golden fixtures**: `functions/prompts/{operation}/fixtures/*.json` — real-shaped inputs (synthetic entries, the `chatprompt-teardown` screenshots turned into transcripts) with *assertions on the output*, not exact matches: contains a verbatim phrase from the input; no banned term; ≤ N characters; JSON validates against the schema; for chat, does not start with the same word as the previous line. Run against the live model in CI on prompt change only (cost: cents).
3. **`PROMPT_VERSION` on every derived doc** (already) plus a **backfill policy**: a version bump never rewrites history; consumers read the doc's version and either accept it or skip it. Today a `mirror-mine-v3` hypothesis and a `v2` one are indistinguishable to `MirrorScore`.

**Why.** The failures in `chatprompt-teardown` — fabricated empathy on a six-word input, verdicts on the husband, the apology loop — are each one fixture. Without fixtures, the next prompt edit reintroduces them silently. The deterministic lints (`tripsBannedLint`, `tripsLabelLint`, `containsCrisisSignal`, `SpilrVoice.tripsLint`) are the strongest quality tools in the codebase; a fixture suite is how you know they still fire.

**Effort.** Medium; do it as part of §1 so prompts move once.

---

## 4. Chat that stays coherent for forty turns

The current design is sound for ten turns. Four changes make it sound for forty, and cheaper.

### 4.1 Rolling session state instead of a truncation notice

**Evidence.** After 12 user turns the window drops earlier messages and appends "Don't refer to specifics from before this point unless the user brings them up" (`AIService+Chat.swift:278–281`). The model is *instructed to forget*. That is the mechanism behind "it lost the thread" and behind re-asking a question from turn 4 at turn 15 — the same circularity Rosebud is criticised for.

**Decision.** Maintain a `SessionState` object, updated by a tiny structured call every 6 user turns (temp 0.2, ≤ 120 output tokens, schema below), injected into the system instruction as `SO FAR`. Shrink the live window from 12 to 8 turns.

```json
{
  "topic": "one line, their words",
  "people": ["Priya (colleague)", "Dan"],
  "asked_already": ["why she said yes", "what she wanted instead"],
  "user_stated_want": "to stop covering shifts without resentment",
  "emotional_read": "flat, a little defensive — their word: 'whatever'",
  "open_thread": "she never answered whether Priya has ever covered for her"
}
```

**Why.** One 120-token call per six turns replaces four resent turns of ~150 tokens each on every subsequent turn; net cheaper by turn 14 and coherent indefinitely. `asked_already` is a stronger anti-repetition control than the last-3-lines block because it tracks *questions*, not sentence shapes. `open_thread` gives the model something Rosebud's users say they want: a companion that remembers what it asked.

**Effort.** Small-medium. Persist `SessionState` on the `chatSessions` doc (encrypted, same as the transcript) so a resumed session resumes its state.

### 4.2 Cancel in-flight work; check `finishReason`; make appends idempotent

**Evidence.** `send()` guards on `isThinking` (`DailyChatView.swift:215`) but the `Task` at `:240` is never stored or cancelled. If the user dismisses the sheet, switches mode, or the app backgrounds mid-call, the reply still lands in `messages` and `persistSession()` writes it. The response parser reads `parts.first.text` and never inspects `finishReason` (`AIService+Chat.swift:359–367`): a `MAX_TOKENS` cut lands as a sentence ending mid-word; a `SAFETY` block produces an empty candidate list and falls to the local engine with no signal to the user or the logs.

**Decision.** Store the in-flight `Task` on the VM and cancel it in `deinit`, on mode change, and on resume-from-another-session. Tag each request with the `messages.count` it was sent against and drop the reply if the count changed. Parse `finishReason`: on `MAX_TOKENS` trim to the last full sentence; on `SAFETY`/`RECITATION` log the reason with the surface and fall back explicitly.

**Effort.** Small. This is the class of bug that shows up as "the AI answered a message I deleted."

### 4.3 Bound the retry, and log why it happened

**Evidence.** A lint trip retries once at temp 0.3 (`:341–370`) — good — but the trip is not logged with the offending term, so you cannot see which banned words the model reaches for.

**Decision.** Log `{surface, promptVersion, lintRule, matchedTerm}` on every trip, client-side to Analytics and server-side to `console.log`. After two weeks, the histogram tells you which prompt lines are earning their tokens.

**Effort.** Trivial.

### 4.4 Server-side session ledger (after §1)

**Decision.** With `chatTurn` server-owned, the server keeps a per-session **turn ledger** in memory-scoped storage keyed by `sessionId`: state summary, turn count, cumulative tokens, last-3 lines. The client stops re-sending the anti-repetition block and the opener. Streaming (`streamGenerateContent`) becomes possible for free; the client-side word-by-word reveal (`revealReply`) can then be real rather than simulated, which matters when the reply is on `flash` rather than `flash-lite` and takes 2–3s.

**Effort.** Medium; only after §1.

---

## 5. Storage

### 5.1 The encryption key cannot be recovered — fix this before anything else in this section

**Evidence.** `EntryEncryption.key()` generates a 256-bit key on first use and stores it in the Keychain with `kSecAttrAccessibleAfterFirstUnlock` (`KeychainHelper.swift:17`). No `kSecAttrSynchronizable`; no escrow; no export. `entries.content` and `chatSessions.transcript` are AES-GCM under this key.

**Consequence.** New phone without iCloud Keychain restore, or a Keychain wipe, or an Apple ID migration: **every entry and every conversation this user has ever written is unrecoverable ciphertext in Firestore**, and the app has no way to tell them so before it happens. The privacy PRD's "export/delete" cannot export plaintext from a device that lacks the key.

**Decision (two parts).**

1. Set `kSecAttrSynchronizable: true` on the key item so it rides iCloud Keychain. This covers the common case (same Apple ID, iCloud Keychain on) and costs one line.
2. Add a **recovery-key flow**: on first entry, derive a 24-word recovery phrase (BIP-39 style or simply base32 of the key), show it once, require acknowledgement, and store `sha256(key)` on the user doc so the app can *verify* a pasted phrase without holding the key. This is what every E2E product from 1Password to Signal backups does. Add a plain "Your entries are encrypted with a key on this device — back it up" card to Settings.

**Why.** This is the one finding in this document that is a latent data-loss incident rather than a cost or quality issue. It should ship before the App Store listing says "encrypted."

**Effort.** Part 1: trivial. Part 2: small-medium (one screen, one setting, one verification).

### 5.2 Be accurate about what the server can read

**Evidence.** `entries.content` is encrypted; `entryAnalyses/{id}` is not, and holds `surfaceSummary`, `evidenceQuote`, `evidence`, `phrasesToTrack`, and per-episode `situation` in plaintext (`EntryAnalysis.swift:220–238`). The server mines and writes hypotheses containing verbatim quotes (`functions/index.js:1295, 1333`). Chat transcripts are encrypted at rest but transit the proxy in plaintext.

**Decision.** Do not change the architecture — it is a reasonable trade for a pattern engine. Change the *claim*. The accurate statement is: "Your full entries and conversations are encrypted with a key only your devices hold. To find patterns, Spilr stores short summaries and the specific phrases it quotes back to you, and those are readable by our servers." Put that in `privacyprd.md`, the privacy policy, and the Sept 2 competitive deck (slide 13 currently says "server sees signals only," which a reader will take to mean "no text").

**Effort.** Copy only. Do it the same day as 5.1.

### 5.3 Server-owned state must not be client-writable

**Evidence.** `firestore.rules:46–47` grants `read, write` on `users/{uid}/{document=**}`. `patternHypotheses`, `selfModel`, `mirrorCards`, `dailyReads`, and the `lastMineRunAt` field on the user doc are written by Admin SDK and are meant to be server truth — but any client can forge a hypothesis, mark itself as mined, or delete the Self Model. `aiUsage` was correctly moved to a top-level Admin-only collection for exactly this reason (`functions/index.js:205–211`); the same reasoning applies here.

**Decision.** Split the rules: client `read, write` on `entries`, `entryAnalyses`, `chatSessions`, `moodLogs`, `profileCorrections`, `lifeContext`, `events`; client **read-only** on `patternHypotheses`, `selfModel`, `mirrorCards`, `mirrors`, `dailyReads`, `echoes`, `rollups`. Move `lastMineRunAt` and any other server bookkeeping to a `users/{uid}/server/state` doc that is read-only to the client. Feedback on a card (`MirrorFeedback`) is a client write — route it to `profileCorrections` (already client-writable) rather than mutating the card doc.

**Why.** Integrity of the Self Model is the product's promise ("correctable, evidence-backed"). A model the client can silently rewrite is not evidence-backed. It also removes a whole class of "why is this user's Mirror weird" support tickets.

**Effort.** Small; one rules file and two write-path moves. Test with the emulator.

### 5.4 Collapse the derived-state sprawl

**Evidence.** Fifteen user subcollections (`FirestoreSchema.swift:38–125`). Three of them are "today's card" in three generations: `dailyReads` (Today's Read), `mirrors` (per-day card), `mirrorCards` (per-hypothesis deck). `patternCallbacks` is the pre-Mirror engine `PATTERNS_MERGE_PLAN.md` already retires. `MemoryProfile` is recomputed on-device from up to 300 decrypted entries and cached in `UserDefaults` (`MemoryProfileService.swift:6, 27`), while `MirrorGraph` and `SelfModel` hold overlapping aggregates in Firestore.

**Decision.**

- Retire `dailyReads` and `patternCallbacks` (delete after one release with the migration in `PATTERNS_MERGE_PLAN.md`). Keep `mirrorCards` as the deck; drop `mirrors`. If the Mirror redesign lands, `mirrorLines/{date}` replaces both.
- Compute `MemoryProfile` **server-side, nightly, from `entryAnalyses`**, and write it to `users/{uid}/derived/memoryProfile`. The client reads one small doc instead of decrypting 300 entries on launch to rebuild a prompt-context string. The 150-token `cachedPromptContext()` becomes a field on that doc.
- Add a **`derivedFrom` field** to every server-written doc: `{entryIds[], analysisVersions[], promptVersion, computedAt}`. This is what makes "show me the proof" and "why did this change" answerable, and what lets a version bump decide what to recompute.

**Why.** Fewer collections is fewer cache-first reads on tab open (`MirrorView.performLoad` currently loads hypotheses, self model, cards, and shifting signals from four places), fewer places for two writers to disagree, and a launch path that does not decrypt the whole journal.

**Effort.** Medium; mostly deletion plus one new nightly job.

### 5.5 Reads: cap, paginate, and stop fetching the whole journal

**Evidence.** `fetchEntries` is `.limit(to: 300)` (`JournalService.swift:117–121`); `fetchAllEntries` is unbounded (`:157`); the on-device Ask (`MirrorView.swift:1018–1081`) scores entries locally and renders them into a prompt with no ceiling on count or tokens (audit row 17).

**Decision.** Move Ask to a server operation over `entryAnalyses` (summaries and quotes are what it needs; it does not need plaintext) with a 5,000-token context ceiling and citations by `entryId`. Delete `fetchAllEntries` or give it a cursor. The journal list should page at 50.

**Effort.** Small-medium; Ask moves as part of §1.

---

## 6. Engineering practice — the decisions that make the others stick

### 6.1 Version control and CI, this week

**Evidence.** Two commits in the repository; the last is "last working version" on 11 June. Every change since — three months, including the Mirror engine, the budget system, and the chat rewrite — is uncommitted working-tree state on one laptop.

**Decision.** Commit today. Then: a `main` branch that always builds; feature branches; GitHub Actions running `xcodebuild test` and `npm test` in `functions/` on every push; Firebase deploy from `main` only. This is not process for its own sake — it is the only backup of the Mirror engine that exists.

**Effort.** Half a day.

### 6.2 Split `functions/index.js`

**Evidence.** 2,918 lines: proxy, budgets, dispatch, Today's Read, mining, counter-evidence, Self Model, Mirror cards, thirteen prompt bodies, and their lints, in one module.

**Decision.** `functions/{proxy,budget,dispatch,jobs/*,prompts/*,lints}.js`. Do it as part of §3 so prompts are extracted once.

### 6.3 Observability that answers product questions

**Evidence.** `console.log("aiUsage", …)` per call is the whole telemetry story for the AI layer. There is no dashboard, no alert, and the lint rejections are not logged.

**Decision.** A BigQuery sink for the structured logs (Cloud Logging → BigQuery is a checkbox), and four saved queries: spend by surface by day; p95 spend per user; `cachedContentTokenCount` ratio by surface; lint-reject histogram by rule. One alert: any UID over 3× the p95 daily spend. Client-side, the events that matter for the Mirror redesign — line shown, expanded, proof opened, feedback — go through the existing `AnalyticsManager`.

**Effort.** Small.

### 6.4 Remote-configurable thresholds

**Evidence.** Surfacing thresholds are literals across both codebases: `MIN_ANALYSES`, `ANALYSIS_LOOKBACK`, `CE_MAX_HYPOTHESES`, `DECAY_DAYS`, `MirrorScore` floor 2.5, `maxContentTurns = 12`, budgets.

**Decision.** Server constants read from a single `config/ai` Firestore doc at cold start; client thresholds from Firebase Remote Config with the current literals as defaults. Then A/B of the Mirror novelty gate or the chat window size is a config change, not a release.

**Effort.** Small.

---

## 7. What not to do

- **Do not add a vector database yet.** Every retrieval need in the product (Mirror evidence, counter-evidence, Ask) is served by `entryAnalyses` plus `evidenceEntryIds` provenance. Rosebud's memory drift is a top-k semantic retrieval problem; you are not there and should not import it. Revisit at 1,000+ entries per user.
- **Do not fine-tune.** The registry plus fixtures will move quality further than a fine-tune on the data volume you have, and keeps you free to switch models per surface.
- **Do not build streaming before §1.** Streaming through a relay whose prompt lives on the client just makes the relay bigger.
- **Do not cut `maxTokens` on chat or the narrative to save money** — the audit's "one thing not to cut" still holds. Save it in §2.1, §2.2 and §2.4 instead.

---

## 8. Sequence

| Week | Ship | Why this order |
|---|---|---|
| **1** | §6.1 git + CI · §5.1 part 1 (synchronisable key) · §5.2 copy fix · §5.3 rules split · §4.2 cancellation + `finishReason` · §4.3 lint logging | Zero-risk, mostly one-liners; removes the data-loss and integrity exposures before any refactor touches those files |
| **2–3** | §1 server operations for `chatTurn`, `analyzeEntry`, `ask` · §3 registry + fixtures for those three · §6.2 split `index.js` | The structural move; chat first because it is the product and the fixtures already exist in `chatprompt-teardown` |
| **4** | §2.1 merged save with hash · §4.1 session state · §2.3 model routing (chat → flash) · §6.3 BigQuery sink | Now possible; measure before/after on the sink |
| **5** | §2.2 caching decision from data · §2.4 batch nightly · §5.4 derived-state collapse + server-side `memoryProfile` · §5.1 part 2 recovery phrase | Cost tail and storage cleanup, informed by two weeks of real numbers |
| **6** | §4.4 server ledger + streaming · §6.4 remote config · remaining operations (`weave`, `enrichHints`) moved to the registry · delete `geminiProxy` | Finish the migration; nothing client-side builds prompts any more |

Expected outcome by week 6: engaged-user inference cost at or below the audit's $0.37/month target *with chat on a better model*; a chat that holds a thread for a full session; every prompt versioned, tested, and deployable in minutes; and no user able to lose their journal by changing phones.
