/* Seeds the Firebase emulators for the iOS UI tests (DailyJournalUITests).
 *
 * Wipes Auth + Firestore in the EMULATOR, then creates one verified account
 * per test so tests never share state. Refuses to run unless the emulator
 * hosts are set — it can never touch production.
 *
 * Accounts must match `E2EAccount` in DailyJournalUITests/SpilrUITestCase.swift.
 */

"use strict";

const path = require("path");
const admin = require(path.join(__dirname, "..", "..", "functions", "node_modules", "firebase-admin"));

const PROJECT = process.env.E2E_PROJECT || "spilr-100f7";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST;

if (!AUTH_HOST || !FS_HOST) {
  console.error("Refusing to seed: FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST must be set.");
  process.exit(1);
}

const PASSWORD = "spilr-e2e-password";
const ACCOUNTS = [
  { email: "onboarding-later@spilr.test" },
  { email: "onboarding-chat@spilr.test" },
  { email: "profile@spilr.test" },
  { email: "purchase@spilr.test" },
  {
    email: "preview-ended@spilr.test",
    // Free preview already used up → geminiProxy answers 402 preview_ended.
    aiUsage: { entitlement: "free", trialInTok: 10_000_000, trialOutTok: 10_000_000 },
  },
  // An owner, to prove the bypass end to end. Emulator-only account.
  { email: "satakshi1710@gmail.com" },
];

async function wipe() {
  await fetch(`http://${AUTH_HOST}/emulator/v1/projects/${PROJECT}/accounts`, { method: "DELETE" });
  await fetch(`http://${FS_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
}

async function main() {
  admin.initializeApp({ projectId: PROJECT });
  await wipe();
  const db = admin.firestore();
  for (const a of ACCOUNTS) {
    const user = await admin.auth().createUser({
      email: a.email, password: PASSWORD, emailVerified: true, displayName: a.email.split("@")[0],
    });
    if (a.aiUsage) {
      await db.collection("aiUsage").doc(user.uid).set({
        trialStartedAt: admin.firestore.Timestamp.now(),
        // Must be set, or geminiProxy treats this as a pre-policy account and
        // starts (and resets) a fresh preview on the first call.
        previewStartedAt: admin.firestore.Timestamp.now(),
        trialPerSurface: {},
        ...a.aiUsage,
      });
    }
    console.log(`seeded ${a.email} (${user.uid})`);
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
