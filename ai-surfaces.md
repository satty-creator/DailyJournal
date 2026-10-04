# AI surfaces

The living inventory of every place Spilr calls Gemini. Derived from code — keep
it in step when you add, rename or remove a surface. (Replaces the old
`AI_PROMPTS.md` / `ai-prompts-verbatim-*.md` dumps.)

- **Model:** `gemini-3.5-flash-lite` everywhere (`MODEL` in `functions/index.js`).
- **Two paths:**
  - **Client** calls go through the `geminiProxy` Cloud Function with a Firebase
    ID token. Each sends a `surface` cost-attribution tag that the server
    validates against `KNOWN_SURFACES` (`functions/index.js`) — an unknown tag
    collapses to `"unknown"`. All client prompts begin with `SpilrVoice.system`
    and end with `MemoryProfileService.shared.cachedPromptContext()`.
  - **Server-internal** calls run in nightly/background jobs via `callGeminiJSON`
    (Admin SDK, no proxy). These do **not** go through `KNOWN_SURFACES`.
- **Safety block (see CLAUDE.md → AI layer):**
  - Reflection surfaces inherit `SpilrVoice.safetyRules` via `SpilrVoice.system`.
  - Live-conversation surfaces use `SpilrVoice.chatSafetyRules` via `ChatPrompts.systemPrompt`.
  - The server mirror is `SAFETY_RULES` in `functions/index.js` (keep in sync with `safetyRules`).

## Client surfaces (via `geminiProxy`, in `KNOWN_SURFACES`)

| `surface` | Where | What it does | Safety block |
|---|---|---|---|
| `journal_insights` | `Home/AIService.swift` | Entry enrichment: summary bullets + a reflective question (patched in by `EntryEnrichment`) | `safetyRules` |
| `echo_extraction` | `Home/AIService.swift` | Pulls one Echo-worthy line from an entry (dropped if no `line`) | `safetyRules` |
| `mirror_analyze_entry` | `Mirror/AIService+Mirror.swift` | Per-entry `EntryAnalysis` that feeds the Mirror corpus | `safetyRules` |
| `template_weave_entry` | `Home/AIService+Template.swift` | Weaves template step answers into one entry | `safetyRules` |
| `chat_turn_cbt` | `Chat/AIService+Chat.swift` | Daily Chat turn-by-turn reply (no local fallback; inline retry on failure) | `chatSafetyRules` |
| `chat_weave_thought_journal` | `Chat/AIService+Chat.swift` | Weaves a chat transcript into a journal entry (local stitch fallback) | `chatSafetyRules` |
| `chat_session_state` | `Chat/AIService+Chat.swift` | Chat session state / readiness signals | `chatSafetyRules` |
| `chat_model_ops` | `Chat/AIService+Chat.swift` | Extracts model write-back ops from the conversation (`ModelOpKind`) | `chatSafetyRules` |

## Server-internal surfaces (via `callGeminiJSON`, nightly/background)

| `surface` | Where (`functions/index.js`) | What it does |
|---|---|---|
| `server_mine` | `mineUserInsights` path | Formulates `patternHypotheses` from the corpus |
| `counter_evidence` | hypothesis audit | Disconfirmation pass before a hypothesis can surface |
| `mirror_formulate` | Person Model, Prompt F | Assembles the Person Model (`personModel`) |
| `mirror_line` | Person Model, Prompt M (`selectAndWriteMirrorLineForUser`) | Writes the daily Mirror reading line; extends `readings/{date}` when it passes lint |
| `mirror_question` | daily question | The reading's follow-up question |
| `mirror_ask_v31` | `mirrorAsk` | The Mirror "Ask" endpoint |
| `mirror_letter` | weekly letter builder | The dated weekly letter |

> Note: the daily reading's deterministic line is written **without** a model
> call — `selectTodayFor` stores the winning observation's own sentence, and
> `mirror_line` (Prompt M) only extends that doc when it passes lint. The old
> `mirror_reading` model call was removed (it was paid for and then overwritten
> by Prompt M).
