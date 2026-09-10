/* lint.js — the copy contract, enforced in code (mirror-v3-prd-2026-09-10.md §6).
 *
 * "The model phrases; it does not decide." Selection, thresholds and dedup are
 * arithmetic; this file is the last gate before anything the model wrote
 * reaches a person. A line that fails is NOT softened and retried — the
 * deterministic observation is shown instead, because the observation is
 * already a good line.
 *
 * Pure. Every rule is a pure function of (text, context), which is what makes
 * the reject log a prompt-quality dashboard rather than a mystery.
 */

"use strict";

const {
  normalise, contentWords, jaccard, hasVerbatimOverlap, readingGrade,
} = require("./text");

/* ── word lists ──────────────────────────────────────────────────────────── */

// KEEP IN SYNC WITH SpilrVoice.bannedPhrases (DailyJournal/Home/SpilrVoice.swift).
// Identity language and clinical terms — the two things that make an insight
// feel like a fortune cookie instead of a good therapist.
const BANNED_SUBSTRINGS = [
  "you are someone who", "you're someone who", "you always", "you never",
  "you are a person who", "this is who you are", "the kind of person who",
  "attachment style", "defense mechanism", "defence mechanism",
  "dissociation", "dissociat", "trauma", "disorder", "diagnos",
  "depression", "depressed", "anxiety disorder", "bipolar", "ptsd", "ocd",
  "narcissi", "codependen", "burnout", "burnt out", "self-sabotage",
  "dysregulat", "gaslighting",
];

// The pop-psychology label lint. The rule is: the taxonomy may be used to FIND
// the pattern, never to STATE it.
const BANNED_LABELS = [
  "catastrophis", "catastrophiz", "all-or-nothing", "all or nothing thinking",
  "black-and-white thinking", "black and white thinking", "mind reading",
  "mind-reading", "overgeneralis", "overgeneraliz", "should statement",
  "emotional reasoning", "personalis", "personaliz",
  "cognitive distortion", "thinking trap", "thinking error", "core belief",
  "limiting belief", "negative self-talk", "inner critic",
  "people pleas", "people-pleas", "perfectionis", "imposter syndrome",
  "impostor syndrome", "fear of failure", "fear of abandonment",
  "fear of success", "scarcity mindset", "growth mindset", "fixed mindset",
  "your worth is tied", "worth is tied to", "tied to your productivity",
  "seeking external validation", "conflict avoidant", "conflict-avoidant",
  "emotionally unavailable", "boundary issues", "attachment wound",
  "inner child", "shadow work", "love language", "trigger warning",
  "high-functioning", "high functioning",
];

/**
 * The metaphor list — every one of these is lifted from a real line in the
 * 9 Sept screenshots or is the same move wearing a different noun.
 *
 * DELIBERATELY NOT IMPLEMENTED, contra §6: "`space` as a noun" and bare
 * "`hold`". Both need part-of-speech tagging to distinguish "hold space" from
 * "hold the report", and a lint that rejects correct lines trains you to
 * disable the lint. Grow this list from the reject log instead — which is what
 * §6 itself recommends.
 */
const METAPHORS = [
  "armor", "armour", "terror", "ledger", "landscape", "journey", "navigate",
  "hold space", "nervous system", "revved", "warding", "tapestry", "unravel",
  "peel back", "sit with", "weight of", "cocoon", "battlefield", "storm cloud",
];

const HEDGE_WORDS = /\b(may|might|seems?|perhaps|possibly)\b/gi;

// Observational voice, not character claims (R4 — self-distancing). Extended
// beyond the original three with §6's "you tend" / "your (need|inability|fear)".
const TRAIT_PHRASING =
  /\byou (are|'re) (someone|a person|the kind of person|a|an)\b|\byou always\b|\byou never\b|\bthis is who you are\b|\byou tend\b|\byour (need|inability|fear|failure) (to|for)\b/i;

// A last clause that "lands somewhere" — a comparison, a question, or a number.
const COMPARISON_MARKER =
  /\b(than|more|less|fewer|instead|except|but|though|although|only|first|still|again|apart)\b/i;

function tripsBannedLint(text) {
  const h = normalise(text);
  return BANNED_SUBSTRINGS.some((p) => h.includes(p));
}
function tripsLabelLint(text) {
  const h = normalise(text);
  return BANNED_LABELS.some((p) => h.includes(p));
}
function findMetaphor(text) {
  const h = normalise(text);
  return METAPHORS.find((p) => h.includes(p)) || null;
}
function findBanned(text) {
  const h = normalise(text);
  return BANNED_SUBSTRINGS.find((p) => h.includes(p)) ||
    BANNED_LABELS.find((p) => h.includes(p)) || null;
}

/* ── per-surface rule table ──────────────────────────────────────────────── */

const KINDS = {
  reading: {
    maxChars: 140, singleSentence: true, maxHedges: 1,
    requireSpecificity: true, maxGrade: 8, requireQuestionEnd: false,
  },
  threadTitle: {
    maxChars: 45, singleSentence: true, maxHedges: 0,
    requireSpecificity: false, maxGrade: 8, requireQuestionEnd: false,
    noTrailingPeriod: true,
  },
  letter: {
    maxWords: 80, singleSentence: false, maxHedges: 3,
    requireSpecificity: true, maxGrade: 8, requireQuestionEnd: true,
  },
  firstSeven: {
    maxChars: 200, singleSentence: false, maxHedges: 2,
    requireSpecificity: true, maxGrade: 8, requireQuestionEnd: false,
  },
};

/**
 * Does the line contain something the user could check — one of their own
 * quoted words, a number that appears in the observation, or a date?
 *
 * This is §6's first row and the antidote to Forer (R2): a line that could be
 * about anyone will FEEL accurate and teach nothing. The three sub-checks are
 * OR'd because a line built on "5 of your 6" is just as checkable as one built
 * on a verbatim phrase.
 */
function hasSpecificity(text, observation) {
  if (!observation) return true; // nothing to check against — don't block
  for (const q of (observation.quotes || [])) {
    if (q && q.text && hasVerbatimOverlap(text, q.text, 3)) return true;
  }
  const numbers = String(text).match(/\d+/g) || [];
  if (numbers.length) {
    const known = new Set([observation.n, observation.m, observation.k, observation.j,
      observation.pct, observation.daysApart, observation.before, observation.after,
      observation.runLength, observation.gapDays]
      .filter((x) => typeof x === "number")
      .map((x) => String(Math.abs(x))));
    if (numbers.some((x) => known.has(x))) return true;
    // A date like "12 Aug" also counts.
    if (/\b\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i.test(text)) return true;
  }
  return false;
}

/**
 * Run the copy contract.
 *
 * @param {string} text
 * @param {object} ctx  { kind, observation, sourceSummary, enforceEndsNegative }
 * @returns {{ok: boolean, reason: string|null, term: string|null}}
 *
 * Rules are evaluated cheapest-first so the FIRST failure is the one logged —
 * that is what makes the reject histogram interpretable.
 */
function lintCopy(text, ctx = {}) {
  const kind = ctx.kind || "reading";
  const rules = KINDS[kind] || KINDS.reading;
  const trimmed = String(text || "").trim();
  const fail = (reason, term) => ({ ok: false, reason, term: term || null });

  if (!trimmed) return fail("empty");

  if (rules.maxChars && trimmed.length > rules.maxChars) return fail("too_long");
  if (rules.maxWords) {
    const words = trimmed.split(/\s+/).filter(Boolean).length;
    if (words > rules.maxWords) return fail("too_long");
  }

  const sentenceEnders = (trimmed.match(/[.!?](?=\s|$)/g) || []).length;
  if (rules.singleSentence && sentenceEnders > 1) return fail("multi_sentence");
  if (rules.noTrailingPeriod && /\.$/.test(trimmed)) return fail("trailing_period");
  if (rules.requireQuestionEnd && !trimmed.endsWith("?")) return fail("no_question");

  const hedgeCount = (trimmed.match(HEDGE_WORDS) || []).length;
  if (hedgeCount > rules.maxHedges) return fail("over_hedged");

  if (TRAIT_PHRASING.test(trimmed)) return fail("trait_phrasing");

  const banned = findBanned(trimmed);
  if (banned) return fail("banned_term_or_label", banned);

  const metaphor = findMetaphor(trimmed);
  if (metaphor) return fail("metaphor", metaphor);

  const grade = readingGrade(trimmed);
  if (rules.maxGrade && grade > rules.maxGrade) return fail("reading_level");

  if (rules.requireSpecificity && !hasSpecificity(trimmed, ctx.observation)) {
    return fail("no_specificity");
  }

  // Legacy receipt anchoring, kept for the hypothesis-driven card path that
  // still calls through lintMirrorLine.
  if (ctx.receiptQuote && !hasVerbatimOverlap(trimmed, ctx.receiptQuote)) {
    return fail("no_receipt_anchor");
  }

  if (ctx.sourceSummary) {
    const overlap = jaccard(contentWords(trimmed), contentWords(ctx.sourceSummary));
    if (overlap > 0.7) return fail("paraphrase");
  }

  // "Never end on the negative" (R5/R6). The fuzziest rule in §6 and the one
  // most likely to reject good copy, so it ships LOG-ONLY: the caller records
  // `endsNegative` and can flip `enforceEndsNegative` on once a week of reject
  // logs shows the false-positive rate is acceptable.
  const endsNegative = !endsWell(trimmed, ctx.observation);
  if (endsNegative && ctx.enforceEndsNegative) return fail("ends_negative");

  return { ok: true, reason: null, term: null, endsNegative, grade };
}

/** The last clause must be a question, a comparison, or carry a number/date —
 *  or the observation itself must already be good news (an exception or a
 *  measured improvement). */
function endsWell(text, observation) {
  const t = String(text).trim();
  if (t.endsWith("?")) return true;
  if (observation && (observation.type === "exception" || observation.type === "delta")) return true;
  // Split on " and " as well as punctuation. "Heavy turned up on 5 work days
  // and it flattened you" ends on the bad half even though a number appears
  // earlier in the sentence — checking only the text after a comma would miss
  // every un-punctuated version of exactly that shape. "but"/"though" stay
  // markers rather than splitters: they signal the pivot TO the good half.
  const parts = t.split(/[,;—–]|\s+and\s+/i);
  const last = parts[parts.length - 1] || t;
  if (COMPARISON_MARKER.test(last)) return true;
  if (/\d/.test(last)) return true;
  return false;
}

/** Back-compat wrapper so the existing mirror-card path keeps working
 *  unchanged while the reading path moves to lintCopy. */
function lintMirrorLine(line, { receiptQuote, sourceSummary } = {}) {
  const r = lintCopy(line, { kind: "reading", receiptQuote, sourceSummary });
  // The card path has no observation to check specificity against; the
  // receipt anchor is its equivalent and is checked above.
  if (!r.ok && r.reason === "no_specificity") return { ok: true, reason: null };
  return { ok: r.ok, reason: r.reason };
}

module.exports = {
  lintCopy,
  lintMirrorLine,
  tripsBannedLint,
  tripsLabelLint,
  findMetaphor,
  findBanned,
  hasSpecificity,
  endsWell,
  BANNED_SUBSTRINGS,
  BANNED_LABELS,
  METAPHORS,
  HEDGE_WORDS,
  TRAIT_PHRASING,
  KINDS,
};
