# Spilr — AI Prompt Inventory & Simplification Review

Every place the app talks to Gemini, the prompt it sends today, a one-line verdict on whether it's "on point vs over-complicated," and a tightened version where it helps. All prompts share two building blocks: **`NinetyVoice.system`** (the persona) and **`MemoryProfileService.cachedPromptContext()`** (per-user memory appended at the end).

## Verdict at a glance

| # | Surface | File | Verdict |
|---|---|---|---|
| 1 | Persona — `NinetyVoice.system` | `Home/NinetyVoice.swift` | ✅ Excellent. Tight, specific, keep as-is. |
| 2 | Chat persona — `chatSystem` | `Home/NinetyVoice.swift` | 🟡 Good but long — safe to trim ~30%. |
| 3 | Chat follow-up turn | `Chat/AIService+Chat.swift` | ✅ Deliberately short. Keep. |
| 4 | Chat opener | `Chat/AIService+Chat.swift` | 🔴 Static/hardcoded — personalize (T1.5). |
| 5 | Chat weave → entry | `Chat/AIService+Chat.swift` | ✅ Strong. Keep. |
| 6 | Mirror extract (Prompt A) | `Mirror/AIService+Mirror.swift` | 🟡 Heavy but justified (structured schema). Trim preamble. |
| 7 | Mirror write card (Prompt D) | `Mirror/AIService+Mirror.swift` | ✅ Good. Keep. |
| 8 | Mirror mine (Prompt B) | now server-side | ✅ Rewritten simple (this change). |
| 9 | Mirror guard (Prompt E) | `Mirror/AIService+Mirror.swift` | ✅ Good, tight. Keep. |
| 10 | Per-entry insights | `Home/AIService.swift` | ✅ Tight. Keep. |
| 11 | Echo extraction | `Echo`/`Home/AIService.swift` | 🟡 Over-long rule stack — simplify. |
| 12 | River mark | `River/AIService+River.swift` | ✅ Clear. Keep. |
| 13 | Daily Read generator (server) | `functions/index.js` | ✅ Best-working surface. Don't touch mechanics; only rename persona. |
| 14 | Daily Read guard (server) | `functions/index.js` | ✅ Good. Keep. |
| 15 | Legacy pattern detection | `Pattern/AIService+Patterns.swift` | 🔴 Says "ninety"; overlaps new miner — consolidate/retire. |

**Two cross-cutting issues:** (a) the server persona `NINETY_VOICE` and the legacy pattern prompt still say **"ninety"** — client-side `NinetyVoice.system` was already renamed to **"YOU ARE SPILR."**, so these two lag. (b) The **legacy pattern prompt (#15)** and the **new nightly miner (#8)** now do overlapping jobs — pick one (the miner is richer); see `IMPLEMENTATION_TASKS.md` §3B.

---

## 1 · Persona — `NinetyVoice.system` — ✅ keep

Prepended to almost every prompt. Already excellent: names the voice, bans clichés/diagnosis/advice, and enforces the "never restate what they wrote — add the layer they didn't" rule with five concrete moves (tension / underneath / absence / reframe / pattern). This is the backbone; don't dilute it.

## 2 · Chat persona — `chatSystem` — 🟡 trim

Current is ~24 lines: warm-friend voice, "stay with what they said," "sound human not mechanical," and a banned-phrase list ("how did that make you feel", "that sounds difficult", "I hear you", "thanks for sharing"). It's good, but the middle two paragraphs overlap. Tighter version:

```
YOU ARE SPILR. You're texting a friend about their day — warm, curious, easy. A good
listener, not a therapist running a protocol.

Only talk about the people, places, feelings and events they've actually named. Never
invent a second person, a motive, or a detail they didn't give. If you're unsure who or
what they mean, just ask.

Read for the part with the most feeling and ask about THAT — don't grab a noun and bolt
a question on. Reflecting a few of their words back first is good. A little commiseration
is welcome ("ugh, that's a long day"). Never say "how did that make you feel", "that
sounds difficult", "I hear you", or "thanks for sharing", and never give advice. Plain,
lowercase-friendly language.
```

## 3 · Chat follow-up turn — ✅ keep

The instruction is intentionally light ("a brief warm acknowledgement, then one question that follows the part with the most feeling"). The code comment explains why: a heavy constraint stack made the model *worse* (bare interrogatives). This is the right call — leave it short. **Only real fix here is behavioural, not prompt:** `readyToWeave` is a turn counter (`userTurns >= 3`); let the model own depth instead (T1.5).

## 4 · Chat opener — 🔴 personalize

Currently five hardcoded lines rotated by `day % 5` — identical for every user. Replace with a memory-grounded opener (from `MemoryProfile` + today's mood + most recent open loop), keeping the five as the offline floor. Suggested prompt for the generated opener:

```
{NinetyVoice.chatSystem}
Open the conversation with ONE short line (max ~90 chars) grounded ONLY in what this
person has told you before. Reference at most one concrete thing — a recent open loop,
a recurring theme, or today's mood. Warm, low-pressure, ends invitingly. If you have
nothing specific, ask an open, gentle question. Never invent anything.
{memory context}
```

## 5 · Chat weave → journal entry — ✅ keep

Turns the back-and-forth into a first-person entry, preserving the user's words, matching length to depth, banning lists. Strong and clear. Keep. (Behavioural fix only: don't offer the weave until there's ≥12 words of material — gate the *button*, don't fail after it.)

## 6 · Mirror extract (Prompt A) — 🟡 trim preamble, keep schema

This is the structured extractor that now runs on every save (just wired). The big JSON schema is *necessary* — it's the structured signal the whole engine needs. The 5 rules are good; you can drop the redundant "may/might/seems" line (the guard enforces hedging downstream) and keep it at 4 rules. Don't touch the schema.

## 7 · Mirror write card (Prompt D) — ✅ keep

Generates the single daily Mirror card from the top hypothesis: headline, mirror sentence, receipts, a gentler alternative read, a tiny experiment, a tomorrow question. Well-scoped and on-voice. Keep.

## 8 · Mirror mine (Prompt B) — ✅ rewritten simple (server-side, this change)

Old location: client-side `buildMirrorMinePrompt` (heavy, ran on tab-open). New: `buildMinePrompt` in `functions/index.js`, deliberately short. Full text:

```
{NINETY_VOICE}
TASK — find at most 6 patterns across these structured notes (most recent first)...
HARD RULES:
- Ground every pattern in the person's OWN words (verbatim quotes; never invent).
- For every pattern, give ≥1 counter_evidence quote — a time it did NOT hold. No exception → drop it.
- Hedged, state/season language. NEVER identity language, NEVER clinical terms.
- Prefer the EXCEPTION (the day a hard pattern softened).
- One sharp earned pattern beats five shallow ones.
```

This bakes in the quality bar (evidence + counter-evidence + hedged + exception-first) instead of asserting it in prose.

## 9 · Mirror guard (Prompt E) — ✅ keep

Final safety gate before a card shows: suppress on clinical labels / fixed-identity language ("you always") / trauma inference / shame / therapy-replacement / ungrounded claims; rewrite if 1–2 phrases cross the line; else approve. Tight and correct. Keep — and keep it running.

## 10 · Per-entry insights — ✅ keep

Returns exactly 2 "noticed" bullets (each must do a MOVE, not restate) + 1 sharp question + 1 sentiment label from a fixed list. Ends with the self-test: *"could I have written this just by re-reading their entry? If yes, replace it."* Excellent, tight. Keep.

## 11 · Echo extraction — 🟡 simplify

Longest prompt in the app — four categories (INTENTION / OPEN_LOOP / THEME / MOOD_MARKER), each with rules, plus surface-timing constants and a callback-line spec. It works but it's dense. Suggested trim: move the `surface_after_hours` mapping out of the prompt into code (the client already knows the type → just look it up), and cut the worked example down to one. That alone removes ~8 lines and reduces the chance the model fixates on formatting over judgment. Keep the 80%-confidence "silence is correct" rule — that's the important part.

## 12 · River mark — ✅ keep

Converts one entry into emotional signals (valence/activation/clarity/pressure/self-compassion + water state + marker + safety level) with clear numeric scales and its own crisis gate. Clean and well-bounded. Keep.

## 13 · Daily Read generator (server) — ✅ keep mechanics, rename persona

The two-stage generator (temp 0.8) → guard (temp 0.0) with six fixed sentence templates is your best-working AI surface — don't refactor it. The one change: `NINETY_VOICE` still opens "YOU ARE NINETY"; align it to Spilr for brand consistency (low risk; the model doesn't emit its own name in `read_text`). The user-visible push copy/title were already renamed to "Spilr" in this change.

## 14 · Daily Read guard (server) — ✅ keep

Scores five axes 1–5; any axis < 4 rejects. Rejects diagnostic language, horoscope fluff, action items, ungrounded insights, cruelty. Solid. Keep.

## 15 · Legacy pattern detection — 🔴 consolidate / retire

Still opens *"a private journaling app called **ninety**"*. Six archetypes, safety flag, evidence-with-index. It's a good prompt — but it now **overlaps the new nightly miner (#8)**. Running both means two prompts, two safety paths, two voices to maintain. Recommendation: once the nightly miner is verified in production, retire this path (see `IMPLEMENTATION_TASKS.md` §3B) and, until then, at minimum fix "ninety" → "Spilr".

---

*Persona note: `NinetyVoice.system` and `chatSystem` already say "YOU ARE SPILR." The remaining "ninety" references in prompts are the server `NINETY_VOICE` and the legacy pattern prompt (#15). Renaming the Swift type `NinetyVoice` itself is a separate mechanical refactor (see IMPLEMENTATION_TASKS.md §3D).*
