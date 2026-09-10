/* node:test — no dependencies, no emulator, no network.
 *
 * Run: npm test   (from functions/)
 *
 * Every expected number in here was counted by hand off test/fixtures/sample.js
 * before the code was run. That is the point: a fixture whose right answer you
 * can only get by running the code proves nothing.
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const { computeFacts, unlockStateFor, mergeFirstSeen } = require("../lib/facts");
const { computeObservations, obsId } = require("../lib/observations");
const { lintCopy } = require("../lib/lint");
const { clusterHypotheses, cosine, normaliseVector } = require("../lib/identity");
const {
  localDateParts, recentDateKeys, weekBounds, daysBetweenKeys, relativeLabel, shortDate,
} = require("../lib/time");
const { normalise, deShout, sentenceCased, readingGrade, hasVerbatimOverlap } = require("../lib/text");
const fixture = require("./fixtures/sample");

function runPipeline() {
  const fx = fixture.build();
  const facts = computeFacts(fx);
  const todayKey = localDateParts(fx.now, fx.tz).dateKey;
  const wb = weekBounds(fx.now, fx.tz);
  const weekKeys = recentDateKeys(fx.now, daysBetweenKeys(wb.start, wb.end) + 1, fx.tz);
  const observations = computeObservations(facts, fx.analyses, {
    now: fx.now, todayKey, weekKeys,
    windowDays: recentDateKeys(fx.now, 30, fx.tz),
    shownHistory: [],
  });
  return { fx, facts, observations, todayKey, weekKeys };
}

/* ── time ────────────────────────────────────────────────────────────────── */

test("localDateParts uses the user's timezone, not UTC", () => {
  const d = new Date("2026-09-10T22:14:00Z");
  assert.equal(localDateParts(d, "Europe/London").dateKey, "2026-09-10");
  assert.equal(localDateParts(d, "Asia/Tokyo").dateKey, "2026-09-11", "Tokyo has rolled over");
  assert.equal(localDateParts(d, "America/New_York").band, "evening");
  assert.equal(localDateParts(d, "Europe/London").band, "late");
});

test("localDateParts falls back to UTC on a bad timezone instead of throwing", () => {
  const p = localDateParts(new Date("2026-09-10T22:14:00Z"), "Not/AZone");
  assert.equal(p.dateKey, "2026-09-10");
});

test("late band wraps midnight", () => {
  assert.equal(localDateParts(new Date("2026-09-10T01:30:00Z"), "UTC").band, "late");
  assert.equal(localDateParts(new Date("2026-09-10T23:30:00Z"), "UTC").band, "late");
});

test("relative labels and short dates", () => {
  assert.equal(relativeLabel("2026-09-10", "2026-09-10"), "today");
  assert.equal(relativeLabel("2026-09-09", "2026-09-10"), "yesterday");
  assert.equal(relativeLabel("2026-09-08", "2026-09-10"), "2 days ago");
  assert.equal(shortDate("2026-08-12"), "12 Aug");
});

/* ── text ────────────────────────────────────────────────────────────────── */

test("deShout fixes ALL-CAPS, which sentenceCased structurally cannot", () => {
  assert.equal(sentenceCased("WARDING OFF THE QUIET"), "WARDING OFF THE QUIET");
  assert.equal(sentenceCased(deShout("WARDING OFF THE QUIET")), "Warding off the quiet");
  assert.equal(deShout("I am OK"), "I am OK", "short allowlisted words survive");
});

test("readingGrade separates plain from clinical prose", () => {
  assert.ok(readingGrade("The cat sat on the mat.") < 3);
  assert.ok(readingGrade("Warding off the quiet terror of unstructured space perpetuates dysregulation.") > 10);
});

test("hasVerbatimOverlap needs a real run of words", () => {
  assert.ok(hasVerbatimOverlap("she said she'd do it for me again", "she'd do it for me"));
  assert.ok(!hasVerbatimOverlap("something entirely different", "she'd do it for me"));
});

/* ── Tier 0 ──────────────────────────────────────────────────────────────── */

test("facts: counts match the hand-built fixture exactly", () => {
  const { facts } = runPipeline();
  assert.equal(facts.entriesTotal, 14);
  assert.equal(facts.month.entries, 14);
  assert.equal(facts.month.activeDays, 14, "one entry per day");
  // 200+90+400+210+95+420+205+100+390+260+240+255+160+180
  assert.equal(facts.month.words, 3205);
  assert.equal(facts.month.wordsKnown, true);
});

test("facts: the dominant emotion word carries its count and its cluster", () => {
  const { facts } = runPipeline();
  assert.equal(facts.month.topEmotion.word, "heavy");
  assert.equal(facts.month.topEmotion.count, 5);
  assert.equal(facts.month.topEmotion.clusteredOn, "domain:work",
    "all 5 'heavy' days are work days, so the cluster claim is unanimous");
});

test("facts: people come through with real names and counts", () => {
  const { facts } = runPipeline();
  assert.deepEqual(facts.month.people, [
    { name: "Priya", mentions: 4 },
    { name: "Dan", mentions: 2 },
  ]);
});

test("facts: entryDates bucket by the ENTRY's timestamp, not the analysis's", () => {
  const { facts } = runPipeline();
  assert.equal(facts.entryDates.e01, "2026-08-13");
  assert.equal(facts.entryDates.e14, "2026-09-10");
  assert.equal(facts.entryMeta.e01.band, "late");
  assert.equal(facts.entryMeta.e03.band, "morning");
});

test("facts: template runs are captured oldest-first", () => {
  const { facts } = runPipeline();
  assert.equal(facts.templateRuns.length, 2);
  assert.deepEqual(
    facts.templateRuns.map((r) => [r.before, r.after]),
    [[7, 4], [6, 3]]
  );
});

test("unlock ladder names the next real threshold", () => {
  const at5 = unlockStateFor(5, { eveningEntries: 1, lateEntries: 4 });
  assert.equal(at5.next.atEntries, 7);
  assert.equal(at5.next.need, 2);
  const at8 = unlockStateFor(8, {});
  assert.equal(at8.next.unlocks, "threads");
  assert.match(at8.next.hint, /2 more entries and a thread can form/);
  assert.equal(unlockStateFor(500, {}).next, null, "no hint past the last rung");
});

test("unlock hint names the MISSING BAND when that is what's actually missing", () => {
  const oneBand = unlockStateFor(5, {
    morningEntries: 0, afternoonEntries: 0, eveningEntries: 0, lateEntries: 5,
  });
  assert.match(oneBand.next.hint, /different time of day/,
    "telling someone to write more when what's missing is a contrast is near-miss advice");
});

test("mergeFirstSeen keeps the EARLIER date as the window slides", () => {
  const merged = mergeFirstSeen(
    { "emotion:calm": "2026-03-01" },
    { "emotion:calm": "2026-08-16", "emotion:new": "2026-09-01" }
  );
  assert.equal(merged["emotion:calm"], "2026-03-01");
  assert.equal(merged["emotion:new"], "2026-09-01");
});

/* ── Tier 1 ──────────────────────────────────────────────────────────────── */

test("observations: all eight types fire on a corpus built to exercise them", () => {
  const { observations } = runPipeline();
  const types = new Set(observations.map((o) => o.type));
  for (const t of ["cooccurrence", "exception", "timeband", "weekday",
    "lag", "callback", "delta", "streak"]) {
    assert.ok(types.has(t), `missing observation type: ${t}`);
  }
});

test("co-occurrence: work + heavy has the exact hand-counted numbers", () => {
  const { observations } = runPipeline();
  const o = observations.find((x) => x.type === "cooccurrence" &&
    x.subject === "domain:work" && x.object === "emotion:heavy");
  assert.ok(o, "work+heavy co-occurrence should exist");
  assert.equal(o.n, 6, "6 work days");
  assert.equal(o.m, 8, "8 non-work days out of 14 active");
  assert.equal(o.k, 5, "'heavy' on 5 of them");
  assert.equal(o.j, 0, "'heavy' never appears on a non-work day");
  assert.equal(o.lift, 2.33);
  assert.equal(o.templateText,
    "On the 6 days you wrote about work, 'heavy' appeared in 5. On the other 8 days: 0.");
});

test("exception: names the single day the rule did not hold", () => {
  const { observations } = runPipeline();
  const o = observations.find((x) => x.type === "exception" && x.subject === "domain:work");
  assert.ok(o);
  assert.deepEqual(o.exceptionDays, ["2026-09-05"]);
  assert.match(o.templateText, /^5 Sep is the only day this month you wrote about work without 'heavy'\.$/);
});

test("exception: never claims the ABSENCE of a phrase as evidence", () => {
  const { observations } = runPipeline();
  const bad = observations.filter((o) => o.type === "exception" &&
    String(o.object).startsWith("phrase:"));
  assert.equal(bad.length, 0,
    "a phrase not being extracted says nothing about what the person felt");
});

test("weekday and lag carry a real effect size, not noise", () => {
  const { observations } = runPipeline();
  const sunday = observations.find((o) => o.type === "weekday" && o.weekday === 0);
  assert.ok(sunday);
  assert.equal(sunday.pct, 122, "403 vs 181 words");
  const lag = observations.find((o) => o.type === "lag");
  assert.ok(Math.abs(lag.pct) >= 25, "the 25% floor is what keeps '3% longer' off the screen");
});

test("callback pairs two DIFFERENT moments, 14+ days apart", () => {
  const { observations } = runPipeline();
  const cb = observations.filter((o) => o.type === "callback");
  assert.ok(cb.length >= 1);
  for (const o of cb) {
    assert.ok(o.daysApart >= 14);
    assert.notEqual(normalise(o.thenQuote.text), normalise(o.nowQuote.text),
      "identical quotes are a repetition, not a callback");
  }
});

test("delta counts the run length", () => {
  const { observations } = runPipeline();
  const d = observations.find((o) => o.type === "delta");
  assert.equal(d.before, 6);
  assert.equal(d.after, 3);
  assert.equal(d.runLength, 2);
  assert.match(d.templateText, /2nd drop in a row/);
});

test("streak reports the true gap", () => {
  const { observations } = runPipeline();
  const s = observations.find((o) => o.type === "streak");
  assert.equal(s.lastBefore, "2026-08-16");
  assert.ok(s.gapDays >= 21);
  assert.match(s.templateText, /First time 'calm' has appeared since 16 Aug\./);
});

test("observation ids are deterministic across runs", () => {
  const a = runPipeline().observations;
  const b = runPipeline().observations;
  assert.deepEqual(a.map((o) => o.id), b.map((o) => o.id),
    "ids must survive a recompute or userStatus/shownAt are lost every night");
  assert.equal(obsId("cooccurrence", ["b", "a"]), obsId("cooccurrence", ["a", "b"]),
    "term order must not change the id");
});

test("no two observations render to the same sentence", () => {
  const { observations } = runPipeline();
  const texts = observations.map((o) => normalise(o.templateText));
  assert.equal(new Set(texts).size, texts.length);
});

test("novelty: an observation shown recently is penalised below the floor", () => {
  const { fx, facts, todayKey, weekKeys, observations } = runPipeline();
  const top = observations[0];
  const rescored = computeObservations(facts, fx.analyses, {
    now: fx.now, todayKey, weekKeys,
    windowDays: recentDateKeys(fx.now, 30, fx.tz),
    shownHistory: [{ date: "2026-09-09", observationId: top.id, terms: top.terms }],
  });
  const again = rescored.find((o) => o.id === top.id);
  assert.ok(again.score < top.score - 1, "showing it yesterday must cost it");
  assert.notEqual(rescored[0].id, top.id, "something else should win today");
});

test("a missing shownAt record counts as MAXIMUM novelty, never zero", () => {
  const { fx, facts, todayKey, weekKeys, observations } = runPipeline();
  const withEmptyHistory = computeObservations(facts, fx.analyses, {
    now: fx.now, todayKey, weekKeys,
    windowDays: recentDateKeys(fx.now, 30, fx.tz),
    // A client on an older build writes no `terms`/`observationId`.
    shownHistory: [{ date: "2026-09-09", observationId: null, terms: null }],
  });
  assert.equal(withEmptyHistory[0].score, observations[0].score,
    "users on old builds must not be silenced");
});

/* ── Tier 2 / copy contract ──────────────────────────────────────────────── */

test("lint rejects every real failing line from the 9 Sept screenshots", () => {
  const observation = { n: 6, m: 8, k: 5, j: 0, quotes: [{ text: "she'd do it for me" }] };
  const cases = [
    ["Warding off the quiet terror of unstructured space.", "metaphor"],
    ["Keeps the nervous system revved up.", "metaphor"],
    ["Weighing the ledger of fairness against quietude.", "metaphor"],
    ["Letting the physical environment drop its armor.", "metaphor"],
    ["You are someone who says yes too fast.", "trait_phrasing"],
    ["You tend to say yes before you think.", "trait_phrasing"],
    ["Your inability to rest is showing.", "trait_phrasing"],
    ["Something shifted for you this week.", "no_specificity"],
  ];
  for (const [line, expected] of cases) {
    const r = lintCopy(line, { kind: "reading", observation });
    assert.equal(r.ok, false, `should reject: ${line}`);
    assert.equal(r.reason, expected, `wrong reason for: ${line}`);
  }
});

test("lint passes a line anchored in a number or the person's own words", () => {
  const observation = { n: 6, m: 8, k: 5, j: 0, quotes: [{ text: "she'd do it for me" }] };
  assert.ok(lintCopy("'She'd do it for me' is the third yes this month.",
    { kind: "reading", observation }).ok);
  assert.ok(lintCopy("On 5 of your 6 work days, heavy turned up too.",
    { kind: "reading", observation }).ok);
});

test("thread titles are short, unhedged and unpunctuated", () => {
  assert.ok(lintCopy("Empty hours become projects", { kind: "threadTitle" }).ok);
  assert.equal(lintCopy("Yes before the report is done.", { kind: "threadTitle" }).reason,
    "trailing_period");
  assert.equal(lintCopy("This might be a pattern about work", { kind: "threadTitle" }).reason,
    "over_hedged");
  assert.equal(
    lintCopy("Turning unmanaged hours into an engineering puzzle again", { kind: "threadTitle" }).reason,
    "too_long");
});

test("letters must end on the question", () => {
  const observation = { n: 6, m: 8, k: 5, j: 0, quotes: [{ text: "she'd do it for me" }] };
  assert.equal(lintCopy("A tidy week overall.", { kind: "letter", observation }).reason,
    "no_question");
  assert.ok(lintCopy(
    "Heavy showed up on 5 of your 6 work days. On 5 Sep it did not. What was different?",
    { kind: "letter", observation }).ok);
});

test("ends_negative is measured but NOT enforced by default", () => {
  const observation = { n: 6, m: 8, k: 5, j: 0, quotes: [{ text: "she'd do it for me" }] };
  const line = "Heavy turned up on 5 work days and it flattened you.";
  const observed = lintCopy(line, { kind: "reading", observation });
  assert.equal(observed.ok, true, "log-only for the first week");
  const enforced = lintCopy(line, { kind: "reading", observation, enforceEndsNegative: true });
  assert.equal(enforced.ok, false);
  assert.equal(enforced.reason, "ends_negative");
});

/* ── identity ────────────────────────────────────────────────────────────── */

function forkedCorpus() {
  const d = (n) => new Date(`2026-09-0${n}T00:00:00Z`);
  return [
    { id: "protectiveLoop_a", patternType: "protective_loop", userFacingTitle: "turning unmanaged hours into an engineering puzzle", timesSeen: 4, evidence: [{ entryId: "e1", entryCreatedAt: d(1) }], evidenceEntryIdsAllTime: ["e1", "e2", "e3", "e4"], firstSeenAt: d(1), status: "pending" },
    { id: "protectiveLoop_b", patternType: "protective_loop", userFacingTitle: "translating empty hours into engineering problems", timesSeen: 1, evidence: [{ entryId: "e3", entryCreatedAt: d(3) }], evidenceEntryIdsAllTime: ["e3"], firstSeenAt: d(3), status: "pending" },
    { id: "valuesConflict_c", patternType: "values_conflict", userFacingTitle: "Converting empty hours into an engineering puzzle", timesSeen: 1, evidence: [{ entryId: "e4", entryCreatedAt: d(4) }], evidenceEntryIdsAllTime: ["e4"], firstSeenAt: d(4), status: "closed" },
    { id: "relationshipRole_z", patternType: "relationship_role", userFacingTitle: "saying yes to Priya before deciding", timesSeen: 3, evidence: [{ entryId: "e9", entryCreatedAt: d(9) }], evidenceEntryIdsAllTime: ["e9", "e8", "e7"], firstSeenAt: d(7), status: "pending" },
  ];
}

test("dedup merges ACROSS patternType — the six-variants bug", () => {
  const { merges } = clusterHypotheses(forkedCorpus(), { now: new Date() });
  assert.equal(merges.length, 1);
  const m = merges[0];
  assert.equal(m.survivorId, "protectiveLoop_a", "most distinct entries wins");
  assert.ok(m.loserIds.includes("valuesConflict_c"),
    "a different patternType must not protect a duplicate");
  assert.equal(m.patch.timesSeen, 4, "timesSeen is the union of distinct entries");
});

test("dedup propagates a kill instead of leaving five siblings alive", () => {
  const { merges } = clusterHypotheses(forkedCorpus(), { now: new Date() });
  assert.equal(merges[0].patch.status, "closed",
    "closing one variant must close the cluster, or the user's 'done' is ignored");
});

test("dedup leaves unrelated hypotheses alone", () => {
  const { merges } = clusterHypotheses(forkedCorpus(), { now: new Date() });
  assert.ok(!merges.some((m) => m.loserIds.includes("relationshipRole_z")));
  assert.ok(!merges.some((m) => m.survivorId === "relationshipRole_z"));
});

test("dedup is deterministic — same input, same survivor", () => {
  const a = clusterHypotheses(forkedCorpus(), { now: new Date() });
  const b = clusterHypotheses(forkedCorpus(), { now: new Date() });
  assert.deepEqual(a.merges, b.merges);
});

test("a user-confirmed hypothesis needs near-identity to be absorbed", () => {
  const corpus = forkedCorpus();
  corpus[1].userStatus = "this_is_me";      // the user vouched for THIS wording
  corpus[1].evidenceEntryIdsAllTime = ["e3"];
  corpus[0].evidenceEntryIdsAllTime = ["e1", "e2", "e3", "e4"];
  const { merges } = clusterHypotheses(corpus, { now: new Date() });
  const absorbed = merges.some((m) => m.loserIds.includes("protectiveLoop_b"));
  assert.equal(absorbed, true,
    "containment of 1.00 is 'strict' enough to cross the boundary");
  const patch = merges.find((m) => m.loserIds.includes("protectiveLoop_b")).patch;
  assert.equal(patch.userStatus, "this_is_me", "the confirmation must survive the merge");
});

test("cosine only means anything on normalised vectors", () => {
  const raw = [3, 0, 4];
  const unit = normaliseVector(raw);
  assert.ok(Math.abs(cosine(unit, unit) - 1) < 1e-9);
  assert.ok(cosine(raw, raw) > 1, "unnormalised vectors make the 0.82 threshold meaningless");
  assert.equal(normaliseVector([0, 0, 0]), null);
});
