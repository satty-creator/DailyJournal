# Mirror v3.1 — the Person Model

**For:** Satakshi · Spilr (ninety) · 10 September 2026 · Rev. B — language pass
**Status:** replaces §§2–5 of `mirror-v3-prd-2026-09-10.md`. Keeps its bug list (§1), its pipeline shape (§8), its lint idea (§6) and its sequence — but changes what the pipeline is *for* and what goes on the screen.
**Stance:** AI product strategy + prompt engineering + CBT formulation + language spec. Every psychological claim below was checked against the original paper; the paraphrase used is the accurate one. Three findings the first draft leaned on turned out to be a failed or contested replication and were replaced — see Sources.

> **Rev B changelog (this pass, over Rev A):** added §2, the language spec — a worked before/after, the seven ways a line goes wrong, and the word-level rules. Dropped Flesch-Kincaid from the lint in favour of length caps, a Brysbaert concreteness floor, a one-image rule, and the swap/contradiction tests. Retimed Prompt M to temperature 0.3 (from 0.4) and retightened its line to ≤ 40 words / ≤ 3 sentences / ≤ 18 words per sentence (from ≤ 45 words). Prompt M now returns `would_be_false_if`, and a null value is a hard lint fail. Every example line in the document — including the four shapes, the Mirror-tab mock, and the before/after table — was rewritten against §2; the Rev A draft's own demonstration line ("When the future goes blank…") is now the worked example of the failure it was meant to fix.

---

## 0. What I got wrong, and the corrected principles

Four critiques, all correct. The fourth arrived after the first draft of this document and is the reason for §2.

**"Data shouldn't be a number."** I read Forer as "be checkable" and turned that into arithmetic. The actual lesson of the Barnum literature (Forer 1949; Dickson & Kelly 1985) is that people accept statements that are *favourable, general, and framed as personal*. The antidote is not a count. It is a statement that **could have been false about this person and wasn't** — a claim with content. "You like the work; what wears you down is needing three people to say yes" is Barnum-proof because a different person would get a different sentence, not because it has a "3" in it. The number is a receipt, not the insight.

**"Why not deduce personality?"** Because I over-applied self-distancing (Kross & Ayduk). That research is about the *user's* vantage point on their own experience — it says nothing against the app having a view of the person. Worse, "on the days you wrote…" is exactly the flat, un-falsifiable register that produces "so?". A mirror that refuses to say what it sees is not a mirror. The correct constraint comes from a different literature: Mischel & Shoda's CAPS model (1995) — personality is best described not as trait averages but as stable **if-then signatures**: *when* teased by a peer, aggressive; *when* warned by an adult, compliant. Signatures are claims about the person. They are also the thing a journal can see and its author cannot.

**"What does 'the model is not involved' mean?"** I put the wrong layer on the screen. Statistics should decide *where to look*; the model should decide *what it means*; code should decide *whether it is safe to say*. The previous PRD displayed the where-to-look layer. Nobody pays for that.

**"Make the language accurate and simple, not vague or romanticised."** The line I wrote to demonstrate the fix — *"When the future goes blank, you build something"* — repeats the failure it was meant to correct. *The future goes blank* is my image, not hers; her entries say "a Saturday with nothing in it". *You build something* is a category, not an action; the entries say she started a project. And neither half can be marked **Not quite**, because it is not clear what would count as wrong. A sentence that cannot be contradicted is a Barnum sentence with better prose. §2 is the spec that stops this, and every example line in this document has been rewritten against it.

Corrected principles:

1. **The product is a working model of the person** — a CBT case formulation (Persons 2008; Kuyken, Padesky & Dudley 2009) held as hypotheses, tested against entries, corrected by the user.
2. **Say what you see, in if-then form.** Claims about the person are the point. What is banned is the trait label without a situation ("you're conflict-avoidant") and the clinical label. What is required is the signature ("with Dan you go quiet; with Priya you over-explain — same trigger, two moves").
3. **An insight is something the user could not have written themselves.** Operationally: a contingency in their data they have never stated as a *because*; a mechanism shared by two areas of life they keep separate; a gap between what they say and what they do; or an exception that reveals the mechanism.
4. **Every claim is falsifiable and carries its test.** The Mirror says what would change its mind, and asks the question that would.
5. **The questions are the product too.** The next journaling prompt is chosen to test the formulation's most valuable open hypothesis — and to help the user untangle it (guided discovery, downward arrow, MI). Data collection and therapy are the same act.
6. **The words are hers, not ours.** Every noun in a Mirror line names something that happened — a day, a person, a list, a project — and the app's own vocabulary is kept to the minimum needed to join them. Not for style: an app that phrases her life better than she does gets copied into the next entry, and then it is reading itself (§2).

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

## 2. The language spec: how a line is worded

The four shapes in §3 decide *what* the Mirror is allowed to claim. This section decides *how the sentence is built*, because the same true claim can be shipped as a checkable observation or as a small poem, and the small poem is worse in ways that are measurable rather than aesthetic.

**Worked example — same signals, same shape, same evidence.**

> **Draft (45 words):** "When the future goes blank, you build something. It's the same move on a free Saturday and in the fairness ledger with Dan — a project makes an uncertain thing feel worked-on. Not on the 'lucky and loved' nights."
> — *"the future goes blank"* is our image; she wrote "a Saturday with nothing in it". Nothing here can be marked *Not quite*. — *"you build something"* is a category, not an action; would be true of half the userbase. — *"makes an uncertain thing feel worked-on"* is a mechanism the entries do not contain, stated as fact. — *"the fairness ledger"* is the app's coinage for a hunch that has two entries and no contrast.
> Reads well · says four things it cannot evidence.

> **Shipped (24 words):** "An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'."
> Receipt: *"honestly just lucky and loved tonight"* (Tue 22:14).
> — *"an empty day"* is one image, and it saves words rather than adding them; her phrase, near enough that she would say it back. — *"turns into a project"* is an action a camera would catch; she can name the six. — *"six of six"* is the count, which is the receipt, not the insight. — the exception comes last, which is where the next question comes from.
> Every clause is something she can contradict.

The left-hand version is the one this document shipped in its first draft; four of its clauses assert things no entry supports, and none of them can be marked wrong.

### What the evidence actually supports

The intuitive argument for plain language — *simple sentences are believed more* — does not survive checking. The two studies usually cited for it are a failed preregistered replication (Hansen & Wänke 2010's concreteness-and-truth effect, *d* = .48, replicated at *d<sub>z</sub>* = .08–.11, non-significant, by Henderson, Vallée-Tourangeau & Simons 2019) and a one-tailed near-null (Reber & Schwarz 1999, 8.36 vs 8.09 items out of 16). Plainness is not a persuasion device, and it would be a bad reason anyway: we do not want the user to believe the line, we want them to *check* it. Five findings that do hold up:

- **Concrete words are how "you were listened to" gets transmitted.** Packard & Berger (2021, *JCR*): in 185 recorded service calls, one standard deviation more linguistic concreteness predicted 8.9% higher satisfaction; in 940 service emails, about $10 more customer spending over the following 90 days ($32.73 → $42.80, a 30% lift; 13% in the more conservative specification); three experiments (*n* = 206, 481, 415) reproduced it with *perceived listening* as the mediator and a linear dose–response across six concreteness levels. This is the single best-supported result available to this product, and it is exactly its job.
- **Concrete words are the ones that survive to tomorrow.** Concreteness effect in free recall, η²<sub>p</sub> = .63 (Carbajal et al. 2019), with the "context availability" alternative explanation ruled out. A line the user can repeat back a day later is a line they can test; a line they can only half-remember the mood of is not.
- **Our phrasing overwrites theirs.** DiaryMate (Kim, Shin, Kim & Hong, CHI 2024): 24 people, 10-day field deployment of an LLM journaling aid. The authors report participants "over-relying on the LLM, often prioritizing its emotional expressions over their own." P10, comparing his DiaryMate entries with his ordinary ones: *"It seems like it's someone else's story."* P15: *"Before I started writing my journal, I had thoughts and emotions. But after I read some suggestions from AI, I forgot my feelings and followed what AI said."* For Spilr this is not a style risk, it is a data-integrity risk: the Mirror's input is the user's unaided description of her life, and every well-turned phrase we hand her contaminates the next entry.
- **A metaphor does not mean the same thing at both ends.** Malkomsen et al. (2022, *BMC Psychiatry*, 10 therapists) found therapists and patients diverging on what a *shared* metaphor meant — "tools" meant "quick fix" to one and "accepting myself" to the other — and most therapists neither listened for metaphors nor corrected unhelpful ones. (The stronger claim, that metaphor covertly steers reasoning, is contested: Thibodeau & Boroditsky 2011/2013 found 18–22 point shifts from a single word; Steen et al. 2014, with a proper non-metaphorical control and up to 1,026 participants, found no framing effect. We do not need it.) Divergence is enough: if "the future goes blank" means one thing to the model and another to the reader, the *That's me* tap carries no information.
- **Overshooting an interpretation is asymmetrically expensive.** MI's own coding manual (MITI 4.2.1) defines the distinction the fourth critique is pointing at: a *simple* reflection "adds little or no meaning"; a *complex* one "adds substantial meaning or emphasis". Magill et al. (2014, *JCCP*, 12 studies, *N* = 1,004) found MI-inconsistent moves predicted more sustain talk (*r* = .07, *p* = .009) and less change talk (*r* = −.17, *p* = .001), and that sustain talk predicted worse outcomes (*r* = −.24, *p* = .001) while change talk did *not* predict better ones (*r* = .06, n.s.). Getting the reflection wrong costs more than getting it right gains. MITI's own tie-break rule when a coder cannot decide: code it simple. Mirror's default is the same.

Three more findings set the register:

- **The user will not catch us being wrong.** Wang et al. (2024, preprint): people shown deliberately *inaccurate* AI inferences about their personality mostly did not reject them — 2 of 10 interviewees rated them "not accurate at all" — and instead searched their own lives for evidence to validate implausible claims. Accuracy is our responsibility, not theirs, which is why every line must name something they can go and check.
- **Hedge impersonally or not at all.** Kim et al. (2024, *FAccT*, *N* = 404): first-person hedges ("I'm not sure, but…") cut agreement from 80.9% to 74.8%, confidence from 3.95 to 3.66, and *willingness to use the system* from 3.25 to 2.91, while raising task accuracy from 63.9% to 72.8%. Impersonal hedges ("it's not clear, but…") moved trust intentions not at all. So "this looks like…" is free; "I might be reading too much into this…" is paid for twice.
- **Don't spend the line on advice, and don't spend it on flourish.** Yin, Jia & Wakslak (2024, *PNAS*, *N* = 455): AI-written responses made people feel *more* heard than human ones (5.74 vs 5.17 on 7), because they offered emotional support (5.76 vs 4.64) and fewer practical suggestions (3.28 vs 4.31); support predicted feeling heard, suggestions did not. An AI label on its own cost 0.68 points. Mirror pays that label tax on every card, so there is no budget left for decoration.

**And the Barnum correction that changes the design.** The received story — *vague statements get accepted* — is only half of it. Snyder (1974, *N* = 63) gave every participant the *identical* horoscope and varied only how personally derived it appeared: accuracy ratings ran 3.24 ("generally true of people") → 3.76 (birth year and month) → 4.38 (year, month and day), *F*(2,60) = 7.56, *p* < .0002. Receipts, counts and dates are that same apparatus. Spilr's evidence drawer therefore sits on the risk side of the ledger, not the defence side — it makes a generic line *more* acceptable, not less. The only real defence is the one Dickson & Kelly (1985) identify: people reject specific false statements ("you have two eyes, one brown and one grey") and cannot evaluate general ones at all. *Make the line specific enough to be wrong.* (Housekeeping: Forer's 39 students rated the fake sketch **4.26**, computed from his Table 1 — the familiar "4.30" conflates the sketch with the ratings of the test itself, 4.31.)

### The seven ways a line goes wrong

Every one of these is taken from a line this project has actually shipped or drafted.

| Failure | Shipped / drafted | Why it fails | Fix |
|---|---|---|---|
| **Image instead of situation** | "When the future goes blank…" | The image is ours. There is no state of the world that contradicts it, so *Not quite* is unavailable. | "On a day with nothing in it…" |
| **Category instead of action** | "you build something"; "translating empty hours into engineering problems" | Survives the swap test — true of thousands of other users. Barnum by construction. | "you start a project" |
| **Unearned *because*** | "a project makes an uncertain thing feel worked-on" | States a mechanism no entry contains, as fact. This is the overshoot MITI codes as complex and Magill prices at *r* = −.24. | Cut it, or convert it into the test question: "Is the project instead of deciding, or while you decide?" |
| **Clinical noun** | "Keeps the nervous system revved up when it might need stillness." | Therapy-speak; and it points at the self rather than the situation, which is where feedback stops working (Kluger & DeNisi 1996). | "You wrote 'wired' after four of the six." |
| **Flourish where the question goes** | "The tell is…"; "it arrives on a schedule" | Spends the last clause — the one the reader keeps — on the writer's cleverness instead of on what would settle it. | End on the exception or the question. Always. |
| **Reassurance** | "Neither is wrong." | The sycophancy failure: its function is to make the reader feel good, not to tell them anything. Positive messages read as dismissive when they overgeneralise or command, an effect carried by the reader's sense that the negative was ignored (Wong, Wan & Lew 2025). | Delete. The MI question already holds both wants as legitimate. |
| **First-person hedge** | "I might be reading too much into this, but…" | Costs agreement, confidence *and* willingness to use the app; the impersonal form costs none of it (Kim et al. 2024). | "This looks like…" — or, better, state it flat and let the tap disagree. |

### The word-level rules

**Write:**
- The **situation** as it appeared in the diary. *"a Saturday with nothing in it", not "when the future goes blank".*
- The **move** as something a camera would catch. *"you start a project", not "you build something".*
- The **count**, when the count is the evidence. *"six of six since the job ended".*
- The **exception**, in their words, last. *"not the two nights you wrote 'lucky and loved'".*
- Their nouns for people, feelings and places. Ours only where they have none — and then the plainest one available.
- **One image per line, and only if it replaces words.** "An empty day" earns its place because the literal version is longer. "The fairness ledger" does not, because it is the same length as "the list of who did more" and is ours.

**Never:**
- A noun that names a category rather than a thing: *pattern, loop, dynamic, tendency, capacity, energy, space, journey, nervous system, bandwidth*.
- A feeling they did not name.
- A *because* the entries do not contain. Co-occurrence is not cause; the question is where the cause goes.
- Clinical or pop-psych vocabulary, including the softened kind: *regulate, hold space, sit with, unpack, process, protective, avoidant, attachment*.
- A compliment, a reassurance, or advice.
- "I think", "I wonder", "I might be wrong".
- Any sentence that would still be true if it appeared on a different user's Mirror.

**Two tests before shipping, both cheap.** The *swap test*: paste the line into another user's account. If it still reads as true, it is Barnum — kill it. The *contradiction test*: name the entry that would have made the line false. If you cannot, the line is not a claim and the *Not quite* button is decorative. Both are enforced in code (§8).

---

## 3. What "mind-blowing" is, operationally: the four insight shapes

A Mirror line is only allowed to be one of these four. Each has a psychological basis, a data test, and a worked example built from the hypotheses the current Mirror generated for your own account (I have not read your entries — the examples are what the *existing* signals could support, phrased against §2).

### Shape 1 — The signature (CAPS)
*Same trigger, different moves by context; or same move across contexts the user keeps separate.*

Test: an `EntryAnalysis.protectiveStrategies` value that co-occurs with ≥ 2 distinct situation types, or two different strategies for the same situation type split by person/domain.

> Your current Mirror: "translating empty hours into engineering problems" (six times).
>
> v3.1: **"An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'."**
>
> *The cross-context half — that the list you make with Dan is the same move — has two entries and no contrast, so it is not in the line. It is tonight's question instead: "When Dan brings it up, do you reach for a feeling first, or a list?"*

### Shape 2 — The unstated because (Nisbett & Wilson; Pennebaker)
*A contingency in the data the user has never written as a causal sentence.*

Test: contingency strength (co-occurrence lift or lag effect, n ≥ 3 with contrast) × (1 − user attribution), where attribution = whether any entry links the two terms with a causal connective ("because", "since", "after", "so"). A strong contingency with zero attribution is the highest-value line in the system. This is the exact operationalisation of "something they wouldn't notice on their own."

> **"All three times you wrote 'heavy', you'd written about the job the same day. You've never put those two in one sentence. Is it the job, or the days the job comes up?"**
>
> *The draft version said 'heavy' arrives "as weather" and "on a schedule". Both are figures of speech doing the work of a claim: neither the weather nor the schedule is in the data, and neither can be marked wrong. What is in the data is 3 of 3, and the absence of a causal connective anywhere near them.*

### Shape 3 — The say/do gap (MI ambivalence; SDT need frustration)
*What the user states they want vs. what the entries show them doing — held as two real wants, not a contradiction to fix.*

Test: a value or stated intention (`valuesPresent`, `openLoops`, template "tomorrow I want to") against a behaviour (`protectiveStrategies`, episodes' outcomes) that runs against it, ≥ 2 occurrences.

> **"Twice this month you wrote that rest was the plan. Both entries end with what you finished instead. So: rest, and having something to show for the day. Which one is harder to give up?"**
>
> *"Neither is wrong" is gone — reassurance is not information, and the MI question already treats both wants as legitimate. "Which one is older?" is gone too: it is a nice sentence and an unanswerable one.*

### Shape 4 — The exception that explains the rule (SFBT; Kuyken's strengths level)
*The day the pattern didn't hold, and what was different — the mechanism read backwards.*

Test: an `exception`-type hypothesis or a contrast day inside a Shape-2 contingency, with at least one distinctive feature (person present, time, body signal, template used).

> **"Tuesday was the one heavy day that didn't turn into a project. An hour earlier you'd written 'being held'. Was anyone around on the other five?"**
>
> *The draft ended "that's the strongest evidence in your journal for what the projects are standing in for" — a verdict, in the position where the question belongs. The question does the same work and can be answered tonight.*

Every one of these could be wrong about you. That is what makes them worth reading — and why each carries a receipt and a question. Note what the four rewrites have in common: they are all *shorter*. The interpretive clauses were the long ones, and they were the ones carrying no evidence.

---

## 4. The Person Model

This is the data structure the Mirror maintains, displays, and asks questions to improve. It replaces the flat `SelfModel` sections with a CBT case formulation in Kuyken's three levels. Every item is a hypothesis with `{confidence, evidenceEntryIds[], counterEvidenceEntryIds[], userStatus, lastTestedAt, testQuestion}`.

**Level 1 — Descriptive (Padesky & Mooney's five-part model, per situation type)**
- `situations[]`: recurring situation types in the user's life, named in their words ("open Saturday", "approvals", "Dan raising it again"). Each links to entries.
- For each situation: typical `thoughts` (automatic, quoted), `emotions` (their words), `bodySignals`, `behaviours` (the move).

**Level 2 — Cross-sectional (triggers and maintenance)**
- `signatures[]`: if-then pairs — `{if: situation, then: move, notWhen: exceptions[], contexts: {work|home|person}}`. The CAPS layer. This is what "Threads" become.
- `rules[]`: intermediate beliefs in conditional form, inferred via the downward arrow from repeated thoughts — "if I rest before something ships, I'm falling behind". Confidence never above `maybe` without user confirmation.
- `maintenanceLoops[]`: the short-term relief a move gives (why it persists) and its cost — the existing `protection`/`cost` fields, kept.
- `needs`: an SDT profile — autonomy / competence / relatedness, each with `satisfactionEvidence[]` and `frustrationEvidence[]`. This is the lens that turns "politics bother you" into "every work complaint in six weeks is about autonomy — approvals, sign-off, being routed — and none is about competence. You don't doubt the work; you mind not owning it." Need frustration, not low satisfaction, is what predicts ill-being (Vansteenkiste & Ryan 2013; Chen et al. 2015), so the model tracks frustration events specifically.
- `distortions[]`: Burns-style thinking patterns *observed in quoted thoughts*, phrased plainly ("treats one late report as the whole week" not "overgeneralisation"), with the quote. Never a diagnosis; a description of a sentence they wrote.
- `people[]`: per-person signature — the role the user takes, the move, the exception.

**Level 3 — Longitudinal**
- `coreBeliefs[]`: reached only by ≥ 3 converging rules and only ever shown as a question ("Is the rule underneath this something like 'I'm only safe when I'm producing'? You'd know."). Hard gate: `doNotInfer` (diagnosis, trauma origin, attachment style, childhood) stays.
- `values[]` (ACT): what the exceptions and the "lucky" entries point at.
- `strengths[]`: what already works — the exceptions, read as competence (Kuyken's strengths principle). Not a consolation section; the mechanism section.
- `trajectory[]`: how a signature has changed over ≥ 30 days.

**Open questions** — `openHypotheses[]` ranked by *value of information*: `confidence uncertainty × emotional weight × actionability`. The top one drives tomorrow's journaling prompt (§6).

**Ask-answerable.** Because the model is structured, "Ask Spilr" becomes a real feature: "What do I do when I'm criticised?" is answered from `signatures` and `people` with receipts, not by re-reading 300 entries.

---

## 5. Who does what: AI, statistics, code

| Step | Who | What it actually does |
|---|---|---|
| Extract signals from each entry | **AI** (Prompt A, exists) | Situations, thoughts, emotions, moves, needs, people, body, quotes. This *is* AI pattern-detection's raw material. |
| Find candidate contingencies | **Code** | Co-occurrence, lag, per-person and per-domain splits over the extracted signals; the `unstated because` score; exception detection. Cheap, exact, and it tells the formulation prompt *where to look* so it can't hallucinate a pattern from one entry. |
| Formulate | **AI** (Prompt F, new — §7) | Turns candidates + quotes into the Person Model: signatures, rules, needs, loops, open questions. This is the deduction. |
| Disconfirm | **AI** (Prompt CE, exists) | "What in the entries makes this untrue?" on every claim before it is shown. |
| Gate | **Code** | n ≥ 3 with contrast for signatures; confidence bands; lint (§8); `doNotInfer`; crisis gate. |
| Express | **AI** (Prompt M, new) | One line in one of the four shapes, with receipt and question. |
| Plan the next question | **AI** (Prompt Q, new) | The journaling prompt / chat move that tests the top open hypothesis. |
| Answer | **AI** (Prompt ASK, new) | Questions about the user, from the model, with receipts. |

So: the model is involved everywhere that meaning is made. Statistics are involved only to make the model's attention earned.

---

## 6. Digging in: questions as hypothesis tests

The formulation improves fastest by asking the right thing, and the user gets the therapeutic benefit of answering it. Three mechanisms, all from the CBT / MI literature, each mapped to a Spilr surface.

**Guided discovery (Padesky 1993): informational question → listening → summarising → synthesising question.** In Daily Chat CBT mode, this is the turn structure — but the *synthesising* question is now supplied by the Person Model: it is the question that would confirm or reject the top open hypothesis. Example: hypothesis "approvals = autonomy frustration". Synthesising question: "If the launch went out with nobody's sign-off, what would be different — the result, or how it felt to send it?"

**Downward (vertical) arrow (Burns 1980; Beck et al. 1979): "and if that were true, what would that mean about you?"** Used at most once per session, only on a thought the user has written ≥ 2 times, only in chat (never on a card), and stopped the moment the user produces a rule ("then I'd be the person who…"). The rule is written to the model as `maybe`.

**MI evocation (Miller & Rollnick): ask for the two wants, never argue for one.** For say/do gaps: "You've written both — rest, and having something to show. Say more about the second one." Change talk is recorded as evidence for `values`.

**Mirror Seeds become tests.** Tomorrow's seed is generated from `openHypotheses[0]` (Prompt Q): "You wrote 'lucky' three times, each on a night nothing got built. Tonight: was there anything you *didn't* do today?" Answerable in 90 seconds; scores the hypothesis either way; the user experiences it as an unusually well-aimed prompt. This is Rosebud's personalised-prompt feature with a reason behind each prompt.

---

## 7. The prompts

Four new prompts. All run server-side per `engineering-decisions` §1, all get `safetyRules`, `LifeContext`, `StylePreferences`, the `doNotInfer` guard, and the §2 word rules — F and M carry them in full, Q and ASK by reference. Temperatures: F 0.3, Q 0.5, M 0.3 (lowered from 0.4 — with §2 in force the variety belongs in which item gets selected, not in how it is phrased), ASK 0.2. Structured output via `responseSchema`.

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

WORDS. Name every situation, move and exception in the person's own
  vocabulary, or in the plainest words that mean the same thing. No
  coinages of your own for their life (no "the fairness ledger") — if
  you need a handle, use the words they used. No category nouns
  (pattern, loop, dynamic, capacity, energy, nervous system). Model
  fields are read by other prompts and shown on screen; a phrase
  invented here becomes a phrase the user reads back to themselves.

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
signatures[0]: { if: "a day with nothing in it (a free Saturday, the
  weeks since the job ended)", then: "they start a project",
  not_when: "someone is there ('being held'); the two 'lucky and
  loved' evenings",
  contexts: ["work","home"], cross_context: true, confidence: "likely" }
signatures[1]: { if: "Dan brings up who did more", then: "they make a
  list of it, and weigh 'a fight versus rest'",
  not_when: "(no contrast yet)", confidence: "hunch" → open_hypotheses }
needs.read: "5 of 5 work complaints are about deciding — approvals,
  sign-off, being routed. None are about the work being hard."
rules[0]: { rule: "if I haven't finished something today, the rest
  doesn't count", from_thoughts: ["whatever, I shipped the thing",
  "a productive night at least"], confidence: "maybe" }
open_hypotheses[0]: { hypothesis: "the projects and the list she makes
  with Dan are the same move",
  would_confirm: "a Dan entry that ends with a plan/list", would_reject:
  "a Dan entry that ends with a feeling and no plan", test_question:
  "When Dan brings it up, do you reach for a feeling first, or a
  list?", value: 0.8 }
strengths[0]: { capacity: "can let a heavy day be heavy",
  shown_when: "someone else is there", evidence: [...] }

Not in this output: "making an uncertain thing feel worked-on", and
"the fairness ledger". Both were in the first draft; neither is in any
entry. The mechanism is a hypothesis, so it lives in open_hypotheses
with the question that settles it — not in a field another prompt will
render on screen as fact.
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
Style: plain, warm, one sentence, ≤ 20 words. The §2 word rules apply:
their nouns, no category nouns, no clinical words, no image that does
not save words. Return { question, hypothesisId,
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
             written the link ("You've never put those two in one
             sentence."). Do not supply the link yourself.
 SAY/DO      hold both wants as legitimate; end with the MI question
             ("Which one is harder to give up?"), never with advice.
 EXCEPTION   the day it didn't hold, and what was different. What it is
             FOR is the question, not the claim.

FORM — hard limits, on the LINE (the question is returned separately
and rendered under it):
 ≤ 40 words, ≤ 3 sentences, ≤ 18 words per sentence. The question is
   its own sentence and ≤ 20 words.
 Second person, present tense, active voice.
 One verbatim phrase from a quote, in single quotes.

WORDS — every one of these is a lint rule (§8):
 Name the SITUATION as it appeared in the entry: "a day with nothing in
   it", never "when the future goes blank".
 Name the MOVE as something a camera would catch: "you start a
   project", never "you build something".
 Every noun names a thing that happened — a day, a person, a list, a
   project. NO category nouns: pattern, loop, dynamic, tendency,
   capacity, energy, space, journey, nervous system, bandwidth.
 NO clinical or pop-psych vocabulary, including the soft kind:
   regulate, hold space, sit with, unpack, process, avoidant,
   protective, attachment.
 ONE image at most, and only if it REPLACES words. If the literal
   version is the same length or shorter, ship the literal version.
 State WHAT happened. Never state WHY. The why goes in the question.
 Hedge impersonally ("this looks like") or not at all. NEVER "I think",
   "I wonder", "I might be wrong" — first-person hedging costs both
   trust and use.
 No compliment, no reassurance ("neither is wrong"), no advice.
 End on the exception or the question — never on the cost.

Then run two checks on your own line before returning it:
 SWAP TEST         Would this sentence be true of a different person
                   with different entries? If yes, return null and let
                   the fallback ship.
 CONTRADICTION     Name the entry that would have made this line false.
                   If you cannot name one, it is not a claim — return
                   null.

Return { line, shape, receipt: {quote, date}, question, would_be_false_if }.

BAD:  "When the future goes blank, you build something — a project makes
       an uncertain thing feel worked-on."
       ← 'the future goes blank' is our image, not hers; 'build
         something' is a category, not an action; the clause after the
         dash is a mechanism no entry contains. Nothing here can be
         marked Not quite.
GOOD: "An empty day turns into a project. Six of six since the job
       ended — and not the two nights you wrote 'lucky and loved'."
```

### Prompt ASK — Questions about the user

```
Answer the person's question about themselves FROM THE MODEL, not from
raw entries. Cite the signature/rule/need you used and give up to three
receipts (quote + date). If the model has no relevant, evidenced item,
say exactly that and offer the question that would let the journal
find out. Never generalise beyond the receipts. ≤ 120 words. Same word
rules as Prompt M, and no internal vocabulary on screen: say what the
entries say, never "your signature" or "this hypothesis".

User: "Why do I always end up doing everything on the team?"
Answer: "The entries don't show 'always'. They show one situation: when
nobody owns a task, you pick it up — 4 times out of 4 since August
('someone had to', 'easier than chasing'). The once you didn't, on
12 Aug with the launch checklist, you'd asked Priya first. So the
difference may be what happens before you ask, not what happens after.
What would it take to ask first, next time?"
```

---

## 8. The gate and the lint (code)

The gate decides what may reach Prompt M; the lint decides whether M's output ships.

**Gate.** A signature needs ≥ 3 entries + ≥ 1 contrast; a `because` needs lift ≥ 2 and zero causal attribution; a say/do gap needs ≥ 2 occurrences of each side; an exception needs its parent to be gated. Confidence band from `(timesSeen, ceVerdict, userStatus)` only — never from a model number. `doNotInfer` and the crisis gate are hard. Ranking: exception ≥ because > signature (cross-context) > say/do > signature (single context); 14-day novelty penalty on Jaccard > 0.5.

**Lint.** Nine checks, all cheap, run on M's output before it can ship. Flesch-Kincaid is *dropped* — on a 3-sentence string it is noise, and it scores "when the future goes blank" as easy reading. The length caps and the concreteness floor do the work it was standing in for.

| # | Check | Rule |
|---|---|---|
| 1 | Length | Line: ≤ 40 words, ≤ 3 sentences, ≤ 18 words per sentence. Question: ≤ 20 words. Counted separately — the question is its own field. |
| 2 | Receipt | Contains a verbatim phrase from the receipt quote. |
| 3 | Concreteness floor | Mean Brysbaert concreteness of content words ≥ 3.0 (scale 1–5, 40k lemmas); no content word below 2.0 unless it is the user's own quoted word. Catches "uncertain thing", "worked-on", "the future". |
| 4 | Banned nouns | Category list (pattern, loop, dynamic, tendency, capacity, energy, space, journey, nervous system, bandwidth) + clinical/pop-psych list (regulate, hold space, sit with, unpack, process, avoidant, protective, attachment). |
| 5 | One image | At most one token flagged figurative and not present in this user's own vocabulary index. Two → fail. |
| 6 | Trait-without-situation | `you('re\| are) (a\|an\|so\|very\|someone)`, `you always`, `you never`. Second person itself is *required*; the regex catches the label form, not the pronoun. |
| 7 | Hedge form | ≤ 1 hedge, and `/\bI (think\|feel\|wonder\|suspect\|might)\b/` → fail. Impersonal hedges pass. |
| 8 | Reassurance | `neither is wrong`, `that's okay`, `nothing wrong with`, `you should`, and the comparative-praise list. |
| 9 | Swap test | Strip quoted phrases, proper nouns and numerals; the remainder must contain ≥ 2 tokens from this user's top-200 entry vocabulary. A line that survives stripping into something universally true is Barnum and fails. |

Last clause must be a question or an exception. `would_be_false_if` must be non-null. Fail → show the previous confirmed signature with a fresh receipt, or silence with the day's seed. Every fail is logged with its rule number: the distribution of lint failures by rule is the fastest read on whether Prompt M is drifting back toward prose.

---

## 9. What is on the Mirror tab

```
Mirror
─────────────────────────────────────────────
TODAY
  An empty day turns into a project. Six of six since
  the job ended — and not the two nights you wrote
  'lucky and loved'.
  ┌ "honestly just lucky and loved tonight" · Tue
  When Dan brings it up, do you reach for a feeling
  first, or a list?                        [Answer tonight]
  [That's me]  [Not quite]  more…

WHAT SPILR THINKS IT KNOWS                  (the model, 3–5 rows max)
  Empty day → you start a project        likely · 6 entries · not when someone's there
  If nothing got finished, rest doesn't count  maybe · from 2 thoughts   [?]
  Work complaints are about deciding     likely · 5 of 5
  With Dan → you make a list             hunch · testing tonight

WHAT IT DOESN'T KNOW YET                    (1–2 open questions, tappable)
  Whether the list you make with Dan is the same move as the projects.

Ask Spilr about yourself ›
```

Gone: Patterns list, counts strip, labels, lifecycle chips, "hunch/not checked" captions, four-button rows, maturity ring. Confidence appears as a word next to each model row because collaborative empiricism requires the user to see how sure the app is — but it is one word, once.

Two taps remain. "Not quite" → three chips: *Wrong* (retire), *Half* (weaken + ask what's missing, one line), *Too much* (`StylePreferences.sharpness −1`). "That's me" is the strongest evidence the model can get and is weighted above any inference.

**Weekly letter** (Sunday): what the model learned this week, what it dropped, the one question it is carrying — ≤ 80 words. **Your first seven**: the first signature *if one exists*, the needs read *if lopsided*, one question. Otherwise: "Seven entries in. Two things Spilr is watching, nothing it's sure of yet — the next question is the one that decides."

---

## 10. What your own Mirror should have said

From the signals the current engine already extracted for your account — before / after:

| Now | v3.1 |
|---|---|
| "translating empty hours into engineering problems" (×6, all "seen 1×") | An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'. |
| "letting the heavy mood land without fixing it" (labelled "Rule you may carry") | Tuesday was the one heavy day that didn't turn into a project. An hour earlier you'd written 'being held'. Was anyone around on the other five? |
| "weighing the ledger of fairness against quietude" | When Dan brings up who did more, you write out who did what. Twice now. Is the list what you want, or what you reach for? |
| "Keeps the nervous system revved up when it might need stillness." | *(not shown — clinical phrasing, and a cost with no exception)* |
| "Your question for the next 7 days: translating empty hours into engineering problems?" | You wrote 'lucky' three times this week, each on a night you didn't start anything. Tonight: what did you not do today? |
| "Sprouting" | Two things Spilr is watching. One question decides the third. |

Every line on the right could be wrong about you — which is why it is on the right. The right-hand column is also shorter than the version this document shipped in its first draft: what got cut was the interpretation, and the interpretation was most of the word count.

---

## 11. Metrics that measure deduction, not decoration

- **"Didn't know that" rate**: add a third reaction on Today — *Huh* (new to me) — alongside That's-me / Not-quite. Target: ≥ 25% of shown lines. This is the mind-blowing metric.
- **Question answer rate**: seeds generated by Prompt Q vs. entries written against them; target ≥ 40%.
- **Hypothesis resolution**: open hypotheses confirmed or rejected within 14 days; target ≥ 50%.
- **Model stability**: signatures confirmed by user that survive 30 days; retirement rate of "Not quite" items.
- **Ask usage and receipt taps.**
- **Not-quite → Wrong rate** by shape (which shapes the model gets wrong).
- **The Barnum canary.** Once a month, on one sampled line the user already reacted to, ask the *uniqueness* question rather than the accuracy one: "Would this have been true of most people?" Dickson & Kelly's review is explicit that people fail to discriminate on accuracy and succeed on uniqueness — so accuracy ratings tell us almost nothing and this tells us a lot. Target ≤ 15% yes. If it rises, the lines have drifted general and the *That's me* rate is worthless.
- **Echo rate** (language health, want it LOW). Share of Mirror lines whose distinctive phrasing reappears in the user's own entries within 7 days. DiaryMate's finding is that people adopt the machine's words for their own experience; if Spilr's vocabulary starts coming back to us as input, the model is reading itself. Target < 10%; a rising echo rate is the signal to tighten §2, not to celebrate resonance.
- **Lint failures by rule number** (§8). Which rule Prompt M keeps hitting is the earliest sign of drift back toward prose.

---

## 12. Changes to the previous PRD

- §2 R4 replaced by CAPS + Kluger & DeNisi: second person required; trait-without-situation banned.
- §4 Tier 1 "Observations" demoted from a surface to an *internal* candidate generator; §5.3 "This week, in your words" removed.
- §4 Tier 3 "Threads" replaced by the Person Model (§4 here); §5.6 profile sections replaced by its levels.
- §5.2 Today: four shapes, second person, question attached.
- **New §2, the language spec** — binding on Prompts F, M, Q and ASK and enforced by nine lint rules (§8). Flesch-Kincaid is dropped in favour of length caps, a Brysbaert concreteness floor, banned-noun lists, a one-image rule, an impersonal-hedge rule and the swap test.
- **Every example line in this document rewritten** against §2, including the four shapes, the phone mock, the Mirror-tab mock and the before/after table. The v3.1 draft's own demonstration line ("When the future goes blank…") is now the worked example of the failure.
- Prompt M returns `would_be_false_if`; a null value is a hard lint fail.
- Prompts F, Q, M, ASK added; Prompt D (mirror-write-v2) retired.
- Metrics: add *Huh*, the monthly Barnum canary (uniqueness, not accuracy), echo rate, and lint-failure distribution.
- Everything in §1 (bugs), §6 (lint mechanism), §7 (unlock ladder), §8 (pipeline order) and §11 (sequence) stands, with the pipeline's Formulation step now Prompt F.

---

## Sources

**Corrections applied while writing §2 — three findings that a first draft would have cited, and should not.**

- **"Concrete language is judged more truthful."** Hansen & Wänke (2010) reported *d* ≈ .48. Henderson, Vallée-Tourangeau & Simons (2019), a preregistered dual-site Registered Report (*n* = 246 and 220), found *d<sub>z</sub>* = .08 [−.03, .18] and .11 [−.01, .22] — both non-significant, both below the minimum detectable effect. The concreteness case in §2 rests on Packard & Berger and on memory instead. — [Collabra 5(1):19](https://online.ucpress.edu/collabra/article/5/1/19/112979/)
- **"Metaphors covertly steer reasoning."** Thibodeau & Boroditsky (2011, 2013) is real and striking; Steen, Reijnierse & Burgers (2014), adding a non-metaphorical control and running up to 1,026 participants, found no framing effect. §2 argues from divergence of meaning, which is not contested, rather than from covert persuasion, which is. — [PLoS ONE 9(12):e113536](https://doi.org/10.1371/journal.pone.0113536)
- **"NIH and CDC recommend a 6th–8th grade reading level."** Neither publishes a grade target; both pages define plain language without a number. **AHRQ** does: 4th–6th grade for consumer materials, against an average adult level of 8th–9th. — [AHRQ Toolkit, Tool 11](https://www.ahrq.gov/health-literacy/improve/precautions/tool11.html)
- **Forer's number.** The familiar "4.30" conflates two rows of his Table 1. The fake sketch was rated **4.26**; the test that supposedly produced it, 4.31. Forer published no means; both are computed from the published distribution.
- **Snyder (1974) is a risk finding, not a supporting one.** He varied the apparent specificity of the *derivation*, not of the content — which is what Spilr's receipts do.

**Language and phrasing (§2).** Packard & Berger (2021) "How Concrete Language Shapes Customer Satisfaction", *J. Consumer Research* 47(5), 787–806 — doi:10.1093/jcr/ucaa038 · Carbajal, Taylor, Francis & Borunda-Vazquez (2019) *Memory & Cognition* 47(1) — doi:10.3758/s13421-018-0857-x · Brysbaert, Warriner & Kuperman (2014) *Behavior Research Methods* 46(3), concreteness norms for 40k lemmas — doi:10.3758/s13428-013-0403-5 · Kim, Shin, Kim & Hong (2024) "DiaryMate: Understanding User Perceptions and Experience in Human-AI Collaboration for Personal Journaling", *CHI '24* — doi:10.1145/3613904.3642693 · Malkomsen et al. (2022) *BMC Psychiatry* 22:433 — doi:10.1186/s12888-022-04083-y · Oppenheimer (2006) *Applied Cognitive Psychology* 20(2) — doi:10.1002/acp.1178 · Sayfi et al. (2024) *J. Clinical Epidemiology* 165:111219 — doi:10.1016/j.jclinepi.2023.11.009 · Wong, Wan & Lew (2025) "Is 'Good vibes only' really good? Investigating perceptions of toxic positivity on social media", *New Media & Society*, OnlineFirst — doi:10.1177/14614448251396941 · Newman, Garry, Bernstein, Kantner & Lindsay (2012) *Psychonomic Bulletin & Review* 19(5), truthiness — doi:10.3758/s13423-012-0292-0

**How people read AI's claims about them (§2).** Yin, Jia & Wakslak (2024) *PNAS* 121(14) — doi:10.1073/pnas.2319112121 · Kim, Liao, Vorvoreanu, Ballard & Wortman Vaughan (2024) *FAccT '24* — doi:10.1145/3630106.3658941 · Wang, Anyi, Das Swain & Goel (2024), arXiv:2405.16355 — *preprint, not peer-reviewed* · Snyder (1974) *J. Clinical Psychology* 30(4) — doi:10.1002/1097-4679(197410)30:4%3C577::AID-JCLP2270300434%3E3.0.CO;2-8

**Reflection calibration (§2, §6).** Moyers, Manuel & Ernst (2015) *MITI 4.2.1 coding manual*, simple vs. complex reflection — motivationalinterviewing.org/sites/default/files/miti4_2.pdf · Magill, Gaume, Apodaca, Walthers, Mastroleo, Borsari & Longabaugh (2014) *J. Consulting & Clinical Psychology* 82(6) — doi:10.1037/a0036833 · *Glossary of MI Terms* (overshooting, amplified reflection, sustain talk, discord) — motivationalinterviewing.org/sites/default/files/glossary_of_mi_terms-1.pdf

**The rest, as before.** Mischel & Shoda (1995) *Psychological Review* 102(2) · Shoda, Mischel & Wright (1994) *JPSP* 67(4) · Vazire (2010) *JPSP* 98(2) · Bollich, Johannet & Vazire (2011) *Frontiers in Psychology* 2:312 · Nisbett & Wilson (1977) *Psychological Review* 84(3) · Kuyken, Padesky & Dudley (2009) *Collaborative Case Conceptualization*, Guilford; (2008) *Behav. Cogn. Psychother.* 36(1) · Padesky & Mooney (1990) five-part model, *Int. Cognitive Therapy Newsletter* 6 · J. Beck (2020) *Cognitive Behavior Therapy: Basics and Beyond*, 3rd ed., Guilford · Burns (1980) *Feeling Good* (vertical/downward arrow; cf. Beck et al. 1979) · Persons (2008) *The Case Formulation Approach to CBT*, Guilford · Vansteenkiste & Ryan (2013) *J. Psychotherapy Integration* 23(3) · Chen et al. (2015) *Motivation and Emotion* 39(2) · Forer (1949) *J. Abnormal & Social Psych.* 44(1) · Dickson & Kelly (1985) *Psychological Reports* 57(2) · Kluger & DeNisi (1996) *Psychological Bulletin* 119(2) · Topolinski & Reber (2010) *Current Directions in Psych. Science* 19(6) · Miller & Rollnick (2013/2023) *Motivational Interviewing*, Guilford · Padesky (1993) Socratic questioning · Pennebaker, Mayne & Francis (1997) *JPSP* 72(4) · Pennebaker & Seagal (1999) *J. Clin. Psych.* 55(10) · Campbell & Pennebaker (2003) *Psych. Science* 14(1) (LSA, not LIWC) · Youyou, Kosinski & Stillwell (2015) *PNAS* 112(4) · Peters & Matz (2024) *PNAS Nexus* 3(6)

Spilr: `mirror-v3-prd-2026-09-10.md`, `engineering-decisions-ai-architecture-2026-09-09.md`, the 9 Sept screenshots.
