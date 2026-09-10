/* node:test — the Person Model store and its gate
 * (mirror-v3.1-person-model-2026-09-10.md §4, §7).
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const {
  itemIdFor, keyTextFor, confidenceBandFor, identityViewOf, notMeShouldReturn,
  displayTitleFor, NOT_ME_RETURN_THRESHOLD,
} = require("../lib/personModel");
const {
  gateSignatureItem, gateBecauseCandidate, gateSayDoCandidate,
  gateExceptionObservation, selectForToday, RANK,
} = require("../lib/gate");

/* ── identity and confidence ─────────────────────────────────────────────── */

test("itemIdFor is deterministic and stable across recomputes of the same signature", () => {
  const a = itemIdFor("signature", keyTextFor({ kind: "signature", if: "a day with nothing in it", then: "you start a project" }));
  const b = itemIdFor("signature", keyTextFor({ kind: "signature", if: "a day with nothing in it", then: "you start a project" }));
  assert.equal(a, b);
});

test("itemIdFor separates two different kinds with the same words", () => {
  const a = itemIdFor("signature", "rest");
  const b = itemIdFor("value", "rest");
  assert.notEqual(a, b);
});

test("confidenceBandFor: this_is_me is always likely, no matter timesSeen", () => {
  assert.equal(confidenceBandFor({ userStatus: "this_is_me", timesSeen: 1 }), "likely");
});

test("confidenceBandFor: a 'drop' disconfirmation verdict floors it at hunch", () => {
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 9, disconfirmationVerdict: "drop" }), "hunch");
});

test("confidenceBandFor: a 'weaken' verdict caps likely down to maybe", () => {
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 9, disconfirmationVerdict: "weaken" }), "maybe");
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 1, disconfirmationVerdict: "weaken" }), "hunch");
});

test("confidenceBandFor: plain timesSeen thresholds without any verdict", () => {
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 1 }), "hunch");
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 3 }), "maybe");
  assert.equal(confidenceBandFor({ userStatus: "unrated", timesSeen: 6 }), "likely");
});

test("identityViewOf adapts a signature to identity.js's expected shape", () => {
  const item = {
    id: "sig_abc", kind: "signature", if: "a day with nothing in it", then: "you start a project",
    evidenceEntryIds: ["e1", "e2", "e3"], userStatus: "unrated", timesSeen: 3,
  };
  const view = identityViewOf(item);
  assert.equal(view.patternType, "signature");
  assert.equal(view.evidence.length, 3);
  assert.equal(view.userFacingTitle, "a day with nothing in it you start a project");
});

test("displayTitleFor a signature reads as if-then", () => {
  const title = displayTitleFor({ kind: "signature", if: "Dan brings it up", then: "you make a list" });
  assert.equal(title, "Dan brings it up → you make a list");
});

test(`notMeShouldReturn: needs ${NOT_ME_RETURN_THRESHOLD} NEW contradicting entries, not just any evidence`, () => {
  const item = { userStatus: "not_me", evidenceEntryIds: ["e1", "e2"] };
  assert.equal(notMeShouldReturn(item, ["e3", "e4"]), false, "only 2 new entries, need 3");
  assert.equal(notMeShouldReturn(item, ["e1", "e2", "e3"]), false, "e1/e2 are not NEW, they're the original evidence");
  assert.equal(notMeShouldReturn(item, ["e3", "e4", "e5"]), true);
});

test("notMeShouldReturn: an item the user did not reject never returns this way", () => {
  const item = { userStatus: "unrated", evidenceEntryIds: [] };
  assert.equal(notMeShouldReturn(item, ["e1", "e2", "e3"]), false);
});

/* ── the gate ─────────────────────────────────────────────────────────────── */

test("gateSignatureItem: needs >=3 entries AND a contrast (notWhen or 2 contexts)", () => {
  const base = { kind: "signature", evidenceEntryIds: ["e1", "e2", "e3"] };
  assert.equal(gateSignatureItem({ ...base, notWhen: "" }), false, "no contrast at all");
  assert.equal(gateSignatureItem({ ...base, notWhen: "the two lucky nights" }), true);
  assert.equal(gateSignatureItem({ ...base, contexts: ["work", "home"] }), true);
  assert.equal(gateSignatureItem({ ...base, evidenceEntryIds: ["e1", "e2"], notWhen: "x" }), false, "only 2 entries");
});

test("gateBecauseCandidate: needs lift >= 2 and zero attribution", () => {
  assert.equal(gateBecauseCandidate({ type: "because", attribution: 0, lift: 2.5, k: 5 }), true);
  assert.equal(gateBecauseCandidate({ type: "because", attribution: 1, lift: 2.5, k: 5 }), false);
  assert.equal(gateBecauseCandidate({ type: "because", attribution: 0, lift: 1.8, k: 5 }), false, "lift below the stricter Phase-3 floor");
});

test("gateSayDoCandidate: needs >= 2 occurrences", () => {
  assert.equal(gateSayDoCandidate({ type: "saydo", n: 2 }), true);
  assert.equal(gateSayDoCandidate({ type: "saydo", n: 1 }), false);
});

test("gateExceptionObservation: shape must actually be an exception with 1-2 exception days", () => {
  assert.equal(gateExceptionObservation({ type: "exception", exceptionDays: ["2026-09-05"] }), true);
  assert.equal(gateExceptionObservation({ type: "cooccurrence", exceptionDays: [] }), false);
});

test("selectForToday: ranks exception over because over cross-context signature over say/do over single signature", () => {
  const pool = [
    { shape: "SIGNATURE", gated: true, crossContext: false, terms: ["a"] },
    { shape: "SAYDO", gated: true, terms: ["b"] },
    { shape: "SIGNATURE", gated: true, crossContext: true, terms: ["c"] },
    { shape: "BECAUSE", gated: true, terms: ["d"] },
    { shape: "EXCEPTION", gated: true, terms: ["e"] },
  ];
  const winner = selectForToday(pool, { shownHistory: [] });
  assert.equal(winner.shape, "EXCEPTION");
});

test("selectForToday: only considers gated candidates", () => {
  const pool = [
    { shape: "EXCEPTION", gated: false, terms: ["e"] },
    { shape: "SAYDO", gated: true, terms: ["b"] },
  ];
  assert.equal(selectForToday(pool, {}).shape, "SAYDO");
});

test("selectForToday: a recently-shown item's overlap term set is penalised below a fresh weaker candidate", () => {
  const pool = [
    { shape: "SIGNATURE", gated: true, crossContext: true, terms: ["empty", "project"] },
    { shape: "SAYDO", gated: true, terms: ["rest", "finished"] },
  ];
  // The cross-context signature was shown yesterday with the exact same terms.
  const shownHistory = [{ terms: ["empty", "project"], daysAgo: 1 }];
  const winner = selectForToday(pool, { shownHistory });
  assert.equal(winner.shape, "SAYDO", "novelty penalty should let the weaker-ranked but fresher item win");
});

test("selectForToday returns null when nothing is gated", () => {
  assert.equal(selectForToday([{ shape: "SAYDO", gated: false, terms: [] }], {}), null);
  assert.equal(selectForToday([], {}), null);
});
