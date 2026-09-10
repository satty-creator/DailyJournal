/* personModel.js — the Person Model store (mirror-v3.1-person-model-2026-09-10.md §4).
 *
 * Replaces the flat SelfModel with a CBT case formulation held as
 * falsifiable hypotheses, in Kuyken's three levels:
 *   Level 1  descriptive   — situations (not modelled as a standalone item
 *                            yet; folded into signature/rule evidence)
 *   Level 2  cross-sectional — signature, rule, need, loop, distortion, person
 *   Level 3  longitudinal  — coreBelief, value, strength
 *
 * Every item is a hypothesis: `{confidence, evidenceEntryIds[],
 * counterEvidenceEntryIds[], userStatus, lastTestedAt, testQuestion}` plus a
 * kind-specific payload. This file is pure — it knows the shape of an item
 * and how to score/identify one, but never touches Firestore. index.js reads
 * and writes; this file decides what the fields mean.
 */

"use strict";

const { normalise, sha1Hex, contentWords } = require("./text");

const SCHEMA_VERSION = 1;

const LEVEL_FOR_KIND = {
  signature: 2, rule: 2, need: 2, loop: 2, distortion: 2, person: 2,
  coreBelief: 3, value: 3, strength: 3,
};

const KINDS = Object.keys(LEVEL_FOR_KIND);

// §4: "Hard gate: doNotInfer (diagnosis, trauma origin, attachment style,
// childhood) stays." PARITY with SelfModel.swift's doNotInfer defaults and
// with SAFETY_RULES rule 1/4 — this is the same floor stated as a checklist
// rather than as prose, for the prompts and any future automated audit that
// wants to check a Person Model item against it directly.
const DO_NOT_INFER = ["diagnosis", "trauma_origin", "attachment_style", "childhood"];

const USER_STATUSES = ["unrated", "this_is_me", "half_true", "not_me"];

/** How many CONFIRMING entries an item's not_me correction needs to see
 *  before it is allowed back — as a question, never as a claim (§7 F rule:
 *  "USER CORRECTIONS OUTRANK YOUR INFERENCE"). */
const NOT_ME_RETURN_THRESHOLD = 3;

function levelForKind(kind) { return LEVEL_FOR_KIND[kind] || 2; }

/**
 * The text an item is identified and title-matched by — one line per kind,
 * in the person's own words wherever the field holds them. Used for the
 * deterministic id (below) and as the `identityViewOf` title for
 * identity.js's containment/Jaccard clustering.
 */
function keyTextFor(item) {
  switch (item.kind) {
    case "signature": return `${item.if || ""} ${item.then || ""}`;
    case "rule": return item.rule || "";
    case "need": return `need:${item.need || ""}`;
    case "loop": return `${item.move || ""} ${item.relief || ""}`;
    case "distortion": return `${item.plainName || ""} ${item.quote || ""}`;
    case "person": return `${item.name || ""} ${item.roleTheyTake || ""}`;
    case "coreBelief": return item.belief || "";
    case "value": return item.value || "";
    case "strength": return `${item.capacity || ""} ${item.shownWhen || ""}`;
    default: return item.title || "";
  }
}

/** Deterministic id — sha1(kind + normalised key text), so recomputing the
 *  same signature twice in one night (before any embedding-based merge
 *  runs) never mints two docs for it. PARITY with observations.js's `obsId`. */
function itemIdFor(kind, keyText) {
  return `${kind}_${sha1Hex(`${kind}|${normalise(keyText)}`, 16)}`;
}

/**
 * Confidence band — from (timesSeen, disconfirmationVerdict, userStatus)
 * ONLY, never from a number the model returned (§7 Gate: "Confidence band
 * from (timesSeen, ceVerdict, userStatus) only"). The model is never asked
 * for a confidence number in the first place; Prompt F's own `confidence`
 * field is a starting hunch/maybe/likely word it is allowed to propose, but
 * this function is the one that gets displayed and gates Prompt M — it can
 * only go up with real evidence and down with a real correction.
 */
function confidenceBandFor(item) {
  if (item.userStatus === "this_is_me") return "likely";
  const verdict = item.disconfirmationVerdict;
  if (verdict === "drop") return "hunch";
  const n = Number(item.timesSeen) || 0;
  if (verdict === "weaken") return n >= 3 ? "maybe" : "hunch";
  if (n >= 6) return "likely";
  if (n >= 3) return "maybe";
  return "hunch";
}

/** Adapts a Person Model item to the shape `identity.js#clusterHypotheses`
 *  expects, so the six-variants fix that already exists for `patternHypotheses`
 *  works unmodified across Person Model kinds too — a signature phrased two
 *  ways, or filed under two kinds by mistake, still collapses to one item. */
function identityViewOf(item) {
  const key = keyTextFor(item);
  return {
    id: item.id,
    status: item.status || "active",
    mergedInto: item.mergedInto || null,
    evidence: (item.evidenceEntryIds || []).map((entryId) => ({ entryId })),
    evidenceEntryIdsAllTime: item.evidenceEntryIds || [],
    userFacingTitle: key,
    coreHypothesis: key,
    embedding: item.embedding || null,
    userStatus: item.userStatus || "unrated",
    timesSeen: item.timesSeen || (item.evidenceEntryIds || []).length || 1,
    firstSeenAt: item.firstSeenAt || null,
    lastEvidenceAt: item.lastEvidenceAt || null,
    salienceScore: 0,
    patternType: item.kind,
  };
}

/**
 * Should a `not_me` item be allowed back as a QUESTION (never a claim)?
 * §0/§7: a hypothesis the user marked "not me" is retired unless
 * NOT_ME_RETURN_THRESHOLD new entries contradict them.
 */
function notMeShouldReturn(item, newContradictingEntryIds) {
  if (item.userStatus !== "not_me") return false;
  const fresh = new Set(newContradictingEntryIds || []);
  for (const id of (item.evidenceEntryIds || [])) fresh.delete(id);
  return fresh.size >= NOT_ME_RETURN_THRESHOLD;
}

/** A short, checkable title for the "WHAT SPILR THINKS IT KNOWS" row and the
 *  ranking display — kept separate from keyTextFor so a future kind can have
 *  a title that differs from its identity key without touching identity. */
function displayTitleFor(item) {
  switch (item.kind) {
    case "signature": {
      const base = `${item.if || ""} → ${item.then || ""}`.trim();
      return base || "signature";
    }
    case "rule": return item.rule || "a rule";
    case "need": return item.need ? `Needs read: ${item.need}` : "needs";
    case "loop": return item.move || "a loop";
    case "distortion": return item.plainName || "a thinking pattern";
    case "person": return item.name ? `With ${item.name}` : "a person";
    case "coreBelief": return item.belief || "a core belief";
    case "value": return item.value || "a value";
    case "strength": return item.capacity || "a strength";
    default: return item.title || "";
  }
}

/** Rough token overlap between an item's own vocabulary and a candidate
 *  vocabulary set — used by the swap test (lint rule 9) and by dedup's
 *  title-Jaccard path, but exposed here since both need the same words. */
function vocabularyOf(item) {
  return contentWords(keyTextFor(item));
}

module.exports = {
  SCHEMA_VERSION,
  KINDS,
  LEVEL_FOR_KIND,
  DO_NOT_INFER,
  USER_STATUSES,
  NOT_ME_RETURN_THRESHOLD,
  levelForKind,
  keyTextFor,
  itemIdFor,
  confidenceBandFor,
  identityViewOf,
  notMeShouldReturn,
  displayTitleFor,
  vocabularyOf,
};
