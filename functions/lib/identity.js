/* identity.js — hypothesis identity and merging (Mirror v3 M2).
 *
 * The bug this exists to kill: `resolveHypothesisId` matched only WITHIN one
 * patternType, by evidence-entry containment. A rewording that cited a
 * different entry, or that the model happened to file under `valuesConflict`
 * instead of `protectiveLoop`, minted a brand-new id. Nothing ever compared
 * meaning, so one pattern became six, each showing "Seen 1x".
 *
 * Two changes fix it:
 *   1. Containment is compared across ALL patternTypes, not within one.
 *   2. Clustering is union-find (transitive), not greedy pairwise. Six variants
 *      that only chain A~B, B~C, C~D collapse into ONE thread; pairwise
 *      comparison leaves three pairs.
 *
 * Embeddings are optional and deliberately second: containment is free and
 * already correct when it fires, so it runs first and the model is only asked
 * about what is left over (plan §4b).
 *
 * Pure — no firebase-admin, no network.
 */

"use strict";

const { normalise, contentWords, jaccard } = require("./text");

const CONTAINMENT_THRESHOLD = 0.5;  // the existing IDENTITY_OVERLAP
const TITLE_JACCARD_THRESHOLD = 0.6;
const COSINE_THRESHOLD = 0.82;      // plan: the highest-risk untuned number here
const COSINE_CONFIRMED_THRESHOLD = 0.90;
const MAX_CLUSTER_SIZE = 12;

const KILLED_STATUSES = new Set(["closed", "muted", "dismissed"]);
const USER_STATUS_RANK = { this_is_me: 3, half_true: 2, unrated: 1 };

/* ── vector maths ────────────────────────────────────────────────────────── */

/** gemini-embedding-001 returns UNNORMALISED vectors whenever
 *  outputDimensionality < 3072. Cosine against unnormalised vectors is not a
 *  similarity and the 0.82 threshold would be meaningless, so normalise on the
 *  way in, once. */
function normaliseVector(v) {
  if (!Array.isArray(v) || v.length === 0) return null;
  let norm = 0;
  for (const x of v) norm += x * x;
  norm = Math.sqrt(norm);
  if (!isFinite(norm) || norm === 0) return null;
  return v.map((x) => x / norm);
}

/** Assumes both vectors are already unit length. */
function cosine(a, b) {
  if (!a || !b || a.length !== b.length) return 0;
  let dot = 0;
  for (let i = 0; i < a.length; i++) dot += a[i] * b[i];
  return dot;
}

/* ── union-find ──────────────────────────────────────────────────────────── */

function makeUnionFind(n) {
  const parent = Array.from({ length: n }, (_, i) => i);
  const size = new Array(n).fill(1);
  function find(i) {
    while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; }
    return i;
  }
  function union(a, b) {
    const ra = find(a); const rb = find(b);
    if (ra === rb) return false;
    if (size[ra] + size[rb] > MAX_CLUSTER_SIZE) return false;
    if (size[ra] < size[rb]) { parent[ra] = rb; size[rb] += size[ra]; }
    else { parent[rb] = ra; size[ra] += size[rb]; }
    return true;
  }
  return { find, union, size };
}

/* ── similarity keys ─────────────────────────────────────────────────────── */

/** All evidence entry ids this hypothesis has ever cited. */
function evidenceIdsOf(h) {
  return new Set([
    ...((h.evidence || []).map((e) => e && e.entryId)),
    ...(h.evidenceEntryIdsAllTime || []),
  ].filter(Boolean));
}

/** Containment, not Jaccard: intersection over the size of the SMALLER set.
 *  An established hypothesis accumulates up to 60 ids while a fresh candidate
 *  cites at most 3, which caps Jaccard at 3/8 and makes it useless here. */
function containment(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const id of a) if (b.has(id)) inter++;
  return inter / Math.min(a.size, b.size);
}

function titleKeyOf(h) {
  return contentWords(`${h.userFacingTitle || ""} ${h.coreHypothesis || ""}`);
}

/**
 * Why two hypotheses were judged the same — returned so the dry-run log can be
 * read by a human before any of this is allowed to write.
 */
function similarity(a, b, aux) {
  const ev = containment(aux.evidence[a], aux.evidence[b]);
  const title = jaccard(aux.titles[a], aux.titles[b]);
  const cos = (aux.vectors[a] && aux.vectors[b])
    ? cosine(aux.vectors[a], aux.vectors[b]) : null;
  return { evidence: ev, title, cosine: cos };
}

/**
 * Should these two merge?
 *
 * A `this_is_me` boundary is treated as load-bearing: the user vouched for a
 * SPECIFIC wording, and folding it into something they never saw launders
 * their confirmation into a claim they did not make. Crossing that boundary
 * needs near-identity, not a family resemblance.
 */
function shouldMerge(sim, aConfirmed, bConfirmed) {
  const crossesConfirmed = aConfirmed !== bConfirmed;
  if (crossesConfirmed) {
    if (sim.cosine != null && sim.cosine >= COSINE_CONFIRMED_THRESHOLD) return "cosine_strict";
    if (sim.evidence >= 0.8) return "evidence_strict";
    return null;
  }
  if (sim.evidence >= CONTAINMENT_THRESHOLD) return "evidence";
  if (sim.title >= TITLE_JACCARD_THRESHOLD) return "title";
  if (sim.cosine != null && sim.cosine >= COSINE_THRESHOLD) return "cosine";
  return null;
}

/* ── the job ─────────────────────────────────────────────────────────────── */

/**
 * Cluster and merge a user's whole hypothesis corpus.
 *
 * @param {Array} hypotheses  raw patternHypotheses docs (with `id`)
 * @param {object} opts       { now }
 * @returns {{clusters: Array, merges: Array, plan: Array}}
 *   `plan` is the human-readable dry-run form; `merges` is what to write.
 */
function clusterHypotheses(hypotheses, opts = {}) {
  const hyps = (hypotheses || []).filter((h) => h && h.id &&
    h.status !== "merged" && h.mergedInto == null);
  const n = hyps.length;
  const aux = {
    evidence: hyps.map(evidenceIdsOf),
    titles: hyps.map(titleKeyOf),
    vectors: hyps.map((h) => (h.embedding && Array.isArray(h.embedding.v))
      ? normaliseVector(h.embedding.v) : null),
  };
  const confirmed = hyps.map((h) => h.userStatus === "this_is_me");

  const uf = makeUnionFind(n);
  const edges = [];
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const sim = similarity(i, j, aux);
      const via = shouldMerge(sim, confirmed[i], confirmed[j]);
      if (!via) continue;
      if (uf.union(i, j)) {
        edges.push({ a: hyps[i].id, b: hyps[j].id, via, sim });
      }
    }
  }

  // Gather clusters.
  const groups = new Map();
  for (let i = 0; i < n; i++) {
    const root = uf.find(i);
    if (!groups.has(root)) groups.set(root, []);
    groups.get(root).push(i);
  }

  const merges = [];
  const plan = [];
  for (const members of groups.values()) {
    if (members.length < 2) continue;
    const docs = members.map((i) => hyps[i]);

    // Survivor: most distinct supporting entries, then oldest, then a stable
    // tiebreak so two runs over the same data always pick the same doc.
    const ranked = [...docs].sort((a, b) => {
      const t = num(b.timesSeen, 1) - num(a.timesSeen, 1);
      if (t !== 0) return t;
      const fa = ms(a.firstSeenAt); const fb = ms(b.firstSeenAt);
      if (fa !== fb) return fa - fb;
      return String(a.id).localeCompare(String(b.id));
    });
    const survivor = ranked[0];
    const losers = ranked.slice(1);

    // Union of evidence across the whole cluster. `timesSeen` is
    // correct-by-construction — the number of DISTINCT supporting entries,
    // which is exactly what collapses six "Seen 1x" cards into one "Seen 9x".
    const allTime = new Set();
    const evidenceByEntry = new Map();
    let firstSeenAt = null;
    let lastEvidenceAt = null;
    let salience = 0;
    let userStatusRank = 0;
    let userStatus = "unrated";
    let killedStatus = null;
    const mergedPatternTypes = new Set();

    for (const d of docs) {
      for (const id of evidenceIdsOf(d)) allTime.add(id);
      for (const e of (d.evidence || [])) {
        if (e && e.entryId && !evidenceByEntry.has(e.entryId)) evidenceByEntry.set(e.entryId, e);
      }
      const f = ms(d.firstSeenAt);
      if (f && (firstSeenAt == null || f < firstSeenAt)) firstSeenAt = f;
      const l = ms(d.lastEvidenceAt);
      if (l && (lastEvidenceAt == null || l > lastEvidenceAt)) lastEvidenceAt = l;
      salience = Math.max(salience, num(d.salienceScore, 0));
      const rank = USER_STATUS_RANK[d.userStatus] || 0;
      if (rank > userStatusRank) { userStatusRank = rank; userStatus = d.userStatus; }
      // Propagate kills, never resurrect. Today, closing one of six variants
      // leaves five — which reads to the user as the app ignoring them.
      if (KILLED_STATUSES.has(d.status)) killedStatus = killedStatus || d.status;
      if (d.patternType) mergedPatternTypes.add(d.patternType);
    }

    const evidence = [...evidenceByEntry.values()]
      .sort((a, b) => ms(b.entryCreatedAt) - ms(a.entryCreatedAt))
      .slice(0, 3);

    merges.push({
      survivorId: survivor.id,
      loserIds: losers.map((d) => d.id),
      patch: {
        evidence,
        evidenceEntryIdsAllTime: [...allTime].slice(-60),
        timesSeen: allTime.size,
        firstSeenAt,
        lastEvidenceAt,
        salienceScore: salience,
        userStatus,
        mergedPatternTypes: [...mergedPatternTypes],
        ...(killedStatus ? { status: killedStatus } : {}),
      },
    });
    plan.push({
      survivor: { id: survivor.id, title: survivor.userFacingTitle, timesSeen: num(survivor.timesSeen, 1) },
      losers: losers.map((d) => ({ id: d.id, title: d.userFacingTitle, timesSeen: num(d.timesSeen, 1) })),
      mergedTimesSeen: allTime.size,
      killedStatus,
      edges: edges.filter((e) =>
        docs.some((d) => d.id === e.a) && docs.some((d) => d.id === e.b)),
    });
  }

  return { merges, plan, edges, clusterCount: merges.length };
}

function num(x, d) { return typeof x === "number" && isFinite(x) ? x : d; }
function ms(ts) {
  if (!ts) return 0;
  if (ts instanceof Date) return ts.getTime();
  if (typeof ts.toDate === "function") return ts.toDate().getTime();
  if (typeof ts === "number") return ts;
  return 0;
}

module.exports = {
  clusterHypotheses,
  cosine,
  normaliseVector,
  containment,
  evidenceIdsOf,
  titleKeyOf,
  shouldMerge,
  makeUnionFind,
  CONTAINMENT_THRESHOLD,
  TITLE_JACCARD_THRESHOLD,
  COSINE_THRESHOLD,
  MAX_CLUSTER_SIZE,
};
