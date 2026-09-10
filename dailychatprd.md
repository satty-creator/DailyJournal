# Daily Chat — Feature PRD

**Status:** Shipped — Day One-style interactive journaling. Spilr opens with a
question, asks adaptive AI follow-ups, and weaves the conversation into a normal
journal entry. Fully local-first with on-device fallbacks for both the follow-ups
and the weaving.

**Naming:** the AI persona in this surface is **Spilr** (avatar + all user-facing
copy); the screen/action is titled **"Spill."**. The underlying voice engine is
still `NinetyVoice.system` — that's an internal symbol, not a user-facing name.

---

## What it is

A conversational way into a journal entry. Instead of facing a blank page, the
person talks to Spilr in a familiar chat thread. Spilr reads each reply and asks
one adaptive follow-up at a time, then — at any point — the conversation can be
**woven** into a first-person journal entry that is saved like any other entry.

Daily Chat is an *input method*, not a new data type: the saved result is an
ordinary `JournalEntry` (with `sessionType == .dailyChat`) so Echoes, River,
Patterns, Memory and the entry list all treat it exactly like a written entry. The
chat transcript itself is **never persisted** — only the woven entry the user
approves. (Decision: "woven narrative only".)

**Files:** `Chat/AIService+Chat.swift`, `Chat/DailyChatView.swift`, `Chat/ChatMode.swift`,
entry point in `Home/HomeView.swift`, `dailyChat` + `cbtReframe` cases in `Journal/JournalEntry.swift`.

---

## Modes — Casual Vent (Normal) & Thought Journal (CBT)

Chat with Spilr runs in one of two **modes**, chosen **per session**, never locked in at
onboarding (`Chat/ChatMode.swift`):

- **`.normal` — 💬 Casual Vent** (default): short, grounded, one-question-at-a-time
  reflection. Header "Spill." Weaves into a first-person prose entry (`sessionType == .dailyChat`).
- **`.cbt` — 🧠 Thought Journal**: a warm, **flexible** CBT-informed guide for **any** topic
  the user brings (a worry, procrastination, ADHD overwhelm, a conflict, a decision — the user
  sets the topic and tone). It follows the Mind Over Mood 7-column thought record (Situation →
  Feelings/intensity → Automatic "hot" thought → Thinking traps → Evidence for/against →
  Balanced thought → Re-rate) and ends in a structured recap card (`sessionType == .cbtReframe`,
  stored as markdown). Header "Reflect." The opener is open-ended (never assumes stress).
  **Internal raw value stays `"cbt"`** so persisted prefs and `.cbtReframe` don't break.

**Mode selection (UX decision):** session-based, not onboarding lock-in. Default is Normal;
the user switches with a two-pill segmented control at the top of the chat (`modePicker`).
The last-used mode is remembered in `UserDefaults` (`spilr.chatMode` via `ChatMode.lastUsed`).
Switching modes starts a **fresh thread** with the new mode's opener (nothing is persisted
until save, so no data is lost). Settings may later expose a *default-mode* preference; it
must never force a choice at onboarding.

**Prompts (`ChatPrompts`):** each mode has its own user-authored system voice. Normal is the
"empathetic conversational partner" prompt (short, validate-and-anchor, one low-friction
question, light "Sounds like…" reflection, memory cue). CBT is the structured 7-step guide
with: ONE-STEP-AT-A-TIME + VALIDATE-FIRST rules, adaptive options when stuck, and three
control directives — **state tracking**, **flexible skipping**, and a **safety override**.
Note: the CBT prompt does **not** prepend `NinetyVoice.system` (which bans clinical language)
— the two would contradict. Each mode's prompt is self-contained; per-user memory context is
appended at call time.

**CBT state tracking (step drift guard):** the model ends every CBT reply with a hidden
`<step>N</step>` tag (and `<complete>true</complete>` when finished). `AIService.parseCBTState`
strips these tags before display and the app owns progress (`DailyChatViewModel.cbtStep`).
**Flexible skipping:** if the user front-loads info for later steps, the guide acknowledges it,
marks those steps done, and advances to the next missing step (never re-asks).

**Weave / exit ramps:**
- Normal: weave becomes available once there's real material (≥2 user turns **and** ≥12 words).
- CBT: the "Wrap up & save" button is an exit ramp available any time after the user has
  engaged (≥1 turn), or as soon as the guide signals completion. It calls
  `AIService.weaveCBTSummary` to render the structured Thought Journal card; failure falls back
  to a local stitch.

---

## Safety gate (both modes)

Because "Thought Journal" explicitly invites distressing material, the chat now runs the same
**deterministic crisis filter** the pattern engine uses (`PatternSafety.containsCrisisSignal`)
on **every user turn, before any AI call**, in both modes. On a trip: the flow pauses, Spilr
shows a calm, non-judgemental resource line (`DailyChatViewModel.crisisReply`), and the
`PatternResourceCardView` is presented. No LLM call is made and the CBT flow does not advance.
This is belt-and-suspenders with the prompt-level "Safety Override" directive. Spilr is a
journaling tool, not a therapist — this is stated in-copy and in the CBT system prompt.

---

## Entry point (`HomeView`)

A dedicated **"Spill."** card on the Today screen, placed directly under
the hero today-card and above the prompt-preview card (`HomeView.dailyChatCard`).
Tapping it opens `DailyChatView` as a `fullScreenCover`; on dismiss the home feed
reloads and the first-entry celebration check runs (same as the other write flows).

The view header title is **"Spill."** with subtitle "Just talk — I'll shape it into
an entry." (changed from "Chat with ninety" / "Talk it out — I'll weave it into an entry.").

---

## Conversation flow (`DailyChatViewModel`)

1. **Opener** — `AIService.chatOpener()` returns a warm, local-instant first line
   (rotates daily) so the chat never waits on the network to begin.
2. **User reply** — appended as a `.user` `ChatMessage`; a typing indicator shows
   while Spilr composes. When the reply arrives it is revealed word-by-word
   (client-side typewriter, ~0.7s budget) via `DailyChatViewModel.revealReply`;
   `isRevealing` gates sending during the reveal.
3. **Adaptive follow-up** — `AIService.nextChatTurn(history:)` returns the next
   Spilr line plus a `ready_to_weave` flag. On any failure it falls back to
   `localNextTurn(history:)` (a non-repeating pick from `UniversalQuestionBank`).
4. **Weave** — once `canWeave` (model says ready, or ≥1 user reply) a prominent
   "Weave into an entry" bar appears. Tapping runs `weaveEntry(from:)`.
5. **Preview & save** — the woven entry opens in `WovenEntryPreviewSheet`, fully
   editable. "Save entry" commits it; "Keep chatting" returns to the thread.

`ChatMessage` is an in-memory `Identifiable`/`Codable` value (`role`: `.spilr` /
`.user`). Nothing is written to Firestore until the user saves a woven entry.

---

## AI layer (`AIService+Chat`)

Both calls go through the shared `AIService.generate(...)` proxy and end with
`MemoryProfileService.shared.cachedPromptContext()`. `weaveEntry` opens with
`NinetyVoice.system`; `nextChatTurn` opens with `NinetyVoice.chatSystem` (see below).

| Call | Tokens | Temp | Transport | Output | Fallback |
|---|---|---|---|---|---|
| `nextChatTurn(history:)` | 180 | 0.9 | multi-turn `contents` | plain-text next reply | `localNextTurn` (UniversalQuestionBank) |
| `weaveEntry(from:)` | 700 | 0.3 | single prompt | plain first-person entry text | `localWeaveEntry` (joins user replies) |

**Multi-turn transport + minimal prompt (updated 2026-08-10, third pass):** benchmarking
the same conversation against the Gemini app on plain Flash — with a *one-sentence*
instruction — produced markedly better replies than the app did, which ruled out the
model tier and identified the prompt and the transport as the causes.

- `AIService.generate(contents:maxTokens:temperature:wantJSON:)` is a new overload that
  sends a real Gemini `contents` array with `role` fields. The old
  `generate(prompt:…)` now delegates to it, so every other call site is unchanged.
  `geminiProxy` forwards `contents` verbatim — **no Cloud Function redeploy needed.**
- `nextChatTurn` now builds `[instruction(user), ack(model)] + history` mapping
  `spilr → model` and `user → user`. `messages[0]` is always the Spilr opener and the
  newest user message is always last, so roles alternate correctly. Previously the whole
  conversation was flattened into one user-role text blob with a pseudo-transcript
  (`spilr: … / me: …`), which asked the model to *simulate* a dialogue rather than
  *continue* one — none of Gemini's multi-turn tuning engaged, and invented details were
  indistinguishable from real ones.
- The prompt is now ~5 lines. **Removed** the 130-character cap, the "no preamble" rule,
  the "ONE question only, never two" ban, and the blanket "no reassurance / no
  summarising" — each of those forbids something the good Gemini replies do. The wanted
  shape is *brief acknowledgement → one question*, and offering two or three concrete
  options is explicitly encouraged because it makes the question easier to answer.
- `NinetyVoice.chatSystem` was updated to match: light commiseration is now sanctioned;
  only the hollow-support clichés ("how did that make you feel", "I hear you", "that
  sounds difficult", "thanks for sharing") and advice-giving remain banned.
- Temperature 0.5 → 0.9. The low value plus a heavy constraint stack was most of the
  flatness; the Gemini app's own default sits near 1.0.

**Conversational voice + prompt rewrite (updated 2026-08-10, later):** the follow-up
prompt was collapsing into mechanical noun-extraction questions ("what did the deceit
look like in the room?", "what did your uncle take it with?") — cross-examining, and
sometimes inventing details. Root cause was a rules-engine prompt layered on top of
`NinetyVoice.system`, which is written for *reflection* ("never restate — add the layer
they didn't write"), not conversation. Two fixes:
1. **New `NinetyVoice.chatSystem`** — a conversation-tuned voice fragment used only by
   `nextChatTurn`. It permits light reflecting-back (how a friend shows they're
   listening), keeps the no-fabrication guardrail, and drops the reflection-surface
   "never restate" instinct.
2. **`nextChatTurn` prompt rewritten** as a conversational brief with three good/bad
   few-shot examples instead of a move taxonomy. Removed the CONCRETE-default move and
   the "MUST reuse at least one exact word" mandate — that mandate is what produced the
   "ask what an abstract noun looks like" failures. The no-invention grounding rule and
   the anti-pattern banlist ("how did that make you feel", opener words) are retained,
   now carried by `chatSystem`.

**Grounding rules (updated 2026-08-10):** the follow-up prompt now hard-forbids
fabrication — Spilr may only reference people, places, relationships, feelings or
motives the person has already named in the conversation. No invented second party
or "them/theirs", no motive-diagnosis ("what are you defending against"), no two-way
factual guesses ("yours or theirs?"). The question must reuse at least one exact word
from the user's message, and `CONCRETE` is the default move on short/early replies.
Temperature dropped 0.65 → 0.5 for steadier, less breathless output. The same
no-fabrication guardrail was added to the shared `NinetyVoice.system`, so it applies
to every AI surface (Echo, River, Mirror, Reads), not just chat.

**Follow-up rules (updated 2026-06-17):** The prompt now:
1. Explicitly extracts the "key noun" from the last user message via `extractKeyNoun(_:)` (a local stopword-filtered helper) and injects it as context, so the model has a concrete anchor.
2. Adds turn-count framing: on turn 1, "keep it open"; on later turns, "pull on the most alive part".
3. Expands moves from 4 to 5: Tension, Underneath, Absence, Reframe, **Concrete** (ask for the specific moment/scene).
4. Adds explicit anti-patterns the model must never say: "how did that make you feel?", "that sounds difficult", "I hear you", "thanks for sharing", never start with "So" or "Well" or "It sounds like".
5. Requires using the person's exact words/nouns — if they said "drained", say "drained", not "exhausted".
6. Max 130 chars (down from 140), temperature raised slightly to 0.65 for more natural variation.

**Weaving rules:** preserve the person's own words; use only what they actually
said (no invention); drop Spilr's questions; 2–4 connected first-person paragraphs
that flow into each other (continuous memory, not a list of events); **absolutely
no bullet points, dashes, or numbered lists** — any such line is also stripped
post-hoc by `stripListFormatting(_:)` before the text reaches the preview sheet;
output the body only (no title, heading, quotes, or commentary). `weaveEntry`
requires ≥12 user words and throws `.textTooShort` otherwise.

**Local fallback (`localWeaveEntry`):** groups user replies into ~3 paragraph-sized
chunks with light connective phrases ("What came next was…", "And then —") so the
offline result reads as flowing prose rather than a raw message dump.

---

## Save pipeline (`DailyChatViewModel.save`)

Mirrors `NinetySecondViewModel.saveEntry`: save instantly with local heuristics
(`LocalAI.detectSentiment`, `NinetyVoice.localReflection`, `LocalAI.extractTopics`),
then enrich in detached background tasks (`generateInsights` → `updateEntryInsights`,
`EchoExtractionService.extractAndStore`, `RiverService.generateMark`). All writes
are fire-and-forget. The entry is tagged `"chat"` plus up to four derived topics and
saved with `sessionType: .dailyChat`.

---

## What triggers a PRD update

- Change the opener set, the follow-up or weaving prompts (rules, temperature,
  token budget, JSON schema)
- Change the `ChatTurn` / `ChatMessage` shape or the `ready_to_weave` / `canWeave`
  thresholds
- Change what is persisted (e.g. start saving the transcript) or the `sessionType`,
  tags, or enrichment used on save
- Move or restyle the Home entry-point card, or change the preview/edit flow
