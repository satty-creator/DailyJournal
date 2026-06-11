/**
 *  geminiProxy — server-side Gemini gateway for ninety.
 *
 *  Why this exists: the Gemini API key must NEVER live in the iOS app (it can be
 *  extracted from the binary) and users must never be asked to paste one. The key
 *  lives here as a Secret Manager secret. The app calls this function with the
 *  signed-in user's Firebase Auth ID token; we verify it, then proxy the request
 *  to Gemini and return Gemini's response *verbatim* so the client's existing
 *  parsers keep working unchanged.
 *
 *  Deploy + secret setup: see README.md in this folder.
 */

const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

// Set with:  firebase functions:secrets:set GEMINI_KEY
const GEMINI_KEY = defineSecret("GEMINI_KEY");

// Keep in sync with the model used across the app.
const MODEL = "gemini-2.5-flash";

exports.geminiProxy = onRequest(
  {
    region: "us-central1",
    secrets: [GEMINI_KEY],
    cors: true,
    timeoutSeconds: 60,
    memory: "256MiB",
    // Soft guardrail against runaway cost on a free-tier hobby project.
    maxInstances: 10,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Require a valid Firebase Auth ID token. This is what stops the proxy
    //    from being an open, anonymous Gemini relay.
    const authHeader = req.headers.authorization || "";
    const match = authHeader.match(/^Bearer (.+)$/);
    if (!match) {
      res.status(401).json({ error: "Missing Authorization bearer token" });
      return;
    }
    let uid;
    try {
      const decoded = await admin.auth().verifyIdToken(match[1]);
      uid = decoded.uid;
    } catch (e) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }

    // 2. Basic shape guard — we forward { contents, generationConfig } only.
    const body = req.body || {};
    if (!body.contents) {
      res.status(400).json({ error: "Missing 'contents' in request body" });
      return;
    }

    // 3. Forward to Gemini. Node 20 has global fetch.
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}` +
      `:generateContent?key=${GEMINI_KEY.value()}`;

    try {
      const upstream = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: body.contents,
          generationConfig: body.generationConfig || {},
        }),
      });
      const text = await upstream.text();
      // Pass status + JSON straight through so the client sees Gemini's own shape.
      res
        .status(upstream.status)
        .set("Content-Type", "application/json")
        .send(text);
    } catch (e) {
      console.error("Gemini upstream error", { uid, error: String(e) });
      res.status(502).json({ error: "Upstream Gemini error" });
    }
  }
);

/* ──────────────────────────────────────────────────────────────────────────
 *  generateDailyReads — the overnight "Today's Read" generator.
 *
 *  Runs once a day before the morning open. For each user with recent activity
 *  it assembles an engine payload, asks Gemini for one "tenderly brutal" read
 *  (Stage 1), then passes that read through an isolated Quality Checker (Stage 2)
 *  that must approve it on every axis before it is written to
 *  `users/{uid}/dailyReads/{yyyy-MM-dd}`. Anything that fails the guard, trips a
 *  distress flag, or scores below threshold is dropped silently — the client's
 *  LocalReadEngine covers the gap so the user always has something behind the
 *  sealed card.
 *
 *  Prompt + schema contracts mirror the iOS DailyRead model and the feature PRD
 *  (todaysreadprd.md). Bump PROMPT_VERSION whenever the prompts or schema change.
 * ────────────────────────────────────────────────────────────────────────── */

const PROMPT_VERSION = "read-gen-v1";
const READ_LOOKBACK_DAYS = 14;
const MIN_SCORE = 4; // any Stage-2 score below this rejects the read.

/** One Gemini JSON call. Returns the parsed object from candidates[0]...text. */
async function callGeminiJSON(prompt, { maxTokens, temperature }) {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}` +
    `:generateContent?key=${GEMINI_KEY.value()}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        maxOutputTokens: maxTokens,
        temperature,
      },
    }),
  });
  if (!resp.ok) throw new Error(`Gemini HTTP ${resp.status}`);
  const json = await resp.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Empty Gemini response");
  return JSON.parse(text);
}

const NINETY_VOICE = `YOU ARE NINETY. A sharp, warm friend who has been quietly reading this person's journal. You notice things; you are specific, a little wry, and unafraid to name the thing they're circling but didn't say. You are NOT a therapist, coach, or guru. Never use wellness clichés, never diagnose, never give advice, never moralise. Never restate what the user already wrote — add the layer they did NOT write.`;

/** yyyy-MM-dd for the given Date (server/UTC — see PRD timezone note). */
function dateKey(d) {
  return d.toISOString().slice(0, 10);
}

/** Stage 1 — the read generator prompt. */
function buildGeneratorPrompt(ctx) {
  return `${NINETY_VOICE}

You are ninety's core insight engine. Process the user's recent journals and context to output ONE incredibly personalized daily text insight ("The Read") plus metadata.

Tone is "tenderly brutal" — honest, observant, sharp, slightly witty, never mean, clinical, or dismissive. You are a fiercely loyal, hyper-observant friend pointing out a blindspot.

CRITICAL INSTRUCTIONS:
1. NOT a therapist. No diagnostic/therapy terms ("defense mechanism", "attachment style", "dissociation").
2. No wellness clichés ("your journey", "healing", "mindfulness", "self-love").
3. No poetic jargon ("choppy waters", "emotional current", "energy fields").
4. No advice or solutions. Hold up a clean mirror only.
5. No generic truisms that could apply to anyone.
6. Rely heavily on the supplied context.
7. NEVER output sensitive topics, physical-health alerts, or trauma deductions. Treat money topics as strictly private and internal.
8. "receipt_chips" must be small clips / keywords / context tokens found DIRECTLY in the payload that justify the read.

STRUCTURAL REQUIREMENT — "read_text" must use exactly one of these six templates:
- "You keep calling it X, but it sounds like Y."
- "The problem is not X. It is Y."
- "X is taking more space than it deserves."
- "You are trying to X before Y."
- "Your words say X. Your pattern says Y."
- "Stop asking X. Ask Y."

Honour the user's tone preference: ${ctx.tonePreference}. Steer clear of failure modes flagged in previous_read_feedback.

USER ENGINE DATA CONTEXT:
${JSON.stringify(ctx.payload, null, 2)}

Return ONLY valid JSON, no markdown, matching this contract:
{
  "notification_copy": "string (max 45 chars)",
  "read_text": "string (max 120 chars, one of the six templates)",
  "receipt_chips": ["string", ...],  // 2 to 4, lifted from the payload
  "why_this_read": "string (internal explanation)",
  "reply_prompt": "string (low-friction question, max 90 chars)",
  "share_safe_text": "string (clean, context-free, for a share card)",
  "sharpness_level": "soft" | "direct" | "funny" | "spicy",
  "confidence": 0.00,
  "should_show": true,
  "safety_level": "none" | "mild_distress" | "high_distress"
}`;
}

/** Stage 2 — the quality + safety guard prompt. */
function buildGuardPrompt(read) {
  return `You are ninety's automated Quality Checker. You intercept a generated "Today's Read" before it is written to production. Verify safety, grounding accuracy, and linguistic alignment.

REJECT (set "approved": false) IF:
1. Diagnostic language, psychological conditions, or clinical phrasing.
2. Generic motivational content, horoscope fluff, or wellness-quote energy.
3. Any instruction or action item ("you should sleep", "talk to your manager").
4. The insight lacks clear structural verification from the receipt_chips evidence.
5. Tone shifts into cruelty, condescension, or shaming.
6. The receipts lack explicit, functional entry chips.

Score each axis 1–5. If ANY score is below ${MIN_SCORE}, "approved" MUST be false.

READ UNDER REVIEW:
${JSON.stringify(read, null, 2)}

Return ONLY valid JSON:
{
  "approved": boolean,
  "specificity_score": int,
  "grounding_score": int,
  "sharp_but_kind_score": int,
  "privacy_score": int,
  "anti_spiral_score": int,
  "issues": ["string"],
  "rewrite_instructions": ["string"]
}`;
}

/** Push notification copy by tone — the manifest from the feature spec. The
 *  model may supply its own `notification_copy`; we prefer that when it's within
 *  the 45-char budget, otherwise we fall back to this on-brand mapping. */
function notificationCopyForTone(tone, modelCopy) {
  if (typeof modelCopy === "string" && modelCopy.trim() && modelCopy.length <= 45) {
    return modelCopy.trim();
  }
  switch (tone) {
    case "soft":  return "One thing is ready.";
    case "funny":
    case "spicy": return "You've been clocked, kindly.";
    default:      return "ninety has a read for you.";
  }
}

/** Derive a tone preference from the user's recent feedback history. */
function deriveTonePreference(previousReads) {
  const ladder = ["soft", "direct", "spicy"];
  let idx = 1; // default: direct
  for (const r of previousReads) {
    if (r.userFeedback === "too_sharp") idx = Math.max(0, idx - 1);
    if (r.userFeedback === "felt_true" && r.sharpnessLevel) {
      const i = ladder.indexOf(r.sharpnessLevel);
      if (i >= 0) idx = i;
    }
  }
  return ladder[idx];
}

/** Build one read for a single user. Returns the doc object or null to skip. */
async function generateForUser(db, uid, today) {
  const since = new Date(today.getTime() - READ_LOOKBACK_DAYS * 86400 * 1000);

  const entriesSnap = await db
    .collection("users").doc(uid).collection("entries")
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();

  const entries = entriesSnap.docs.map((d) => d.data());
  const substantial = entries.filter((e) => (e.content || "").length > 40);
  if (substantial.length === 0) return null; // nothing to ground a read on.

  // Recent reads — context + feedback steering.
  const readsSnap = await db
    .collection("users").doc(uid).collection("dailyReads")
    .orderBy("createdAt", "desc").limit(5).get();
  const previousReads = readsSnap.docs.map((d) => {
    const r = d.data();
    return { readText: r.readText, sharpnessLevel: r.sharpnessLevel, userFeedback: r.userFeedback || null, detailedFeedbackCode: r.detailedFeedbackCode || null };
  });

  const tonePreference = deriveTonePreference(previousReads);

  const payload = {
    local_date: dateKey(today),
    days_since_last_entry: 0,
    entries_last_14_days_summary: substantial.slice(0, 10).map((e) => ({
      created: e.createdAt && e.createdAt.toDate ? e.createdAt.toDate().toISOString().slice(0, 10) : null,
      sentiment: e.sentimentLabel || null,
      mood: e.mood || null,
      snippet: (e.content || "").slice(0, 220),
      tags: e.tags || [],
    })),
    previous_reads: previousReads.map((r) => r.readText).filter(Boolean),
    previous_read_feedback: previousReads
      .filter((r) => r.userFeedback)
      .map((r) => ({ feedback: r.userFeedback, code: r.detailedFeedbackCode })),
    tone_preference: tonePreference,
  };

  // Stage 1.
  const gen = await callGeminiJSON(
    buildGeneratorPrompt({ payload, tonePreference }),
    { maxTokens: 500, temperature: 0.8 }
  );

  if (!gen || gen.should_show === false) return null;
  if (gen.safety_level && gen.safety_level !== "none") return null; // distress → hold back.
  if (!gen.read_text || !Array.isArray(gen.receipt_chips) || gen.receipt_chips.length < 2) return null;

  // Stage 2.
  const guard = await callGeminiJSON(buildGuardPrompt(gen), { maxTokens: 400, temperature: 0.0 });
  const scores = [
    guard.specificity_score, guard.grounding_score, guard.sharp_but_kind_score,
    guard.privacy_score, guard.anti_spiral_score,
  ];
  const passed = guard.approved === true && scores.every((s) => typeof s === "number" && s >= MIN_SCORE);
  if (!passed) {
    console.log("Read rejected by guard", { uid, issues: guard.issues });
    return null;
  }

  const validTones = ["soft", "direct", "funny", "spicy"];
  const tone = validTones.includes(gen.sharpness_level) ? gen.sharpness_level : "direct";
  // The sharpness ladder the app's "too sharp" loop walks is soft/direct/spicy.
  const sharpness = ["soft", "direct", "spicy"].includes(tonePreference) ? tonePreference : "direct";

  return {
    id: dateKey(today),
    userId: uid,
    localDate: admin.firestore.Timestamp.fromDate(new Date(dateKey(today) + "T00:00:00Z")),
    readText: String(gen.read_text).slice(0, 200),
    receiptChips: gen.receipt_chips.slice(0, 4).map(String),
    replyPrompt: String(gen.reply_prompt || "What's one true sentence back?").slice(0, 120),
    shareSafeText: String(gen.share_safe_text || gen.read_text).slice(0, 200),
    notificationCopy: notificationCopyForTone(tone, gen.notification_copy),
    tone,
    sharpnessLevel: sharpness,
    safetyLevel: "none",
    confidence: typeof gen.confidence === "number" ? gen.confidence : 0.7,
    shouldShow: true,
    sourceEntryIds: entriesSnap.docs.map((d) => d.id),
    sourcePatternIds: [],
    sourceRiverMarkIds: [],
    modelProvider: "google",
    modelName: MODEL,
    promptVersion: PROMPT_VERSION,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/** Send the morning curiosity push to every device token the user has stored.
 *  Title is always the brand; body is the tone-keyed notification copy. The read
 *  text itself is NEVER in the payload — the curiosity gap lives behind the
 *  sealed card. Invalid/expired tokens are pruned. */
async function sendReadPush(db, uid, read) {
  const tokensSnap = await db.collection("users").doc(uid)
    .collection("pushTokens").get();
  const tokens = tokensSnap.docs.map((d) => d.id).filter(Boolean);
  if (tokens.length === 0) return;

  const message = {
    tokens,
    notification: { title: "ninety", body: read.notificationCopy },
    data: { type: "daily_read", localDate: read.id },
    apns: { payload: { aps: { sound: "default" } } },
  };

  const resp = await admin.messaging().sendEachForMulticast(message);

  // Prune tokens FCM reports as permanently dead.
  const dead = [];
  resp.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-argument") {
      dead.push(tokens[i]);
    }
  });
  await Promise.all(dead.map((t) =>
    db.collection("users").doc(uid).collection("pushTokens").doc(t).delete()
  ));
}

exports.generateDailyReads = onSchedule(
  {
    // 05:00 UTC daily. NOTE: local_date is currently server (UTC) — see PRD
    // "Timezone" section for the planned per-user-timezone refinement.
    schedule: "0 5 * * *",
    timeZone: "Etc/UTC",
    region: "us-central1",
    secrets: [GEMINI_KEY],
    timeoutSeconds: 540,
    memory: "512MiB",
    maxInstances: 3,
  },
  async () => {
    const db = admin.firestore();
    const today = new Date();
    const usersSnap = await db.collection("users").get();

    let written = 0, skipped = 0, failed = 0;
    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      // Idempotency: never overwrite a read already written for today.
      const existing = await db.collection("users").doc(uid)
        .collection("dailyReads").doc(dateKey(today)).get();
      if (existing.exists) { skipped++; continue; }

      try {
        const read = await generateForUser(db, uid, today);
        if (!read) { skipped++; continue; }
        await db.collection("users").doc(uid)
          .collection("dailyReads").doc(read.id).set(read);
        written++;

        // Fire the morning push. Never let a delivery failure fail the write.
        try {
          await sendReadPush(db, uid, read);
        } catch (e) {
          console.error("sendReadPush error", { uid, error: String(e) });
        }
      } catch (e) {
        failed++;
        console.error("generateDailyReads user error", { uid, error: String(e) });
      }
    }
    console.log("generateDailyReads done", { written, skipped, failed });
  }
);
