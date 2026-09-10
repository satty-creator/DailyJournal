# RevenueCat Setup — Runbook

Companion to `DEPLOY_CHECKLIST.md`. Covers turning on the trial/paid entitlement
layer described in `ai-cost-audit-2026-09-06.md` (Phase 5). The code side is
already done — this is the remaining Xcode / App Store Connect / RevenueCat
dashboard work, none of which can be scripted.

**Already done, in code:**
- `revenueCatWebhook` Cloud Function (`functions/index.js`) — writes `entitlements/{uid}` (full event record) and mirrors `entitlement` into `aiUsage/{uid}` (the doc `geminiProxy` actually budgets against).
- `firestore.rules` — `aiUsage/{uid}` and `entitlements/{uid}` are top-level, deny-all to clients (Admin SDK only).
- `geminiProxy`'s token-budget check (`checkAIBudget`/`recordAIUsage` in `functions/index.js`) — reads `aiUsage/{uid}.entitlement` on every AI call.
- **The RevenueCat + RevenueCatUI SPM package is already added to the Xcode project** (`purchases-ios-spm`, both products on the `DailyJournal` target).

**Not done — this doc:** configuring the actual product/entitlement/webhook, and the few lines of app code that call the SDK.

---

## 1. App Store Connect — the product

- [ ] App Store Connect → the app → Subscriptions → create a Subscription Group (e.g. "Spilr Pro") if none exists.
- [ ] Create one auto-renewable subscription inside it (e.g. `spilr_pro_monthly`).
- [ ] Add an **Introductory Offer**: type "Free Trial", duration **14 days**, on that subscription.
- [ ] Fill in the required localized display name/description. Submit for review — can ride along with your next app build submission, doesn't need its own release.

## 2. RevenueCat dashboard — project + entitlement

- [ ] Create (or open) the project; add the iOS app with bundle id `com.satakshi.DailyJournal`.
- [ ] App Store Connection → add the App Store Connect **In-App Purchase Key** (App Store Connect → Users and Access → Integrations → In-App Purchase) so RevenueCat can validate receipts server-side.
- [ ] Create an **Entitlement** (e.g. `pro`) and attach `spilr_pro_monthly` to it.
- [ ] Create an **Offering** with a **Package** wrapping that product.
- [ ] Copy the **public Apple API key** from RevenueCat → API Keys. This ships in the app — it's a public SDK key, not a secret.

## 3. App code — configure + identify

The SDK is linked; nothing calls it yet. Three call sites:

- [ ] **`DailyJournal/App/DailyJournalApp.swift`**, in `init()`, before any sign-in UI:
  ```swift
  import RevenueCat
  // ...
  Purchases.configure(withAPIKey: "<public key from step 2>")
  ```
  Don't pass `appUserID` here — the Firebase uid isn't known yet at launch. Omitting it gives an anonymous ID until login below.

- [ ] **`DailyJournal/Auth/AuthService.swift`** — `signIn` (:103), `signInWithGoogle` (:113), `signInWithApple` (:160), and `signUp` (:58) each return an `AppUser` on success. Add right after each success:
  ```swift
  try? await Purchases.shared.logIn(user.id)   // or whatever the uid field is named on AppUser
  ```
  **This match matters**: `revenueCatWebhook` keys every write on `event.app_user_id`, which is whatever RevenueCat's App User ID is set to. If it doesn't equal the Firebase uid, the webhook writes to the wrong doc (or a stray anonymous one) and `geminiProxy` never sees the entitlement — silently, since the client already treats a missing/expired entitlement as "fall back to local," so there's no visible error to notice the mismatch by.

- [ ] A paywall (RevenueCatUI's `PaywallView` against the Offering from step 2, or a custom screen over `Purchases.shared.offerings()`) and where it hooks into `AppRouter`/`OnboardingView` — a product decision, not covered here.

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
