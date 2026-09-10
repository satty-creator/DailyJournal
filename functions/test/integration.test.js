/* End-to-end run of the nightly derived pipeline against an in-memory
 * Firestore. No emulator, no network, no credentials.
 *
 * This is the test that would have caught the things `node --check` cannot:
 * a mistyped field name, a missing await, a batch over 500 writes, a map key
 * with a "." in it. It loads the REAL functions/index.js with firebase-admin
 * and firebase-functions mocked out at the module-cache level, then invokes
 * the actual `computeUserDerived` handler.
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");
const path = require("node:path");
const Module = require("node:module");

const { MockFirestore, Timestamp } = require("./fixtures/mockFirestore");
const fixture = require("./fixtures/sample");
const { localDateParts } = require("../lib/time");

/* ── load index.js with the Firebase surface mocked ──────────────────────── */

let db;
const enqueued = [];

function loadIndexWithMocks() {
  const store = new MockFirestore();
  db = store;
  enqueued.length = 0;

  const firestoreFn = () => store;
  firestoreFn.Timestamp = Timestamp;
  firestoreFn.FieldValue = {
    serverTimestamp: () => Timestamp.now(),
    delete: () => undefined,
    increment: (n) => n,
  };
  firestoreFn.FieldPath = { documentId: () => "__name__" };

  const mocks = {
    "firebase-admin": {
      initializeApp() {},
      firestore: firestoreFn,
      auth: () => ({ verifyIdToken: async () => ({ uid: "u1", firebase: { sign_in_provider: "password" } }) }),
      messaging: () => ({ sendEachForMulticast: async () => ({ responses: [] }) }),
    },
    "firebase-admin/functions": {
      getFunctions: () => ({
        taskQueue: (name) => ({
          enqueue: async (payload, opts) => { enqueued.push({ name, payload, opts }); },
        }),
      }),
    },
    "firebase-functions/v2/https": { onRequest: (opts, h) => h },
    "firebase-functions/v2/scheduler": { onSchedule: (opts, h) => h },
    // Return the raw handler so a task function is directly callable.
    "firebase-functions/v2/tasks": { onTaskDispatched: (opts, h) => h },
    "firebase-functions/params": { defineSecret: () => ({ value: () => "" }) },
  };

  const indexPath = require.resolve("../index.js");
  delete require.cache[indexPath];

  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (Object.prototype.hasOwnProperty.call(mocks, request)) return mocks[request];
    return originalLoad.apply(this, arguments);
  };
  try {
    return require(indexPath);
  } finally {
    Module._load = originalLoad;
  }
}

/** Seed the mock with the shared fixture corpus, in Firestore's own shapes. */
function seedCorpus(store, uid = "u1", { withMeta = true } = {}) {
  const fx = fixture.build();
  store.seed("users", uid, { timezone: fixture.TZ });
  store.seed(`users/${uid}/rollups`, "stats", { entryCount: fx.entries.length });

  for (const e of fx.entries) {
    const doc = {
      createdAt: Timestamp.fromDate(e.createdAt),
      sessionType: e.sessionType,
      mood: e.mood,
      tags: [],
    };
    if (withMeta && typeof e.wordCount === "number") doc.wordCount = e.wordCount;
    if (e.templateId) {
      doc.templateId = e.templateId;
      doc.templateScaleBefore = e.templateScaleBefore;
      doc.templateScaleAfter = e.templateScaleAfter;
    }
    store.seed(`users/${uid}/entries`, e.id, doc);
  }

  for (const a of fx.analyses) {
    const doc = {
      entryId: a.entryId,
      createdAt: Timestamp.fromDate(a.createdAt),
      surfaceSummary: a.surfaceSummary,
      lifeDomains: a.lifeDomains,
      explicitEmotions: a.explicitEmotions,
      phrasesToTrack: a.phrasesToTrack,
      bodySignals: a.bodySignals,
      relationshipRoles: a.relationshipRoles,
      people: a.people,
      needs: [],
      protectiveStrategies: [],
      valuesPresent: [],
      episodes: [],
      promptVersion: a.promptVersion,
    };
    if (withMeta) {
      doc.entryCreatedAt = Timestamp.fromDate(a.entryCreatedAt);
      doc.wordCount = a.wordCount;
    }
    if (a.templateDelta) doc.templateDelta = a.templateDelta;
    store.seed(`users/${uid}/entryAnalyses`, a.entryId, doc);
  }
  return fx;
}

async function runNightly(opts = {}) {
  const mod = loadIndexWithMocks();
  const fx = seedCorpus(db, "u1", opts);
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  return { mod, fx };
}

/* ── the tests ───────────────────────────────────────────────────────────── */

test("the whole nightly pipeline runs without throwing", async () => {
  const { fx } = await runNightly();
  assert.ok(db.peek("users/u1/derived", "facts"), "derived/facts must be written");
  assert.ok(db.peek("users/u1/derived", "threads"), "derived/threads must be written");
  const todayKey = localDateParts(fx.now, fixture.TZ).dateKey;
  assert.ok(db.peek("users/u1/readings", todayKey), "today's reading must be written");
});

test("facts land in Firestore with the counts the unit tests expect", async () => {
  await runNightly();
  const facts = db.peek("users/u1/derived", "facts");
  assert.equal(facts.entriesTotal, 14);
  assert.equal(facts.month.entries, 14);
  assert.equal(facts.month.words, 3205);
  assert.equal(facts.month.topEmotion.word, "heavy");
  assert.deepEqual(facts.month.people.map((p) => p.name), ["Priya", "Dan"]);
  assert.equal(facts.coverage.wordCountKnown, 14);
});

test("firstSeen persists as a LIST, never as map keys", async () => {
  await runNightly();
  const facts = db.peek("users/u1/derived", "facts");
  assert.ok(Array.isArray(facts.firstSeenList),
    "must persist as {t,d} pairs — a phrase containing '.' cannot be a Firestore field name");
  assert.equal(facts.firstSeen, undefined, "the map form must not reach Firestore");
  const term = facts.firstSeenList.find((x) => x.t === "domain:work");
  assert.equal(term.d, "2026-08-13");
});

test("firstSeen survives a second night, keeping the EARLIER date", async () => {
  const { mod, fx } = await runNightly();
  // Pretend a term was first seen long before the current window.
  const facts = db.peek("users/u1/derived", "facts");
  facts.firstSeenList.push({ t: "emotion:heavy", d: "2026-03-01" });
  facts.firstSeenList = facts.firstSeenList.filter(
    (x, i, all) => all.findIndex((y) => y.t === x.t && y.d === x.d) === i);
  db.seed("users/u1/derived", "facts", facts);

  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  const after = db.peek("users/u1/derived", "facts");
  const heavy = after.firstSeenList.filter((x) => x.t === "emotion:heavy").map((x) => x.d).sort();
  assert.equal(heavy[0], "2026-03-01",
    "the window slides; the true first date must not slide with it");
});

test("observations are written with stable ids and survive a recompute", async () => {
  const { mod, fx } = await runNightly();
  const first = db.ids("users/u1/observations").sort();
  assert.ok(first.length > 0);

  // Mark one as shown + rated, then run again.
  const target = first[0];
  const before = db.peek("users/u1/observations", target);
  db.seed("users/u1/observations", target,
    { ...before, userStatus: "this_is_me", notQuiteCount: 1 });

  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });

  const second = db.ids("users/u1/observations").sort();
  assert.deepEqual(second, first, "ids must be deterministic across nights");
  const after = db.peek("users/u1/observations", target);
  assert.equal(after.userStatus, "this_is_me", "user feedback must survive a recompute");
  assert.equal(after.notQuiteCount, 1);
});

test("today's reading is grounded and, without a model key, is the observation itself", async () => {
  const { fx } = await runNightly();
  const todayKey = localDateParts(fx.now, fixture.TZ).dateKey;
  const reading = db.peek("users/u1/readings", todayKey);

  assert.equal(reading.silence, false, "this corpus has plenty to say");
  assert.equal(reading.lintPassed, false, "the deterministic worker makes no model call");
  assert.equal(reading.line, reading.templateText,
    "with no model line, the line IS the observation");
  assert.ok(reading.source && reading.source.id, "must record which observation it came from");
  assert.ok(reading.proof && reading.proof.n > 0, "the proof sheet needs its numbers");
  assert.ok(/\d/.test(reading.line), "every line carries a checkable number");
});

test("an exception wins the day over a plain co-occurrence (R6)", async () => {
  const { fx } = await runNightly();
  const todayKey = localDateParts(fx.now, fixture.TZ).dateKey;
  const reading = db.peek("users/u1/readings", todayKey);
  assert.equal(reading.source.type, "exception",
    "exceptions outrank problems — step 1 of the §5.2 selection order");
});

test("an exception's receipt comes from the day it DIDN'T happen", async () => {
  const { fx } = await runNightly();
  const todayKey = localDateParts(fx.now, fixture.TZ).dateKey;
  const reading = db.peek("users/u1/readings", todayKey);

  assert.ok(reading.receipt, "an exception must still carry the user's own words");
  // The exception is 5 Sep — the one work day without 'heavy'. Its receipt has
  // to be what was written THAT day. Looking quotes up by the absent term
  // ('heavy') returns nothing by definition, which is how this first shipped
  // with receipt: null.
  assert.equal(reading.receipt.date, "2026-09-05");
  assert.match(reading.receipt.quote, /lucky/);
  assert.ok(reading.proof.quotes.every((q) => q.date === "2026-09-05"),
    "every quote on the proof sheet must come from the exception day");
});

test("no CONTENT observation is ever shown with numbers but no words", async () => {
  await runNightly();
  const all = db.ids("users/u1/observations").map((id) => db.peek("users/u1/observations", id));

  // A card that says "on 6 of your days..." with nothing of the user's own
  // underneath it is the Forer failure mode (R2): agreeable and uncheckable.
  const contentTypes = ["cooccurrence", "exception", "timeband", "callback", "streak", "delta"];
  const missing = all.filter((o) => contentTypes.includes(o.type) && (o.quotes || []).length === 0);
  assert.deepEqual(missing.map((o) => o.type), [],
    `these content observations produced no receipt: ${missing.map((o) => o.type).join(", ")}`);

  // `weekday` and `lag` are exempt BY DESIGN: they are facts about when and
  // how much this person writes, not about what they said. Attaching a quote
  // would imply a connection the arithmetic never made. They still satisfy the
  // copy contract, because they carry a percentage.
  for (const o of all.filter((x) => ["weekday", "lag"].includes(x.type))) {
    assert.ok(/\d/.test(o.templateText), "a metric observation must carry its number");
  }
});

test("threads are EMPTY on a corpus with no audited hypotheses, and say why", async () => {
  await runNightly();
  const threads = db.peek("users/u1/derived", "threads");
  assert.equal(threads.count, 0);
  assert.equal(threads.emptyReason, "no_hypotheses");
});

test("a hypothesis needs n>=3 AND a contrast set AND an audit to become a thread", async () => {
  const mod = loadIndexWithMocks();
  const fx = seedCorpus(db);
  const base = {
    userFacingTitle: "Yes before the report is done",
    coreHypothesis: "Saying yes lands before the decision does.",
    patternType: "protective_loop",
    status: "pending",
    stability: "stable",
    lifecycle: "recurring",
    scope: "recurring",
    salienceScore: 0.8,
    evidence: [{ entryId: "e01", entryCreatedAt: Timestamp.fromDate(fx.entries[0].createdAt), quote: "x" }],
    evidenceEntryIdsAllTime: ["e01", "e07", "e14"],
    firstSeenAt: Timestamp.fromDate(fx.entries[0].createdAt),
    lastEvidenceAt: Timestamp.fromDate(fx.now),
  };

  // (a) n>=3 but never audited -> not a thread
  db.seed("users/u1/patternHypotheses", "h_unaudited", { ...base, timesSeen: 3 });
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  assert.equal(db.peek("users/u1/derived", "threads").count, 0, "unaudited must not surface");

  // (b) audited and held -> a thread
  db.seed("users/u1/patternHypotheses", "h_unaudited", {
    ...base,
    timesSeen: 3,
    counterEvidenceEntryIds: ["e05"],
    disconfirmation: { ranAt: Timestamp.fromDate(fx.now), verdict: "hold", entriesRead: 9 },
  });
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  const threads = db.peek("users/u1/derived", "threads");
  assert.equal(threads.count, 1);
  const t = threads.threads[0];
  assert.equal(t.label, "recurring", "labels come from counts only");
  assert.equal(t.dots.length, 30, "the 30-day dot strip");
  assert.ok(t.dots.some((d) => d.f), "at least one day must be filled");
  assert.ok(t.title.length <= 45, "thread titles are capped at 45 chars");
});

test("a user-confirmed hypothesis bypasses the audit gate", async () => {
  const mod = loadIndexWithMocks();
  const fx = seedCorpus(db);
  db.seed("users/u1/patternHypotheses", "h_confirmed", {
    userFacingTitle: "Empty hours become projects",
    patternType: "protective_loop",
    status: "pending", stability: "stable", lifecycle: "user_confirmed", scope: "recurring",
    salienceScore: 0.5, timesSeen: 1, userStatus: "this_is_me",
    evidence: [], evidenceEntryIdsAllTime: ["e01"],
    firstSeenAt: Timestamp.fromDate(fx.entries[0].createdAt),
    lastEvidenceAt: Timestamp.fromDate(fx.now),
  });
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  const threads = db.peek("users/u1/derived", "threads");
  assert.equal(threads.count, 1, "the user's own confirmation outranks every threshold");
  assert.equal(threads.threads[0].label, "confirmed");
});

test("decay retires a stale hypothesis even when the mine never runs", async () => {
  const mod = loadIndexWithMocks();
  const fx = seedCorpus(db);
  const longAgo = new Date(fx.now.getTime() - 60 * 86400000);
  db.seed("users/u1/patternHypotheses", "h_stale", {
    userFacingTitle: "Something from a past season",
    patternType: "identity_rule",
    status: "pending", stability: "stable", lifecycle: "recurring", scope: "recurring",
    timesSeen: 4, salienceScore: 0.7,
    evidence: [], evidenceEntryIdsAllTime: ["old1"],
    firstSeenAt: Timestamp.fromDate(longAgo),
    lastEvidenceAt: Timestamp.fromDate(longAgo),
  });
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  const h = db.peek("users/u1/patternHypotheses", "h_stale");
  assert.equal(h.stability, "retired",
    "decay used to run only inside a successful mine, so dormant users never decayed");
});

test("decay never retires something the user confirmed", async () => {
  const mod = loadIndexWithMocks();
  const fx = seedCorpus(db);
  const longAgo = new Date(fx.now.getTime() - 90 * 86400000);
  db.seed("users/u1/patternHypotheses", "h_vouched", {
    userFacingTitle: "Still true", patternType: "identity_rule",
    status: "pending", stability: "stable", lifecycle: "user_confirmed", scope: "recurring",
    timesSeen: 4, userStatus: "this_is_me", evidence: [], evidenceEntryIdsAllTime: ["old1"],
    firstSeenAt: Timestamp.fromDate(longAgo), lastEvidenceAt: Timestamp.fromDate(longAgo),
  });
  await mod.computeUserDerived({ data: { uid: "u1", runDate: fx.now.toISOString() } });
  assert.notEqual(db.peek("users/u1/patternHypotheses", "h_vouched").stability, "retired");
});

test("word-count-dependent observations are suppressed when coverage is low", async () => {
  // Exactly the state of a real account tonight: v1 analyses, no wordCount.
  await runNightly({ withMeta: false });
  const facts = db.peek("users/u1/derived", "facts");
  assert.equal(facts.coverage.wordCountKnown, 0);

  const types = new Set(db.ids("users/u1/observations")
    .map((id) => db.peek("users/u1/observations", id).type));
  assert.ok(!types.has("weekday"), "weekday needs word counts it does not have");
  assert.ok(!types.has("lag"), "lag needs word counts it does not have");
  assert.ok(types.size > 0, "but everything else must still work");
});

test("the run tail-chains into the mining worker", async () => {
  await runNightly();
  assert.ok(enqueued.some((e) => e.name.includes("mineUserInsights")),
    "facts must be written before the mine, and the mine must still be triggered");
});

test("a user with no entries at all does not crash the job", async () => {
  const mod = loadIndexWithMocks();
  db.seed("users", "empty", { timezone: "UTC" });
  await mod.computeUserDerived({ data: { uid: "empty", runDate: new Date().toISOString() } });
  const facts = db.peek("users/empty/derived", "facts");
  assert.ok(facts, "the strip must still have a document to read");
  assert.equal(facts.entriesTotal, 0);
  const todayKey = localDateParts(new Date(), "UTC").dateKey;
  const reading = db.peek("users/empty/readings", todayKey);
  assert.equal(reading.silence, true);
  assert.equal(reading.reason, "no_analyses");
});

test("every written document survives Firestore's own value rules", async () => {
  // The mock throws on undefined, nested arrays, "."-containing map keys and
  // oversized batches — so simply completing the run is the assertion.
  await runNightly();
  assert.ok(db.writes > 0);
});
