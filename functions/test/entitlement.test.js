/* node:test — Spilr Pro access policy (lib/entitlement.js).
 *
 * Every branch here is money: a leak is unbounded model spend, an over-block
 * is a paying user with a dead app. So each rule gets a test, including the
 * ones that only matter at the edges (policy start clamp, expiry grace,
 * out-of-order webhooks, anonymous RevenueCat ids).
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const E = require("../lib/entitlement");
const { stubGeminiResponse, isStubEnabled, STUB_CHAT_REPLY } = require("../lib/geminiStub");

const DAY = 24 * 60 * 60 * 1000;
const T0 = Date.parse("2026-10-01T00:00:00Z");

function freeDoc(overrides = {}) {
  return {
    entitlement: "free",
    trialStartedAt: new Date(T0),
    previewStartedAt: new Date(T0),
    trialInTok: 0, trialOutTok: 0, trialPerSurface: {},
    day: new Date(T0).toISOString().slice(0, 10), dayInTok: 0, dayOutTok: 0, dayPerSurface: {},
    ...overrides,
  };
}

/* ── owners ──────────────────────────────────────────────────────────────── */

test("owner emails bypass only when Firebase says the email is verified", () => {
  assert.equal(E.isOwnerToken({ uid: "x", email: "satakshi1710@gmail.com", email_verified: true }), true);
  assert.equal(E.isOwnerToken({ uid: "x", email: "SataksP@Gmail.com ", email_verified: true }), true);
  assert.equal(E.isOwnerToken({ uid: "x", email: "ssahni30@gmail.com", email_verified: true }), true);
  // Registered with email/password but never verified — could be anyone.
  assert.equal(E.isOwnerToken({ uid: "x", email: "satakshi1710@gmail.com", email_verified: false }), false);
  assert.equal(E.isOwnerToken({ uid: "x", email: "someone@else.com", email_verified: true }), false);
  assert.equal(E.isOwnerToken(null), false);
});

test("owner uids bypass even without an email claim (Apple relay)", () => {
  assert.equal(E.isOwnerToken({ uid: "KrLOcdVDPKVjmmxhu85N3tibeRH3" }), true);
});

test("the App Review demo account is NOT an owner — reviewers must see the paywall", () => {
  assert.equal(E.isOwnerToken({ uid: "gqRvwbUxQxO3pGGdSZaj3nltzAz2", email: "test@spilr.com", email_verified: true }), false);
});

test("owners are allowed even with an expired entitlement and an exhausted preview", () => {
  const d = freeDoc({ entitlement: "expired", trialInTok: 10_000_000 });
  const r = E.decideAccess(d, T0 + 100 * DAY, "chat_turn", true);
  assert.equal(r.allowed, true);
  assert.equal(r.entitlement, "owner");
  assert.equal(r.ledger, "day");
});

test("owners still have a (very high) daily ceiling against runaway loops", () => {
  const d = freeDoc({ dayInTok: E.OWNER_DAILY_BUDGET.inTok });
  const r = E.decideAccess(d, T0, "chat_turn", true);
  assert.equal(r.allowed, false);
  assert.equal(r.reason, "daily_budget");
});

test("an owner flag stamped on the doc grants server-side jobs access", () => {
  const d = freeDoc({ owner: true, previewStartedAt: new Date(T0 - 100 * DAY) });
  assert.equal(E.hasAIAccess(d, T0), true);
});

/* ── free preview ────────────────────────────────────────────────────────── */

test("a brand-new user (no doc yet) gets AI — the preview starts on first use", () => {
  assert.equal(E.hasAIAccess(null, T0), true);
  assert.equal(E.decideAccess(null, T0, "journal_insights").allowed, true);
});

test("the preview allows AI inside its window and budget", () => {
  const r = E.decideAccess(freeDoc(), T0 + 1 * DAY, "journal_insights");
  assert.deepEqual([r.allowed, r.entitlement, r.ledger], [true, "free", "trial"]);
});

test("the preview ends after PREVIEW_DAYS", () => {
  const r = E.decideAccess(freeDoc(), T0 + (E.PREVIEW_DAYS * DAY) + 1, "journal_insights");
  assert.deepEqual([r.allowed, r.reason], [false, "preview_ended"]);
});

test("the preview ends early when its token budget is spent", () => {
  const d = freeDoc({ trialOutTok: E.PREVIEW_BUDGET.outTok });
  const r = E.decideAccess(d, T0 + 1000, "journal_insights");
  assert.deepEqual([r.allowed, r.reason], [false, "preview_ended"]);
});

test("legacy 'trial' docs are treated as the free preview", () => {
  const r = E.decideAccess(freeDoc({ entitlement: "trial" }), T0 + 1000, "chat_turn");
  assert.equal(r.entitlement, "free");
  assert.equal(r.allowed, true);
});

test("pre-policy accounts (only an old trialStartedAt) haven't started their preview yet", () => {
  // index.js stamps previewStartedAt on their next AI call; until then the
  // nightly jobs must not treat an August trialStartedAt as an expired preview.
  const d = freeDoc({ trialStartedAt: new Date(T0 - 40 * DAY), previewStartedAt: undefined });
  assert.equal(E.previewStartMs(d), null);
  assert.equal(E.hasAIAccess(d, T0), true);
});

test("one surface can't eat more than its share of the preview", () => {
  // A non-chat surface is capped at SURFACE_SHARE_CAP (0.5).
  const d = freeDoc({ trialPerSurface: { journal_insights: { inTok: E.PREVIEW_BUDGET.inTok * E.SURFACE_SHARE_CAP, outTok: 0 } } });
  const r = E.decideAccess(d, T0 + 1000, "journal_insights");
  assert.deepEqual([r.allowed, r.reason], [false, "surface_cap"]);
  // A different surface keeps its own untouched bucket.
  assert.equal(E.decideAccess(d, T0 + 1000, "chat_turn").allowed, true);
});

test("chat gets a larger preview share than other surfaces (temporary)", () => {
  // Chat is lifted to CHAT_SURFACE_SHARE_CAP (0.7): still allowed at the 0.5
  // mark that would cap any other surface...
  const mid = freeDoc({ trialPerSurface: { chat_turn: { inTok: E.PREVIEW_BUDGET.inTok * E.SURFACE_SHARE_CAP, outTok: 0 } } });
  assert.equal(E.decideAccess(mid, T0 + 1000, "chat_turn").allowed, true);
  // ...and capped at its own 0.7 share.
  const full = freeDoc({ trialPerSurface: { chat_turn: { inTok: E.PREVIEW_BUDGET.inTok * E.CHAT_SURFACE_SHARE_CAP, outTok: 0 } } });
  const r = E.decideAccess(full, T0 + 1000, "chat_turn");
  assert.deepEqual([r.allowed, r.reason], [false, "surface_cap"]);
});

/* ── paid / expired ──────────────────────────────────────────────────────── */

test("paid users are allowed long after the preview, on the daily ledger", () => {
  const d = freeDoc({ entitlement: "paid", expiresAtMs: T0 + 400 * DAY });
  const r = E.decideAccess(d, T0 + 200 * DAY, "chat_turn");
  assert.deepEqual([r.allowed, r.entitlement, r.ledger], [true, "paid", "day"]);
});

test("paid users hit a daily cap with a reason that must NOT trigger the paywall", () => {
  const d = freeDoc({ entitlement: "paid", dayInTok: E.PAID_DAILY_BUDGET.inTok });
  const r = E.decideAccess(d, T0, "chat_turn");
  assert.deepEqual([r.allowed, r.reason], [false, "daily_budget"]);
});

test("yesterday's paid usage doesn't count against today", () => {
  const d = freeDoc({ entitlement: "paid", day: "2000-01-01", dayInTok: 10_000_000 });
  assert.equal(E.decideAccess(d, T0, "chat_turn").allowed, true);
});

test("lifetime (no expiry) stays paid forever", () => {
  const d = freeDoc({ entitlement: "paid", expiresAtMs: null });
  assert.equal(E.effectiveEntitlement(d, T0 + 5000 * DAY, false), "paid");
});

test("a lapsed subscription is enforced server-side even if EXPIRATION never arrives", () => {
  const d = freeDoc({ entitlement: "paid", expiresAtMs: T0 });
  assert.equal(E.effectiveEntitlement(d, T0 + E.EXPIRY_GRACE_MS - 1, false), "paid");
  assert.equal(E.effectiveEntitlement(d, T0 + E.EXPIRY_GRACE_MS + 1, false), "expired");
  const r = E.decideAccess(d, T0 + E.EXPIRY_GRACE_MS + 1, "chat_turn");
  assert.deepEqual([r.allowed, r.reason], [false, "expired"]);
});

test("expired users are blocked everywhere", () => {
  const d = freeDoc({ entitlement: "expired" });
  assert.equal(E.hasAIAccess(d, T0), false);
  assert.equal(E.decideAccess(d, T0, "chat_turn").reason, "expired");
});

/* ── RevenueCat webhook mapping ──────────────────────────────────────────── */

test("trial start / purchase / renewal → paid, with the expiry carried through", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "TRANSFER"]) {
    const u = E.entitlementUpdateFromEvent({ type, expiration_at_ms: 123, period_type: "TRIAL" });
    assert.deepEqual(u, { entitlement: "paid", expiresAtMs: 123, periodType: "TRIAL" }, type);
  }
});

test("the lifetime purchase (NON_RENEWING_PURCHASE) grants paid with no expiry", () => {
  const u = E.entitlementUpdateFromEvent({ type: "NON_RENEWING_PURCHASE", period_type: "NORMAL" });
  assert.deepEqual(u, { entitlement: "paid", expiresAtMs: null, periodType: "NORMAL" });
});

test("cancelling auto-renew keeps access until expiry (only the date updates)", () => {
  assert.deepEqual(E.entitlementUpdateFromEvent({ type: "CANCELLATION", expiration_at_ms: 999 }), { expiresAtMs: 999 });
  assert.equal(E.entitlementUpdateFromEvent({ type: "CANCELLATION" }), null);
});

test("EXPIRATION ends access", () => {
  assert.equal(E.entitlementUpdateFromEvent({ type: "EXPIRATION", expiration_at_ms: 1 }).entitlement, "expired");
});

test("events for some other entitlement are ignored", () => {
  assert.equal(E.entitlementUpdateFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["other"] }), null);
  assert.equal(E.entitlementUpdateFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: [E.PRO_ENTITLEMENT_ID] }).entitlement, "paid");
});

test("unknown and TEST events change nothing", () => {
  assert.equal(E.entitlementUpdateFromEvent({ type: "TEST" }), null);
  assert.equal(E.entitlementUpdateFromEvent({ type: "SOMETHING_NEW" }), null);
  assert.equal(E.entitlementUpdateFromEvent(null), null);
});

test("anonymous RevenueCat ids resolve to the Firebase uid from aliases", () => {
  assert.equal(E.resolveAppUserId({ app_user_id: "uid123" }), "uid123");
  assert.equal(E.resolveAppUserId({
    app_user_id: "$RCAnonymousID:abc", aliases: ["$RCAnonymousID:abc", "uid456"],
  }), "uid456");
  assert.equal(E.resolveAppUserId({ app_user_id: "$RCAnonymousID:abc" }), null);
});

/* ── emulator stub ───────────────────────────────────────────────────────── */

test("the Gemini stub only switches on inside the emulator with the flag set", () => {
  assert.equal(isStubEnabled({}), false);
  assert.equal(isStubEnabled({ SPILR_GEMINI_STUB: "1" }), false); // production can't enable it
  assert.equal(isStubEnabled({ FUNCTIONS_EMULATOR: "true" }), false);
  assert.equal(isStubEnabled({ FUNCTIONS_EMULATOR: "true", SPILR_GEMINI_STUB: "1" }), true);
});

test("the Gemini stub returns Gemini's own response shape", () => {
  const chat = stubGeminiResponse("chat_turn", {});
  assert.equal(chat.candidates[0].content.parts[0].text, STUB_CHAT_REPLY);
  const insights = stubGeminiResponse("journal_insights", { responseMimeType: "application/json" });
  const parsed = JSON.parse(insights.candidates[0].content.parts[0].text);
  assert.equal(parsed.bullets.length, 2);
});
