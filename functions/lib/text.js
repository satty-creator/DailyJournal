/* text.js — string helpers shared by every Mirror surface.
 *
 * Pure: requires neither firebase-admin nor fetch, so it is unit-testable
 * without emulators or network (functions/test/*.test.js). This is decision (B)
 * of the Mirror v3 plan — Tier 0/1 is entirely arithmetic, and arithmetic is
 * only verifiable if it lives somewhere a test can call.
 *
 * PARITY: `sentenceCased` and the banned-phrase lists these feed are ports of
 * DailyJournal/Home/SpilrVoice.swift. Keep in sync — the client runs the same
 * output-side enforcement, and drift produces "it said this yesterday and now
 * it won't" bug reports.
 */

"use strict";

const crypto = require("crypto");

/** Lowercase, fold curly apostrophes, strip accents. Every other function in
 *  this file compares against this normal form. */
function normalise(t) {
  return (t || "").toLowerCase().replace(/’/g, "'")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

/** Stable short hash — deterministic ids for observations, and the
 *  change-detection key for cached embeddings. */
function sha1Hex(s, len) {
  const h = crypto.createHash("sha1").update(String(s)).digest("hex");
  return len ? h.slice(0, len) : h;
}

// Deliberately generic. This is a best-effort paraphrase check against an
// EntryAnalysis summary, NOT a cross-language parity point.
const MIRROR_STOPWORDS = new Set([
  "this", "that", "with", "have", "from", "were", "been", "your", "their",
  "there", "about", "into", "just", "like", "really", "would", "could",
  "should", "when", "what", "them", "then", "than", "over", "want", "know",
  "feel", "felt", "think", "thing", "things", "time", "today", "week",
  "going", "getting", "make", "made", "back", "does", "doing",
]);

function contentWords(text) {
  return new Set(
    normalise(text)
      .split(/[^a-z0-9]+/)
      .filter((w) => w.length >= 4 && !MIRROR_STOPWORDS.has(w))
  );
}

function jaccard(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const w of a) if (b.has(w)) intersection++;
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

/** Does `line` contain a run of at least `minWords` consecutive words that
 *  also appear, in order, in `quote`? A proxy for "quotes the person's own
 *  words" that's stricter than sharing any content word and looser than
 *  requiring the exact full phrase. */
function hasVerbatimOverlap(line, quote, minWords = 3) {
  const lineNorm = normalise(line);
  const quoteWords = normalise(quote).split(/\s+/).filter(Boolean);
  if (quoteWords.length === 0) return false;
  if (quoteWords.length < minWords) {
    return lineNorm.includes(quoteWords.join(" "));
  }
  for (let i = 0; i + minWords <= quoteWords.length; i++) {
    if (lineNorm.includes(quoteWords.slice(i, i + minWords).join(" "))) return true;
  }
  return false;
}

/** PARITY: SpilrVoice.sentenceCased. Only ever CAPITALISES — see deShout for
 *  the other direction. */
const SENTENCE_START_SKIP = new Set(["\"", "'", "“", "”", "‘", "’", "(", "["]);
function sentenceCased(text) {
  if (!text) return text;
  const chars = Array.from(String(text));
  let atStart = true;
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (/\s/.test(c) || SENTENCE_START_SKIP.has(c)) continue;
    if (atStart && /\p{L}/u.test(c)) {
      const upper = c.toUpperCase();
      if (Array.from(upper).length === 1) chars[i] = upper;
    }
    atStart = (c === "." || c === "!" || c === "?");
  }
  return chars.join("");
}

// Words allowed to stay fully uppercase.
const SHOUT_ALLOWLIST = new Set(["I", "OK", "AM", "PM", "TV", "UK", "US", "ID"]);

/** Un-shouts text.
 *
 *  `sentenceCased` cannot fix "WARDING OFF THE QUIET TERROR" — it only ever
 *  raises case, never lowers it, so an all-caps model output passed straight
 *  through to the screen. Run this BEFORE sentenceCased so the first letter is
 *  restored afterwards.
 *
 *  Distinguishes a WORD in caps (an acronym — keep it) from TEXT that is
 *  shouting (fix all of it). A lone 4+ letter capital run is treated as an
 *  acronym; once a third or more of the words are capitalised, the text is
 *  shouting and even two- and three-letter words get lowered — otherwise
 *  "WARDING OFF THE QUIET" comes out as "Warding OFF THE quiet", which is
 *  worse than either extreme. */
function deShout(text) {
  if (!text) return text;
  const s = String(text);
  const words = s.match(/\b[\p{L}]+\b/gu) || [];
  const shouted = words.filter((w) => w.length >= 2 && w === w.toUpperCase() &&
    /[\p{Lu}]/u.test(w) && !SHOUT_ALLOWLIST.has(w));
  const isShouting = words.length > 0 && shouted.length / words.length >= 0.34;
  const minLen = isShouting ? 2 : 4;
  return s.replace(/\b[\p{Lu}]{2,}\b/gu, (w) =>
    (w.length >= minLen && !SHOUT_ALLOWLIST.has(w) ? w.toLowerCase() : w));
}

/** Vowel-group syllable heuristic. Not linguistically exact — it does not need
 *  to be, since it only feeds a Flesch-Kincaid threshold comparison. */
function syllables(word) {
  const w = normalise(word).replace(/[^a-z]/g, "");
  if (!w) return 0;
  const groups = w.match(/[aeiouy]+/g);
  let n = groups ? groups.length : 0;
  if (w.length > 2 && w.endsWith("e") && !/[aeiouy]e$/.test(w)) n -= 1;
  return Math.max(1, n);
}

/** Flesch-Kincaid grade level: 0.39·(words/sentences) + 11.8·(syllables/words) − 15.59 */
function readingGrade(text) {
  const t = String(text || "").trim();
  if (!t) return 0;
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length === 0) return 0;
  const sentences = Math.max(1, (t.match(/[.!?](?=\s|$)/g) || []).length);
  const syl = words.reduce((sum, w) => sum + syllables(w), 0);
  return 0.39 * (words.length / sentences) + 11.8 * (syl / words.length) - 15.59;
}

module.exports = {
  normalise,
  sha1Hex,
  contentWords,
  jaccard,
  hasVerbatimOverlap,
  sentenceCased,
  deShout,
  syllables,
  readingGrade,
  MIRROR_STOPWORDS,
};
