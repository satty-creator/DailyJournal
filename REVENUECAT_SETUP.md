# RevenueCat Setup — Runbook

Companion to `DEPLOY_CHECKLIST.md`. Covers turning on the trial/paid entitlement
layer described in `ai-cost-audit-2026-09-06.md` (Phase 5). The code side is
already done — this is the remaining Xcode / App Store Connect / RevenueCat
dashboard work, none of which can be scripted.

**Already done, in code (§3 below is reference only):**
- `revenueCatWebhook` Cloud Function (`functions/index.js`) — writes `entitlements/{uid}` (full event record) and mirrors `entitlement` into `aiUsage/{uid}` (the doc `geminiProxy` actually budgets against).
- `firestore.rules` — `aiUsage/{uid}` and `entitlements/{uid}` are top-level, deny-all to clients (Admin SDK only).
- `geminiProxy`'s token-budget check (`checkAIBudget`/`recordAIUsage` in `functions/index.js`) — reads `aiUsage/{uid}.entitlement` on every AI call.
- **The RevenueCat + RevenueCatUI SPM package is already added to the Xcode project** (`purchases-ios-spm`, both products on the `DailyJournal` target).
- `Purchases.configure`, `logIn`/`logOut` at every sign-in/sign-out/session-restore path, and
  `SpilrPaywallView` are all implemented — see §3.

**Not done — dashboard/App Store Connect work only, none of it scriptable:** clearing
`spilr_pro_monthly`'s Missing Metadata (§1), fixing the `$rc_annual`/`$rc_lifetime` package wiring and
creating a paywall (§2), and setting the webhook secret (§4). Until those are done, the paywall fails
with RevenueCat error 23.

---

## 1. App Store Connect — the product

- [ ] App Store Connect → the app → Subscriptions → create a Subscription Group (e.g. "Spilr Pro") if none exists.
- [x] Create one auto-renewable subscription inside it — `spilr_pro_monthly`, live in App Store Connect.
- [ ] Add an **Introductory Offer**: type "Free Trial", duration **14 days**, on that subscription.
- [ ] Fill in the required localized display name/description — `spilr_pro_monthly` is currently showing
  **Missing Metadata** in the RevenueCat dashboard, which is why the paywall fails with error 23
  (RevenueCat/StoreKit can't fetch a product in that state). Submit for review — can ride along with
  your next app build submission, doesn't need its own release.

## 2. RevenueCat dashboard — project + entitlement

- [x] Project created; iOS app added with bundle id `com.satakshi.DailyJournal`.
- [x] App Store Connection — In-App Purchase Key (`X3J3US7QN4.p8`) and App Store Connect API key
  (`Y7MA28SL73.p8`) are both uploaded and show **Valid credentials**.
- [x] Entitlement `spilr_ai_mood_journal_pro` exists, attached to 4 products (**not** `pro` — the
  identifier below and in `EntitlementService.swift:29` is the one actually live; this doc previously
  said to create `pro`, which was never done and would have been a mismatch had it been).
- [x] Offering `default` exists with 3 packages (`$rc_monthly`, `$rc_annual`, `$rc_lifetime`) — **but
  `$rc_annual` and `$rc_lifetime` are mis-wired**: `$rc_annual` points at `spilr_pro_monthly` (the
  monthly product, not an annual one) and `$rc_lifetime` only has a Test Store product attached, which
  the shipped `appl_` API key can never fetch. Either create real `spilr_pro_yearly` /
  `spilr_pro_lifetime` App Store products and attach those, or delete those two packages until you do.
- [ ] **No paywall exists yet** (RevenueCat → Paywalls → "No paywalls yet") — the `default` offering's
  "Add Paywall" link is unclicked. `SpilrPaywallView` renders whichever paywall is attached to the
  offering it fetches; without one there's nothing to draw even once the products above resolve.
- [x] Public Apple API key copied into the app (see §3 — already done in code).

## 3. App code — configure + identify

Already implemented — this section is historical/reference only, not a to-do.

- **`DailyJournal/App/DailyJournalApp.swift`**, in `init()`, before any sign-in UI:
  ```swift
  import RevenueCat
  // ...
  Purchases.configure(withAPIKey: "appl_cEAPPXndXigFKNIjpttRQWIDEkE")
  ```
  No `appUserID` passed — the Firebase uid isn't known yet at launch. Omitting it gives an anonymous ID
  until login below. `Purchases.logLevel = .debug` is also set under `#if DEBUG` right before this, so a
  configuration failure (like the ones above) prints the underlying StoreKit error instead of only
  showing RevenueCatUI's generic alert.

- **`DailyJournal/Auth/AuthService.swift`** — every sign-in/sign-up success path (`signUp`, `signIn`,
  `signInWithGoogle`, `signInWithApple`, and the guest→permanent `linkGuestWithEmail` upgrade) calls
  `identifyRevenueCat(uid:)`, which does:
  ```swift
  _ = try? await Purchases.shared.logIn(uid)
  ```
  `signOut()` and `deleteAccount(...)` call the mirror-image `deidentifyRevenueCat()` (`logOut()`), and
  `AuthViewModel.listenToAuthState()` re-identifies on every session restore, so a device switching
  accounts or recovering a Firebase session after a reinstall can't drift onto the wrong App User ID.

  **This match matters**: `revenueCatWebhook` keys every write on `event.app_user_id`, which is
  whatever RevenueCat's App User ID is set to. If it doesn't equal the Firebase uid, the webhook writes
  to the wrong doc (or a stray anonymous one) and `geminiProxy` never sees the entitlement — silently,
  since the client already treats a missing/expired entitlement as "fall back to local," so there's no
  visible error to notice the mismatch by.

- **`DailyJournal/Components/SpilrPaywallView.swift`** — preflights `Purchases.shared.offerings()`
  itself and renders `RevenueCatUI.PaywallView(offering:)` against the current Offering from step 2, with
  a themed failure state (and a logged error) if the offering has no fetchable packages. Hooked in from
  the Profile "Get Spilr Pro" row via `RootView.swift`.

## 4. Wire the webhook

- [ ] Function URL (live once `firebase deploy --only functions` has run): `https://us-central1-spilr-100f7.cloudfunctions.net/revenueCatWebhook`
- [ ] Pick a long random secret string yourself — this isn't issued by RevenueCat, it's a shared value both sides check.
- [ ] RevenueCat dashboard → Project Settings → Integrations → Webhooks → add the URL above, set the **Authorization header value** to that secret.
- [ ] `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET` with the same secret. Redeploy functions if this happens after the last deploy.

## 5. Test before trusting it

- [ ] Use a Sandbox Apple ID (App Store Connect → Users and Access → Sandbox Testers) on a device/simulator signed into that sandbox account.
- [ ] Make a test purchase through the app's paywall.
- [ ] RevenueCat dashboard → that customer's history shows the event.
- [ ] Firestore: `entitlements/{uid}` has `lastEventType: "INITIAL_PURCHASE"`; `aiUsage/{uid}.entitlement` is `"paid"`.
- [ ] Make one AI call as that user; confirm in the `aiUsage` console logs (Phase 0 instrumentation) it's now budgeted against `PAID_DAILY_BUDGET`, not `TRIAL_BUDGET`.
- [ ] RevenueCat's sandbox accelerates renewal/expiry — let a subscription lapse and confirm the `EXPIRATION` event flips `entitlement` to `"expired"`, and that a subsequent AI call as that user gets a silent local-fallback (402 under the hood), not an error.
