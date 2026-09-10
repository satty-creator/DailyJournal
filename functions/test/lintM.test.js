/* node:test — the Prompt M lint (mirror-v3.1-person-model-2026-09-10.md §8).
 *
 * The BAD/GOOD pairs here are transcribed from the design doc's own §2 and
 * §3 worked examples — the document ships its own test cases, and the point
 * of this suite is to prove the code actually enforces the rules it argues
 * for, not to invent new fixtures.
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const {
  lintMirrorLineText, lintMirrorM, findCategoryOrClinical, concretenessCheck,
  figurativeHits, swapTestFails,
} = require("../lib/lint");

// A plausible top-200 vocabulary for the account §2/§3 are built from.
const VOCAB = [
  "empty", "project", "lucky", "loved", "heavy", "work", "dan", "list",
  "fairness", "rest", "priya", "shift", "job", "saturday", "held",
];

/* ── §2's own worked example: the draft vs. the shipped line ────────────── */

test("§2 draft: 'When the future goes blank...' fails — image instead of situation", () => {
  const r = lintMirrorLineText(
    "When the future goes blank, you build something. It's the same move on a free Saturday and in the fairness ledger with Dan — a project makes an uncertain thing feel worked-on. Not on the 'lucky and loved' nights.",
    { receiptQuote: "lucky and loved", vocabTop200: VOCAB }
  );
  assert.equal(r.ok, false);
  // 45 words, 3 sentences, but the middle sentence alone is well over 18
  // words — this must trip on length before anything else gets a chance to.
  assert.equal(r.rule, 1);
});

test("§2 shipped: 'An empty day turns into a project...' passes every rule", () => {
  const r = lintMirrorLineText(
    "An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'.",
    { receiptQuote: "honestly just lucky and loved tonight", vocabTop200: VOCAB }
  );
  assert.equal(r.ok, true, JSON.stringify(r));
});

/* ── the seven ways a line goes wrong (§2 table) ─────────────────────────── */

test("category instead of action: 'you build something' fails the swap test", () => {
  const r = lintMirrorLineText(
    "On a day with nothing in it, you build something to fill it.",
    { vocabTop200: VOCAB }
  );
  assert.equal(r.ok, false);
  assert.equal(r.rule, 9, "true of thousands of other users once stripped — Barnum by construction");
});

test("findCategoryOrClinical: the category-noun and soft-clinical lists (rule 4's own check)", () => {
  assert.equal(findCategoryOrClinical("Keeps the nervous system revved up."), "nervous system");
  assert.equal(findCategoryOrClinical("This is your protective move."), "protective");
  assert.equal(findCategoryOrClinical("Same old pattern again."), "pattern");
  assert.equal(findCategoryOrClinical("An empty day turns into a project."), null);
});

test("clinical noun in a full line: 'protective' fails rule 4 once the rest of the line is concrete enough to clear rule 3 first", () => {
  const r = lintMirrorLineText(
    "You wrote 'wired' after four of the six days — this is your protective move with the project.",
    { vocabTop200: VOCAB }
  );
  assert.equal(r.ok, false);
  assert.equal(r.rule, 4);
});

test("reassurance: 'Neither is wrong' fails rule 8 once the line clears concreteness and every earlier rule", () => {
  const r = lintMirrorLineText(
    "Rest happened and the project got finished anyway on Saturday. Neither is wrong.",
    { vocabTop200: VOCAB }
  );
  assert.equal(r.ok, false);
  assert.equal(r.rule, 8);
});

test("first-person hedge: 'I might be reading too much into this' is a hard fail (rule 7), not a count", () => {
  const r = lintMirrorLineText("I might be reading too much into this, but an empty day turns into a project.", { vocabTop200: VOCAB });
  assert.equal(r.ok, false);
  assert.equal(r.rule, 7);
});

test("impersonal hedge is free: 'this looks like' does not trip rule 7 on its own", () => {
  const r = lintMirrorLineText("This looks like an empty day turning into a project, six of six since the job ended.", { vocabTop200: VOCAB });
  assert.notEqual(r.rule, 7);
});

/* ── the word-level rules individually ───────────────────────────────────── */

test("rule 1: over the 40-word / 3-sentence / 18-words-per-sentence caps", () => {
  const tooManyWords = new Array(45).fill("word").join(" ") + ".";
  assert.equal(lintMirrorLineText(tooManyWords, {}).rule, 1);

  const tooManySentences = "One. Two. Three. Four.";
  assert.equal(lintMirrorLineText(tooManySentences, {}).rule, 1);

  const oneLongSentence = new Array(20).fill("word").join(" ") + ".";
  assert.equal(lintMirrorLineText(oneLongSentence, {}).rule, 1);
});

test("rule 2: the line must contain a verbatim phrase from the receipt", () => {
  const r = lintMirrorLineText(
    "An empty day turns into a project, six of six since the job ended.",
    { receiptQuote: "honestly just lucky and loved tonight", vocabTop200: VOCAB }
  );
  assert.equal(r.ok, false);
  assert.equal(r.rule, 2);
});

test("rule 3: the concreteness floor catches 'uncertain thing' style abstraction", () => {
  const r = lintMirrorLineText(
    "The tendency toward capacity and purpose shapes your process and meaning, drawn from an idea of value.",
    {}
  );
  assert.equal(r.ok, false);
  assert.equal(r.rule, 3);
});

test("rule 5: one image is free, but a second one that isn't the user's own word fails", () => {
  const oneImage = lintMirrorLineText(
    "An empty day is armor against a heavy Saturday, six of six since the job ended.",
    { vocabTop200: VOCAB }
  );
  assert.notEqual(oneImage.rule, 5);
  const twoImages = lintMirrorLineText(
    "An empty day is armor against the storm cloud of a heavy Saturday.",
    { vocabTop200: VOCAB }
  );
  assert.equal(twoImages.rule, 5);
});

test("rule 6: the label form fails, but plain second person does not", () => {
  assert.equal(lintMirrorLineText("You are someone who fills an empty day with a project.", { vocabTop200: VOCAB }).rule, 6);
  assert.equal(lintMirrorLineText("You always turn an empty day into a project.", { vocabTop200: VOCAB }).rule, 6);
  const plainSecondPerson = lintMirrorLineText(
    "An empty day turns into a project, six of six since the job ended.",
    { vocabTop200: VOCAB }
  );
  assert.notEqual(plainSecondPerson.rule, 6, "second person itself is required, not banned");
});

test("rule 9: the swap test kills a line that is true of anyone once quotes/names/numbers are stripped", () => {
  const barnum = lintMirrorLineText(
    "Sometimes a day feels empty and you find something to fill it with.",
    { vocabTop200: VOCAB }
  );
  assert.equal(barnum.ok, false);
  assert.equal(barnum.rule, 9);
});

/* ── lintMirrorM: the full Prompt M output contract ──────────────────────── */

test("lintMirrorM: the §2 shipped line with a real question and would_be_false_if passes whole", () => {
  const output = {
    line: "An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'.",
    shape: "SIGNATURE",
    receipt: { quote: "honestly just lucky and loved tonight", date: "2026-09-05" },
    question: "When Dan brings it up, do you reach for a feeling first, or a list?",
    would_be_false_if: "an empty day that did not turn into a project, with no exception",
  };
  const r = lintMirrorM(output, { receiptQuote: output.receipt.quote, vocabTop200: VOCAB });
  assert.equal(r.ok, true, JSON.stringify(r));
});

test("lintMirrorM: a null would_be_false_if is a hard fail even if the line itself passes", () => {
  const output = {
    line: "An empty day turns into a project. Six of six since the job ended — and not the two nights you wrote 'lucky and loved'.",
    shape: "SIGNATURE",
    receipt: { quote: "honestly just lucky and loved tonight" },
    question: "When Dan brings it up, do you reach for a feeling first, or a list?",
    would_be_false_if: null,
  };
  const r = lintMirrorM(output, { receiptQuote: output.receipt.quote, vocabTop200: VOCAB });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "no_would_be_false_if");
});

test("lintMirrorM: an EXCEPTION shape may end without a question", () => {
  const output = {
    line: "Tuesday was the one heavy day that did not turn into a project. An hour earlier you had written 'being held'.",
    shape: "EXCEPTION",
    receipt: { quote: "being held" },
    question: null,
    would_be_false_if: "a heavy day with no project and no one present",
  };
  const r = lintMirrorM(output, { receiptQuote: output.receipt.quote, vocabTop200: VOCAB });
  assert.equal(r.ok, true, JSON.stringify(r));
});

test("lintMirrorM: a non-exception shape with no question fails — last clause must land somewhere", () => {
  const output = {
    line: "An empty day turns into a project, six of six since the job ended.",
    shape: "SIGNATURE",
    receipt: { quote: "an empty day" },
    question: null,
    would_be_false_if: "an empty day that did not turn into a project",
  };
  const r = lintMirrorM(output, { receiptQuote: "empty day", vocabTop200: VOCAB });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "does_not_end_in_exception_or_question");
});
