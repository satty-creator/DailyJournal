/**
 * One-time migration: encrypt existing plaintext `content` fields in Firestore.
 *
 * This script reads all entries for all users, encrypts the `content` field
 * using the SAME AES-256-GCM algorithm as the iOS app (CryptoKit-compatible),
 * and writes the ciphertext back with `encrypted: true`.
 *
 * IMPORTANT: The iOS app generates a per-device encryption key stored in the
 * iOS Keychain. For server-side migration, you have two options:
 *
 *   Option A (recommended): Let the app migrate entries lazily on first read.
 *              Keep this script as a reference but don't run it server-side —
 *              the app already handles unencrypted entries gracefully (the
 *              `encrypted` field defaults to false, and the init reads plaintext).
 *
 *   Option B: Run this script with a SHARED key that you also provision into
 *              each user's Keychain via a one-time app update. This is complex
 *              and not recommended for a small user base.
 *
 * For a small-to-medium user base, Option A is correct: existing entries remain
 * readable (the app checks `encrypted: false` and skips decryption), and ALL NEW
 * entries are encrypted from the moment the app update ships.
 *
 * If you still want to migrate server-side for defense-in-depth, set the
 * ENCRYPTION_KEY env var to a base64-encoded 32-byte key that matches what's in
 * the user's Keychain (only viable for a single-user or test scenario).
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json
 *   export ENCRYPTION_KEY=<base64-encoded 32-byte key>  # optional
 *   node scripts/migrate-encrypt-entries.js [--dry-run]
 */

const crypto = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_SIZE = 50;

// AES-256-GCM, same as CryptoKit's AES.GCM (nonce=12, tag=16, key=32).
// CryptoKit's `sealed.combined` layout: nonce (12) || ciphertext || tag (16).
function encrypt(plaintext, keyBuffer) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", keyBuffer, nonce);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  // combined = nonce || ciphertext || tag (matches CryptoKit SealedBox.combined)
  const combined = Buffer.concat([nonce, encrypted, tag]);
  return combined.toString("base64");
}

async function migrateUser(uid, keyBuffer) {
  const entriesRef = db.collection("users").doc(uid).collection("entries");
  let migrated = 0;
  let cursor = null;

  while (true) {
    let query = entriesRef.orderBy("createdAt").limit(BATCH_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.encrypted === true) continue;
      if (!data.content || data.content.length === 0) continue;

      const ciphertext = encrypt(data.content, keyBuffer);
      if (DRY_RUN) {
        console.log(`  [dry-run] Would encrypt entry ${doc.id} (${data.content.length} chars)`);
      } else {
        batch.update(doc.ref, { content: ciphertext, encrypted: true });
      }
      batchCount++;
    }

    if (!DRY_RUN && batchCount > 0) await batch.commit();
    migrated += batchCount;
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < BATCH_SIZE) break;
  }

  return migrated;
}

async function main() {
  const keyEnv = process.env.ENCRYPTION_KEY;
  if (!keyEnv) {
    console.log("No ENCRYPTION_KEY set. Running in AUDIT mode (counts unencrypted entries only).\n");
    const usersSnap = await db.collection("users").get();
    let totalUnencrypted = 0;

    for (const userDoc of usersSnap.docs) {
      const entriesSnap = await db.collection("users").doc(userDoc.id)
        .collection("entries")
        .where("encrypted", "!=", true)
        .get();
      const count = entriesSnap.size;
      if (count > 0) {
        console.log(`  ${userDoc.id}: ${count} unencrypted entries`);
        totalUnencrypted += count;
      }
    }

    console.log(`\nTotal unencrypted entries: ${totalUnencrypted}`);
    console.log("Set ENCRYPTION_KEY env var to encrypt. New entries are encrypted by the app automatically.");
    process.exit(0);
  }

  const keyBuffer = Buffer.from(keyEnv, "base64");
  if (keyBuffer.length !== 32) {
    console.error("ENCRYPTION_KEY must be exactly 32 bytes (256 bits) when base64-decoded.");
    process.exit(1);
  }

  console.log(`Mode: ${DRY_RUN ? "DRY RUN" : "LIVE"}`);
  console.log("Starting migration...\n");

  const usersSnap = await db.collection("users").get();
  let totalMigrated = 0;

  for (const userDoc of usersSnap.docs) {
    const count = await migrateUser(userDoc.id, keyBuffer);
    if (count > 0) {
      console.log(`  ${userDoc.id}: ${count} entries encrypted`);
      totalMigrated += count;
    }
  }

  console.log(`\nDone. ${totalMigrated} entries ${DRY_RUN ? "would be" : ""} encrypted.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
