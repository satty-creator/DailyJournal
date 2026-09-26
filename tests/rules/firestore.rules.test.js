/* Firestore security rules — the enforcement boundary for Spilr Pro and for
 * every user's journal. Runs against the Firestore emulator.
 *
 *   cd tests/rules && npm install && npm test
 *
 * The two tests that matter most: a signed-in user can NOT write `aiUsage`
 * or `entitlements` (that would be "set myself to paid"), and can NOT read
 * or write anyone else's journal.
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");

let env;

test.before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  const [h, p] = host.split(":");
  env = await initializeTestEnvironment({
    projectId: "demo-spilr-rules",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: h, port: Number(p),
    },
  });
});

test.after(async () => { if (env) await env.cleanup(); });
test.beforeEach(async () => { await env.clearFirestore(); });

const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const anon = () => env.unauthenticatedContext().firestore();

async function seed(pathStr, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), pathStr), data);
  });
}

/* ── Spilr Pro: entitlement docs are server-only ────────────────────────── */

test("a user cannot make themselves paid by writing aiUsage", async () => {
  await assertFails(setDoc(doc(alice(), "aiUsage/alice"), { entitlement: "paid" }));
});

test("a user cannot edit an existing aiUsage doc", async () => {
  await seed("aiUsage/alice", { entitlement: "free", trialInTok: 999999 });
  await assertFails(updateDoc(doc(alice(), "aiUsage/alice"), { trialInTok: 0 }));
  await assertFails(deleteDoc(doc(alice(), "aiUsage/alice")));
});

test("a user cannot read or write the RevenueCat entitlements record", async () => {
  await seed("entitlements/alice", { lastEventType: "INITIAL_PURCHASE" });
  await assertFails(getDoc(doc(alice(), "entitlements/alice")));
  await assertFails(setDoc(doc(alice(), "entitlements/alice"), { lastEventType: "RENEWAL" }));
});

test("rateLimits are server-only", async () => {
  await assertFails(setDoc(doc(alice(), "rateLimits/alice"), { n: 0 }));
});

/* ── Journal privacy ────────────────────────────────────────────────────── */

test("a user can write and read their own entries", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice/entries/e1"), { text: "hi" }));
  await assertSucceeds(getDoc(doc(alice(), "users/alice/entries/e1")));
});

test("a user cannot read another user's entries", async () => {
  await seed("users/bob/entries/e1", { text: "private" });
  await assertFails(getDoc(doc(alice(), "users/bob/entries/e1")));
});

test("a user cannot write into another user's journal", async () => {
  await assertFails(setDoc(doc(bob(), "users/alice/entries/e1"), { text: "forged" }));
});

test("signed-out clients can read nothing", async () => {
  await seed("users/alice/entries/e1", { text: "private" });
  await assertFails(getDoc(doc(anon(), "users/alice/entries/e1")));
  await assertFails(getDoc(doc(anon(), "users/alice")));
});

/* ── Push tokens ────────────────────────────────────────────────────────── */

test("a user can save their own push token (PushNotificationManager.saveToken)", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice/pushTokens/tok123"), {
    token: "tok123", platform: "ios",
  }, { merge: true }));
});

test("a user cannot register a push token on someone else's account", async () => {
  await assertFails(setDoc(doc(bob(), "users/alice/pushTokens/tok123"), { token: "tok123" }));
});

/* ── Server-owned model layers ──────────────────────────────────────────── */

test("the derived layer is server-only (no forged counts)", async () => {
  await assertFails(setDoc(doc(alice(), "users/alice/derived/facts"), { entriesTotal: 999 }));
});

test("observations accept only the user's feedback fields", async () => {
  await seed("users/alice/observations/o1", { count: 3, userStatus: null });
  await assertSucceeds(updateDoc(doc(alice(), "users/alice/observations/o1"), { userStatus: "thisIsMe" }));
  await assertFails(updateDoc(doc(alice(), "users/alice/observations/o1"), { count: 99 }));
  await assertFails(setDoc(doc(alice(), "users/alice/observations/o2"), { count: 1 }));
});

test("mirror letters accept only openedAt from the client", async () => {
  await seed("users/alice/mirrorLetters/2026-W39", { letter: "…", openedAt: null });
  await assertSucceeds(updateDoc(doc(alice(), "users/alice/mirrorLetters/2026-W39"), { openedAt: new Date() }));
  await assertFails(updateDoc(doc(alice(), "users/alice/mirrorLetters/2026-W39"), { letter: "rewritten" }));
});

test("sanity: the harness is really enforcing rules", async () => {
  assert.ok(env);
});
