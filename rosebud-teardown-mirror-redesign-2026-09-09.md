# Rosebud reverse-engineering → Spilr Mirror redesign

**Prepared for:** Satakshi · Spilr (ninety) · 2026-09-09
**Scope:** product mechanics, prompt architecture, memory/data strategy, and a step-by-step blueprint for turning Today's Mirror from a dense multi-zone card into a single-line insight engine.
**Relationship to `Rosebud_Teardown_Spilr.pptx` (Sept 2):** that deck is the competitive/strategic view (fault lines, wedge, roadmap). This document is the mechanical view — how the reflection loop actually works, what the prompts must be doing, and what to change in `Mirror/`. It does not repeat the pricing/positioning material.

**Evidence tags.** `[C]` = confirmed against a public Rosebud page, review, or founder interview (sources at the end). `[I]` = inferred from observed behaviour; Rosebud has never published an engineering post, and no credible system-prompt leak exists. `[S]` = observed directly in the Spilr codebase (`MirrorView.swift`, `TodayMirrorCardView.swift`, `ai-prompts-verbatim-2026-09-02.md`, `mirrorprd.md`, `functions/index.js`).

One correction to the Sept 2 deck: Rosebud's current privacy policy names OpenAI, Anthropic and Groq as AI subprocessors under BAAs with zero-data-retention ("immediately discard data after processing"), and permits "aggregated and anonymized data" use for trends and with "academic research partners" `[C]`. The policy is silent on model training; Rosebud's blog and its ChatGPT-comparison page are where the "doesn't train AI models on individual user entries" claim lives `[C]`. Keep the wedge, but phrase it as "aggregate/de-identified use permitted, no opt-out, and the policy itself never rules training in or out" — not "trains on your journal".

---

## Part 1 — Rosebud teardown

### 1.1 The one-sentence model of Rosebud

Rosebud is a **chat-first journal whose reflection surfaces are deliberately separated by cadence**: a fast, low-load conversational unit while you write (one perspective + one question), a medium synthesis unit when you finish (summary + a few insights + tags + a suggested goal), and a slow synthesis unit once a week (report). Insight density rises as cadence slows. That separation — not any single prompt — is the main reason it avoids overload during writing, and the reason its weekly report can afford to be long.

### 1.2 End-to-end journey

**Onboarding.** A short profile (relationship status, age, occupation, religion in the 2024 version) plus a "Brief Bio" — values, significant relationships, milestones, aspirations — whose stated purpose is so users "won't have to revisit the same topics repetitively" `[C]`. On mobile the user picks one of five personas (Sage, Challenger, Connector, Gardener, Strategist), each with its own instructions, model, and voice `[C]`. Goals are not picked upfront; they are proposed after entries (Happiness Recipe) `[C]`.

**Home.** Five tabs: Today, Explore, +, Insights, History `[C]`. Today carries the daily check-in, a "For You" slot with exactly one piece of personalised content per day (artwork, psychology insight, perspective shift, book rec — each toggleable) once you've written 20+ words `[C]`, and personalised prompts derived from recent entries that disappear once used `[C]`.

**Entry types.** Morning Intention (3 rotating questions, 3am–12pm), Evening Reflection (Rose/Bud/Thorn, 12pm–3am), Blank entry (with a "Recent topics" picker to resume a thread), Guided journals built with therapists (CBT "Reframing Negative Thoughts", ACT, Gratitude, IFS), and Custom journals with a user-defined goal and auto-generated prompts `[C]`. An "imagination" slider controls how varied the AI-generated prompts are `[C]`.

**Inside the entry — the interaction unit.** After answering the structured prompts, the user chooses *Finish* or *Go deeper*. "Dig deeper" has two modes `[C]`:

- **Interactive** — each AI turn is "a perspective along with a single pointed follow-up question". One perspective. One question. This is the most concrete public statement of Rosebud's turn shape.
- **Focused** — "three questions, based on your entry so far"; the user picks one and keeps writing; *no AI commentary at all*. A one-way mode for people who don't want to be talked at.

Mid-entry there is also **Guiding Light**, a menu of five explicit moves the user invokes: Suggest ideas, Challenge your thinking, Alternative viewpoint, Identify thinking traps, Positive reframing `[C]`. Note the design choice: the *user* picks the cognitive move; the model doesn't decide to reframe you.

**After finishing — Entry Reflection.** "Each journal entry is summarized and reflected back to you with key insights, mirroring your own unique wisdom" `[C]`. The reflection screen contains a summary, Insights, a Haiku, auto-tags (Mood / Relationships / Life themes), and suggested goals the user can edit before adding `[C]`. Ordering summary → insights → haiku → tags → goals is inferred from the help pages `[I]`. Web summaries are reportedly shallower than mobile `[C]`.

**Weekly.** A Weekly Report with writing stats, an "Emotional landscape" (mood), "Key themes", a "Cast of Characters" (people mentioned), and up to five key insights; an in-depth version unlocks above 1,500 words/week; push notification when ready; mid-week progress nudges toward the unlock `[C]`. The 2024 form was "three top insights + three weekly wins on Sunday" `[C]`.

**Pull surfaces.** *Ask Rosebud* answers questions over your whole journal "including links to related journal entries", with suggested questions like "What do I avoid talking about?" and "What energizes me vs. drains me?" `[C]`. *Long-term memory* (paid) "triggers relevant memories when you write new entries or ask questions" `[C]`.

### 1.3 The reflection loop — how it avoids overload (and where it doesn't)

What Rosebud does that keeps in-session load low:

1. **One perspective, one question per turn.** Structural, not stylistic. Matches Xiao et al. (CHI 2020): one-question-at-a-time chat produced significantly higher-quality responses than presenting questions together `[C]`.
2. **A no-commentary mode exists.** Focused mode is an admission that the AI voice itself is a load; some users want prompts, not perspectives `[C]`.
3. **Cognitive moves are user-invoked.** Reframes, thinking-trap detection and challenges live in a menu (Guiding Light), so the default turn doesn't stack them `[C]`.
4. **Synthesis is deferred.** The heavy stuff — themes, cast of characters, five insights — waits for the weekly report, where the user arrives expecting a read `[C]`.
5. **Exactly one personalised item per day** in "For You"; a 20-word threshold before anything is generated at all `[C]`.
6. **Quality gates by volume.** In-depth weekly analysis needs 1,500 words; below that the report is mostly stats and tags `[C]` — i.e. the LLM synthesis pass is gated on evidence quantity `[I]`.

Where it still overloads (the complaints are consistent across App Store, Trustpilot, and reviewers `[C]`):

- **Circularity / formulaic follow-ups** after weeks of use: "the follow-up questions can start to feel formulaic"; "conversations can become circular".
- **Entries become AI transcripts**: "your entries end up as transcripts of the AI's questions rather than your own thinking".
- **Memory drift as the corpus grows**: "the larger my account grew with entries the worse it functioned"; persona became "obtuse, harsher"; forgets topics; weak chronology. Classic top-k semantic retrieval degradation `[I]`.
- **Too neutral by default**; challenge must be opted into. One 2★ reported it "reinforced sad thoughts".
- **Usage caps interrupt flow** ("ten messages left until midnight").

The post-entry reflection has five parts (summary, insights, haiku, tags, goals) and the weekly report has five sections — Rosebud is *not* minimalist at synthesis time. It gets away with it because those surfaces are read, not written into, and because the user chose to open them.

### 1.4 Information hierarchy

| Surface | Hierarchy | Density | When |
|---|---|---|---|
| Interactive turn | perspective → one question | very low | while writing, on demand |
| Focused turn | three candidate questions | low; no AI voice | while writing |
| Entry Reflection | summary → insights → haiku → tags → suggested goal | medium | on Finish, synchronous |
| For You | one item | one item | daily |
| Weekly Report | stats → emotional landscape → key themes → cast → ≤5 insights | high | weekly, notified |
| Ask Rosebud | answer + linked entries | user-controlled | on demand |

Emotional state is carried by mood tags and the weekly "emotional landscape" graph, not stated back in-line. Cognitive distortions appear only if the user invokes "identify thinking traps" — they are never volunteered `[C]`. Core themes are a weekly artefact. Actionable questions are one per turn, or the user picks one of three.

### 1.5 AI and prompt strategy (what can be established)

**Stack.** Multi-model: OpenAI, Anthropic, Groq as subprocessors; per-persona model selection; "efficient models like Haiku or Tulip use at least 3x less usage" `[C]`. Full conversation is resent each turn within an entry (usage grows with entry length) `[C]`. No fine-tuning is claimed; Fast Company describes the proprietary layer as "prompt engineering and data collection" refined with licensed therapists `[C]`.

**Stated behavioural principles** (founders and help centre) `[C]`:

- *Don't jump to solutions.* Bader: they worked specifically to stop the base model solving prematurely, "to spend time understanding the user's experiences, helping them articulate their experience and digging into it."
- *Anti-sycophancy as a design goal.* Dadashi: "Models tend to be sycophantic: they agree and comply." Marketing: an AI "that can't be charmed". In practice the default is validating and challenge is opt-in (persona / Guiding Light).
- *Memory as leverage for confrontation.* "It has memory, so it will also call you out… it connects the dots."
- *Adaptive next question:* "the next question comes from what you just wrote, not from a generic prompt list"; a vague entry triggers a clarifying question ("is it physical, emotional, relational?").
- *Non-capabilities are enumerated in the product:* cannot act outside the entry, cannot reliably reference dates, cannot diagnose; crisis → Find a Helpline; stays in conversation rather than hard-stopping.
- *Learned Preferences:* feedback about "writing style, formatting, approach" is auto-classified into durable rules, applied to all future entries, and editable in Settings `[C]`. This is a *second, separate memory* — style memory, distinct from life-fact memory `[I]`.

**How "non-obvious" insight is produced.** Nothing published. From observed outputs `[C]` (e.g. "The constant pull between seeking external validation and finding internal peace reflects a deeper need for grounded self-trust"; "explore what specifically about my work feels misaligned with my working style") the pattern is: name a *tension between two things the user wrote*, then abstract one level ("a deeper need for…"), then hand it back as a question. That is Padesky's guided-discovery sequence — informational question → empathic listening → summary → synthesising question `[C]` — compressed into a turn. The quality ceiling is visible in the same outputs: "grounded self-trust" is exactly the kind of abstraction Spilr's `mirror-write-v2` prompt bans. Rosebud does not appear to run an anti-paraphrase or anti-horoscope check `[I]`.

**Rosebud's own CARE benchmark** (crisis response, Nov 2025) shows they evaluate models on crisis recognition and route model choice partly on that `[C]`.

### 1.6 Data model and context architecture

**Extracted per entry** `[C]`: mood tag, relationship tags, life-theme tags (auto-tagging), people (surfaces as "Cast of Characters"), and — for memory — "the important stuff you mention". `[I]`: a per-entry extraction pass writing salient facts/themes/people into a memory store.

**Memory pipeline, as Rosebud describes it** `[C]`: note important things → build contextual understanding over time → organise → trigger relevant memories on new entries or questions. Works by topic, not date; a "Memory Precision Experiment" toggle improves time-oriented queries at the cost of latency `[C]`. `[I]`: semantic retrieval over memories/entry chunks injected into the prompt, with the precision toggle adding a slower date-aware step. Ask Rosebud's "links to related entries" indicates entry-level retrieval with source attribution (RAG with citations) `[I]`.

**Known failure surface** `[C]`: repetition, forgetting, weak chronology, degradation with corpus size — the signature of unranked top-k retrieval with no novelty/repetition control. Rosebud is rebuilding memory ("a best-in-class memory system that will remember your story like never before") and ending the free plan Sept 30, 2026 to fund it `[C]`.

**What is not public:** default model, response-length rules, whether memories are user-editable, the reflection JSON schema, any yearly review.

---

## Part 2 — Reverse-engineered prompt patterns

These are reconstructions that reproduce Rosebud's observed behaviour, written so they can be dropped into a Gemini/Claude system prompt. They are deliberately short; most of Rosebud's quality comes from *turn shape and gating*, not from long instructions.

### 2.1 Interactive turn (the "perspective + one question" unit)

```
You are a reflective journaling companion. The user is writing a journal
entry and has asked you to go deeper.

TURN SHAPE (non-negotiable):
1. One perspective: 1–2 sentences that add something the user did not
   already say — a tension between two things they wrote, a word they
   used twice, something conspicuously absent, or a more precise name for
   what they described. It must reuse at least one of their exact words.
2. One question: a single open question the user can answer from their
   own experience (they must already hold the answer). Never two questions.
   Never a question that requires expertise or a decision.

DO NOT:
- Summarise or restate the entry. If your perspective could be produced
  by re-reading their text, delete it.
- Advise, fix, or suggest actions unless the user asks ("what should I do").
- Ask about anything not present in their words (no invented people,
  motives, histories).
- Stack hedges. One "might" per turn at most.
- Repeat a question shape you have already used in this entry. Track them:
  {asked_shapes}.

IF THE ENTRY IS VAGUE ("feeling off"): skip the perspective and ask one
clarifying question that splits the space (body / mood / people / work).

IF DISTRESS OR RISK: drop the shape. Respond plainly, name the resource
{crisis_resource}, stay present, do not analyse.

Persona: {persona_instructions}
Learned preferences: {style_rules}
Relevant memories (topic-matched, may be stale — do not assert dates):
{memories}
```

Few-shot (the pair that teaches the difference between paraphrase and perspective):

```
ENTRY: "Said yes to covering Priya's shift again. I was already behind on
the report. Whatever, it's fine, she'd do it for me."

BAD (paraphrase + double question):
"It sounds like you took on extra work even though you were already
stretched. Why do you think you said yes? What would it feel like to say no?"

GOOD (tension + one question):
"You wrote 'she'd do it for me' right after 'already behind' — the yes
seems to be paying a debt that may not exist. Has Priya ever actually
covered for you?"
```

### 2.2 Entry Reflection (post-finish synthesis)

```
Produce the reflection for a finished journal entry. Output JSON only.

{
 "summary":   1 sentence, factual, in the user's own nouns. No adjectives
              the user didn't use.
 "insights":  0–3 items. Each ≤ 25 words. Each must pass:
              (a) not derivable by re-reading the entry,
              (b) contains one quoted phrase from the entry,
              (c) tentative ("may", "seems") — never certain.
              Return [] if nothing passes. Empty beats filler.
 "tags":      {"mood": [..], "people": [..], "themes": [..]} — from the
              entry only.
 "suggested_goal": null unless the user stated an intention; if so, their
              intention verbatim, made specific (when/where), ≤ 15 words.
 "question_for_next_time": 1 open question, ≤ 20 words.
}
```

### 2.3 Weekly synthesis (deferred, high-density surface)

```
You have {n} entries from {start}–{end} ({words} words) and their per-entry
tags and summaries. Write the weekly report.

Sections, in order:
- emotional_landscape: 2 sentences. Name the dominant tone AND the day it
  broke (an exception). Cite dates.
- key_themes: ≤ 3. Each = theme label + one verbatim quote + the number of
  entries it appeared in.
- people: each person mentioned ≥ 2 times, with the role they played this
  week in the user's words.
- insights: ≤ 5, ranked by (recurrence × novelty vs. last week's report).
  Each ≤ 30 words, each anchored to ≥ 2 entries by date.
- one_question: what the week is asking the user; open; ≤ 20 words.

Gate: if words < 1500, produce emotional_landscape and key_themes only.
Do not produce insights from thin evidence.
```

### 2.4 Memory extraction (two memories, not one)

Rosebud's separation of *life memory* from *learned preferences* is the pattern worth stealing.

```
From this entry, extract:

life_memories: facts that will still be true next month. Each:
 {fact, category: person|place|commitment|value|ongoing_situation,
  salience 0–1, quote}. Skip moods and one-off events.

style_preferences: only if the user addressed the AI's behaviour
 ("stop asking so many questions", "be blunter", "no bullet points").
 Each: {rule, scope: always|this_topic, quote}. Skip one-off requests
 ("skip this one").

Return empty arrays freely.
```

### 2.5 Retrieval instruction (the fix for Rosebud's chronology problem)

```
Memories are ranked by: topic similarity × recency decay (half-life 30
days) × novelty (penalise anything surfaced in the last 14 days). When you
reference a memory, name the topic, never the date, unless a date is
attached to the memory record. Never say "last week" from inference.
```

### 2.6 The moves menu (Guiding Light, as a controllable)

Expose cognitive moves as *user-invoked* operations rather than default behaviour, each with one output and a hard cap:

| Move | Output | Cap |
|---|---|---|
| Challenge | one counter-example from their own entries + one question | 40 words |
| Alternative viewpoint | one other reading of the same facts, marked "or:" | 30 words |
| Thinking trap | one Burns distortion named in plain words, with the quoted phrase | 30 words |
| Reframe | the same situation re-described precisely (not positively) | 30 words |
| Suggest | one tiny action, today-sized | 20 words |

---

## Part 3 — Redesign blueprint for Spilr's Mirror

### 3.1 Diagnosis: why Today's Mirror feels noisy `[S]`

The pipeline is *better* than Rosebud's — counter-evidence pass, deterministic MirrorScore, receipts with provenance, a correctable Self Model, no caps. The noise is not in the analysis. It is in three places downstream of it.

**(a) The display unit is the analysis unit.** The deeper-insight formula — *When [trigger], you often [move], which may help you [benefit], but may cost you [cost]; the exception is [x]; a useful question is [y]* — is an excellent internal contract. Rendered as `mirrorSentence` it is a five-clause compound sentence carrying five distinct ideas. Cowan's working-memory limit is ~4 chunks; the sentence is over budget before the card adds anything.

**(b) The card renders every field.** `TodayMirrorCardView` stacks: pulsing status dot + "today's mirror" label + "From N entries" pill → 26pt headline → mirrorSentence → "why this came up" box → "your words" with up to 3 quotes each with a `whyItMatters` caption → tiny experiment → five feedback options → "Saved. Spilr will weigh this." → "Read the full mirror →". Nine zones, three type sizes, two label styles (mono uppercase + rounded bold). Rosebud's equivalent unit has two zones.

**(c) The writer prompt demands 12 fields.** `mirror-write-v2` asks for headline, components, mirrorSentence, whyThisCameUp, temporalAnchor, patternName, receipts[], possibleRead, tinyExperiment, tomorrowCallbackQuestion, shareSafeSummary, confidence — from a context that already includes safety rules, a voice block, a reading-level block, 8 quotes, tracked phrases, avoidance signals, 5 summaries, memory context, and life context. The prompt says "if you can't point to something concrete, return empty fields", but the schema and `isComplete` reward filling every slot. A model asked for twelve things produces twelve things; the weak ones are filler, and filler is what "generic" feels like. `generateMirrorDeck` then writes one card *per hypothesis*, so the writer runs several times a night.

**(d) The tab leaks the ontology.** Under the card: "Go deeper when you want" → *Patterns being watched (7)*, *What you might not be noticing (2)*, *What's shifting (3)*, *When the loop softened (1)*, *Your living profile*, plus the Ask pill and the First Sketch banner. Counts create an obligation. The four rows are your internal `patternType` taxonomy (protectiveLoop / avoidedSubject / exception / timeRhythm) with friendlier labels. Users don't have a mental model for "blind spots" vs "shifting" vs "softened" — to them it is all "things the app thinks about me".

**(e) Five feedback options.** This is me / Almost / Not me / Too intense / Ask tomorrow. Rosebud collects feedback implicitly (Learned Preferences) or not at all. Five explicit choices on every card is a form.

The net effect: a user opens Mirror and is asked to *read* ~120–180 words across nine zones, *evaluate* one hypothesis on a five-point scale, and *choose* among five further sections. Rosebud asks them to read two sentences.

### 3.2 Design principle: earn the next layer

Keep the formula as the *analysis contract*. Change the *display contract* to three layers, each one tap apart, each independently sufficient.

```
L0  The Line      one sentence, ≤ 140 chars, one move, one of their phrases
                  + one implicit affordance (tap)
L1  The Card      the Line + ONE of: a question | a receipt | a then/now pair
                  + two feedback taps
L2  The Proof     receipts (≤3), exception, counter-evidence, confidence-in-
                  words, alternative read, tiny experiment, "Teach Spilr"
```

Rosebud's split is by *cadence* (turn / finish / week). Spilr's split should be by *depth*, because Mirror is a passive surface — there is no turn to pace. Depth is the pacing mechanism.

### 3.3 The Line (L0)

Contract:

- ≤ 140 characters, one sentence, one interpretive move (TENSION, UNDERNEATH, ABSENCE, REFRAME, PATTERN — you already have these in `SpilrVoice.personality`; make the writer *declare* which one it used).
- Contains at least one phrase copied verbatim from an entry (deterministic check: substring match against `receipts[].quote` or `phrasesToTrack`).
- At most one hedge word. "May protect against … but may cost …" is two hedges and two ideas; the Line gets one.
- No headline above it. The Line *is* the headline. Kill the 26pt `headline` field.
- Scope-bound wording per `mirrorprd.md` §2.9 (state, not trait).

The formula maps to Lines like this:

| Formula clause | Line move | Example |
|---|---|---|
| trigger → move | PATTERN | "Three 'quick favours' this week, all on days you wrote 'behind'." |
| move → cost | TENSION | "You call it 'resetting' — and it's the word you use right before a lost weekend." |
| exception | EXCEPTION | "Tuesday you said no to Dan and the entry got shorter, not worse." |
| absence | ABSENCE | "Eleven entries about the team. You appear in two of them." |
| benefit | UNDERNEATH | "Saying yes to Priya seems to be repaying something. It's not clear she's keeping score." |

The rest of the formula (benefit, cost, exception, question) is still generated — as the *proof*, not the sentence.

### 3.4 The Card (L1) — four shapes, one payload each

Select the shape deterministically from the hypothesis, not by asking the model:

| Shape | When (`patternType` / state) | Payload under the Line |
|---|---|---|
| **Notice** | protectiveLoop, identityRule, relationshipRole, valuesConflict | one receipt: quote + date, nothing else |
| **Ask** | avoidedSubject, or `timesSeen < 3` (soft) | one question (`tomorrowCallbackQuestion`), no receipt |
| **Then / Now** | vocabularyFingerprint, timeRhythm, `timesSeen ≥ 5` | two quotes, oldest and newest, with "N weeks apart" |
| **Softened** | exception | the exception receipt + "what was different" (from `counterEvidence`) |

Feedback on the card is two taps — **This is me** / **Not quite** — plus a text-only "more…" that opens the L2 controls (Too intense, Ask tomorrow, Teach Spilr). Two taps is a reaction; five is a survey. Map "Not quite" → `almost` in `MirrorFeedback` so the SM-1 correction loop keeps its signal.

Card chrome: drop the pulsing dot, the "From N entries" pill, the mono-uppercase section labels, and the gradient blob. One type size for the Line (editorial, ~20pt), one smaller size for the payload. The card should be readable in under eight seconds; instrument it (see 3.9).

### 3.5 The Proof (L2)

`EvidenceDrawerView` already exists and is close to right. Move everything that was on the card into it: receipts (≤3, each with `whyItMatters`), "seen N times / first seen / when it softened", counter-evidence, confidence as a word, `possibleRead` ("or, it might be…"), `tinyExperiment`, `shareSafeSummary`, and the "Teach Spilr" correction flow. Keep "Read the full mirror →" (the Daily Chat hand-off with `seedContext`) here — that is Spilr's equivalent of Rosebud's *Go deeper*, and it belongs behind intent, not on the face of the card.

### 3.6 The tab

Replace the four counted disclosure rows with two uncounted ones:

- **Your patterns** — a single chronological list of surfaceable hypotheses, each rendered as its Line with a small type label (pattern / blind spot / softened / shifting). The taxonomy becomes a *tag on the item*, not a *navigation branch*. Sort by `MirrorScore`, group nothing.
- **Your living profile** — unchanged.

Ask stays as a pill; the First Sketch banner shows only until opened once. Remove the subtitle ("One reflection a day, from your words") — the Line says it.

A **silence state** is a feature, not a fallback. When no hypothesis clears the floor *or* novelty gate (3.8), the card slot shows a Mirror Seed / NBQ question instead: "Nothing new to show. Your last three entries read like one week. — When did today feel 5 percent lighter?" Rosebud's users complain about circularity because Rosebud never chooses silence; `safetyRules` rules 8 and 10 already give Spilr permission to.

### 3.7 Prompt architecture: split the writer

Replace the single 12-field `mirror-write-v2` call with a three-stage pipeline. Stages 1 and 3 are deterministic; only stage 2 is an LLM call, and its output is tiny.

**Stage 1 — Select (Swift, no LLM).** Pick the top hypothesis by MirrorScore, apply the novelty gate (3.8), choose the shape (3.4), and pick the receipt(s) by id from `evidenceEntryIds` / `counterEvidenceEntryIds`. The writer never gets to choose or rewrite evidence.

**Stage 2 — Write (LLM, temp 0.4, maxTokens ≈ 200).**

```
{SpilrVoice.safetyRules}

Write ONE line for this person's mirror. Output JSON only.

THE HYPOTHESIS (already verified, do not soften or expand it):
{coreHypothesis} · scope: {scope} · seen {timesSeen}× since {firstSeen}

THE RECEIPT YOU MUST USE (quote it or reuse its exact nouns):
"{receipt.quote}" — {daysAgo} days ago

SHAPE: {Notice|Ask|ThenNow|Softened}
MOVE: choose exactly one of TENSION / UNDERNEATH / ABSENCE / REFRAME /
PATTERN and name it in "move".

RULES
- "line": ≤ 140 characters. One sentence. One idea. At most one of:
  may / might / seems.
- Must contain a phrase from the receipt verbatim.
- Must fail the re-read test: if the line could be written by re-reading
  the entry, it is a summary — return "" instead.
- Must fail the horoscope test: swapping this person for a stranger
  must break the sentence.
- 8th-grade vocabulary. No metaphor. No "journey / space / navigate /
  honour / show up".
- State, not trait: "this week", "on the days you wrote X" — never
  "you are someone who".
- For shape Ask, also return "question": one open question ≤ 20 words
  that the person already knows the answer to. Otherwise "question": null.

{
 "line": "...",
 "move": "TENSION",
 "question": null,
 "confidence": "low|medium|high"
}

{lifeContextBlock}
```

Everything else the old prompt produced — `whyThisCameUp`, `possibleRead`, `tinyExperiment`, `shareSafeSummary`, `temporalAnchor` — is either derivable from the hypothesis record (temporal anchor, why it came up = the trigger clause of the mined `components`) or generated *lazily* when the user opens L2, in a second small call. Don't pay for proof nobody reads.

Few-shot for stage 2:

```
HYPOTHESIS: When plans are cancelled on her, she immediately fills the
slot with work and describes the evening as "productive".
RECEIPT: "Maya bailed so I just cleared my inbox, honestly a productive
night" — 2 days ago
SHAPE: Notice · MOVE: REFRAME

BAD (summary):    "When plans get cancelled you tend to fill the time with
                   work and call it productive."           ← re-read test fails
BAD (horoscope):  "You may be using busyness to avoid sitting with
                   disappointment."                         ← no phrase, any stranger
BAD (overloaded): "When Maya cancels you clear your inbox, which may keep
                   the evening from feeling empty but may cost you the
                   chance to notice you were let down."     ← 3 ideas, 2 hedges
GOOD:             "'Honestly a productive night' is the third time a
                   cancelled plan has ended in your inbox."  ← 87 chars, PATTERN,
                                                               verbatim phrase
```

**Stage 3 — Lint (Swift, no LLM).** Reject and fall to silence if: length > 140; hedge count > 1; no verbatim overlap with the receipt; content-word overlap with the source entry > 70% (paraphrase detector — Jaccard over lemmatised nouns/verbs is enough); any banned-term hit (`safetyRules` list); trait phrasing regex (`you are (someone|a person) who`, `you always`, `you never`). Log every rejection reason — this is your prompt-quality dashboard.

Keep `mirror-guard` (Prompt E, temp 0.0) as a final LLM check, but shrink its job to safety and scope-language; the lint handles form.

### 3.8 Selection: novelty is a gate, not a score term

`MirrorScore` already subtracts `repetitionFatigue` for the *same* hypothesis. Rosebud's circularity problem is *different* hypotheses that read the same. Add a hard gate before writing:

```
reject if  jaccard(contentWords(candidate.coreHypothesis),
                   contentWords(any line shown in last 14 days)) > 0.5
reject if  candidate.evidenceEntryIds ⊆ union(evidence of lines shown
           in last 7 days)          // same evidence, new wording = repeat
prefer     candidates whose evidence includes an entry from the last 48h
           // "why this came up today" is then true by construction
```

And bias toward `exception`-type hypotheses whenever one is available — they are the highest-learning signal in your own PRD and the least likely to feel like an accusation.

### 3.9 Data model changes

- **New `MirrorLine`** (`users/{uid}/mirrorLines/{yyyy-MM-dd}`): `line`, `move`, `shape`, `question?`, `hypothesisId`, `receiptRefs[{entryId, quote, date}]`, `confidence`, `scoreBreakdown`, `lintPassed`, `shownAt`, `expandedAt?`, `proofOpenedAt?`, `feedback?`, `promptVersion: mirror-line-v1`. Replaces per-day `MirrorCard` for the daily surface; `MirrorCard`'s long fields move to a lazily-written `mirrorLines/{date}/proof` sub-doc.
- **Add `StylePreferences`** (`users/{uid}/stylePreferences`): the Learned-Preferences pattern. `Too intense` writes `{sharpness: -1}`; two consecutive `Not quite` on the same `patternType` writes `{muteType: X, until: +14d}`; free-text corrections that address Spilr's *behaviour* rather than the *content* are routed here instead of to `ProfileCorrection`. Injected into stage 2 as `{style_rules}`. Currently the only style control is the global depth setting; this makes feedback change behaviour, which is what makes people keep giving it.
- **Retrieval:** you don't need semantic search for the daily line — `evidenceEntryIds` is provenance and beats it. Reserve embedding retrieval (`MirrorRetrieval` in the plan) for Ask and for the counter-evidence pass, and apply the ranking in 2.5 (topic × recency decay × 14-day novelty penalty) so Ask doesn't inherit Rosebud's drift.
- **`EntryAnalysis`** stays as is. Guided-exercise entries from the prototype (CBT before/after intensity, gratitude "why it mattered", Best Possible Self "7-day action") should write typed fields into `EntryAnalysis` — a before→after delta of 8→4 is the best receipt a Softened card can have, and the "7-day action" is a ready-made `tinyExperiment`.

### 3.10 Rhythm

| Cadence | Surface | Density |
|---|---|---|
| Per entry | nothing on Mirror; Echo stays the in-editor one-liner | 0 |
| Daily | one Line (or silence + seed) | 1 sentence |
| Weekly | a "Mirror letter": 3 sentences — the week's tone and the day it broke; one theme with a quote; one question. Push notification. | ≤ 80 words |
| 7 / 30 / 90 entries | First Sketch / Monthly / Rhythm (existing `MirrorMaturity`) | card |

The weekly letter is the place for the density Rosebud puts in its report; it is what gives the daily Line permission to be one sentence.

### 3.11 Instrumentation for "high signal, low noise"

Track per Line: `shown → expanded` rate, `expanded → proofOpened` rate, `feedback` rate and split, time-on-card (target median < 8s at L0, < 25s at L1), `lintRejectReason` distribution, silence-day rate (healthy range 15–35%; below 15% you're forcing lines, above 35% mining is too conservative), and 14-day line Jaccard (repeat detector). Success metric: **"This is me" rate rises while time-on-card falls.**

### 3.12 Sequence

1. **Week 1 — subtraction only, no AI change.** Hide `headline`, `whyThisCameUp`, receipts, experiment, and three feedback options from `TodayMirrorCardView`; show `mirrorSentence` + one receipt + two taps; collapse the four disclosure rows into one uncounted list. Measure. This alone will move the "noisy" perception because the content is already reasonably specific.
2. **Week 2 — Stage 3 lint + novelty gate** on the existing writer's output, with silence fallback. Watch the reject-reason log.
3. **Week 3 — Stage 2 writer** (`mirror-line-v1`) and `MirrorLine` model; lazy proof generation; stop writing a full card per hypothesis nightly (cost drops with it — see `ai-cost-audit-2026-09-06.md`).
4. **Week 4 — StylePreferences** memory wired to feedback; weekly Mirror letter.
5. **Then** typed `EntryAnalysis` fields from guided exercises; shape "Then / Now" once ≥ 5-seen hypotheses exist for enough users.

---

## Sources

Rosebud help centre: dig-deeper · entry-reflection · weekly-report · long-term-memory · ai-personalization · learned-preferences · usage-limits · auto-tagging · ask-rosebud · guiding-light · personalized-prompts · personalized-content · morning-intention · evening-reflection · blank-entry · guided-journals · custom-journals · entry-history · notifications · rosebud's-limitations · privacy-policy · changes-to-the-free-plan · comparison/chatgpt-vs.-rosebud (all under https://help.rosebud.app/).
Rosebud blog / site: meet-rosebud · rosebud-raises-6m · why-journaling-fails-high-achievers · ai-journaling-vs-traditional-journaling · unlock-your-inner-wisdom (IFS) · https://www.rosebud.app/care.
Press and interviews: Fast Company (https://www.fastcompany.com/91167593/rosebud-ai-journaling-app-writing-partner) · TechCrunch (https://techcrunch.com/2025/06/04/rosebud-lands-6m-to-scale-its-interactive-ai-journaling-app) · Forbes on CARE (https://www.forbes.com/sites/johnkoetsier/2025/11/21/gemini-3-just-scored-100-on-a-critical-test-all-other-ai-models-fail/) · ODAAT podcast with Sean Dadashi (https://odaatchat.com/index.php/2025/11/05/sean-dadashi-on-not-belonging-suicidal-depression-and-tools-for-healing/) · Bustle review (https://www.bustle.com/wellness/rosebud-therapy-app-review-features-price).
Reviews: App Store (https://apps.apple.com/us/app/rosebud-ai-journal-diary/id6451135127) · Trustpilot (https://www.trustpilot.com/review/rosebud.app) · Casey Douglass (https://www.casey-douglass.com/2024/10/app-review-rosebud.html) · IT Nerd (https://itnerd.blog/2025/11/19/review-rosebud/) · Life Note (https://blog.mylifenote.ai/rosebud-journal-alternative/) · Mindsera comparisons (https://mindsera.com/articles/rosebud-vs-mindsera/) · Reflection.app (https://www.reflection.app/blog/ai-journaling-apps-compared).
Research: Padesky, Socratic Questioning (https://padesky.com/wp-content/uploads/2012/11/socquest.pdf) · Xiao et al., "Tell Me About Yourself", CHI 2020 (https://research.ibm.com/publications/tell-me-about-yourself) · Cowan on working-memory capacity (https://journalofcognition.org/articles/10.5334/joc.387) · Burns' distortions list (https://feelinggood.com/wp-content/uploads/2017/04/41656-distortions-v-18.pdf) · VA on expressive writing (https://www.va.gov/WHOLEHEALTHLIBRARY/docs/Therapeutic-Journaling.pdf) · Day One multi-entry summary limits (https://dayoneapp.com/guides/ai-features/ai-multi-entry-summary/).
Spilr codebase: `mirrorprd.md`, `MIRROR_IMPLEMENTATION_PLAN.md`, `ai-prompts-verbatim-2026-09-02.md` §3, `chatprompt-teardown-2026-09-02.md`, `DailyJournal/Mirror/MirrorView.swift`, `TodayMirrorCardView.swift`, `MirrorCard.swift`, `MirrorScore.swift`, `functions/index.js` (`writeMirrorCardFor`, `generateMirrorDeck`), `Rosebud_Teardown_Spilr.pptx`, `spilr_guided_journaling_prototype.html`.
