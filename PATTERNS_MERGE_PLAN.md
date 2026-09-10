# Patterns Merge + Ask — Implementation Plan

**Status:** Plan only (no code written for this item yet).
**Goal:** Collapse the five-tab structure to three by merging **River** and **Mirror** into a single **Patterns** page, promoting the Mirror daily card to **Today**, and adding a grounded **Ask** feature that answers questions using only the user's own entries (with citations).
**Source of intent:** "Spilr Audit and Redesign" doc (sections 3–5) and the current codebase.

> Note: the repo's PRD-update rule is currently PAUSED (see `CLAUDE.md`), so this plan intentionally does **not** modify `riverprd.md` / `mirrorprd.md` / `patternsprd.md`. Re-fold these changes into those PRDs when the pause is lifted.

---

## 1. Target end state

Three tabs: **Today**, **Journal**, **Patterns** (Patterns hidden until entry 5).

- **Today** holds one observation (the promoted Mirror card) + one write button. "Ask about this" opens the Ask thread.
- **Journal** unchanged, except it must accept an *entry-id filter* so "Read those 6 →" deep links work.
- **Patterns** is one page of plain-language sentences: *what keeps coming back*, *what made it easier*, *the shape of the month*. No resilience ring, no word count, no "0 this week", no glyph vocabulary.
- **River tab** and **Mirror tab** are removed from the tab bar. Their *engines and data stay* — River marks still feed the month-shape strip and Ask grounding; the Mirror card moves to Today; the Self-Model becomes a row inside Patterns (or Profile), not a destination tab.

Retire the coined vocabulary everywhere user-facing except **Spilr** and **Patterns** ("Loop", "Lens", "River", "Mirror", "Echo", "seed", "blind spot", "Resilience" → plain language).

---

## 2. What already exists (so we build on it, not around it)

| Capability | Where | Reuse for |
|---|---|---|
| Server Mirror engine → `patternHypotheses` + `selfModel/current` | `functions/index.js` `generateNightlyInsights` (cron `0 4 * * *`) | "What keeps coming back" / "what made it easier" |
| Per-entry structured analysis → `users/{uid}/entryAnalyses/{entryId}` | `AIService+Mirror.analyzeEntry` | Ask retrieval + Patterns content |
| Pattern callbacks → `users/{uid}/patternCallbacks/{id}` (verbatim evidence quotes) | `Pattern/PatternCallbackService` | Patterns "coming back" + citation shape |
| River marks → `users/{uid}/riverMarks/{entryId}` (1 per entry) | `River/RiverService.generateMark` | Month-shape strip + Ask grounding signal |
| Citation UI (quote + date + why) | `MirrorReceipt`, `EvidenceDrawerView`, `TodayMirrorCardView` | Ask answer citations |
| Entry-count maturity gate | `Mirror/MirrorMaturity.swift` (seed/first/soft 3 / unlock 7 / deeper 14 …) | Patterns tab gating |
| "Not right" correction signal | `Mirror/ProfileCorrection` → `users/{uid}/profileCorrections/{id}` | Keep wired on the promoted card |
| Shared prompt scaffolding | `SpilrVoice.system` + `MemoryProfileService.cachedPromptContext()` | Ask prompt |
| Thin Gemini gateway (auth'd passthrough) | `functions/index.js` `geminiProxy`; client `AIService.generate` | Ask AI calls (no new function needed for v1) |
| Crisis gate (client + server mirror) | `PatternSafety` / `CRISIS_PHRASES` | Ask safety |

Two facts that constrain the design:

1. **No entry-body retrieval exists today.** Chat and every AI pass work off *aggregates* (`MemoryProfile`) or *structured* `EntryAnalysis`, never raw bodies. Grounded Ask-over-entries is genuinely net-new retrieval.
2. **`JournalService` has no date-range or keyword query.** It only offers `fetchAllEntries` (ascending, uncapped), `fetchEntries` (desc, limit 300), `fetchRecentEntries(limit:)` — all cache-first over `users/{uid}/entries`.

Known landmine to verify first: the Mirror card is written/read at `users/{uid}/mirrors/{yyyy-MM-dd}` in code (`AIService+Mirror`), but `MirrorCard.swift`'s header comment says `mirrorCards/{localDate}`. Confirm the real path before promoting the card.

---

## 3. Client work

### 3.1 Tab restructure — `App/RootView.swift` (`MainTabView`)

- Remove the `RiverView` and `MirrorView` `.tabItem` blocks. Result: Today, Journal, Patterns.
- **Gate Patterns at entry 5.** MainTabView needs the entry count. Add a lightweight `@State var entryCount` populated in the existing `.task` (reuse `MirrorViewModel.fetchEntryCount()` logic or a small count query). Render the Patterns tab only when `entryCount >= 5`; until then show two tabs (Today, Journal). Add a maturity constant (either a new `MirrorMaturity` case at 5, or a named `PatternsGate.minEntries = 5`) so the number lives in one place. *(Open question: 5 vs the existing `unlock = 7`.)*
- Consolidate the hoisted VMs: `mirrorVM` is no longer a tab. Decide whether Today owns a `MirrorCardViewModel` (recommended) and Patterns owns `PatternsViewModel`. Keep the pre-warm `.task` for whichever survive.

### 3.2 Promote the Mirror card to Today — `Home/HomeView.swift`

- Render `TodayMirrorCardView` as the Home hero when `MirrorMaturity.current(...).canShowDailyMirror` (≈ entry 3+). Below entry 3, show the current neutral "Today's question" prompt ("After three entries, this page starts showing what I notice").
- Move the card's data load into `HomeViewModel` (fetch/generate the mirror card via `AIService+Mirror.fetchLatestMirrorCard` / `generateMirrorCard` + guard). Keep it fetched-once-per-session like Today's Read.
- Keep **"show proof"** → evidence drawer (`card.receipts`) and **This-is-me / Half-true / Not-me** → `ProfileCorrection` exactly as wired today.
- Add an **"Ask about this"** button that opens the Ask thread seeded with the card's topic + `sourceEntryIds`.

### 3.3 Rebuild the Patterns page — `Patterns/PatternsView.swift`

Replace the ring/grid/stats body with three sentence sections:

1. **What keeps coming back** — read `patternHypotheses` (via `MirrorGraphService.loadHypotheses`, already ordered by `salienceScore`, `isSurfaceable`-filtered) and/or `patternCallbacks`. Render each as: title sentence + count + "*Read those N →*". Filter out `exception` type here.
2. **What made it easier** — the `exception`-type hypotheses and/or `SelfModel.whatHelps`.
3. **Last 30 days (the shape of your month)** — one plain sentence derived from entries (+ optionally `riverMarks`): "You wrote on X of the last 30 days. The longest gap was N days." Keep a *simple* activity strip (reuse the existing `activityGrid` pebbles) but drop the RiverShape canvas/glyphs and the 7/14/30 filter.

Remove: `resilienceCard` (ring), word-count / `sessionsThisWeek` / "0 this week" stats, word cloud framing that reads as a score. Keep a `my self-model →` nav row to `SelfModelView` so nothing is deleted, just relocated.

**Data-source switch:** today `PatternsViewModel` computes everything locally from entries and never reads the server hypotheses. Switch it to *prefer* server-generated `patternHypotheses` / `entryAnalyses`, with the current deterministic computation as the `< 14 entries` / offline fallback. This is the "uses what you already built" step from the redesign.

### 3.4 Journal deep-link filter — `Journal/JournalListView.swift`

- Add an optional `filterEntryIds: [String]?` (or a `PatternsFilter` route param) so "Read those N →" can open Journal showing only those entries. Reuse the existing list; just filter the data source. No new query needed (entries are already loaded/cached).

### 3.5 Ask feature (client) — new `Chat/AskView.swift` (+ `AskViewModel`)

Build on the `DailyChatView` shell (thread UI, input bar, streaming, safety gate) but change the semantics from "conversational journaling" to "grounded Q&A":

- **Entry points:** "Ask about this" on the Today card (seeded with topic + `sourceEntryIds`) and an "Ask about your entries" affordance on Patterns.
- **Blank-page cure:** three suggested questions (e.g. "When did I last feel easy about him?", "What else happens on my heavy nights?", "Read me back the calmest thing I wrote"). Seed from the card topic / top hypotheses when available; otherwise a generic trio.
- **Retrieval (v1, on-device — recommended):**
  1. Build a candidate set from `JournalService` (recent + any entries referenced by the seeded hypothesis) and rank by keyword overlap with the question, recency, and `entryAnalyses` theme match.
  2. Pass the **top-K entry snippets** (id + date + text, K≈8–12, truncated) into the Ask prompt through `geminiProxy` — consistent with the existing "client assembles context, proxy is a passthrough" architecture. No new Cloud Function required for v1.
- **Grounding contract (prompt → JSON):** `{ answer, citations: [{entryId, quote, entryDate}], usedEntryCount, refusal? }`. Prompt rules: answer *only* from supplied entries; every claim must cite a verbatim quote; if the entries don't support an answer, say so plainly.
- **Hard citation gate (client):** verify each returned `quote` actually appears in the cited entry text; drop uncited claims. If nothing verifies, show "I can only go on what you wrote — I don't see enough about that yet." Render citations with the existing receipt UI (quote + date chips → tap to open the entry).
- **Safety:** run `PatternSafety.containsCrisisSignal` on the question *and* on the answer; on a trip, show `PatternResourceCardView` and do not answer.
- **Empty-period honesty:** decide the tone for "you didn't write that week" (see Open Questions). Recommended v1: answer honestly but gently, never as a scorecard.
- **Persistence:** v1 threads are ephemeral (like Chat today). If we want history, add `users/{uid}/askThreads/{id}` later.

### 3.6 Copy pass (retire coined words)

Sweep user-facing strings: "Resilience" → "Last 30 days"; "River" → "the shape of your month"; "Mirror" (as a label) → "What I noticed"; "blind spot" → "what you might not be noticing"; "Spill" stays or becomes "Write" per the redesign. Keep **Spilr** and **Patterns**.

---

## 4. Backend work

### 4.1 Ask — v1 needs **no new Cloud Function**

Because retrieval is on-device and Gemini is reached through the existing `geminiProxy` (auth'd passthrough forwarding `{contents, generationConfig}`), the v1 Ask feature ships with **zero backend changes**. This matches how Chat and all current AI passes already work.

### 4.2 Ask — v2 (optional, if on-device retrieval proves insufficient)

If corpora grow large or ranking is weak, add a server retrieval endpoint:

- New `onCall` **`askEntries`**: verifies the ID token (like `geminiProxy`), reads `users/{uid}/entries` (+ `entryAnalyses`) via Admin SDK, does keyword/date-range (later: embedding) retrieval, calls Gemini with the grounded prompt, returns `{answer, citations}`.
- Trade-off: this is the first place the *server* would read raw entry bodies at request time. The nightly engine deliberately reasons over `entryAnalyses` only. Document this privacy delta and gate it behind the AI-consent flag before building.
- Semantic search (embeddings + vector store) is a **future** enhancement: needs an embedding job (extend `generateNightlyInsights` or a new scheduled function), a store, and is out of scope for the merge.

### 4.3 Firestore indexes — `firestore.indexes.json`

- Only two composite indexes exist today; none for Pattern/Mirror/River (queries are single-field by design).
- Adding **date-range retrieval** on `entries` for Ask (range + order) will require a new composite index. Add it when 3.5's retrieval query is finalized. On-device keyword ranking over already-fetched/cached entries may avoid this for v1.

### 4.4 River / Mirror engines — keep running

- `generateNightlyInsights` (Mirror/self-model) and per-entry `analyzeEntry` / `generateMark` are unchanged — the merged Patterns page and Ask *consume* their output. Removing the tabs is a **client-only** change for these engines.
- The `generateRiverNarrative` Gemini pass can be dropped from the month-shape strip (replace with a deterministic plain sentence) — a simplification, not a new dependency.

### 4.5 Firestore rules

- No change needed. Rules are owner-scoped recursively (`request.auth.uid == userId`), so any new subcollection (e.g. `askThreads`) is already covered.

---

## 5. Data model summary

- **No new required collections for v1.** Reuse `entries`, `entryAnalyses`, `patternHypotheses`, `patternCallbacks`, `riverMarks`, `selfModel/current`, `mirrors/{date}`, `profileCorrections`.
- **Optional new:** `users/{uid}/askThreads/{id}` if Ask history is desired.
- **Client-only additions:** entry-id filter param on Journal; a `PatternsGate.minEntries` constant; Ask request/response Codable types; a small on-device retrieval/ranking helper in `JournalService`.

---

## 6. Phasing (ordered by confusion-removed-per-hour, per the redesign)

**Phase 1 — Quiet the noise (this week, no new AI, client-only)**
- Remove River + Mirror tab items; gate Patterns to entry 5 (2 tabs on day one).
- Strip the resilience ring, word-count, and "0 this week" stats from Patterns.
- (If in scope) simplify the write screen; add the three-step first-run card. *(Adjacent to this task; call out separately.)*

**Phase 2 — Promote the Mirror (next, uses what's built)**
- Move `TodayMirrorCardView` to Today; retire the Mirror tab.
- Show source entries under each observation (receipts already stored); keep "Not right" → `ProfileCorrection`.
- Switch Patterns to read server `patternHypotheses` / `entryAnalyses` with local fallback.
- Plainer copy: "what I noticed", "what keeps coming back", "what made it easier".

**Phase 3 — Let people Ask (the differentiator)**
- Ship `AskView` grounded in entries: citations required, 3 suggested questions, hard citation gate, safety gate.
- Merge River's shape into Patterns as one plain-language strip; retire remaining coined words.

---

## 7. Risks & mitigations

- **Hallucinated citations.** Mitigate with the client-side verbatim-quote verification gate; drop anything that doesn't match a real entry.
- **Firestore read volume / cost for Ask retrieval.** Prefer on-device ranking over already-cached entries; cap K; add composite index only if a range query is truly needed.
- **Privacy delta if v2 server retrieval is built** — server would read raw bodies at request time. Gate behind AI consent; document.
- **Xcode project membership.** New files (`AskView.swift`, etc.) must be added to `DailyJournal.xcodeproj`'s `project.pbxproj` or they won't compile. Prefer adding types to existing files where reasonable, as we did for the Thought-Journal education screen.
- **Mirror card path bug** (`mirrors/` vs `mirrorCards/`) — verify before promoting the card, or the Home hero will silently render nothing.
- **Maturity-threshold churn.** Keep the entry-5/7 gate in one constant so it's a one-line change during testing.
- **Removing tabs without deleting engines** — ensure River-mark generation and nightly insights keep firing after the tabs go; add a regression check that entries still produce marks/analyses.

---

## 8. Verification / test plan

- Tab bar shows 2 tabs < entry 5, 3 tabs ≥ entry 5.
- Today shows the promoted Mirror card ≥ entry 3 with working proof drawer + correction feedback.
- Patterns renders the three sentence sections from real hypotheses; "Read those N →" opens Journal filtered to exactly those entry ids.
- Ask: every answer's citations resolve to real entries and quotes; an unanswerable question yields the honest fallback, not an invented answer; crisis input routes to the resource card.
- River-mark and nightly-insight generation still run after tab removal (spot-check Firestore).
- No user-facing coined words remain except Spilr / Patterns.

---

## 9. Open questions (need a product call)

1. **Entry threshold for the Patterns tab:** 5 (redesign doc) vs the existing `MirrorMaturity.unlock = 7`?
2. **Ask over empty periods:** answer "you didn't write that week" honestly, or suppress to avoid the report-card feeling? (Called out in the redesign doc.)
3. **Ask retrieval:** ship on-device v1 (recommended) and defer server/embeddings, or invest in `askEntries` + indexes now?
4. **Ask history:** ephemeral threads (like Chat) or persist `askThreads`?
5. **Self-Model destination:** a row inside Patterns, or move it under Profile?
