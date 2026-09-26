/* entitlement.js — who may spend AI, and how much.
 *
 * Pure: no firebase-admin, no network. index.js reads `aiUsage/{uid}` and the
 * caller's decoded ID token, then asks this file for a decision. Keeping the
 * policy here is what lets `npm test` pin every branch of it — a paywall
 * that leaks is a cost bug and a paywall that over-blocks is a churn bug,
 * and neither shows up in a code review of a transaction callback.
 *
 * THE MODEL (Spilr Pro, Sept 2026)
 *   - Writing is never gated. Only AI (reflections, chat replies, Mirror,
 *     letters) is.
 *   - Everyone starts on a FREE PREVIEW: PREVIEW_DAYS of AI from their first
 *     AI call, capped at PREVIEW_BUDGET tokens, whichever runs out first. That
 *     is what makes onboarding's first reflection and first sketch work
 *     before the paywall has been shown.
 *   - Starting the App Store free trial (2 weeks, configured in App Store
 *     Connect — not here) or paying makes the RevenueCat webhook set
 *     `entitlement: "paid"`. Trial users are "paid" for budgeting: Apple is
 *     holding their card, and the trial is the product working as sold.
 *   - `expiresAtMs` (from the webhook) is enforced HERE too, with a grace
 *     window, so a missed EXPIRATION webhook can't leave access on forever.
 *   - OWNERS (the founder's accounts) bypass the paywall entirely. They still
 *     get a very high daily ceiling, so a runaway loop on a dev build can't
 *     spend unbounded money.
 */

"use strict";

/** Must match `OwnerAccess.emails` in DailyJournal/Auth/OwnerAccess.swift. */
const OWNER_EMAILS = new Set([
  "satakshi1710@gmail.com",
  "sataksp@gmail.com",
  "ssahni30@gmail.com",
]);

/** Belt and braces for owners whose token has no email claim (e.g. an Apple
 *  "hide my email" relay). Firebase uids from the spilr-100f7 Auth console. */
const OWNER_UIDS = new Set([
  "KrLOcdVDPKVjmmxhu85N3tibeRH3", // satakshi1710@gmail.com
  "cy7T8gtnH9bqmYC0JeWAvXdkbLM2", // ssahni30@gmail.com
]);

const DAY_MS = 24 * 60 * 60 * 1000;

const PREVIEW_DAYS = 3;
const PREVIEW_BUDGET = { inTok: 150000, outTok: 25000 };  // whole preview
const PAID_DAILY_BUDGET = { inTok: 150000, outTok: 25000 };
const OWNER_DAILY_BUDGET = { inTok: 3000000, outTok: 500000 };
const SURFACE_SHARE_CAP = 0.5;

/* The preview clock is `previewStartedAt`, stamped on a user's first AI call
 * under THIS policy (see checkAIBudget in index.js). Accounts from the old
 * token-only "trial" (some from August) have only `trialStartedAt`; they get
 * `previewStartedAt` stamped on their first call after the deploy, so every
 * existing user gets a full preview starting then — nobody is cut off the
 * moment this ships, and there's no date to set by hand. */

/** Billing-retry grace after `expiresAtMs`. Apple retries a failed renewal for
 *  up to 60 days, but RevenueCat keeps the entitlement active through the
 *  grace period it reports and moves `expiration_at_ms` accordingly, so a
 *  short buffer here only has to cover webhook delivery delay. */
const EXPIRY_GRACE_MS = 3 * DAY_MS;

function normEmail(email) {
  return typeof email === "string" ? email.trim().toLowerCase() : "";
}

/**
 * True for the founder's accounts. `decoded` is a verified Firebase ID token.
 * An email only counts once Firebase says the address is verified — otherwise
 * anyone could register "satakshi1710@gmail.com" with email/password and,
 * before verifying it, get unlimited AI.
 */
function isOwnerToken(decoded) {
  if (!decoded) return false;
  if (OWNER_UIDS.has(decoded.uid)) return true;
  const email = normEmail(decoded.email);
  return !!email && decoded.email_verified === true && OWNER_EMAILS.has(email);
}

function toMs(v) {
  if (v == null) return null;
  if (typeof v === "number") return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v.toDate === "function") return v.toDate().getTime();
  return null;
}

/** When this user's free preview started, or null if it hasn't yet. */
function previewStartMs(data) {
  return toMs(data && data.previewStartedAt);
}

/** The state an entitlement is actually in at `nowMs`, after expiry checks. */
function effectiveEntitlement(data, nowMs, isOwner) {
  if (isOwner) return "owner";
  const ent = data && data.entitlement;
  if (ent === "paid") {
    const exp = toMs(data.expiresAtMs);
    if (exp != null && nowMs > exp + EXPIRY_GRACE_MS) return "expired";
    return "paid";
  }
  if (ent === "expired") return "expired";
  return "free"; // "trial" (legacy), "free", missing — all the preview tier
}

/**
 * Status-only check for server-side AI jobs (nightly mining, the weekly
 * letter, Mirror Ask, bootstrap). They have no per-call token count up front,
 * so they get the same yes/no a client call would, minus the budget ledger.
 */
function hasAIAccess(data, nowMs, { isOwner = false } = {}) {
  const ent = effectiveEntitlement(data, nowMs, isOwner || !!(data && data.owner));
  if (ent === "owner" || ent === "paid") return true;
  if (ent === "expired") return false;
  const start = previewStartMs(data);
  if (start == null) return true; // never used AI yet — the preview hasn't begun
  if (nowMs - start > PREVIEW_DAYS * DAY_MS) return false;
  const inTok = (data && data.trialInTok) || 0;
  const outTok = (data && data.trialOutTok) || 0;
  return inTok < PREVIEW_BUDGET.inTok && outTok < PREVIEW_BUDGET.outTok;
}

/**
 * The per-call decision geminiProxy makes before spending anything.
 *
 * @param data     the current `aiUsage/{uid}` doc, or null if none exists
 * @param nowMs    epoch ms
 * @param surface  the (already validated) surface tag
 * @param isOwner  from `isOwnerToken(decoded)`
 * @returns {{ allowed, entitlement, reason, ledger }}
 *   entitlement: "owner" | "paid" | "free" | "expired"
 *   reason:      null when allowed, else "preview_ended" | "expired" |
 *                "daily_budget" | "surface_cap"
 *   ledger:      which counter pair to charge — "day" or "trial"
 */
function decideAccess(data, nowMs, surface, isOwner = false) {
  const ent = effectiveEntitlement(data, nowMs, isOwner);

  if (ent === "expired") {
    return { allowed: false, entitlement: ent, reason: "expired", ledger: "trial" };
  }

  if (ent === "owner" || ent === "paid") {
    const budget = ent === "owner" ? OWNER_DAILY_BUDGET : PAID_DAILY_BUDGET;
    const today = new Date(nowMs).toISOString().slice(0, 10);
    const sameDay = data && data.day === today;
    const usedIn = sameDay ? (data.dayInTok || 0) : 0;
    const usedOut = sameDay ? (data.dayOutTok || 0) : 0;
    if (usedIn >= budget.inTok || usedOut >= budget.outTok) {
      return { allowed: false, entitlement: ent, reason: "daily_budget", ledger: "day" };
    }
    const per = (sameDay && data.dayPerSurface && data.dayPerSurface[surface]) || { inTok: 0, outTok: 0 };
    if (ent !== "owner" &&
        (per.inTok >= budget.inTok * SURFACE_SHARE_CAP || per.outTok >= budget.outTok * SURFACE_SHARE_CAP)) {
      return { allowed: false, entitlement: ent, reason: "surface_cap", ledger: "day" };
    }
    return { allowed: true, entitlement: ent, reason: null, ledger: "day" };
  }

  // Free preview.
  if (!hasAIAccess(data, nowMs)) {
    return { allowed: false, entitlement: "free", reason: "preview_ended", ledger: "trial" };
  }
  const per = (data && data.trialPerSurface && data.trialPerSurface[surface]) || { inTok: 0, outTok: 0 };
  if (per.inTok >= PREVIEW_BUDGET.inTok * SURFACE_SHARE_CAP ||
      per.outTok >= PREVIEW_BUDGET.outTok * SURFACE_SHARE_CAP) {
    return { allowed: false, entitlement: "free", reason: "surface_cap", ledger: "trial" };
  }
  return { allowed: true, entitlement: "free", reason: null, ledger: "trial" };
}

/* ── RevenueCat webhook ──────────────────────────────────────────────────── */

const PRO_ENTITLEMENT_ID = "spilr_ai_mood_journal_pro";

// NON_RENEWING_PURCHASE is how RevenueCat reports the lifetime (non-consumable)
// product. It was missing before, so a lifetime buyer was never marked paid.
const PAID_EVENTS = new Set([
  "INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE",
  "TRANSFER", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_EXTENDED",
]);
// CANCELLATION = auto-renew turned off; access continues to expiry, so it only
// refreshes the expiry date. BILLING_ISSUE = retry window; same.
const EXPIRY_ONLY_EVENTS = new Set(["CANCELLATION", "BILLING_ISSUE"]);
const EXPIRED_EVENTS = new Set(["EXPIRATION"]);

function isAnonymousRcId(id) {
  return typeof id === "string" && id.startsWith("$RCAnonymousID:");
}

/** The Firebase uid an event belongs to. A purchase made before `logIn(uid)`
 *  arrives under an anonymous RevenueCat id, with the real one in `aliases`
 *  or (for TRANSFER) `transferred_to`. */
function resolveAppUserId(event) {
  if (!event) return null;
  const candidates = [
    event.app_user_id,
    ...(Array.isArray(event.transferred_to) ? event.transferred_to : []),
    ...(Array.isArray(event.aliases) ? event.aliases : []),
    event.original_app_user_id,
  ];
  return candidates.find((id) => typeof id === "string" && id && !isAnonymousRcId(id)) || null;
}

/** What an event should write to `aiUsage/{uid}`, or null to leave it alone. */
function entitlementUpdateFromEvent(event) {
  if (!event || !event.type) return null;
  const ids = event.entitlement_ids;
  if (Array.isArray(ids) && ids.length && !ids.includes(PRO_ENTITLEMENT_ID)) return null;

  const expiresAtMs = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
  const periodType = event.period_type || null;
  if (PAID_EVENTS.has(event.type)) {
    return { entitlement: "paid", expiresAtMs, periodType };
  }
  if (EXPIRY_ONLY_EVENTS.has(event.type)) {
    return expiresAtMs != null ? { expiresAtMs } : null;
  }
  if (EXPIRED_EVENTS.has(event.type)) {
    return { entitlement: "expired", expiresAtMs, periodType };
  }
  return null;
}

module.exports = {
  OWNER_EMAILS, OWNER_UIDS, PREVIEW_DAYS, PREVIEW_BUDGET, PAID_DAILY_BUDGET,
  OWNER_DAILY_BUDGET, SURFACE_SHARE_CAP, EXPIRY_GRACE_MS,
  PRO_ENTITLEMENT_ID,
  isOwnerToken, effectiveEntitlement, hasAIAccess, decideAccess, previewStartMs,
  resolveAppUserId, entitlementUpdateFromEvent,
};
