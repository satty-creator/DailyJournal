/* facts.js — Tier 0 of Mirror v3 (mirror-v3-prd-2026-09-10.md §4).
 *
 * Counts, dates and the person's own words. No model, no inference, no
 * thresholds beyond "is this even known". Everything here is arithmetic over
 * data the app already captured, which is exactly why it is allowed to be the
 * most specific thing on the screen: arithmetic can't hallucinate.
 *
 * Pure — no firebase-admin, no network. `computeFacts` takes plain objects and
 * returns a plain object; index.js does the reading and writing around it.
 */

"use strict";

const { normalise } = require("./text");
const {
  localDateParts, recentDateKeys, weekBounds, daysBetweenKeys,
} = require("./time");

const SCHEMA_VERSION = 1;
const WINDOW_DAYS = 30;

// Word-frequency stop list. PARITY (loose): Memory/MemoryProfileService.swift's
// `compose` uses the same idea on-device over decrypted text; this runs over
// entryAnalyses instead, so the two will not agree token-for-token and are not
// meant to.
const STOP = new Set([
  "the", "and", "but", "for", "with", "that", "this", "was", "were", "been",
  "have", "has", "had", "not", "you", "your", "youre", "she", "her", "hers",
  "him", "his", "they", "them", "their", "there", "here", "what", "when",
  "where", "which", "who", "whom", "how", "why", "all", "any", "both", "each",
  "few", "more", "most", "other", "some", "such", "than", "too", "very", "can",
  "will", "just", "dont", "should", "now", "get", "got", "like", "really",
  "about", "into", "over", "then", "them", "want", "know", "feel", "felt",
  "think", "thing", "things", "time", "today", "week", "day", "days", "going",
  "getting", "make", "made", "back", "does", "doing", "from", "out", "off",
  "its", "it's", "im", "i'm", "ive", "i've", "am", "are", "is", "be", "being",
]);

/** The unlock ladder — mirror-v3-prd-2026-09-10.md §7.
 *
 *  PARITY: DailyJournal/Mirror/MirrorMaturity.swift `UnlockLadder.steps`. The
 *  client needs the same table so a user whose FactsJob has not run yet still
 *  sees an honest hint instead of nothing. */
const LADDER = [
  { atEntries: 1, unlocks: "strip" },
  { atEntries: 3, unlocks: "observations" },
  { atEntries: 7, unlocks: "firstSeven" },
  { atEntries: 10, unlocks: "threads" },
  { atEntries: 14, unlocks: "lag" },
  { atEntries: 30, unlocks: "monthly" },
];

function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}

/**
 * "What would unlock the next thing" (PRD principle 7, R9).
 *
 * Deliberately concrete and checkable — "two more entries" is a promise the
 * user can hold the app to, unlike "keep writing". Where a band contrast is
 * what's actually missing, say THAT instead of a bare count: telling someone
 * to write two more entries when what the statistics need is one evening entry
 * is the kind of near-miss advice that teaches people to ignore hints.
 */
function unlockStateFor(entriesTotal, counters) {
  const next = LADDER.find((s) => s.atEntries > entriesTotal) || null;
  const stage = [...LADDER].reverse().find((s) => s.atEntries <= entriesTotal);
  if (!next) {
    return {
      stage: stage ? stage.unlocks : "seed",
      entriesTotal,
      next: null,
      counters,
    };
  }
  const need = next.atEntries - entriesTotal;
  let hint;
  if (next.unlocks === "observations") {
    hint = `${plural(need, "more entry", "more entries")} and Spilr can compare days.`;
  } else if (next.unlocks === "firstSeven") {
    // If every entry so far lands in one time-of-day band, THAT is the missing
    // ingredient for a comparison, not raw volume.
    const bands = ["morning", "afternoon", "evening", "late"]
      .filter((b) => (counters[`${b}Entries`] || 0) > 0);
    hint = bands.length <= 1 && entriesTotal >= 3
      ? "One entry at a different time of day and Spilr can compare your mornings and evenings."
      : `${plural(need, "more entry", "more entries")} and Spilr can show you your first seven.`;
  } else if (next.unlocks === "threads") {
    hint = `${plural(need, "more entry", "more entries")} and a thread can form.`;
  } else if (next.unlocks === "lag") {
    hint = `${plural(need, "more entry", "more entries")} and Spilr can look at what follows what.`;
  } else if (next.unlocks === "monthly") {
    hint = `${plural(need, "more entry", "more entries")} and Spilr can look at a whole month.`;
  } else {
    hint = `${plural(need, "more entry", "more entries")} to go.`;
  }
  return {
    stage: stage ? stage.unlocks : "seed",
    entriesTotal,
    next: { atEntries: next.atEntries, need, unlocks: next.unlocks, hint },
    counters,
  };
}

/** Count occurrences into a Map, ignoring empties. */
function bump(map, key, by = 1) {
  if (!key) return;
  map.set(key, (map.get(key) || 0) + by);
}

/** Map → [{key, count}] sorted desc, capped. */
function topN(map, n, keyName, countName = "count") {
  return [...map.entries()]
    .filter(([k]) => k)
    .sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0])))
    .slice(0, n)
    .map(([k, v]) => ({ [keyName]: k, [countName]: v }));
}

/**
 * Build the per-day term index every Tier-1 observation is computed over.
 *
 * DAY-GRAIN, not entry-grain: §4's copy says "on the {n} DAYS you wrote about
 * {A}". Two entries on one day mentioning "work" is one day, not two — the
 * alternative silently inflates every count for people who write in bursts.
 *
 * Terms are namespaced so a domain called "work" and a phrase called "work"
 * can never collide, and so the renderer knows how to say each one out loud.
 */
function buildDayTerms(analyses, entryDates) {
  const dayTerms = new Map();   // dateKey -> Set(term)
  const termQuotes = new Map(); // term -> [{text, entryId, date}]
  const termLabels = new Map(); // term -> the person's own spelling of it
  const termEntries = new Map();// term -> Set(entryId)
  // dateKey -> [{text, entryId, date}] — what the person wrote THAT DAY,
  // regardless of which terms it produced. An exception's receipt has to come
  // from here: an exception is defined by a term being ABSENT, so looking its
  // quotes up by that term can only ever return nothing.
  const dayQuotes = new Map();
  const add = (dateKey, term, quote, entryId, label) => {
    if (!dateKey || !term) return;
    if (!dayTerms.has(dateKey)) dayTerms.set(dateKey, new Set());
    dayTerms.get(dateKey).add(term);
    // First spelling wins. Terms are matched normalised but SHOWN verbatim —
    // rendering "priya" or "tight chest" back at someone who wrote "Priya" is
    // exactly the kind of small wrongness that reads as not-actually-reading.
    if (label && !termLabels.has(term)) termLabels.set(term, String(label).trim());
    if (!termEntries.has(term)) termEntries.set(term, new Set());
    termEntries.get(term).add(entryId);
    if (quote) {
      if (!termQuotes.has(term)) termQuotes.set(term, []);
      const list = termQuotes.get(term);
      if (list.length < 12) list.push({ text: quote, entryId, date: dateKey });
    }
  };

  for (const a of analyses) {
    const dateKey = entryDates[a.entryId];
    if (!dateKey) continue;
    // Day-level receipts, most specific first: a distinctive phrase the person
    // chose beats the model's one-line summary of the entry.
    if (!dayQuotes.has(dateKey)) dayQuotes.set(dateKey, []);
    const bucket = dayQuotes.get(dateKey);
    for (const p of (a.phrasesToTrack || [])) {
      if (p) bucket.push({ text: String(p), entryId: a.entryId, date: dateKey });
    }
    if (a.surfaceSummary) {
      bucket.push({ text: String(a.surfaceSummary), entryId: a.entryId, date: dateKey });
    }
    for (const d of (a.lifeDomains || [])) add(dateKey, `domain:${normalise(d)}`, null, a.entryId, d);
    for (const e of (a.explicitEmotions || [])) add(dateKey, `emotion:${normalise(e)}`, a.surfaceSummary, a.entryId, e);
    for (const p of (a.phrasesToTrack || [])) add(dateKey, `phrase:${normalise(p)}`, p, a.entryId, p);
    for (const b of (a.bodySignals || [])) add(dateKey, `body:${normalise(b)}`, b, a.entryId, b);
    for (const r of (a.relationshipRoles || [])) add(dateKey, `role:${normalise(r)}`, null, a.entryId, r);
    for (const p of (a.people || [])) {
      if (p && p.name) add(dateKey, `person:${normalise(p.name)}`, a.surfaceSummary, a.entryId, p.name);
    }
    for (const s of (a.protectiveStrategies || [])) {
      const label = typeof s === "string" ? s : (s && s.strategy);
      if (label) add(dateKey, `strategy:${normalise(label)}`, (s && s.evidence) || null, a.entryId, label);
    }
    for (const v of (a.valuesPresent || [])) add(dateKey, `value:${normalise(v)}`, null, a.entryId, v);
  }
  return { dayTerms, termQuotes, termLabels, termEntries, dayQuotes };
}

/** Aggregate one slice of days into the shape §5.3's strip renders. */
function summariseWindow(dateKeys, entries, analyses, entryMeta, entryDates) {
  const keySet = new Set(dateKeys);
  const inWindowEntries = entries.filter((e) => keySet.has(entryDates[e.id]));
  const inWindowAnalyses = analyses.filter((a) => keySet.has(entryDates[a.entryId]));

  const byBand = { morning: 0, afternoon: 0, evening: 0, late: 0 };
  const byWeekday = [0, 0, 0, 0, 0, 0, 0];
  const byMode = {};
  const activeDays = new Set();
  let words = 0;
  let wordsKnownCount = 0;

  for (const e of inWindowEntries) {
    const meta = entryMeta[e.id];
    if (!meta) continue;
    activeDays.add(entryDates[e.id]);
    byBand[meta.band] = (byBand[meta.band] || 0) + 1;
    byWeekday[meta.weekday] = (byWeekday[meta.weekday] || 0) + 1;
    byMode[meta.mode] = (byMode[meta.mode] || 0) + 1;
    if (typeof meta.words === "number") { words += meta.words; wordsKnownCount++; }
  }

  const emotions = new Map();
  const emotionDays = new Map();  // emotion -> Set(dateKey)
  const emotionDomains = new Map(); // emotion -> Map(domain -> count)
  const phrases = new Map();
  const domains = new Map();
  const bodySignals = new Map();
  const people = new Map();
  const roles = new Map();
  const moods = {};

  for (const a of inWindowAnalyses) {
    const dateKey = entryDates[a.entryId];
    for (const raw of (a.explicitEmotions || [])) {
      const w = normalise(raw);
      if (!w || STOP.has(w) || w.length < 3) continue;
      bump(emotions, w);
      if (!emotionDays.has(w)) emotionDays.set(w, new Set());
      emotionDays.get(w).add(dateKey);
      if (!emotionDomains.has(w)) emotionDomains.set(w, new Map());
      for (const d of (a.lifeDomains || [])) bump(emotionDomains.get(w), normalise(d));
    }
    for (const p of (a.phrasesToTrack || [])) bump(phrases, String(p).trim());
    for (const d of (a.lifeDomains || [])) bump(domains, normalise(d));
    for (const b of (a.bodySignals || [])) bump(bodySignals, String(b).trim());
    for (const r of (a.relationshipRoles || [])) bump(roles, normalise(r));
    for (const p of (a.people || [])) {
      if (p && p.name) bump(people, String(p.name).trim());
    }
  }
  for (const e of inWindowEntries) {
    if (e.mood) moods[e.mood] = (moods[e.mood] || 0) + 1;
  }

  // The single most-repeated emotion word, with WHERE it clustered — a count
  // alone ("'heavy' — 3 times") is true but thin; "all on work days" is the
  // half that makes it feel read rather than counted.
  let topEmotion = null;
  const rankedEmotions = topN(emotions, 1, "word");
  if (rankedEmotions.length && rankedEmotions[0].count >= 2) {
    const word = rankedEmotions[0].word;
    const domainCounts = emotionDomains.get(word) || new Map();
    const topDomain = topN(domainCounts, 1, "domain")[0];
    const days = [...(emotionDays.get(word) || [])].sort();
    topEmotion = {
      word,
      count: rankedEmotions[0].count,
      days,
      // Only claim a cluster when it is unanimous — "all on work days" is a
      // strong claim and a 2-of-3 is not that.
      clusteredOn: topDomain && topDomain.count === rankedEmotions[0].count
        ? `domain:${topDomain.domain}` : null,
    };
  }

  const wordsKnown = inWindowEntries.length > 0 &&
    wordsKnownCount / inWindowEntries.length >= 0.8;

  return {
    start: dateKeys[0] || null,
    end: dateKeys[dateKeys.length - 1] || null,
    entries: inWindowEntries.length,
    activeDays: activeDays.size,
    words,
    wordsKnown,
    byBand,
    byWeekday,
    byMode,
    topEmotion,
    people: topN(people, 5, "name", "mentions"),
    roles: topN(roles, 5, "role", "mentions"),
    topPhrases: topN(phrases, 5, "phrase"),
    topDomains: topN(domains, 5, "domain"),
    bodySignals: topN(bodySignals, 5, "signal"),
    moods,
  };
}

/**
 * Tier 0. Returns the full `users/{uid}/derived/facts` body.
 *
 * @param {object} input
 * @param {Array}  input.entries   [{id, createdAt:Date, sessionType, mood, templateId,
 *                                   templateScaleBefore, templateScaleAfter, wordCount}]
 * @param {Array}  input.analyses  entryAnalyses docs (plain objects, Dates already resolved)
 * @param {string} input.tz        IANA timezone
 * @param {Date}   input.now
 * @param {number} input.entriesTotal  lifetime count, from rollups/stats
 */
function computeFacts({ entries, analyses, tz, now, entriesTotal }) {
  const safeEntries = (entries || []).filter((e) => e && e.id && e.createdAt);
  const safeAnalyses = (analyses || []).filter((a) => a && a.entryId);
  const analysisById = {};
  for (const a of safeAnalyses) analysisById[a.entryId] = a;

  // entryId -> local dateKey, and the per-entry metadata every later job needs
  // so it never has to re-read `entries`.
  const entryDates = {};
  const entryMeta = {};
  for (const e of safeEntries) {
    const a = analysisById[e.id];
    // Prefer the analysis's typed `entryCreatedAt` passthrough, then the entry
    // doc's own createdAt. NEVER the analysis's own createdAt — that is when
    // the ANALYSIS ran, and it moves every time an entry is re-analysed.
    const instant = (a && a.entryCreatedAt) || e.createdAt;
    const parts = localDateParts(instant, tz);
    entryDates[e.id] = parts.dateKey;
    const words = typeof e.wordCount === "number" ? e.wordCount
      : (a && typeof a.wordCount === "number" ? a.wordCount : null);
    entryMeta[e.id] = {
      band: parts.band,
      weekday: parts.weekday,
      mode: e.sessionType || "freeWrite",
      ...(words != null ? { words } : {}),
    };
  }

  const weekKeys = (() => {
    const { start, end } = weekBounds(now, tz);
    const span = daysBetweenKeys(start, end);
    return recentDateKeys(now, span + 1, tz);
  })();
  const monthKeys = recentDateKeys(now, WINDOW_DAYS, tz);

  const week = summariseWindow(weekKeys, safeEntries, safeAnalyses, entryMeta, entryDates);
  const month = summariseWindow(monthKeys, safeEntries, safeAnalyses, entryMeta, entryDates);

  // First appearance of every tracked term, so "first time since 12 Aug" is a
  // fact rather than a guess. Bounded — this doc is read on every tab open.
  const firstSeen = {};
  const { dayTerms } = buildDayTerms(safeAnalyses, entryDates);
  const orderedDays = [...dayTerms.keys()].sort();
  for (const dateKey of orderedDays) {
    for (const term of dayTerms.get(dateKey)) {
      if (!(term in firstSeen)) firstSeen[term] = dateKey;
    }
  }
  const firstSeenCapped = {};
  for (const k of Object.keys(firstSeen).slice(0, 200)) firstSeenCapped[k] = firstSeen[k];

  // Template before/after runs, oldest first — the Delta observation's input.
  // `computeMeasuredDeltas` in index.js already does this arithmetic for the
  // mine prompt; this is the same fact, persisted so Tier 1 can reach it.
  const templateRuns = safeEntries
    .filter((e) => e.templateId &&
      typeof e.templateScaleBefore === "number" &&
      typeof e.templateScaleAfter === "number")
    .map((e) => ({
      entryId: e.id,
      date: entryDates[e.id],
      templateId: e.templateId,
      before: e.templateScaleBefore,
      after: e.templateScaleAfter,
    }))
    .sort((a, b) => String(a.date).localeCompare(String(b.date)))
    .slice(-20);

  // Unlock counters — each one is the literal quantity a gated feature is
  // waiting on, so the hint can name it.
  const monthKeySet = new Set(monthKeys);
  const activeDayKeys = [...new Set(
    safeEntries.map((e) => entryDates[e.id]).filter((k) => monthKeySet.has(k))
  )].sort();
  let lagPairs = 0;
  for (let i = 1; i < activeDayKeys.length; i++) {
    if (daysBetweenKeys(activeDayKeys[i - 1], activeDayKeys[i]) === 1) lagPairs++;
  }
  const counters = {
    morningEntries: month.byBand.morning || 0,
    afternoonEntries: month.byBand.afternoon || 0,
    eveningEntries: month.byBand.evening || 0,
    lateEntries: month.byBand.late || 0,
    daysWithContrast: activeDayKeys.filter((k) => (dayTerms.get(k) || new Set()).size > 0).length,
    sundays: month.byWeekday[0] || 0,
    lagPairs,
  };

  const analysesInWindow = safeAnalyses.filter((a) => monthKeySet.has(entryDates[a.entryId])).length;
  const entriesInWindow = safeEntries.filter((e) => monthKeySet.has(entryDates[e.id])).length;
  const wordCountKnown = safeEntries.filter((e) =>
    monthKeySet.has(entryDates[e.id]) && entryMeta[e.id] &&
    typeof entryMeta[e.id].words === "number").length;
  const peopleKnown = safeAnalyses.filter((a) =>
    monthKeySet.has(entryDates[a.entryId]) && (a.people || []).length > 0).length;

  return {
    schemaVersion: SCHEMA_VERSION,
    timezone: tz || "UTC",
    entriesTotal: typeof entriesTotal === "number" ? entriesTotal : safeEntries.length,
    coverage: {
      entriesInWindow,
      analysesInWindow,
      wordCountKnown,
      peopleKnown,
    },
    week,
    month,
    entryDates,
    entryMeta,
    firstSeen: firstSeenCapped,
    templateRuns,
    unlock: unlockStateFor(
      typeof entriesTotal === "number" ? entriesTotal : safeEntries.length,
      counters
    ),
  };
}

/**
 * Carry forward the earliest known first-appearance for every term.
 *
 * The facts doc is recomputed from a 90-day read every night, so a term first
 * written 100 days ago would otherwise "first appear" on the oldest day still
 * in the window — and the copy would confidently tell the user something began
 * in June that actually began in March. Merging with the prior doc keeps the
 * true earliest date.
 */
function mergeFirstSeen(priorFirstSeen, nextFirstSeen) {
  const out = { ...(nextFirstSeen || {}) };
  for (const [term, date] of Object.entries(priorFirstSeen || {})) {
    if (!out[term] || String(date) < String(out[term])) out[term] = date;
  }
  // Bound it — this doc is read on every Mirror tab open.
  const keys = Object.keys(out).sort();
  if (keys.length <= 300) return out;
  const trimmed = {};
  for (const k of keys.slice(0, 300)) trimmed[k] = out[k];
  return trimmed;
}

module.exports = {
  SCHEMA_VERSION,
  WINDOW_DAYS,
  LADDER,
  STOP,
  computeFacts,
  mergeFirstSeen,
  buildDayTerms,
  unlockStateFor,
};
