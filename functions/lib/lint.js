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
  MIRROR_STOPWORDS,
} = require("./text");
const CONCRETENESS = require("./data/concreteness.json");

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

/* ── Mirror v3.1 §8: the nine-rule lint for Prompt M ─────────────────────── */

// Rule 4 (part 1): a noun that names a category rather than a thing. The
// v3.0 METAPHORS list already caught most of the FIGURATIVE version of this
// failure ("the fairness ledger"); this catches the literal abstract noun
// even when it isn't dressed up as an image ("keeps you in a protective
// loop"). PARITY note: several of these already sit on SpilrVoice's client
// list too, but v3.1 needs them enforced on the specific mirrorLine kind.
const CATEGORY_NOUNS = [
  "pattern", "loop", "dynamic", "tendency", "capacity", "energy", "space",
  "journey", "nervous system", "bandwidth",
];

// Rule 4 (part 2): the soft-clinical vocabulary — words a wellness account
// would use, which read as insight but are actually a taxonomy label with
// the edges filed off. Distinct from BANNED_SUBSTRINGS' harder clinical
// terms (dissociation, trauma, disorder) because these ones don't even sound
// alarming, which is exactly why they slip past a casual read.
const SOFT_CLINICAL = [
  "regulate", "hold space", "sit with", "unpack", "process", "avoidant",
  "protective", "attachment",
];

// Rule 8: reassurance. Its function is to make the reader feel good, not to
// tell them anything — the sycophancy failure (Wong, Wan & Lew 2025).
const REASSURANCE = [
  "neither is wrong", "neither one is wrong", "that's okay", "thats okay",
  "nothing wrong with", "you should", "you're doing great",
  "youre doing great", "good job", "well done", "proud of you",
  "that's healthy", "thats healthy", "that's valid", "thats valid",
];

// Rule 6 (mirrorLine only — narrower than the v3.0 TRAIT_PHRASING above,
// because v3.1 makes second person REQUIRED; this regex catches only the
// label form, never the pronoun itself).
const MIRROR_TRAIT_PHRASING = /\byou('re| are) (a|an|so|very|someone)\b|\byou always\b|\byou never\b/i;

// Rule 7: a first-person hedge is a HARD fail on mirrorLine, not a count —
// Kim et al. (2024) found it costs agreement, confidence AND willingness to
// use the app, where the impersonal form ("this looks like") costs nothing.
const FIRST_PERSON_HEDGE = /\bI (think|feel|wonder|suspect|might)\b/i;

function contentTokens(text) {
  return normalise(text).split(/[^a-z0-9']+/).filter(
    (w) => w.length >= 4 && !MIRROR_STOPWORDS.has(w)
  );
}

function concretenessOf(word) {
  const w = normalise(word);
  return Object.prototype.hasOwnProperty.call(CONCRETENESS, w) ? CONCRETENESS[w] : null;
}

/** Rule 3: mean Brysbaert concreteness of content words >= 3.0; no content
 *  word below 2.0 unless it is the user's own quoted word. Words the norms
 *  don't cover are skipped rather than failing the line — an unscored word
 *  is not evidence either way. */
function concretenessCheck(text, quotedText) {
  const quotedWords = new Set(contentTokens(quotedText || ""));
  const known = contentTokens(text)
    .map((t) => ({ t, c: concretenessOf(t) }))
    .filter((x) => x.c != null);
  if (known.length === 0) return { ok: true };
  const mean = known.reduce((s, x) => s + x.c, 0) / known.length;
  if (mean < 3.0) return { ok: false, term: null, mean };
  const low = known.find((x) => x.c < 2.0 && !quotedWords.has(x.t));
  if (low) return { ok: false, term: low.t, mean };
  return { ok: true, mean };
}

/** Rule 5: at most one figurative token not already in the user's own
 *  vocabulary. Two such hits (or one that isn't theirs) fails — an image is
 *  only earned when it replaces words the person hasn't used themselves. */
function figurativeHits(text, vocabTop200) {
  const h = normalise(text);
  const vocab = new Set((vocabTop200 || []).map(normalise));
  return METAPHORS.filter((p) => h.includes(p) && !vocab.has(normalise(p)));
}

/** Rule 9: strip quotes, proper nouns and numerals; what's left must contain
 *  >= 2 tokens from this user's own top-200 vocabulary. A line that survives
 *  stripping into something universally true is Barnum by construction — the
 *  swap test names the failure the whole language spec exists to prevent. */
function swapTestFails(originalText, vocabTop200) {
  if (!vocabTop200 || vocabTop200.length === 0) return false; // nothing to check against
  let stripped = String(originalText)
    .replace(/["“][^"”]*["”]/g, " ")
    .replace(/'[^']*'/g, " ")
    .replace(/\d+/g, " ");
  const words = stripped.split(/\s+/);
  const isSentenceStart = (i) => i === 0 || /[.!?]$/.test(words[i - 1] || "");
  const kept = words.filter((w, i) => {
    if (!w) return false;
    if (/^[A-Z]/.test(w) && !isSentenceStart(i)) return false; // proper-noun proxy
    return true;
  });
  const vocab = new Set((vocabTop200 || []).map(normalise));
  const overlap = new Set(contentTokens(kept.join(" ")).filter((t) => vocab.has(t)));
  return overlap.size < 2;
}

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

/** Rule 4: the category-noun list plus the soft-clinical vocabulary, on top
 *  of the existing BANNED_SUBSTRINGS/BANNED_LABELS — mirrorLine's version of
 *  findBanned, kept separate so the other kinds' behaviour never shifts. */
function findCategoryOrClinical(text) {
  const h = normalise(text);
  return CATEGORY_NOUNS.find((p) => h.includes(p)) ||
    SOFT_CLINICAL.find((p) => h.includes(p)) || null;
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
  // Prompt M's line (mirror-v3.1 §8). Flesch-Kincaid is deliberately absent —
  // on a 3-sentence string it is noise, and it scored "when the future goes
  // blank" as easy reading; the length caps and the concreteness floor do
  // its job properly. Checked by lintMirrorM, not lintCopy, because Prompt
  // M's output is a structured object, not a single string.
  mirrorLine: {
    maxWords: 40, maxSentences: 3, maxWordsPerSentence: 18, maxHedges: 1,
  },
  mirrorQuestion: {
    maxWords: 20, singleSentence: true, requireQuestionEnd: true,
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

/**
 * The nine-rule lint for Prompt M's LINE text alone (mirror-v3.1 §8, rules
 * 1/3/4/5/6/7/8 plus the receipt check). Kept separate from lintCopy because
 * several of these rules (concreteness, one-image-against-this-user's-own-
 * vocabulary, the swap test) need data lintCopy's other callers don't carry
 * (`vocabTop200`, the receipt quote as a positive exemption for rule 3). Rule
 * 2 (receipt) and rule 9 (swap test) both need the ORIGINAL line text, not a
 * normalised copy, so this operates on `text` directly rather than routing
 * through lintCopy's shared pipeline.
 *
 * @param {string} text
 * @param {object} ctx  { receiptQuote, vocabTop200 }
 * @returns {{ok:boolean, rule:number|null, reason:string|null, term:string|null}}
 */
function lintMirrorLineText(text, ctx = {}) {
  const trimmed = String(text || "").trim();
  const fail = (rule, reason, term) => ({ ok: false, rule, reason, term: term || null });
  if (!trimmed) return fail(1, "empty");

  const rules = KINDS.mirrorLine;

  // Rule 1 — length.
  const words = trimmed.split(/\s+/).filter(Boolean);
  if (words.length > rules.maxWords) return fail(1, "too_long");
  const sentences = trimmed.split(/(?<=[.!?])\s+/).filter(Boolean);
  if (sentences.length > rules.maxSentences) return fail(1, "too_many_sentences");
  for (const s of sentences) {
    const n = s.split(/\s+/).filter(Boolean).length;
    if (n > rules.maxWordsPerSentence) return fail(1, "sentence_too_long");
  }

  // Rule 2 — receipt: a verbatim phrase from the receipt quote.
  if (ctx.receiptQuote && !hasVerbatimOverlap(trimmed, ctx.receiptQuote, 3)) {
    return fail(2, "no_receipt_anchor");
  }

  // Rule 3 — concreteness floor.
  const conc = concretenessCheck(trimmed, ctx.receiptQuote);
  if (!conc.ok) return fail(3, "concreteness_floor", conc.term);

  // Rule 6 — trait without situation, checked BEFORE rule 4's findBanned:
  // BANNED_SUBSTRINGS (shared with the client, v3.0-era) already contains
  // several of these exact phrases ("you are someone who", "you always",
  // "you never") because v3.0 banned second person outright. v3.1 keeps
  // banning the LABEL form but now requires second person, so this specific
  // check must win the attribution — otherwise every trait-phrasing failure
  // would silently log as rule 4 and the reject histogram would never show
  // rule 6 firing at all.
  if (MIRROR_TRAIT_PHRASING.test(trimmed)) return fail(6, "trait_phrasing");

  // Rule 4 — banned category/clinical nouns, plus the existing hard bans.
  const banned = findCategoryOrClinical(trimmed) || findBanned(trimmed);
  if (banned) return fail(4, "banned_noun", banned);

  // Rule 5 — one image at most, and only if it's not already this user's word.
  const figurative = figurativeHits(trimmed, ctx.vocabTop200);
  if (figurative.length > 1) return fail(5, "more_than_one_image", figurative[1]);

  // Rule 7 — hedge form: a first-person hedge is a hard fail regardless of
  // count; an impersonal hedge is capped at maxHedges (1).
  if (FIRST_PERSON_HEDGE.test(trimmed)) return fail(7, "first_person_hedge");
  const hedgeCount = (trimmed.match(HEDGE_WORDS) || []).length;
  if (hedgeCount > rules.maxHedges) return fail(7, "over_hedged");

  // Rule 8 — reassurance.
  const h = normalise(trimmed);
  const reassurance = REASSURANCE.find((p) => h.includes(p));
  if (reassurance) return fail(8, "reassurance", reassurance);

  // Rule 9 — the swap test.
  if (swapTestFails(trimmed, ctx.vocabTop200)) return fail(9, "swap_test");

  return { ok: true, rule: null, reason: null, term: null };
}

/**
 * The full gate on Prompt M's structured output — `{line, shape, receipt,
 * question, would_be_false_if}` — combining lintMirrorLineText on the line,
 * the question's own (looser) length/question-mark check, the
 * `would_be_false_if` non-null requirement, and "last clause must be a
 * question or an exception."
 *
 * @param {object} output  Prompt M's parsed JSON
 * @param {object} ctx     { receiptQuote, vocabTop200 }
 */
function lintMirrorM(output, ctx = {}) {
  if (!output || typeof output.line !== "string") {
    return { ok: false, rule: 1, reason: "empty" };
  }
  const lineResult = lintMirrorLineText(output.line, ctx);
  if (!lineResult.ok) return lineResult;

  if (output.question != null && String(output.question).trim()) {
    const q = lintCopy(output.question, { kind: "mirrorQuestion" });
    if (!q.ok) return { ok: false, rule: 1, reason: `question_${q.reason}` };
  }

  if (output.would_be_false_if == null || !String(output.would_be_false_if).trim()) {
    return { ok: false, rule: null, reason: "no_would_be_false_if" };
  }

  const hasQuestion = output.question != null && String(output.question).trim().endsWith("?");
  const isException = output.shape === "EXCEPTION";
  if (!hasQuestion && !isException) {
    return { ok: false, rule: null, reason: "does_not_end_in_exception_or_question" };
  }

  return { ok: true, rule: null, reason: null };
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
  lintMirrorLineText,
  lintMirrorM,
  tripsBannedLint,
  tripsLabelLint,
  findMetaphor,
  findBanned,
  findCategoryOrClinical,
  hasSpecificity,
  concretenessCheck,
  figurativeHits,
  swapTestFails,
  endsWell,
  BANNED_SUBSTRINGS,
  BANNED_LABELS,
  METAPHORS,
  CATEGORY_NOUNS,
  SOFT_CLINICAL,
  REASSURANCE,
  HEDGE_WORDS,
  FIRST_PERSON_HEDGE,
  TRAIT_PHRASING,
  MIRROR_TRAIT_PHRASING,
  KINDS,
};
