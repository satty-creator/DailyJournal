/* gate.js — Phase 3's gate (mirror-v3.1-person-model-2026-09-10.md §7).
 *
 * "The gate decides what may reach Prompt M; the lint decides whether M's
 * output ships." This file is the first half. It takes the heterogeneous
 * pool a night's work can offer Prompt M — confirmed signature items from
 * the Person Model, fresh `because`/`sayDo` candidates from candidates.js,
 * and `exception` observations from observations.js — normalises them to one
 * shape, filters by the per-shape threshold, ranks by the fixed priority
 * order, and applies the 14-day novelty penalty. What comes out is at most
 * one candidate: the thing Prompt M is asked to write about today.
 *
 * Pure — no firebase-admin, no network.
 */

"use strict";

const { jaccard } = require("./text");

const MIN_SIGNATURE_ENTRIES = 3;
const MIN_BECAUSE_LIFT = 2;
const MIN_SAYDO_N = 2;
const NOVELTY_WINDOW_DAYS = 14;
const NOVELTY_JACCARD_CEILING = 0.5;

// §7: "Ranking: exception >= because > signature (cross-context) > say/do >
// signature (single context)."
const RANK = {
  EXCEPTION: 4,
  BECAUSE: 3,
  SIGNATURE_CROSS: 2.5,
  SAYDO: 2,
  SIGNATURE_SINGLE: 1,
};

/** A signature item needs >= 3 evidence entries AND at least one contrast —
 *  a `notWhen` clause or a second context. Below that it is not a signature;
 *  Prompt F is instructed to return it under open_hypotheses instead, so a
 *  well-behaved model output should already fail to reach here — this is the
 *  code floor underneath that instruction. */
function gateSignatureItem(item) {
  if (!item || item.kind !== "signature") return false;
  const n = (item.evidenceEntryIds || []).length || Number(item.timesSeen) || 0;
  if (n < MIN_SIGNATURE_ENTRIES) return false;
  const hasContrast = !!(item.notWhen && String(item.notWhen).trim()) ||
    (Array.isArray(item.contexts) && item.contexts.length >= 2);
  return hasContrast;
}

/** A `because` candidate (candidates.js#unstatedBecause output) needs a
 *  stricter lift floor than the underlying co-occurrence (>= 2, not the
 *  Tier-1 floor of 1.5) and zero causal attribution — unstatedBecause()
 *  already drops anything with attribution, so this mostly re-asserts the
 *  lift floor and the n >= 3 the candidate inherited. */
function gateBecauseCandidate(c) {
  if (!c || c.type !== "because") return false;
  return c.attribution === 0 && (c.lift || 0) >= MIN_BECAUSE_LIFT && (c.k || 0) >= 3;
}

/** A say/do candidate needs >= 2 occurrences — candidates.js#sayDoGaps
 *  already enforces this at generation time; this is the explicit re-check
 *  so a caller assembling its own pool can't skip it by construction. */
function gateSayDoCandidate(c) {
  if (!c || c.type !== "saydo") return false;
  return (c.n || 0) >= MIN_SAYDO_N;
}

/** An exception observation's parent (the co-occurrence it hangs off) is
 *  already gated by observations.js's own thresholds before it can become an
 *  `exception` type at all (k >= 3, k/n >= band dominance, 1-2 exception
 *  days) — this just confirms the shape rather than re-deriving the checks. */
function gateExceptionObservation(o) {
  if (!o || o.type !== "exception") return false;
  return Array.isArray(o.exceptionDays) && o.exceptionDays.length >= 1 && o.exceptionDays.length <= 2;
}

function rankOf(shape, crossContext) {
  if (shape === "EXCEPTION") return RANK.EXCEPTION;
  if (shape === "BECAUSE") return RANK.BECAUSE;
  if (shape === "SIGNATURE") return crossContext ? RANK.SIGNATURE_CROSS : RANK.SIGNATURE_SINGLE;
  if (shape === "SAYDO") return RANK.SAYDO;
  return 0;
}

/**
 * 1 − max Jaccard overlap (content-word vocabulary) against anything shown
 * in the last NOVELTY_WINDOW_DAYS. Mirrors observations.js#observationScore's
 * `novelty` term. A missing shown record is MAXIMUM novelty (1), never 0 —
 * same reasoning as Tier 1: an unknown history must never read as "already
 * shown everything."
 */
function noveltyFactor(terms, shownHistory, todayDaysAgo) {
  const mine = new Set((terms || []).map(String));
  let maxOverlap = 0;
  for (const rec of (shownHistory || [])) {
    const days = typeof rec.daysAgo === "number" ? rec.daysAgo : 999;
    if (days > NOVELTY_WINDOW_DAYS) continue;
    if (!Array.isArray(rec.terms) || rec.terms.length === 0) continue;
    maxOverlap = Math.max(maxOverlap, jaccard(mine, new Set(rec.terms)));
  }
  return { novelty: 1 - maxOverlap, penalised: maxOverlap > NOVELTY_JACCARD_CEILING };
}

/**
 * Normalise a candidate pool into one shape and pick the single best one for
 * today. Every entry in `pool` is `{shape, gated, crossContext?, terms, ref}`
 * — `gated` should already reflect the per-shape gate function above; this
 * function does not re-run them, so a caller that skips gating gets whatever
 * it asked for. `ref` is passed through untouched so the caller can go from
 * "this won" back to the original item/observation/candidate.
 *
 * @param {Array} pool
 * @param {object} opts  { shownHistory: [{terms, daysAgo}] }
 * @returns {object|null} the winning pool entry, with `.score` and `.novelty` added
 */
function selectForToday(pool, opts = {}) {
  const candidates = (pool || []).filter((c) => c && c.gated);
  if (candidates.length === 0) return null;
  const scored = candidates.map((c) => {
    const rank = rankOf(c.shape, c.crossContext);
    const { novelty, penalised } = noveltyFactor(c.terms, opts.shownHistory);
    return { ...c, rank, novelty, penalised, score: rank * novelty };
  });
  scored.sort((a, b) => b.score - a.score);
  return scored[0];
}

module.exports = {
  MIN_SIGNATURE_ENTRIES,
  MIN_BECAUSE_LIFT,
  MIN_SAYDO_N,
  NOVELTY_WINDOW_DAYS,
  NOVELTY_JACCARD_CEILING,
  RANK,
  gateSignatureItem,
  gateBecauseCandidate,
  gateSayDoCandidate,
  gateExceptionObservation,
  rankOf,
  noveltyFactor,
  selectForToday,
};
