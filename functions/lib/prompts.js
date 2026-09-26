/* prompts.js — Prompts F, Q, M, ASK (mirror-v3.1-person-model-2026-09-10.md
 * §7). Pure string builders: no firebase-admin, no network, no access to
 * SAFETY_RULES/SPILR_VOICE directly — index.js supplies those (and
 * styleRulesBlock/lifeContextBlock's rendered output) so this file has
 * exactly one job, matching every other module in lib/: given the inputs,
 * return the exact prompt text, transcribed from the design doc rather than
 * paraphrased.
 *
 * "All four prompts get safetyRules, LifeContext, StylePreferences, the
 * doNotInfer guard, and the §2 word rules — F and M carry them in full, Q
 * and ASK by reference."
 */

"use strict";

const { DO_NOT_INFER } = require("./personModel");

const DO_NOT_INFER_LINE =
  `NEVER infer or state any of: ${DO_NOT_INFER.join(", ")}. This is a hard ` +
  "gate — not a hedge, not a maybe.";

/** Prompt F — Formulation (nightly, when >= 3 new analyses). Temp 0.3. */
function buildFormulationPrompt({
  safetyRules, spilrVoice, lifeContext, styleRules,
  signalsBlock, candidatesBlock, currentModelBlock,
}) {
  return `${safetyRules}

${spilrVoice}
${styleRules || ""}${lifeContext || ""}

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
   [exception]." A signature needs >= 3 entries and at least one
   contrasting entry or it is not a signature — return it under
   open_hypotheses with the question that would test it.
  Prefer signatures that cross contexts the person keeps separate (work
  and a relationship; body and a decision). Those are the ones they
  cannot see from inside.

UNSTATED BECAUSE. For each candidate contingency, check whether any
  entry links the two terms causally in the person's own words. If none
  does, this is high value: say so explicitly in why_they_might_not_see_it.

RULES. Infer conditional beliefs ("if...then...") only from a thought
  quoted >= 2 times. Confidence <= "maybe". Phrase as the person would.

NEEDS. Classify each frustration event as autonomy / competence /
  relatedness with the quote. Report the distribution; name it only if
  lopsided (>= 70% one need).

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

${DO_NOT_INFER_LINE}

NEVER: diagnose; infer childhood, trauma, attachment, disorder; use
  clinical or pop-psychology labels; describe a trait without its
  situation ("they are avoidant"); claim more than the quotes support.

SIGNALS (their recent entries, most recent first):
${signalsBlock}

CANDIDATES (statistics found these in the signals above — you decide what,
if anything, they mean; you may reject any of them):
${candidatesBlock}

CURRENT MODEL (what has already been formulated, with the user's own
confirmations and corrections — outrank your inference where they conflict):
${currentModelBlock}

Return ONLY valid JSON:
{
 "signatures": [{ "if": "", "then": "", "not_when": "", "contexts": [],
                  "evidence": [{"entryId":"", "quote":"", "date":""}],
                  "confidence": "hunch|maybe|likely", "cross_context": false }],
 "rules": [{ "rule": "if ... then ...", "from_thoughts": [""],
             "confidence": "hunch|maybe" }],
 "needs": { "autonomy": {"frustration": [""], "satisfaction": [""]},
            "competence": {"frustration": [""], "satisfaction": [""]},
            "relatedness": {"frustration": [""], "satisfaction": [""]},
            "read": "one sentence or null" },
 "maintenance_loops": [{ "move": "", "relief": "", "cost": "", "evidence": [""] }],
 "distortions": [{ "plain_name": "", "quote": "", "entryId": "" }],
 "people": [{ "name": "", "role_they_take": "", "move": "", "exception": "" }],
 "strengths": [{ "capacity": "", "shown_when": "", "evidence": [""] }],
 "open_hypotheses": [{ "hypothesis": "", "would_confirm": "", "would_reject": "",
                       "test_question": "", "value": 0.5 }],
 "retire": [""]
}`;
}

/** Prompt Q — Next question (daily; feeds Mirror Seeds and chat). Temp 0.5. */
function buildNextQuestionPrompt({ safetyRules, openHypothesesBlock, askedRecentlyBlock }) {
  return `${safetyRules}

Pick ONE question for tomorrow's journal from the model's open
hypotheses. Choose the hypothesis with the highest value that has not
been asked about in 7 days. The question must:
- be answerable from one ordinary day in <= 90 seconds;
- discriminate: an honest answer should make the hypothesis more or
  less likely (state which answers do which, in scoring);
- be a question the person can answer from experience, not a request
  for self-analysis ("what's the pattern?" is banned);
- name something concrete from their entries (a word they used, a
  person, a time), never the hypothesis itself;
- never be a leading question toward the answer you expect.
Style: plain, warm, one sentence, <= 20 words. The word rules apply:
their nouns, no category nouns, no clinical words, no image that does
not save words.

OPEN HYPOTHESES (ranked by value of information):
${openHypothesesBlock}

ALREADY ASKED IN THE LAST 7 DAYS (do not pick these again):
${askedRecentlyBlock || "(none)"}

BAD: "Do you use projects to avoid uncertainty?"     <- names the hypothesis
BAD: "What patterns do you notice in your free time?" <- asks for analysis
GOOD: "You wrote 'lucky' three times this week, all on nights nothing
       got built. Tonight: what did you not do today?"

Return ONLY valid JSON:
{ "question": "", "hypothesisId": "", "scoring": {"confirms_if": "", "rejects_if": ""},
  "seed_label": "" }`;
}

/** Prompt M — The Mirror line (daily, one). Temp 0.3. */
function buildMirrorMPrompt({
  safetyRules, spilrVoice, styleRules, itemBlock, shape, quotesBlock, testQuestion,
}) {
  return `${safetyRules}

${spilrVoice}
${styleRules || ""}

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
 <= 40 words, <= 3 sentences, <= 18 words per sentence. The question is
   its own sentence and <= 20 words.
 Second person, present tense, active voice.
 One verbatim phrase from a quote, in single quotes.

WORDS — every one of these is a lint rule:
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

THE ITEM (shape: ${shape}):
${itemBlock}

QUOTES (dated, verbatim):
${quotesBlock}

THE TEST QUESTION THIS ITEM ALREADY CARRIES (use it, or write a sharper
one that tests the same thing):
${testQuestion || "(none supplied — write one)"}

Return ONLY valid JSON:
{ "line": "", "shape": "${shape}",
  "receipt": {"quote": "", "date": ""},
  "question": "" }

BAD:  "When the future goes blank, you build something — a project makes
       an uncertain thing feel worked-on."
       <- 'the future goes blank' is our image, not hers; 'build
         something' is a category, not an action; the clause after the
         dash is a mechanism no entry contains. Nothing here can be
         marked Not quite.
GOOD: "An empty day turns into a project. Six of six since the job
       ended — and not the two nights you wrote 'lucky and loved'."`;
}

/** Prompt ASK — Questions about the user. Temp 0.2. */
function buildAskPrompt({ safetyRules, question, modelBlock }) {
  return `${safetyRules}

Answer the person's question about themselves FROM THE MODEL, not from
raw entries. Cite the signature/rule/need you used and give up to three
receipts (quote + date). If the model has no relevant, evidenced item,
say exactly that and offer the question that would let the journal
find out. Never generalise beyond the receipts. <= 120 words. Same word
rules as Prompt M, and no internal vocabulary on screen: say what the
entries say, never "your signature" or "this hypothesis".

${DO_NOT_INFER_LINE}

THE MODEL (what has been formulated so far, with evidence):
${modelBlock}

USER'S QUESTION:
"${question}"

Return ONLY valid JSON:
{ "answer": "", "citations": [{"itemId": "", "quote": "", "date": ""}] }`;
}

module.exports = {
  DO_NOT_INFER_LINE,
  buildFormulationPrompt,
  buildNextQuestionPrompt,
  buildMirrorMPrompt,
  buildAskPrompt,
};
