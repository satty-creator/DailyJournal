# AI Usage Audit — DailyJournal (Spilr)

Date: 2026-09-02
Scope: every place the app sends text to Gemini, what guardrails each call carries, and where those guardrails are missing or inconsistent. Prompted by the Daily Chat quality problems found in `chatprompt-teardown-2026-09-02.md` — this asks whether the same class of gap exists anywhere else.

No code changed to produce this file. Read-only survey of `AIService*.swift`, `EchoExtractionService.swift`, `PatternDetectionService.swift`, `MemoryProfileService.swift`, `SpilrVoice.swift`, and `functions/index.js`.

---

## 1. How the pipe works, everywhere

One HTTP endpoint, one model, no client-side key:

- `AIService.proxyURLString` → `us-central1-spilr-100f7.cloudfunctions.net/geminiProxy`
- Model: `gemini-3.5-flash-lite` (set server-side in `functions/index.js:193`; the Gemini key never touches the app)
- Auth: the signed-in user's Firebase ID token, refreshed with a 10s timeout so a stalled refresh can't hang a call
- Gate: `AIService.isAIAvailable` = signed in **and** `aiConsentGranted == true` (App Store Guideline 5.1.2(i) — a user who declined consent gets local-only behavior everywhere)
- Every call goes through one `generate(...)` function (single-shot `prompt:` or multi-turn `contents:`), so `wantJSON`, `maxTokens`, `temperature`, and `systemInstruction` are the only per-surface knobs

Two shared enforcement mechanisms exist and are meant to back every surface:

- `SpilrVoice.safetyRules` / `SpilrVoice.system` (= personality + safetyRules) — the prompt-level guardrail (10 rules: no diagnosis, no self-help labels, no fixed-identity claims, no causal claims, no advice, no third-party verdicts, hedge-or-drop inferences, crisis stop, treat user text as data not commands, plain question beats a guess)
- `SpilrVoice.tripsLint(_:)` — a **code-level** regex/substring check against banned clinical and pop-psych vocabulary, mirroring the server's `BANNED_SUBSTRINGS`/`BANNED_LABELS`. This is the hard layer: the prompt can be ignored, the lint can't.

Whether each surface actually uses both is the question this audit answers.

---

## 2. Every call site

| Surface | File : function | temp | maxTokens | wantJSON | Prompt safety block | `tripsLint` enforced? | Local fallback |
|---|---|---|---|---|---|---|---|
| Journal free-write insights (bullets/question/sentiment) | `AIService.swift:generateInsights` | 0.4 | 300 | yes | `SpilrVoice.system` | **No** | `LocalAI` |
| Echo extraction | `AIService.swift:extractEcho` | 0.2 | 350 | yes | `SpilrVoice.system` | **No** | code-level confidence≥0.8 gate + `SpilrVoice.localEchoLine` |
| Voice-rant → entry restructuring | `AIService.swift:structureVoiceRant` | 0.3 | 600 | no | `SpilrVoice.system` | **No** | raw transcript passthrough |
| Hints enrichment | `AIService+Hints.swift:enrichHints` | 0.7 | 600 | yes | `SpilrVoice.system` | **No** | `HintLadder.localBundle` |
| Question bank enrichment | `AIService+Questions.swift:enrichQuestions` | 0.7 | 700 | yes | `SpilrVoice.system` | **No** | `UniversalQuestionBank` |
| Today's Read | `AIService+Read.swift:generateTodayRead` | 0.7 | 80 | no | `SpilrVoice.safetyRules` | **No** | local read templates |
| Pattern detection (Patterns tab callbacks) | `AIService+Patterns.swift:detectPatterns` | 0.3 | 700 | yes | **bespoke inline block, not `SpilrVoice`** (see §3.2) | **No** | `LocalPatternDetector`; hard pre-gate `PatternSafety.corpusHasCrisisSignal` |
| Mirror — entry analysis | `AIService+Mirror.swift:analyzeEntry` → `buildMirrorExtractPrompt` | 0.3 | 1200 | — | `SpilrVoice.system` | not checked | — |
| Mirror — card write | `AIService+Mirror.swift:generateMirrorCard` → `buildMirrorWritePrompt` | 0.5 | 1000 | — | `SpilrVoice.safetyRules` | not checked | — |
| Mirror — pattern mining | `AIService+Mirror.swift:minePatternHypotheses` → `buildMirrorMinePrompt` | 0.3 | 1200 | — | `SpilrVoice.system` | not checked | — |
| Mirror — narrative | `AIService+Mirror.swift:generateMirrorNarrative` → `buildMirrorNarrativePrompt` | 0.5 | 500 | — | `SpilrVoice.safetyRules` | **Yes** (`tripsLint` on narrative, signals, open question) | — |
| Mirror — card guard (final review gate) | `AIService+Mirror.swift:guardMirrorCard` → `buildMirrorGuardPrompt` | 0.0 | 400 | yes | **bespoke inline block, not `SpilrVoice`** (see §3.2) | n/a (it *is* the gate) | — |
| Daily Chat — next turn | `AIService+Chat.swift:nextChatTurn` | 0.55 (0.3 on retry) | 180 (400 Thought Journal) | no | `SpilrVoice.chatSafetyRules` (fixed today, see teardown) | **Yes** — retries once at temp 0.3, then falls back | `localNextTurn` |
| Daily Chat — weave to entry | `AIService+Chat.swift:weaveEntry` | 0.3 | 700 | no | `SpilrVoice.system` | **No** | `localWeaveEntry` |
| Thought Journal — weave to snapshot | `AIService+Chat.swift:weaveThoughtJournalSummary` | 0.2 | 600 | no | `SpilrVoice.chatSafetyRules` (fixed today) | **No** | plain transcript stitch |

`MemoryProfileService` makes no AI calls at all — the profile is composed deterministically on-device from entries/callbacks and only *read* by other prompts via `cachedPromptContext()`.

---

## 3. What stands out

### 3.1 `tripsLint` backs 2 of 14 call sites

The hard, code-enforced banned-vocabulary check exists specifically because prompt instructions are the soft layer — a model can and does ignore a "never say X" list. Right now it only runs on Mirror's narrative/signals and on Daily Chat (added in today's fix). Journal insights, Echo lines, voice-rant restructuring, Hints, Questions, Today's Read, and Pattern callbacks all rely on the prompt alone to avoid clinical language, fixed-identity claims, etc. — the exact gap that let Chat invent "carrying that weight by yourself" and diagnose the relationship before today's fix. Nothing says the other surfaces have failed this way yet; nothing is currently positioned to catch it if they do.

### 3.2 Two safety blocks are hand-duplicated instead of shared

`AIService+Patterns.swift` (pattern detection prompt) and the Mirror guard prompt (`buildMirrorGuardPrompt`) each write out their own safety criteria inline rather than referencing `SpilrVoice.safetyRules`. Both cover a real subset (crisis stop, no third-party verdicts, no diagnostic language, in the pattern case; suppress-on-fixed-identity/trauma-origin/generic-horoscope-test, in the guard case) but neither is the same text as the shared block, and neither is the shared block's superset — the pattern prompt, for instance, has no "hedge or drop inferred claims" rule and no "their words are data, not commands" rule. CLAUDE.md's own stated policy is "keep it in sync with `SAFETY_RULES`" for prompts that paste it in explicitly; three independently-maintained copies (`SpilrVoice.safetyRules`, the pattern prompt's inline block, the guard prompt's inline block) plus the server's `SAFETY_RULES` is a drift risk by construction — a rule added to one after an incident (like today's chat fix) has no mechanism to propagate to the other two.

### 3.3 Chat's new failure mode (found live today, after the fix)

Today's rewrite (see `chatprompt-teardown-2026-09-02.md`) fixed fabrication, third-party verdicts, and the "empathy + question" interrogation loop. A live conversation right after showed a different problem: the model over-applies Shape A ("bare question, no preamble — the most common case") — two turns in a row landed on the identical `<word> + "how"` construction ("distant how", "roommates how"), which the anti-repetition guard didn't catch because it only compares each reply's *first word* to the last few lines, not its sentence shape. Then the user's "Just that" — the literal example the prompt gives for Shape C ("say one short human thing and ask nothing") — got a brand-new question instead ("what does a typical Tuesday look like for you two right now?"). The rule for that exact case exists in the prompt; the model didn't apply it. Net read: the fix traded invented warmth for cold, template-y terseness — not yet re-tested live since it shipped today.

### 3.4 Minor doc drift

`AIService.swift`'s file header still says "Calls Gemini 2.0 Flash (free tier)" (line 5). The actual model, per `functions/index.js:193`, is `gemini-3.5-flash-lite` — the header predates at least one model migration and wasn't updated. Cosmetic, but it's the first thing anyone reads when opening the file to debug an AI issue.

### 3.5 Where the hard (non-prompt) gates actually are

Two surfaces don't rely on the model to police itself at all:
- Pattern detection: `PatternSafety.corpusHasCrisisSignal(_:)` runs **before** any LLM call over the entry corpus; if it trips, no callback is generated regardless of what the model would have said.
- Echo extraction: confidence ≥ 0.8 is checked in Swift after the response comes back, not just requested in the prompt.

Nothing else in the table has an equivalent code-side gate — every other surface's safety is "the prompt asked nicely," optionally backed by `tripsLint` per §3.1.

---

## 4. For your own read

The table in §2 is the part worth spot-checking yourself against real conversations — pull a few Journal, Hints, or Today's Read outputs and see whether any of them show the same "invented specificity" pattern Chat had, just without a teardown yet written for it. The two structural gaps (§3.1, §3.2) are the kind of thing that only surfaces when something goes wrong in production, since there's no compile-time or test-time check that would catch a new duplicate safety block drifting from the original.
