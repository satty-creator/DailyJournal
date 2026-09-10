# Mirror v3.1 — the Person Model

**For:** Satakshi · Spilr (ninety) · 2026-09-10
**Status:** replaces §§2–5 of `mirror-v3-prd-2026-09-10.md`. Keeps its bug list (§1), its pipeline shape (§8), its lint idea (§6) and its sequence — but changes what the pipeline is *for* and what goes on the screen.
**Stance:** AI product strategy + prompt engineering + CBT formulation. Every psychological claim below was checked against the original paper; the paraphrase used is the accurate one.

---

## 0. What I got wrong, and the corrected principles

Three critiques, all correct.

**"Data shouldn't be a number."** I read Forer as "be checkable" and turned that into arithmetic. The actual lesson of the Barnum literature (Forer 1949; Dickson & Kelly 1985) is that people accept statements that are *favourable, general, and framed as personal*. The antidote is not a count. It is a statement that **could have been false about this person and wasn't** — a claim with content. "You like the work; what wears you down is needing three people to say yes" is Barnum-proof because a different person would get a different sentence, not because it has a "3" in it. The number is a receipt, not the insight.

**"Why not deduce personality?"** Because I over-applied self-distancing (Kross & Ayduk). That research is about the *user's* vantage point on their own experience — it says nothing against the app having a view of the person. Worse, "on the days you wrote…" is exactly the flat, un-falsifiable register that produces "so?". A mirror that refuses to say what it sees is not a mirror. The correct constraint comes from a different literature: Mischel & Shoda's CAPS model (1995) — personality is best described not as trait averages but as stable **if-then signatures**: *when* teased by a peer, aggressive; *when* warned by an adult, compliant. Signatures are claims about the person. They are also the thing a journal can see and its author cannot.

**"What does 'the model is not involved' mean?"** I put the wrong layer on the screen. Statistics should decide *where to look*; the model should decide *what it means*; code should decide *whether it is safe to say*. The previous PRD displayed the where-to-look layer. Nobody pays for that.

Corrected principles:

1. **The product is a working model of the person** — a CBT case formulation (Persons 2008; Kuyken, Padesky & Dudley 2009) held as hypotheses, tested against entries, corrected by the user.
2. **Say what you see, in if-then form.** Claims about the person are the point. What is banned is the trait label without a situation ("you're conflict-avoidant") and the clinical label. What is required is the signature ("with Dan you go quiet; with Priya you over-explain — same trigger, two moves").
3. **An insight is something the user could not have written themselves.** Operationally: a contingency in their data they have never stated as a *because*; a mechanism shared by two areas of life they keep separate; a gap between what they say and what they do; or an exception that reveals the mechanism.
4. **Every claim is falsifiable and carries its test.** The Mirror says what would change its mind, and asks the question that would.
5. **The questions are the product too.** The next journaling prompt is chosen to test the formulation's most valuable open hypothesis — and to help the user untangle it (guided discovery, downward arrow, MI). Data collection and therapy are the same act.

---

## 1. Why a journal can see what its author can't — the research that licenses deduction

- **People do not have introspective access to the causes of their own behaviour** (Nisbett & Wilson 1977): asked why, they generate plausible a-priori theories. A journal is a record of *what happened and what was felt*, with the causal story bolted on afterwards by the same person. The contingencies are in the record; the author's explanations are not evidence of them.
- **Others know some things about us better than we do** (Vazire 2010, SOKA): the self is best on low-observability, low-evaluative traits (how anxious I feel); *close others* are better on evaluative traits (how creative, how difficult). Bollich, Johannet & Vazire (2011) argue explicit feedback from close others is the most promising route to self-knowledge. The Mirror is a close other with perfect recall and no social cost for candour.
- **Machines already do this at useful accuracy.** Youyou, Kosinski & Stillwell (2015, PNAS): computer personality judgments from Facebook Likes (r = .56) beat human judges (r = .49); 70 Likes matched a friend, 300 a spouse. Peters & Matz (2024, PNAS Nexus): zero-shot GPT-4 inference of Big Five from ~200 status updates correlated r ≈ .29 with self-report. Journal entries are far richer per token than Likes or statuses. Big Five is the wrong target for a product (it is exactly the general-trait layer Barnum lives in), but the finding establishes that text-to-disposition inference is real, not a parlour trick.
- **Personality *is* the if-then signature** (Mischel & Shoda 1995; Shoda, Mischel & Wright 1994): children's situation-behaviour profiles were stable and distinctive after normative situation effects were removed. This is the unit the Mirror should infer, because (a) it is where the self is blind (you experience each situation separately; the pattern across them is invisible from inside), (b) it is checkable against entries, and (c) it is actionable — a signature names the trigger.
- **The CBT frame for holding all of this is the case formulation** (Beck's cognitive model: automatic thoughts ← intermediate beliefs/rules ← core beliefs, with coping strategies; Kuyken, Padesky & Dudley's three levels: descriptive → cross-sectional (triggers and maintenance) → longitudinal; Persons' formulation-as-hypothesis tested collaboratively). Its ethics are *collaborative empiricism*: the formulation is offered, evidenced, and revised with the client — never delivered as a verdict.
- **Feedback works when it points at the situation, not the self** (Kluger & DeNisi 1996: 38% of feedback interventions made performance *worse*; effectiveness falls as attention moves from the task toward the self). This is the empirical reason for the signature form over the label form. "You're avoidant" points at the self. "When Dan raises his voice you go quiet" points at a situation the user can do something about.
- **Ambivalence is elicited, not resolved by telling** (Miller & Rollnick, MI): the helper's "righting reflex" — arguing for the change — produces sustain talk. The Mirror never tells the user what to do; it names the two things they want and asks.
- **What makes an insight feel like one** (Topolinski & Reber 2010): suddenness, ease, positive affect, felt certainty — all from a sudden gain in fluency. A well-formed Mirror line is *short*, connects two things already in the user's head, and ends before the user has to work.

---

## 2. What "mind-blowing" is, operationally: the four insight shapes

A Mirror line is only allowed to be one of these four. Each has a psychological basis, a data test, and a worked example built from the hypotheses the current Mirror generated for your own account (I have not read your entries — the examples are what the *existing* signals could support, phrased the way v3.1 would phrase them).

### Shape 1 — The signature (CAPS)
*Same trigger, different moves by context; or same move across contexts the user keeps separate.*

Test: an `EntryAnalysis.protectiveStrategies` value that co-occurs with ≥ 2 distinct situation types, or two different strategies for the same situation type split by person/domain.

> Your current Mirror: "translating empty hours into engineering problems" (six times).
>
> v3.1: **"When the future goes blank, you build something. It shows up twice: open hours since the job change, and the fairness ledger with Dan — both are a project that makes an uncertain thing feel worked-on. The tell is that the 'lucky and loved' evenings are the ones where nothing got built."**

### Shape 2 — The unstated because (Nisbett & Wilson; Pennebaker)
*A contingency in the data the user has never written as a causal sentence.*

Test: contingency strength (co-occurrence lift or lag effect, n ≥ 3 with contrast) × (1 − user attribution), where attribution = whether any entry links the two terms with a causal connective ("because", "since", "after", "so"). A strong contingency with zero attribution is the highest-value line in the system. This is the exact operationalisation of "something they wouldn't notice on their own."

> **"Every entry with 'heavy' in it was written on a day you also wrote about the job. You've written 'heavy' as weather — it arrives. The entries say it arrives on a schedule."**

### Shape 3 — The say/do gap (MI ambivalence; SDT need frustration)
*What the user states they want vs. what the entries show them doing — held as two real wants, not a contradiction to fix.*

Test: a value or stated intention (`valuesPresent`, `openLoops`, template "tomorrow I want to") against a behaviour (`protectiveStrategies`, episodes' outcomes) that runs against it, ≥ 2 occurrences.

> **"Twice this month you wrote that rest was the plan. Both times the entry ends with what you shipped instead. Two things you want: to stop, and to have something to show for the day. Neither is wrong. Which one is older?"**

### Shape 4 — The exception that explains the rule (SFBT; Kuyken's strengths level)
*The day the pattern didn't hold, and what was different — the mechanism read backwards.*

Test: an `exception`-type hypothesis or a contrast day inside a Shape-2 contingency, with at least one distinctive feature (person present, time, body signal, template used).

> **"Tuesday was the one heavy day that didn't turn into a project. You'd written 'being held' an hour earlier. That's the strongest evidence in your journal for what the projects are standing in for."**

Every one of these could be wrong about you. That is what makes them worth reading — and why each carries a receipt and a question.

---

## 3. The Person Model

This is the data structure the Mirror maintains, displays, and asks questions to improve. It replaces the flat `SelfModel` sections with a CBT case formulation in Kuyken's three levels. Every item is a hypothesis with `{confidence, evidenceEntryIds[], counterEvidenceEntryIds[], userStatus, lastTestedAt, testQuestion}`.

**Level 1 — Descriptive (Padesky & Mooney's five-part model, per situation type)**

- `situations[]`: recurring situation types in the user's life, named in their words ("open Saturday", "approvals", "Dan raising it again"). Each links to entries.
- For each situation: typical `thoughts` (automatic, quoted), `emotions` (their words), `bodySignals`, `behaviours` (the move).

**Level 2 — Cross-sectional (triggers and maintenance)**

- `signatures[]`: if-then pairs — `{if: situation, then: move, notWhen: exceptions[], contexts: {work|home|person}}`. The CAPS layer. This is what "Threads" become.
- `rules[]`: intermediate beliefs in conditional form, inferred via the downward arrow from repeated thoughts — "if I rest before something ships, I'm falling behind". Confidence never above `maybe` without user confirmation.
- `maintenanceLoops[]`: the short-term relief a move gives (why it persists) and its cost — the existing `protection/cost` fields, kept.
- `needs`: an SDT profile — autonomy / competence / relatedness, each with `satisfactionEvidence[]` and `frustrationEvidence[]`. This is the lens that turns "politics bother you" into "every work complaint in six weeks is about autonomy — approvals, sign-off, being routed — and none is about competence. You don't doubt the work; you mind not owning it." Need frustration, not low satisfaction, is what predicts ill-being (Vansteenkiste & Ryan 2013; Chen et al. 2015), so the model tracks frustration events specifically.
- `distortions[]`: Burns-style thinking patterns *observed in quoted thoughts*, phrased plainly ("treats one late report as the whole week" not "overgeneralisation"), with the quote. Never a diagnosis; a description of a sentence they wrote.
- `people[]`: per-person signature — the role the user takes, the move, the exception.

**Level 3 — Longitudinal**

- `coreBeliefs[]`: reached only by ≥ 3 converging rules and only ever shown as a question ("Is the rule underneath this something like 'I'm only safe when I'm producing'? You'd know."). Hard gate: `doNotInfer` (diagnosis, trauma origin, attachment style, childhood) stays.
- `values[]` (ACT): what the exceptions and the "lucky" entries point at.
- `strengths[]`: what already works — the exceptions, read as competence (Kuyken's strengths principle). Not a consolation section; the mechanism section.
- `trajectory[]`: how a signature has changed over ≥ 30 days.

**Open questions** — `openHypotheses[]` ranked by *value of information*: `confidence uncertainty × emotional weight × actionability`. The top one drives tomorrow's journaling prompt (§5).

**Ask-answerable.** Because the model is structured, "Ask Spilr" becomes a real feature: "What do I do when I'm criticised?" is answered from `signatures` and `people` with receipts, not by re-reading 300 entries.

---

## 4. Who does what: AI, statistics, code

| Step | Who | What it actually does |
|---|---|---|
| Extract signals from each entry | **AI** (Prompt A, exists) | Situations, thoughts, emotions, moves, needs, people, body, quotes. This *is* AI pattern-detection's raw material. |
| Find candidate contingencies | **Code** | Co-occurrence, lag, per-person and per-domain splits over the extracted signals; the `unstated because` score; exception detection. Cheap, exact, and it tells the formulation prompt *where to look* so it can't hallucinate a pattern from one entry. |
| Formulate | **AI** (Prompt F, new — §6) | Turns candidates + quotes into the Person Model: signatures, rules, needs, loops, open questions. This is the deduction. |
| Disconfirm | **AI** (Prompt CE, exists) | "What in the entries makes this untrue?" on every claim before it is shown. |
| Gate | **Code** | n ≥ 3 with contrast for signatures; confidence bands; lint (§7); `doNotInfer`; crisis gate. |
| Express | **AI** (Prompt M, new) | One line in one of the four shapes, with receipt and question. |
| Plan the next question | **AI** (Prompt Q, new) | The journaling prompt / chat move that tests the top open hypothesis. |
| Answer | **AI** (Prompt ASK, new) | Questions about the user, from the model, with receipts. |

So: the model is involved everywhere that meaning is made. Statistics are involved only to make the model's attention earned.

---

## 5. Digging in: questions as hypothesis tests

The formulation improves fastest by asking the right thing, and the user gets the therapeutic benefit of answering it. Three mechanisms, all from the CBT / MI literature, each mapped to a Spilr surface.

**Guided discovery (Padesky 1993): informational question → listening → summarising → synthesising question.** In Daily Chat CBT mode, this is the turn structure — but the *synthesising* question is now supplied by the Person Model: it is the question that would confirm or reject the top open hypothesis. Example: hypothesis "approvals = autonomy frustration". Synthesising question: "If the launch went out with nobody's sign-off, what would be different — the result, or how it felt to send it?"

**Downward (vertical) arrow (Burns 1980; Beck et al. 1979): "and if that were true, what would that mean about you?"** Used at most once per session, only on a thought the user has written ≥ 2 times, only in chat (never on a card), and stopped the moment the user produces a rule ("then I'd be the person who…"). The rule is written to the model as `maybe`.

**MI evocation (Miller & Rollnick): ask for the two wants, never argue for one.** For say/do gaps: "You've written both — rest, and having something to show. Say more about the second one." Change talk is recorded as evidence for `values`.

**Mirror Seeds become tests.** Tomorrow's seed is generated from `openHypotheses[0]` (Prompt Q): "You wrote 'lucky' three times, each on a night nothing got built. Tonight: was there anything you *didn't* do today?" Answerable in 90 seconds; scores the hypothesis either way; the user experiences it as an unusually well-aimed prompt. This is Rosebud's personalised-prompt feature with a reason behind each prompt.

---

## 6. The prompts

Four new prompts. All run server-side per `engineering-decisions` §1, all get `safetyRules`, `LifeContext`, `StylePreferences`, and the `doNotInfer` guard. Temperatures: F 0.3, Q 0.5, M 0.4, ASK 0.2. Structured output via `responseSchema`.

### Prompt F — Formulation (nightly, when ≥ 3 new analyses)

```
You are building a working model of one person from their own journal, the
way a CBT therapist builds a case formulation: as HYPOTHESES to be tested
with them, never verdicts. You will be given (1) extracted signals from
their recent entries with verbatim quotes and dates, (2) candidate
contingencies that statistics found in those signals, (3) the current
model with the user's confirmations and corrections, (4) their life
context.

Produce an UPDATE to the model. Rules:

SIGNATURES (the core unit). Write personality as if-then:
  "When [situation, their words], they [move, their words]; not when
   [exception]." A signature needs ≥ 3 entries and at least one
   contrasting entry or it is not a signature — return it under
   open_hypotheses with the question that would test it.
  Prefer signatures that cross contexts the person keeps separate (work
  and a relationship; body and a decision). Those are the ones they
  cannot see from inside.

UNSTATED BECAUSE. For each candidate contingency, check whether any
  entry links the two terms causally in the person's own words. If none
  does, this is high value: say so explicitly in `why_they_might_not_see_it`.

RULES. Infer conditional beliefs ("if…then…") only from a thought
  quoted ≥ 2 times. Confidence ≤ "maybe". Phrase as the person would.

NEEDS. Classify each frustration event as autonomy / competence /
  relatedness with the quote. Report the distribution; name it only if
  lopsided (≥ 70% one need).

STRENGTHS. Every exception is evidence of a capacity. Name the capacity.

USER CORRECTIONS OUTRANK YOUR INFERENCE. A hypothesis the user marked
  "not me" is retired unless three new entries contradict them; then it
  returns as a question, not a claim.

NEVER: diagnose; infer childhood, trauma, attachment, disorder; use
  clinical or pop-psychology labels; describe a trait without its
  situation ("they are avoidant"); claim more than the quotes support.

Return JSON:
{
 "signatures": [{ "if": "", "then": "", "not_when": "", "contexts": [],
                  "evidence": [{entryId, quote, date}], "contrast": [...],
                  "confidence": "hunch|maybe|likely", "cross_context": bool }],
 "rules": [{ "rule": "if … then …", "from_thoughts": [quotes],
             "confidence": "hunch|maybe" }],
 "needs": { "autonomy": {"frustration": [quotes], "satisfaction": [quotes]},
            "competence": {...}, "relatedness": {...},
            "read": "one sentence or null" },
 "maintenance_loops": [{ "move": "", "relief": "", "cost": "", "evidence": [] }],
 "distortions": [{ "plain_name": "", "quote": "", "entryId": "" }],
 "people": [{ "name": "", "role_they_take": "", "move": "", "exception": "" }],
 "strengths": [{ "capacity": "", "shown_when": "", "evidence": [] }],
 "open_hypotheses": [{ "hypothesis": "", "would_confirm": "", "would_reject": "",
                       "test_question": "", "value": 0-1 }],
 "retire": [hypothesisIds]
}
```

Worked example (input abbreviated to the signals your current Mirror already extracted):

```
SIGNALS: job change (LifeContext: "between things"); moves: "engineering
puzzle/project" ×6 entries on days tagged "empty hours"; emotions:
"heavy sadness" ×3 on low-energy days; "lucky and loved" ×3, all
evenings, all entries with no project; "fairness"/"justice" vs "cost
of a fight"/"rest" ×2 with Dan; body: "physical momentum" bypassing
"heavy questions" ×1; exceptions: "let the heavy day land" ×2, "being
held" ×1.
CANDIDATES: project ↔ empty-hours lift 4.1 (n 6/2); heavy ↔ job-mention
lift 3.0 (n 3/1), attribution: none; lucky ↔ no-project (n 3/0);
fairness-ledger ↔ Dan (n 2).

OUTPUT (excerpt):
signatures[0]: { if: "time opens up with nothing decided (a free
  Saturday, the gap between jobs)", then: "they turn it into a build —
  a project with steps and a finish", not_when: "someone is physically
  close ('being held'); the two 'lucky and loved' evenings",
  contexts: ["work","home"], cross_context: true, confidence: "likely" }
signatures[1]: { if: "Dan reopens a fairness question", then: "they run
  a ledger — who owes what — and weigh 'a fight versus rest'",
  not_when: "(no contrast yet)", confidence: "hunch" → open_hypotheses }
needs.read: "Frustration entries are 5/5 autonomy-shaped (deciding
  alone, not being routed); none are about competence."
rules[0]: { rule: "if I haven't produced something today, then the rest
  doesn't count", from_thoughts: ["whatever, I shipped the thing",
  "a productive night at least"], confidence: "maybe" }
open_hypotheses[0]: { hypothesis: "the projects and the fairness ledger
  are the same move — making an uncertain thing feel worked-on",
  would_confirm: "a Dan entry that ends with a plan/list", would_reject:
  "a Dan entry that ends with a feeling and no plan", test_question:
  "When Dan brings it up, what do you reach for first — a feeling, or
  a list?", value: 0.8 }
strengths[0]: { capacity: "can let a heavy day land without fixing it",
  shown_when: "physically close to someone", evidence: [...] }
```

### Prompt Q — Next question (daily; feeds Mirror Seeds and chat)

```
Pick ONE question for tomorrow's journal from the model's open
hypotheses. Choose the hypothesis with the highest value that has not
been asked about in 7 days. The question must:
- be answerable from one ordinary day in ≤ 90 seconds;
- discriminate: an honest answer should make the hypothesis more or
  less likely (state which answers do which, in `scoring`);
- be a question the person can answer from experience, not a request
  for self-analysis ("what's the pattern?" is banned);
- name something concrete from their entries (a word they used, a
  person, a time), never the hypothesis itself;
- never be a leading question toward the answer you expect.
Style: plain, warm, one sentence. Return { question, hypothesisId,
scoring: {confirms_if, rejects_if}, seed_label (≤ 3 words) }.

BAD: "Do you use projects to avoid uncertainty?"     ← names the hypothesis
BAD: "What patterns do you notice in your free time?" ← asks for analysis
GOOD: "You wrote 'lucky' three times this week, all on nights nothing
       got built. Tonight: what did you not do today?"
```

### Prompt M — The Mirror line (daily, one)

```
Write today's Mirror: ONE claim about this person, in one of four shapes,
from the item the gate selected. You will be given the item (a signature,
an unstated-because contingency, a say/do gap, or an exception), its
quotes with dates, and its test question.

Shape rules:
 SIGNATURE   "When X, you Y. Not when Z." — must include the exception or
             the second context; otherwise it is a paraphrase.
 BECAUSE     name the two things and say plainly that they have never
             written the link ("You've written 'heavy' as weather.").
 SAY/DO      hold both wants as legitimate; end with the MI question
             ("Which one is older?"), never with advice.
 EXCEPTION   the day it didn't hold, what was different, and what that
             suggests the pattern is FOR.

Form: ≤ 45 words. Second person is REQUIRED — this is about them. One
verbatim phrase from a quote. No trait nouns without a situation. No
clinical or pop-psych words. One hedge at most. End with the test
question or with the exception — never on the cost.

Return { line, shape, receipt: {quote, date}, question }.
```

### Prompt ASK — Questions about the user

```
Answer the person's question about themselves FROM THE MODEL, not from
raw entries. Cite the signature/rule/need you used and give up to three
receipts (quote + date). If the model has no relevant, evidenced item,
say exactly that and offer the question that would let the journal
find out. Never generalise beyond the receipts. ≤ 120 words.

User: "Why do I always end up doing everything on the team?"
Answer: "The entries don't show 'always' — they show a signature: when
a task is unowned, you take it (4 of 4 times since August: 'someone
had to', 'easier than chasing'). The one time you didn't — 12 Aug,
the launch checklist — you'd asked Priya directly first. So it may be
less about doing everything and more about what happens before you
ask. What would it take to ask first, next time?"
```

---

## 7. The gate and the lint (code)

The gate decides what may reach Prompt M; the lint decides whether M's output ships.

**Gate.** A signature needs ≥ 3 entries + ≥ 1 contrast; a `because` needs lift ≥ 2 and zero causal attribution; a say/do gap needs ≥ 2 occurrences of each side; an exception needs its parent to be gated. Confidence band from `(timesSeen, ceVerdict, userStatus)` only — never from a model number. `doNotInfer` and the crisis gate are hard. Ranking: exception ≥ because > signature (cross-context) > say/do > signature (single context); 14-day novelty penalty on Jaccard > 0.5.

**Lint.** ≤ 45 words; contains a quote from the receipt; ≤ 1 hedge; Flesch-Kincaid ≤ 8; metaphor list; banned clinical/pop-psych list; **trait-without-situation** regex (`you('re| are) (a|an|so|very|someone)`, `you always`, `you never`) — note second person itself is *required*; the regex catches the label form, not the pronoun. Last clause must be a question or an exception. Fail → show the previous confirmed signature with a fresh receipt, or silence with the day's seed.

---

## 8. What is on the Mirror tab

```
Mirror
─────────────────────────────────────────────
TODAY
  When the future goes blank, you build something. It's
  the same move on a free Saturday and in the fairness
  ledger with Dan — a project makes an uncertain thing
  feel worked-on. Not on the 'lucky and loved' nights.
  ┌ "honestly just lucky and loved tonight" · Tue
  When Dan brings it up, what do you reach for first —
  a feeling, or a list?                    [Answer tonight]
  [That's me]  [Not quite]  more…

WHAT SPILR THINKS IT KNOWS                  (the model, 3–5 rows max)
  When time opens up → you build         likely · 6 entries · not when held
  If nothing shipped, rest doesn't count maybe · from 2 thoughts   [?]
  Work frustration = autonomy, not skill likely · 5 of 5
  With Dan → the ledger                  hunch · testing tonight

WHAT IT DOESN'T KNOW YET                    (1–2 open questions, tappable)
  Whether the ledger with Dan is the same move as the projects.

Ask Spilr about yourself ›
```

Gone: Patterns list, counts strip, labels, lifecycle chips, "hunch/not checked" captions, four-button rows, maturity ring. Confidence appears as a word next to each model row because collaborative empiricism requires the user to see how sure the app is — but it is one word, once.

Two taps remain. "Not quite" → three chips: *Wrong* (retire), *Half* (weaken + ask what's missing, one line), *Too much* (`StylePreferences.sharpness −1`). "That's me" is the strongest evidence the model can get and is weighted above any inference.

**Weekly letter** (Sunday): what the model learned this week, what it dropped, the one question it is carrying — ≤ 80 words. **Your first seven**: the first signature *if one exists*, the needs read *if lopsided*, one question. Otherwise: "Seven entries in. Two things Spilr is watching, nothing it's sure of yet — the next question is the one that decides."

---

## 9. What your own Mirror should have said

From the signals the current engine already extracted for your account — before / after:

| Now | v3.1 |
|---|---|
| "translating empty hours into engineering problems" (×6, all "seen 1×") | When the future goes blank, you build something. Same move on a free Saturday and in the fairness ledger with Dan. Not on the 'lucky and loved' nights. |
| "letting the heavy mood land without fixing it" (labelled "Rule you may carry") | Tuesday was the one heavy day that didn't become a project. You'd written 'being held' an hour before. |
| "weighing the ledger of fairness against quietude" | With Dan, fairness turns into arithmetic — who owes what, 'a fight versus rest'. Is the list what you want, or what you reach for? |
| "Keeps the nervous system revved up when it might need stillness." | *(not shown — clinical phrasing, and a cost with no exception)* |
| "Your question for the next 7 days: translating empty hours into engineering problems?" | You wrote 'lucky' three times this week, all on nights nothing got built. Tonight: what did you not do today? |
| "Sprouting" | Two things Spilr is watching. One question decides the third. |

Every line on the right could be wrong about you — which is why it is on the right.

---

## 10. Metrics that measure deduction, not decoration

- **"Didn't know that" rate**: add a third reaction on Today — *Huh* (new to me) — alongside That's-me / Not-quite. Target: ≥ 25% of shown lines. This is the mind-blowing metric.
- **Question answer rate**: seeds generated by Prompt Q vs. entries written against them; target ≥ 40%.
- **Hypothesis resolution**: open hypotheses confirmed or rejected within 14 days; target ≥ 50%.
- **Model stability**: signatures confirmed by user that survive 30 days; retirement rate of "Not quite" items.
- **Ask usage and receipt taps.**
- **Not-quite → Wrong rate** by shape (which shapes the model gets wrong).

---

## 11. Changes to the previous PRD

- §2 R4 replaced by CAPS + Kluger & DeNisi: second person required; trait-without-situation banned.
- §4 Tier 1 "Observations" demoted from a surface to an *internal* candidate generator; §5.3 "This week, in your words" removed.
- §4 Tier 3 "Threads" replaced by the Person Model (§3 here); §5.6 profile sections replaced by its levels.
- §5.2 Today: four shapes, second person, question attached.
- Prompts F, Q, M, ASK added; Prompt D (mirror-write-v2) retired.
- Metrics: add *Huh*.
- Everything in §1 (bugs), §6 (lint mechanism), §7 (unlock ladder), §8 (pipeline order) and §11 (sequence) stands, with the pipeline's Formulation step now Prompt F.

---

## Sources

Mischel & Shoda (1995) *Psychological Review* 102(2) — https://psychology.columbia.edu/sites/default/files/2016-11/246.pdf · Shoda, Mischel & Wright (1994) *JPSP* 67(4) — https://pubmed.ncbi.nlm.nih.gov/7965613/
Vazire (2010) *JPSP* 98(2) — https://www.simine.com/docs/Vazire_JPSP_2010.pdf · Bollich, Johannet & Vazire (2011) *Frontiers in Psychology* 2:312 — https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2011.00312/full
Nisbett & Wilson (1977) *Psychological Review* 84(3) — https://eric.ed.gov/?id=EJ163657
Kuyken, Padesky & Dudley (2009) *Collaborative Case Conceptualization*, Guilford; (2008) *Behav. Cogn. Psychother.* 36(1) — https://www.padesky.com/wp-content/uploads/2023/07/Science-and-Practice-of-Case-Conceptualization-padesky-web.pdf · Padesky & Mooney (1990) five-part model, *Int. Cognitive Therapy Newsletter* 6
J. Beck (2020) *Cognitive Behavior Therapy: Basics and Beyond*, 3rd ed., Guilford · Burns (1980) *Feeling Good* (vertical/downward arrow; cf. Beck et al. 1979) — https://www.commonlanguagepsychotherapy.org/assets/accepted_procedures/downward.pdf · Persons (2008) *The Case Formulation Approach to CBT*, Guilford
Vansteenkiste & Ryan (2013) *J. Psychotherapy Integration* 23(3) — https://selfdeterminationtheory.org/wp-content/uploads/2014/07/2013_VansteenkisteRyan_JOPI2.pdf · Chen et al. (2015) *Motivation and Emotion* 39(2) — https://link.springer.com/article/10.1007/s11031-014-9450-1
Forer (1949) *J. Abnormal & Social Psych.* 44(1) · Dickson & Kelly (1985) *Psychological Reports* 57(2) — https://journals.sagepub.com/doi/abs/10.2466/pr0.1985.57.2.367
Kluger & DeNisi (1996) *Psychological Bulletin* 119(2)
Topolinski & Reber (2010) *Current Directions in Psych. Science* 19(6) — https://journals.sagepub.com/doi/10.1177/0963721410388803
Miller & Rollnick (2013/2023) *Motivational Interviewing*, Guilford
Padesky (1993) Socratic questioning — https://padesky.com/wp-content/uploads/2012/11/socquest.pdf
Pennebaker, Mayne & Francis (1997) *JPSP* 72(4) · Pennebaker & Seagal (1999) *J. Clin. Psych.* 55(10) — https://pubmed.ncbi.nlm.nih.gov/11045774/ · Campbell & Pennebaker (2003) *Psych. Science* 14(1) (LSA, not LIWC)
Youyou, Kosinski & Stillwell (2015) *PNAS* 112(4) — https://www.pnas.org/doi/10.1073/pnas.1418680112 · Peters & Matz (2024) *PNAS Nexus* 3(6) — https://academic.oup.com/pnasnexus/article/3/6/pgae231/7692212
Spilr: `mirror-v3-prd-2026-09-10.md`, `engineering-decisions-ai-architecture-2026-09-09.md`, the 9 Sept screenshots.
