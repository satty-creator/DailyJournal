/* candidates.js — Phase 2 of Mirror v3.1 (mirror-v3.1-person-model-2026-09-10.md §5).
 *
 * "Statistics decide where to look; the model decides what it means; code
 * decides whether it is safe to say." This file is the first clause. It does
 * NOT decide whether something is a signature, a because, or a say/do gap —
 * that judgment belongs to Prompt F. It only finds the candidates worth
 * putting in front of the model, the same way observations.js finds
 * candidate comparisons worth putting in front of Prompt M's predecessor.
 *
 * Every function here is pure and takes the Tier-0/Tier-1 building blocks
 * (`dayTerms`, `dayQuotes`, `termLabels` from facts.buildDayTerms; the
 * `cooccurrence` observations from observations.cooccurrences) rather than
 * re-deriving them, so this module has exactly one source of truth for "what
 * happened on what day."
 *
 * CONSTRAINT (flagged in the v3.1 plan): the server cannot decrypt
 * `entries.content`. Attribution can only be checked against the plaintext
 * `entryAnalyses` already holds — `surfaceSummary`, `phrasesToTrack`, and each
 * episode's `situation` (all folded into `dayQuotes` by buildDayTerms). That
 * is a narrower read than "any entry", so `unstatedBecause` will over-report
 * "never stated" relative to the full journal. The gate in gate.js compensates
 * by requiring n >= 3 with contrast before a `because` can reach Prompt M.
 */

"use strict";

const { normalise } = require("./text");

const CAUSAL_CONNECTIVES = /\b(because|since|after|so)\b/i;
const MIN_BECAUSE_K = 3;          // parity with the signature gate's n >= 3
const MIN_SAYDO_OCCURRENCES = 2;  // v3.1 §3 Shape 3: >= 2 occurrences
const MIN_CONTEXT_SPLIT_DAYS = 3; // parity with the signature gate's n >= 3

function prefixOf(term) { return String(term).split(":")[0]; }

/* ── Shape 2: the unstated because ──────────────────────────────────────── */

/**
 * For each cooccurrence observation, check whether ANY of the co-occurring
 * days' own quotable text (phrases, summary, episode situations — everything
 * buildDayTerms folded into `dayQuotes`) already uses a causal connective.
 * That is a proxy for "the person has linked these in their own words," not
 * proof they linked THESE TWO terms specifically — the model still has to
 * read the actual quotes before Prompt F is allowed to say "you've never put
 * those two in one sentence."
 *
 * score = contingencyStrength (lift, capped) × (1 − attribution). A
 * contingency the person has already narrated causally scores 0 and is
 * dropped — Prompt F's job is naming what they have NOT said, not repeating
 * what they have.
 */
function unstatedBecause(cooc, dayQuotes) {
  const out = [];
  for (const c of cooc) {
    if (c.k < MIN_BECAUSE_K) continue;
    const attributionQuote = (c.coDays || [])
      .flatMap((d) => dayQuotes.get(d) || [])
      .find((q) => q && q.text && CAUSAL_CONNECTIVES.test(q.text)) || null;
    const attribution = attributionQuote ? 1 : 0;
    const contingencyStrength = Math.min(3, c.lift);
    const score = Math.round(contingencyStrength * (1 - attribution) * 100) / 100;
    if (score <= 0) continue;
    out.push({
      type: "because",
      subject: c.subject,
      object: c.object,
      terms: c.terms,
      n: c.n, m: c.m, k: c.k, j: c.j,
      lift: c.lift,
      attribution,
      attributionEvidence: attributionQuote,
      score,
      coDays: c.coDays,
      aDays: c.aDays,
    });
  }
  return out.sort((a, b) => b.score - a.score);
}

/* ── Shape 3: the say/do gap ─────────────────────────────────────────────── */

/**
 * A stated want (`valuesPresent`, `openLoops`) and an enacted behaviour
 * (`protectiveStrategies`, an episode's `outcome`) recurring together across
 * >= 2 entries. This function makes NO claim that the two are in tension —
 * that reading is Prompt F's, per "statistics decide where to look." It only
 * surfaces pairs that keep showing up in the same entries, which is the raw
 * material a say/do gap is built from.
 */
function sayDoGaps(analyses) {
  const pairs = new Map(); // "want||did" -> {wantLabel, didLabel, entryIds[]}
  for (const a of (analyses || [])) {
    if (!a || !a.entryId) continue;
    const wants = new Set([
      ...(a.valuesPresent || []).map((v) => String(v).trim()).filter(Boolean),
      ...(a.openLoops || []).map((v) => String(v).trim()).filter(Boolean),
    ]);
    const dids = new Set([
      ...(a.protectiveStrategies || [])
        .map((s) => (typeof s === "string" ? s : (s && s.strategy)))
        .map((s) => s && String(s).trim())
        .filter(Boolean),
      ...(a.episodes || [])
        .map((e) => e && e.outcome && String(e.outcome).trim())
        .filter(Boolean),
    ]);
    for (const want of wants) {
      for (const did of dids) {
        const key = `${normalise(want)}||${normalise(did)}`;
        if (!pairs.has(key)) pairs.set(key, { wantLabel: want, didLabel: did, entryIds: [] });
        pairs.get(key).entryIds.push(a.entryId);
      }
    }
  }
  const out = [];
  for (const rec of pairs.values()) {
    const entryIds = [...new Set(rec.entryIds)];
    if (entryIds.length < MIN_SAYDO_OCCURRENCES) continue;
    out.push({
      type: "saydo",
      wantTerm: rec.wantLabel,
      didTerm: rec.didLabel,
      n: entryIds.length,
      entryIds: entryIds.slice(0, 10),
    });
  }
  return out.sort((a, b) => b.n - a.n);
}

/* ── Shape 1: cross-context splits (the CAPS detector) ──────────────────── */

/**
 * A strategy that shows up across >= 2 distinct domains (work AND a
 * relationship), or a situation split two ways by person/domain. This is
 * what makes `crossContext: true` possible in Prompt F's output — the
 * signatures the person "cannot see from inside" because each context is
 * lived separately.
 */
function contextSplits(dayTerms, activeDays) {
  const strategyDays = new Map();    // strategy -> Set(day)
  const strategyContexts = new Map(); // strategy -> Set(domain|person)
  for (const day of activeDays) {
    const terms = dayTerms.get(day) || new Set();
    const strategies = [...terms].filter((t) => prefixOf(t) === "strategy");
    const contexts = [...terms].filter((t) => prefixOf(t) === "domain" || prefixOf(t) === "person");
    for (const s of strategies) {
      if (!strategyDays.has(s)) strategyDays.set(s, new Set());
      strategyDays.get(s).add(day);
      if (!strategyContexts.has(s)) strategyContexts.set(s, new Set());
      for (const c of contexts) strategyContexts.get(s).add(c);
    }
  }
  const out = [];
  for (const [strategy, days] of strategyDays) {
    if (days.size < MIN_CONTEXT_SPLIT_DAYS) continue;
    const contexts = [...(strategyContexts.get(strategy) || [])];
    if (contexts.length < 2) continue;
    out.push({
      type: "contextsplit",
      subject: strategy,
      contexts,
      n: days.size,
      days: [...days].sort(),
      crossContext: true,
    });
  }
  return out.sort((a, b) => b.n - a.n);
}

module.exports = {
  unstatedBecause,
  sayDoGaps,
  contextSplits,
  CAUSAL_CONNECTIVES,
  MIN_BECAUSE_K,
  MIN_SAYDO_OCCURRENCES,
  MIN_CONTEXT_SPLIT_DAYS,
};
