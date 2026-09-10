/* node:test — Phase 2 of Mirror v3.1: the candidate contingencies that feed
 * Prompt F (mirror-v3.1-person-model-2026-09-10.md §5).
 *
 * Every expected number here is counted by hand against the small fixtures
 * built inline, same discipline as pipeline.test.js's sample.js corpus.
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const {
  unstatedBecause, sayDoGaps, contextSplits, MIN_BECAUSE_K, MIN_SAYDO_OCCURRENCES,
} = require("../lib/candidates");
const { computeVocabTop } = require("../lib/facts");

/* ── unstatedBecause (Shape 2) ───────────────────────────────────────────── */

test("unstatedBecause: zero attribution scores the full contingency strength", () => {
  const cooc = [{
    type: "cooccurrence", subject: "domain:work", object: "emotion:heavy",
    terms: ["domain:work", "emotion:heavy"], n: 6, m: 8, k: 5, j: 0, lift: 2.33,
    coDays: ["d1", "d2", "d3", "d4", "d5"], aDays: ["d1", "d2", "d3", "d4", "d5", "d6"],
  }];
  const dayQuotes = new Map([
    ["d1", [{ text: "Long day at work.", entryId: "e1", date: "d1" }]],
    ["d3", [{ text: "Felt heavy again.", entryId: "e3", date: "d3" }]],
  ]);
  const out = unstatedBecause(cooc, dayQuotes);
  assert.equal(out.length, 1);
  assert.equal(out[0].attribution, 0);
  assert.equal(out[0].score, 2.33);
  assert.equal(out[0].attributionEvidence, null);
});

test("unstatedBecause: a causal connective anywhere on a co-occurring day scores it to zero and drops it", () => {
  const cooc = [{
    type: "cooccurrence", subject: "domain:work", object: "emotion:heavy",
    terms: ["domain:work", "emotion:heavy"], n: 6, m: 8, k: 5, j: 0, lift: 2.33,
    coDays: ["d1", "d2", "d3"], aDays: ["d1", "d2", "d3", "d4"],
  }];
  const dayQuotes = new Map([
    ["d2", [{ text: "Heavy today because work would not let up.", entryId: "e2", date: "d2" }]],
  ]);
  const out = unstatedBecause(cooc, dayQuotes);
  assert.equal(out.length, 0, "an already-narrated causal link is not high value, so it must not reach Prompt M");
});

test(`unstatedBecause: needs k >= ${MIN_BECAUSE_K}, parity with the signature gate`, () => {
  const cooc = [{
    type: "cooccurrence", subject: "domain:work", object: "emotion:heavy",
    terms: ["domain:work", "emotion:heavy"], n: 4, m: 4, k: 2, j: 0, lift: 2.0,
    coDays: ["d1", "d2"], aDays: ["d1", "d2", "d3", "d4"],
  }];
  const out = unstatedBecause(cooc, new Map());
  assert.equal(out.length, 0);
});

test("unstatedBecause: lift is capped at 3 so one wild outlier can't dominate the ranking", () => {
  const cooc = [{
    type: "cooccurrence", subject: "domain:work", object: "emotion:heavy",
    terms: ["domain:work", "emotion:heavy"], n: 3, m: 3, k: 3, j: 0, lift: 9.5,
    coDays: ["d1", "d2", "d3"], aDays: ["d1", "d2", "d3"],
  }];
  const out = unstatedBecause(cooc, new Map());
  assert.equal(out[0].score, 3);
});

/* ── sayDoGaps (Shape 3) ─────────────────────────────────────────────────── */

test("sayDoGaps: the same stated want and enacted behaviour recurring twice is a candidate", () => {
  const analyses = [
    { entryId: "e1", valuesPresent: ["rest"], protectiveStrategies: [{ strategy: "started a project" }] },
    { entryId: "e2", valuesPresent: ["rest"], protectiveStrategies: ["started a project"] },
  ];
  const out = sayDoGaps(analyses);
  assert.equal(out.length, 1);
  assert.equal(out[0].n, 2);
  assert.deepEqual(out[0].entryIds, ["e1", "e2"]);
});

test(`sayDoGaps: fewer than ${MIN_SAYDO_OCCURRENCES} occurrences is not a candidate`, () => {
  const analyses = [
    { entryId: "e1", valuesPresent: ["rest"], protectiveStrategies: [{ strategy: "started a project" }] },
  ];
  assert.equal(sayDoGaps(analyses).length, 0);
});

test("sayDoGaps: openLoops and episode outcomes count on either side", () => {
  const analyses = [
    { entryId: "e1", openLoops: ["actually slow down"], episodes: [{ outcome: "finished the deck anyway" }] },
    { entryId: "e2", openLoops: ["actually slow down"], episodes: [{ outcome: "finished the deck anyway" }] },
  ];
  const out = sayDoGaps(analyses);
  assert.equal(out.length, 1);
  assert.equal(out[0].wantTerm, "actually slow down");
  assert.equal(out[0].didTerm, "finished the deck anyway");
});

test("sayDoGaps: unrelated wants and behaviours in different entries never pair", () => {
  const analyses = [
    { entryId: "e1", valuesPresent: ["rest"], protectiveStrategies: [] },
    { entryId: "e2", valuesPresent: [], protectiveStrategies: [{ strategy: "started a project" }] },
  ];
  assert.equal(sayDoGaps(analyses).length, 0);
});

/* ── contextSplits (Shape 1, the CAPS detector) ─────────────────────────── */

test("contextSplits: a strategy across >=2 distinct domains is a cross-context candidate", () => {
  const dayTerms = new Map([
    ["d1", new Set(["strategy:started a project", "domain:work"])],
    ["d2", new Set(["strategy:started a project", "domain:work"])],
    ["d3", new Set(["strategy:started a project", "domain:home"])],
  ]);
  const out = contextSplits(dayTerms, ["d1", "d2", "d3"]);
  assert.equal(out.length, 1);
  assert.equal(out[0].n, 3);
  assert.equal(out[0].crossContext, true);
  assert.deepEqual(new Set(out[0].contexts), new Set(["domain:work", "domain:home"]));
});

test("contextSplits: fewer than 3 days is not enough, even across two domains", () => {
  const dayTerms = new Map([
    ["d1", new Set(["strategy:started a project", "domain:work"])],
    ["d2", new Set(["strategy:started a project", "domain:home"])],
  ]);
  assert.equal(contextSplits(dayTerms, ["d1", "d2"]).length, 0);
});

test("contextSplits: the same single domain every time is not a cross-context split", () => {
  const dayTerms = new Map([
    ["d1", new Set(["strategy:started a project", "domain:work"])],
    ["d2", new Set(["strategy:started a project", "domain:work"])],
    ["d3", new Set(["strategy:started a project", "domain:work"])],
  ]);
  assert.equal(contextSplits(dayTerms, ["d1", "d2", "d3"]).length, 0);
});

/* ── vocabTop200 (facts.js, feeds lint rule 9's swap test) ──────────────── */

test("computeVocabTop: counts content words across summary, phrases and episode situations, drops stopwords", () => {
  const analyses = [
    { surfaceSummary: "Started another project on a Saturday with nothing in it." },
    { surfaceSummary: "Another project, another Saturday.", phrasesToTrack: ["lucky and loved"] },
    { episodes: [{ situation: "Dan brought up the project again" }] },
  ];
  const top = computeVocabTop(analyses, 200);
  assert.ok(top.includes("project"), "the recurring content word must survive");
  assert.ok(top.includes("saturday"));
  assert.ok(!top.includes("with"), "'with' is on the stopword list");
  assert.ok(!top.includes("the"), "'the' is too short/stopped either way");
  assert.equal(top[0], "another", "tied with 'project' at count 3, alphabetically first");
});

test("computeVocabTop: respects the cap and ranks by frequency", () => {
  const analyses = [
    { surfaceSummary: "project project project quietude quietude solo" },
  ];
  const top = computeVocabTop(analyses, 2);
  assert.equal(top.length, 2);
  assert.equal(top[0], "project");
});
