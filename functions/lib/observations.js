/* observations.js — Tier 1 of Mirror v3 (mirror-v3-prd-2026-09-10.md §4).
 *
 * An observation is a COMPARISON between two sets of the person's own days.
 * Everything here is deterministic and costs zero model tokens; the language
 * model's only job (Tier 2) is to phrase ONE of these, on top of numbers it
 * cannot move.
 *
 * Three thresholds here are additions to the PRD, and each one exists to kill a
 * specific way of shipping noise as signal:
 *   - co-occurrence needs k >= 2. With k = 1, `lift` can be arbitrarily large
 *     off a single coincidence — precisely the n=1 "pattern" v3 exists to end.
 *   - weekday/lag need an effect size of at least 25%. As the PRD is written,
 *     "Sunday entries are 3% longer" passes.
 *   - lag additionally needs 14 lifetime entries, reconciling §4's "3 lag
 *     pairs" with §7's ladder, which does not unlock lag until 14.
 *
 * Pure — no firebase-admin, no network.
 */

"use strict";

const { normalise, jaccard, contentWords, sha1Hex } = require("./text");
const { daysBetweenKeys, shortDate, relativeLabel } = require("./time");

const SCHEMA_VERSION = 1;

// §4 thresholds.
const MIN_DAYS_WITH_TERM = 3;      // n
const MIN_CONTRAST_DAYS = 3;       // m
const MIN_LIFT = 1.5;
const MIN_CO_DAYS = 2;             // k — see header
const BAND_DOMINANCE = 0.67;       // k/n for time-band
const MIN_WEEKDAY_OCCURRENCES = 3;
const MIN_WEEKDAY_OTHERS = 6;
const MIN_EFFECT_PCT = 25;         // |x| for weekday + lag — see header
const MIN_LAG_PAIRS = 3;
const MIN_ENTRIES_FOR_LAG = 14;    // §7's ladder
const CALLBACK_MIN_DAYS_APART = 14;
const STREAK_MIN_GAP_DAYS = 21;
const MAX_EXCEPTIONS = 2;
const WORDCOUNT_COVERAGE_FLOOR = 0.8;

// Terms that read naturally as the SUBJECT of "on the days you wrote about X".
const SUBJECT_PREFIXES = ["domain", "person", "role", "strategy", "value"];
// ...and the ones that read naturally as the thing that showed up.
const OBJECT_PREFIXES = ["emotion", "phrase", "body"];

function prefixOf(term) { return String(term).split(":")[0]; }
function valueOf(term) { return String(term).slice(String(term).indexOf(":") + 1); }

/** How a term is spoken in a sentence. Quoted when it is the person's own
 *  wording (an emotion word, a phrase, a body signal); bare when it is a
 *  category (a domain) or a name. */
function speak(term, labels) {
  const label = (labels && labels.get(term)) || valueOf(term);
  switch (prefixOf(term)) {
    case "emotion":
    case "phrase":
    case "body":
      return `'${label}'`;
    case "person":
      return label;
    case "domain":
      return label;
    case "role":
      return `being the ${label}`;
    case "strategy":
      return `'${label}'`;
    case "value":
      return label;
    default:
      return label;
  }
}

const BAND_PHRASE = {
  morning: "before noon",
  afternoon: "in the afternoon",
  evening: "in the evening",
  late: "after 9pm",
};
const WEEKDAY_NAME = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function obsId(type, terms) {
  const sorted = [...terms].map(String).sort();
  return `${type}_${sha1Hex(`${type}|${sorted.join("|")}`, 16)}`;
}

/** Up to `n` quotes for a term, preferring the most recent and never repeating
 *  the same text twice. */
function quotesFor(term, termQuotes, n, onlyDays) {
  const all = (termQuotes.get(term) || [])
    .filter((q) => q && q.text && (!onlyDays || onlyDays.has(q.date)))
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));
  const seen = new Set();
  const out = [];
  for (const q of all) {
    const key = normalise(q.text);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push({ text: String(q.text), entryId: q.entryId, date: q.date });
    if (out.length >= n) break;
  }
  return out;
}

/** Newest first, no repeated text. */
function dedupeQuotes(list) {
  const seen = new Set();
  const out = [];
  for (const q of [...list].sort((a, b) => String(b.date).localeCompare(String(a.date)))) {
    if (!q || !q.text) continue;
    const key = normalise(q.text);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push({ text: String(q.text), entryId: q.entryId, date: q.date });
  }
  return out;
}

function entryIdsForDays(days, entryDates) {
  const set = new Set(days);
  return Object.keys(entryDates).filter((id) => set.has(entryDates[id]));
}

/* ── the eight types ─────────────────────────────────────────────────────── */

/**
 * Co-occurrence with lift. "On the {n} days you wrote about {A}, '{B}'
 * appeared in {k}. On the other {m} days: {j}."
 *
 * `lift` is (k/n) ÷ (base rate of B) — how much more often B shows up on A's
 * days than on an average day. 1.0 means "no relationship"; the floor is 1.5.
 */
function cooccurrences(dayTerms, activeDays, labels) {
  const D = activeDays.length;
  const out = [];
  if (D < MIN_DAYS_WITH_TERM + MIN_CONTRAST_DAYS) return out;

  // Days each term appeared on. Terms on fewer than 2 days can never satisfy
  // k >= 2, so drop them before the pairwise pass.
  const termDays = new Map();
  for (const day of activeDays) {
    for (const term of (dayTerms.get(day) || [])) {
      if (!termDays.has(term)) termDays.set(term, new Set());
      termDays.get(term).add(day);
    }
  }
  const terms = [...termDays.keys()].filter((t) => termDays.get(t).size >= 2);

  for (let i = 0; i < terms.length; i++) {
    for (let j = i + 1; j < terms.length; j++) {
      const [t1, t2] = [terms[i], terms[j]];
      // A domain paired with a domain, or an emotion with an emotion, is a
      // co-occurrence the user cannot act on and cannot easily picture. Only
      // cross-kind pairs are surfaced.
      if (prefixOf(t1) === prefixOf(t2)) continue;

      // Orient: which one is the subject of "on the days you wrote about ___".
      let A = t1; let B = t2;
      const s1 = SUBJECT_PREFIXES.indexOf(prefixOf(t1));
      const s2 = SUBJECT_PREFIXES.indexOf(prefixOf(t2));
      const o1 = OBJECT_PREFIXES.indexOf(prefixOf(t1));
      const o2 = OBJECT_PREFIXES.indexOf(prefixOf(t2));
      if (s2 >= 0 && s1 < 0) { A = t2; B = t1; }
      else if (o1 >= 0 && o2 < 0) { A = t2; B = t1; }

      const aDays = termDays.get(A);
      const bDays = termDays.get(B);
      const n = aDays.size;
      const m = D - n;
      if (n < MIN_DAYS_WITH_TERM || m < MIN_CONTRAST_DAYS) continue;

      const coDays = [...aDays].filter((d) => bDays.has(d));
      const k = coDays.length;
      if (k < MIN_CO_DAYS) continue;

      const baseRate = bDays.size / D;
      if (baseRate <= 0) continue;
      const lift = (k / n) / baseRate;
      if (lift < MIN_LIFT) continue;

      const jj = bDays.size - k;
      out.push({
        type: "cooccurrence",
        subject: A,
        object: B,
        terms: [A, B],
        n, m, k, j: jj,
        lift: Math.round(lift * 100) / 100,
        strength: Math.min(3, lift),
        coDays: coDays.sort(),
        aDays: [...aDays].sort(),
      });
    }
  }
  return out;
}

/**
 * Exception — the day the rule did NOT hold.
 *
 * Hangs off an already-emitted co-occurrence, which is what makes it both
 * cheap and honest: an exception is only interesting when there is an
 * established regularity to be an exception TO. Requires the rule to hold on
 * at least two-thirds of its days and to be missed at most twice, so this is
 * "the one time it didn't", not "it's inconsistent".
 *
 * Exceptions outrank problems (R6/de Shazer) — they carry exceptionBonus and
 * win Today's selection.
 */
function exceptionsFrom(cooc) {
  const out = [];
  for (const c of cooc) {
    // An exception asserts an ABSENCE ("the day you wrote about work WITHOUT
    // 'heavy'"). That is only honest for something reliably extracted. A
    // distinctive phrase not being picked up on a given day says nothing about
    // whether the person felt it, so absence-of-a-phrase is never evidence —
    // it would let the app tell someone a day was different when all that
    // differed was the wording they happened to use.
    if (prefixOf(c.object) === "phrase") continue;
    if (c.k < 3) continue; // the rule has to have actually held, repeatedly
    if (c.k / c.n < BAND_DOMINANCE) continue;
    const exceptionDays = c.aDays.filter((d) => !c.coDays.includes(d));
    if (exceptionDays.length < 1 || exceptionDays.length > MAX_EXCEPTIONS) continue;
    out.push({
      type: "exception",
      subject: c.subject,
      object: c.object,
      terms: [c.subject, c.object],
      n: c.n, m: c.m, k: c.k, j: c.j,
      lift: c.lift,
      strength: 2,
      exceptionOf: obsId("cooccurrence", c.terms),
      exceptionDays,
      coDays: c.coDays,
      aDays: c.aDays,
    });
  }
  return out;
}

/** Time band. "{k} of your {n} entries with '{phrase}' were written after 9pm." */
function timeBands(analysesByEntry, entryMeta, entryDates, dayTerms, activeDays, labels) {
  // Entry-grain, not day-grain: this is a claim about when things get WRITTEN.
  const termEntries = new Map();
  for (const [entryId, terms] of analysesByEntry) {
    for (const term of terms) {
      if (!termEntries.has(term)) termEntries.set(term, new Set());
      termEntries.get(term).add(entryId);
    }
  }
  const out = [];
  for (const [term, entryIds] of termEntries) {
    const ids = [...entryIds].filter((id) => entryMeta[id]);
    const n = ids.length;
    if (n < MIN_DAYS_WITH_TERM) continue;
    const counts = {};
    for (const id of ids) counts[entryMeta[id].band] = (counts[entryMeta[id].band] || 0) + 1;
    const [band, k] = Object.entries(counts).sort((a, b) => b[1] - a[1])[0] || [];
    if (!band || k / n < BAND_DOMINANCE) continue;
    // A term that only ever appears when this person writes at all is not an
    // observation about the term — check it beats the person's own baseline.
    const allBandCount = Object.keys(entryMeta)
      .filter((id) => entryMeta[id].band === band).length;
    const allCount = Object.keys(entryMeta).length;
    if (allCount > 0 && allBandCount / allCount >= k / n) continue;
    out.push({
      type: "timeband",
      subject: term,
      object: `band:${band}`,
      terms: [term, `band:${band}`],
      n, m: 0, k, j: 0,
      lift: allCount > 0 ? Math.round(((k / n) / (allBandCount / allCount)) * 100) / 100 : 1,
      strength: Math.min(3, (k / n) / 0.25),
      band,
      entryIdsForTerm: ids,
    });
  }
  return out;
}

/** Weekday length. "Sunday entries are {x}% longer than the rest." */
function weekdays(entryMeta, coverageOk) {
  if (!coverageOk) return [];
  const byWeekday = new Map();
  const withWords = Object.entries(entryMeta).filter(([, m]) => typeof m.words === "number");
  for (const [id, m] of withWords) {
    if (!byWeekday.has(m.weekday)) byWeekday.set(m.weekday, []);
    byWeekday.get(m.weekday).push({ id, words: m.words });
  }
  const out = [];
  for (const [weekday, items] of byWeekday) {
    if (items.length < MIN_WEEKDAY_OCCURRENCES) continue;
    const others = withWords.filter(([, m]) => m.weekday !== weekday);
    if (others.length < MIN_WEEKDAY_OTHERS) continue;
    const mean = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length;
    const mine = mean(items.map((i) => i.words));
    const rest = mean(others.map(([, m]) => m.words));
    if (rest <= 0) continue;
    const pct = Math.round(((mine / rest) - 1) * 100);
    if (Math.abs(pct) < MIN_EFFECT_PCT) continue;
    out.push({
      type: "weekday",
      subject: `weekday:${weekday}`,
      object: "metric:words",
      terms: [`weekday:${weekday}`],
      n: items.length, m: others.length, k: Math.round(mine), j: Math.round(rest),
      lift: Math.round((mine / rest) * 100) / 100,
      strength: Math.min(3, Math.abs(pct) / MIN_EFFECT_PCT),
      weekday, pct,
      entryIdsForTerm: items.map((i) => i.id),
    });
  }
  return out;
}

/** Lag. "The day after you write about {person}, entries are {x}% shorter." */
function lags(dayTerms, activeDays, entryDates, entryMeta, entriesTotal, coverageOk, labels) {
  if (!coverageOk || entriesTotal < MIN_ENTRIES_FOR_LAG) return [];
  const wordsByDay = new Map();
  for (const [id, meta] of Object.entries(entryMeta)) {
    if (typeof meta.words !== "number") continue;
    const day = entryDates[id];
    if (!day) continue;
    if (!wordsByDay.has(day)) wordsByDay.set(day, []);
    wordsByDay.get(day).push(meta.words);
  }
  const dayMean = (d) => {
    const xs = wordsByDay.get(d) || [];
    return xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
  };
  const activeSet = new Set(activeDays);
  const out = [];
  const termDays = new Map();
  for (const day of activeDays) {
    for (const term of (dayTerms.get(day) || [])) {
      if (!["person", "domain"].includes(prefixOf(term))) continue;
      if (!termDays.has(term)) termDays.set(term, new Set());
      termDays.get(term).add(day);
    }
  }
  for (const [term, days] of termDays) {
    const pairs = [];
    for (const d of days) {
      const next = activeDays.find((x) => daysBetweenKeys(d, x) === 1);
      if (next && activeSet.has(next)) {
        const w = dayMean(next);
        if (w != null) pairs.push(w);
      }
    }
    if (pairs.length < MIN_LAG_PAIRS) continue;
    const followerDays = new Set();
    for (const d of days) {
      const next = activeDays.find((x) => daysBetweenKeys(d, x) === 1);
      if (next) followerDays.add(next);
    }
    const baseline = activeDays.filter((d) => !followerDays.has(d))
      .map(dayMean).filter((x) => x != null);
    if (baseline.length < MIN_CONTRAST_DAYS) continue;
    const mean = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length;
    const after = mean(pairs);
    const rest = mean(baseline);
    if (rest <= 0) continue;
    const pct = Math.round(((after / rest) - 1) * 100);
    if (Math.abs(pct) < MIN_EFFECT_PCT) continue;
    out.push({
      type: "lag",
      subject: term,
      object: "metric:words",
      terms: [term, "metric:words"],
      n: pairs.length, m: baseline.length, k: Math.round(after), j: Math.round(rest),
      lift: Math.round((after / rest) * 100) / 100,
      strength: Math.min(3, Math.abs(pct) / MIN_EFFECT_PCT),
      pct,
    });
  }
  return out;
}

/**
 * Callback — then / now. The "it remembers" moment, made exact.
 *
 * A term written today that also appeared at least a fortnight ago, with both
 * quotes verbatim. This is the single most-praised Rosebud behaviour and the
 * one Spilr's provenance can do precisely rather than impressionistically.
 */
function callbacks(dayTerms, activeDays, todayKey, termQuotes, labels) {
  const todayTerms = dayTerms.get(todayKey);
  if (!todayTerms) return [];
  const out = [];
  for (const term of todayTerms) {
    // Body signals are excluded on purpose: "'tight chest'. Today: 'tight
    // chest'." is a repetition, not a callback. A callback has to put two
    // different moments side by side.
    if (!["phrase", "emotion", "person"].includes(prefixOf(term))) continue;
    const older = activeDays
      .filter((d) => d !== todayKey && (dayTerms.get(d) || new Set()).has(term))
      .filter((d) => daysBetweenKeys(d, todayKey) >= CALLBACK_MIN_DAYS_APART)
      .sort();
    if (older.length === 0) continue;
    const thenDay = older[0];
    const thenQuotes = quotesFor(term, termQuotes, 1, new Set([thenDay]));
    const nowQuotes = quotesFor(term, termQuotes, 1, new Set([todayKey]));
    if (!thenQuotes.length || !nowQuotes.length) continue;
    // Then and now must actually differ. Identical strings mean the "quote" is
    // the tracked term itself echoed twice, which reads as a bug, not memory.
    if (normalise(thenQuotes[0].text) === normalise(nowQuotes[0].text)) continue;
    out.push({
      type: "callback",
      subject: term,
      object: null,
      terms: [term],
      n: older.length + 1, m: 0, k: 1, j: 0,
      lift: 1,
      strength: 2,
      daysApart: daysBetweenKeys(thenDay, todayKey),
      thenQuote: thenQuotes[0],
      nowQuote: nowQuotes[0],
    });
  }
  return out;
}

/** Delta — a measured before/after drop from a guided template, plus its run
 *  length. The only observation in the set the user themselves supplied both
 *  numbers for, which makes it the least arguable thing on the screen. */
function deltas(templateRuns) {
  if (!templateRuns || templateRuns.length === 0) return [];
  const sorted = [...templateRuns].sort((a, b) => String(a.date).localeCompare(String(b.date)));
  const last = sorted[sorted.length - 1];
  if (!last || !(last.after < last.before)) return [];
  let run = 0;
  for (let i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i].after < sorted[i].before) run++; else break;
  }
  return [{
    type: "delta",
    subject: `template:${last.templateId}`,
    object: "metric:intensity",
    terms: [`template:${last.templateId}`, last.date],
    n: run, m: 0, k: last.after, j: last.before,
    lift: last.before > 0 ? Math.round((last.after / last.before) * 100) / 100 : 1,
    strength: 2,
    before: last.before,
    after: last.after,
    runLength: run,
    entryIdsForTerm: [last.entryId],
    date: last.date,
  }];
}

/** Streak / first / last. "First time 'calm' has appeared since 12 Aug." */
function streaks(dayTerms, activeDays, weekKeys, firstSeen) {
  const weekSet = new Set(weekKeys);
  const out = [];
  const seenThisWeek = new Set();
  for (const day of weekKeys) {
    for (const term of (dayTerms.get(day) || [])) seenThisWeek.add(term);
  }
  for (const term of seenThisWeek) {
    if (!["phrase", "emotion", "body"].includes(prefixOf(term))) continue;
    const priorDays = activeDays
      .filter((d) => !weekSet.has(d) && (dayTerms.get(d) || new Set()).has(term))
      .sort();
    if (priorDays.length === 0) continue;
    const lastBefore = priorDays[priorDays.length - 1];
    const thisWeekDay = weekKeys.filter((d) => (dayTerms.get(d) || new Set()).has(term)).sort()[0];
    if (!thisWeekDay) continue;
    const gap = daysBetweenKeys(lastBefore, thisWeekDay);
    if (gap < STREAK_MIN_GAP_DAYS) continue;
    out.push({
      type: "streak",
      subject: term,
      object: null,
      terms: [term],
      n: priorDays.length + 1, m: 0, k: gap, j: 0,
      lift: 1,
      strength: 1.5,
      gapDays: gap,
      lastBefore,
      returnedOn: thisWeekDay,
      firstEver: (firstSeen && firstSeen[term]) || priorDays[0],
    });
  }
  return out;
}

/* ── rendering ───────────────────────────────────────────────────────────── */

/**
 * The observation, said out loud, deterministically.
 *
 * This string is stored on the doc and is what the client renders when no
 * model line exists or the model's line fails lint. It is deliberately good
 * enough to ship on its own — §5.2 step 4 shows the observation alone, and the
 * PRD's position is that the observation IS already a good line.
 */
function renderObservation(o, labels) {
  const A = () => speak(o.subject, labels);
  const B = () => speak(o.object, labels);
  switch (o.type) {
    case "cooccurrence":
      return `On the ${o.n} days you wrote about ${A()}, ${B()} appeared in ${o.k}. On the other ${o.m} days: ${o.j}.`;
    case "exception": {
      const d = o.exceptionDays[0];
      return o.exceptionDays.length === 1
        ? `${shortDate(d)} is the only day this month you wrote about ${A()} without ${B()}.`
        : `${o.exceptionDays.map(shortDate).join(" and ")} are the only days you wrote about ${A()} without ${B()}.`;
    }
    case "timeband":
      return `${o.k} of your ${o.n} entries with ${A()} were written ${BAND_PHRASE[o.band] || "then"}.`;
    case "weekday":
      return `${WEEKDAY_NAME[o.weekday]} entries are ${Math.abs(o.pct)}% ${o.pct > 0 ? "longer" : "shorter"} than the rest.`;
    case "lag":
      return `The day after you write about ${A()}, entries are ${Math.abs(o.pct)}% ${o.pct > 0 ? "longer" : "shorter"}.`;
    case "callback":
      return `${shortDate(o.thenQuote.date)}: "${trimQuote(o.thenQuote.text)}". Today: "${trimQuote(o.nowQuote.text)}". ${o.daysApart} days apart.`;
    case "delta":
      return o.runLength > 1
        ? `Thought record: ${o.before} → ${o.after}. That's your ${ordinal(o.runLength)} drop in a row.`
        : `Thought record: ${o.before} → ${o.after}.`;
    case "streak":
      return `First time ${A()} has appeared since ${shortDate(o.lastBefore)}.`;
    default:
      return "";
  }
}

/** Strip trailing sentence punctuation from a span that is about to be
 *  wrapped in quotes, so a quoted sentence doesn't render as `"...it.".` */
function trimQuote(text) {
  return String(text || "").trim().replace(/[.,;:]+$/, "");
}

function ordinal(n) {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

/* ── scoring ─────────────────────────────────────────────────────────────── */

/**
 * ObservationScore — which one observation gets today.
 *
 * score = strength × log(1+n) × recency × novelty × exceptionBonus − shownPenalty
 *
 * `novelty` is Jaccard distance from anything shown in the last 14 days, so a
 * true-but-already-said observation loses to a weaker fresh one — the single
 * most important term for making a daily surface bearable. A missing shown
 * record counts as maximum novelty, never zero: users on older builds have no
 * `terms` field on their mirrorShown docs, and treating that as "identical to
 * everything" would silence them completely.
 */
function observationScore(o, { now, todayKey, shownHistory }) {
  const strength = Math.max(1, Math.min(3, o.strength || 1));
  const nTerm = Math.log(1 + Math.max(1, o.n || 1));

  const newest = newestDateOf(o);
  const ageDays = newest ? Math.max(0, daysBetweenKeys(newest, todayKey)) : 7;
  const recency = Math.exp(-ageDays / 7);

  let maxOverlap = 0;
  let shownPenalty = 0;
  const myTerms = new Set(o.terms || []);
  for (const rec of (shownHistory || [])) {
    const days = rec.date ? daysBetweenKeys(rec.date, todayKey) : 999;
    if (days > 30) continue;
    if (rec.observationId && rec.observationId === o.id) {
      shownPenalty = Math.max(shownPenalty, days <= 14 ? 2.0 : 0.5);
    }
    if (Array.isArray(rec.terms) && rec.terms.length && days <= 14) {
      maxOverlap = Math.max(maxOverlap, jaccard(myTerms, new Set(rec.terms)));
    }
  }
  const novelty = 1 - maxOverlap;
  const exceptionBonus = (o.type === "exception" || o.type === "delta") ? 1.5 : 1.0;

  const score = strength * nTerm * recency * novelty * exceptionBonus - shownPenalty;
  return Math.round(score * 1000) / 1000;
}

function newestDateOf(o) {
  const candidates = [];
  if (o.coDays) candidates.push(...o.coDays);
  if (o.aDays) candidates.push(...o.aDays);
  if (o.exceptionDays) candidates.push(...o.exceptionDays);
  if (o.nowQuote) candidates.push(o.nowQuote.date);
  if (o.returnedOn) candidates.push(o.returnedOn);
  if (o.date) candidates.push(o.date);
  const sorted = candidates.filter(Boolean).sort();
  return sorted.length ? sorted[sorted.length - 1] : null;
}

/* ── the job ─────────────────────────────────────────────────────────────── */

/**
 * Compute every observation for one user from their Tier-0 facts.
 *
 * @param {object} facts        users/{uid}/derived/facts
 * @param {Array}  analyses     entryAnalyses in the window
 * @param {object} opts         { now, todayKey, weekKeys, activeDays, shownHistory }
 * @returns {Array} observation docs, scored and sorted desc
 */
function computeObservations(facts, analyses, opts) {
  const { todayKey, weekKeys, shownHistory } = opts;
  const { buildDayTerms } = require("./facts");
  const { dayTerms, termQuotes, termLabels, dayQuotes } = buildDayTerms(analyses, facts.entryDates);

  const activeDays = [...new Set(Object.values(facts.entryDates || {}))].sort();
  const windowDays = new Set(opts.windowDays || activeDays);
  const daysInWindow = activeDays.filter((d) => windowDays.has(d));

  // entryId -> Set(term), for the entry-grain types.
  const analysesByEntry = new Map();
  for (const a of analyses) {
    const day = facts.entryDates[a.entryId];
    if (!day || !windowDays.has(day)) continue;
    const terms = new Set();
    for (const d of (a.lifeDomains || [])) terms.add(`domain:${normalise(d)}`);
    for (const e of (a.explicitEmotions || [])) terms.add(`emotion:${normalise(e)}`);
    for (const p of (a.phrasesToTrack || [])) terms.add(`phrase:${normalise(p)}`);
    for (const b of (a.bodySignals || [])) terms.add(`body:${normalise(b)}`);
    for (const p of (a.people || [])) { if (p && p.name) terms.add(`person:${normalise(p.name)}`); }
    analysesByEntry.set(a.entryId, terms);
  }

  const cov = facts.coverage || {};
  const coverageOk = cov.entriesInWindow > 0 &&
    (cov.wordCountKnown / cov.entriesInWindow) >= WORDCOUNT_COVERAGE_FLOOR;

  const cooc = cooccurrences(dayTerms, daysInWindow, termLabels);
  const raw = [
    ...cooc,
    ...exceptionsFrom(cooc),
    ...timeBands(analysesByEntry, facts.entryMeta, facts.entryDates, dayTerms, daysInWindow, termLabels),
    ...weekdays(facts.entryMeta, coverageOk),
    ...lags(dayTerms, daysInWindow, facts.entryDates, facts.entryMeta,
      facts.entriesTotal || 0, coverageOk, termLabels),
    ...callbacks(dayTerms, daysInWindow, todayKey, termQuotes, termLabels),
    ...deltas(facts.templateRuns),
    ...streaks(dayTerms, daysInWindow, weekKeys || [], facts.firstSeen),
  ];

  const out = raw.map((o) => {
    const id = obsId(o.type, o.terms);
    const days = o.exceptionDays || o.coDays || o.aDays || null;
    const entryIds = o.entryIdsForTerm
      || (days ? entryIdsForDays(days, facts.entryDates) : []);
    const contrastEntryIds = o.type === "exception"
      ? entryIdsForDays(o.coDays || [], facts.entryDates)
      : (o.aDays ? entryIdsForDays(
        daysInWindow.filter((d) => !o.aDays.includes(d)), facts.entryDates) : []);

    let quotes;
    if (o.type === "callback") {
      quotes = [o.thenQuote, o.nowQuote];
    } else if (o.type === "exception") {
      // The receipt for an exception is what the person wrote ON THE DAY IT
      // DIDN'T HAPPEN — "honestly just lucky and loved tonight". Looking it up
      // by the absent term returns nothing by definition, which is how this
      // shipped with no receipt at all the first time.
      quotes = dedupeQuotes((o.exceptionDays || [])
        .flatMap((d) => dayQuotes.get(d) || [])).slice(0, 3);
    } else if (o.type === "delta") {
      // The numbers here are the person's OWN before/after ratings, so the
      // receipt is what they wrote in the same sitting.
      quotes = dedupeQuotes(dayQuotes.get(o.date) || []).slice(0, 2);
    } else {
      quotes = quotesFor(o.object || o.subject, termQuotes, 3, null);
      if (quotes.length === 0) quotes = quotesFor(o.subject, termQuotes, 3, null);
      // Last resort: any receipt from a day this actually happened, so a
      // CONTENT observation is never shown with a number and no words behind
      // it. `weekday` and `lag` are exempt by nature — they are facts about
      // when and how much this person writes, not about what they said, and
      // attaching an arbitrary quote to one would imply a connection the
      // arithmetic never made.
      if (quotes.length === 0 && !["weekday", "lag"].includes(o.type)) {
        const days = o.coDays || o.aDays || [];
        quotes = dedupeQuotes(days.flatMap((d) => dayQuotes.get(d) || [])).slice(0, 3);
      }
    }

    const doc = {
      schemaVersion: SCHEMA_VERSION,
      id,
      type: o.type,
      subject: o.subject || null,
      object: o.object || null,
      terms: o.terms,
      n: o.n, m: o.m, k: o.k, j: o.j,
      lift: o.lift,
      strength: Math.round((o.strength || 1) * 100) / 100,
      exceptionOf: o.exceptionOf || null,
      entryIds: entryIds.slice(0, 30),
      contrastEntryIds: contrastEntryIds.slice(0, 30),
      quotes: quotes.slice(0, 3),
      window: {
        days: (opts.windowDays || activeDays).length,
        start: daysInWindow[0] || null,
        end: daysInWindow[daysInWindow.length - 1] || null,
      },
    };
    // Type-specific payload the proof sheet and renderer need.
    for (const key of ["band", "weekday", "pct", "daysApart", "thenQuote", "nowQuote",
      "before", "after", "runLength", "gapDays", "lastBefore", "returnedOn",
      "firstEver", "exceptionDays", "date"]) {
      if (o[key] !== undefined) doc[key] = o[key];
    }
    doc.templateText = renderObservation(o, termLabels);
    doc.score = observationScore({ ...o, id }, { now: opts.now, todayKey, shownHistory });
    return doc;
  })
    // A renderer that produced nothing must never reach the user as an empty
    // card; drop it here rather than guarding at every read site.
    .filter((d) => d.templateText && d.templateText.length > 0)
    .sort((a, b) => b.score - a.score);

  // Two different observations can render to the SAME sentence — "the day
  // after you write about work" and "...about Priya" are distinct facts with
  // identical wording when Priya only ever appears on work days. Keep the
  // highest-scoring one; the rest are noise that would eventually surface as
  // an apparent repeat.
  const seenText = new Set();
  const deduped = [];
  for (const d of out) {
    const key = normalise(d.templateText);
    if (seenText.has(key)) continue;
    seenText.add(key);
    deduped.push(d);
  }
  return deduped;
}

module.exports = {
  SCHEMA_VERSION,
  computeObservations,
  observationScore,
  renderObservation,
  obsId,
  speak,
  // exported for tests
  cooccurrences,
  exceptionsFrom,
  timeBands,
  weekdays,
  lags,
  callbacks,
  deltas,
  streaks,
  thresholds: {
    MIN_DAYS_WITH_TERM, MIN_CONTRAST_DAYS, MIN_LIFT, MIN_CO_DAYS,
    BAND_DOMINANCE, MIN_EFFECT_PCT, MIN_LAG_PAIRS, MIN_ENTRIES_FOR_LAG,
    CALLBACK_MIN_DAYS_APART, STREAK_MIN_GAP_DAYS, MAX_EXCEPTIONS,
  },
};
