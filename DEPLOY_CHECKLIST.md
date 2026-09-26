# Spilr — Deploy Checklist (end-to-end)

Goal: get the backend live so Firestore writes stop failing and the **server LLM** Today's Read + nightly Mirror engine actually run. Project: **`spilr-100f7`**. Do these in order.

---

## 0 · Prerequisites (once)

- [ ] You're signed in to the Google account that has **Owner** (or Editor) on `spilr-100f7`. Check at [console.firebase.google.com](https://console.firebase.google.com) — the account that lists `spilr-100f7` is the right one.
- [ ] Node 20 installed (`node -v`).
- [ ] Firebase CLI installed and logged in:
  ```bash
  npm install -g firebase-tools
  firebase login          # sign in as the Owner account above
  firebase use spilr-100f7
  ```

---

## 1 · Provision the Firestore `(default)` database  ← the thing that's currently missing

Easiest (Console):
- [ ] Firebase Console → **spilr-100f7** → Build → **Firestore Database** → **Create database**
- [ ] Mode: **Production** (your `firestore.rules` already lock it down per-user)
- [ ] Location: **`nam5`** (US multi-region; compatible with your `us-central1` functions). ⚠️ **Location is permanent.**

Or CLI:
```bash
gcloud firestore databases create --location=nam5 --project=spilr-100f7
```
- [ ] Confirm it exists: Console shows an empty Firestore, no "database not found" error.

---

## 2 · Set the Gemini secret (must exist in THIS project)

Migrations often miss this — without it `geminiProxy` and the nightly jobs fail.
```bash
firebase functions:secrets:set GEMINI_KEY --project spilr-100f7
# paste the Gemini API key when prompted
```
- [ ] Verify: `firebase functions:secrets:access GEMINI_KEY --project spilr-100f7` prints the key.

- [ ] Also set `REVENUECAT_WEBHOOK_SECRET` (a self-chosen long random string, not issued by
  RevenueCat — see `REVENUECAT_SETUP.md` §4). Without it, `revenueCatWebhook` 401s every event,
  and paying users stay on the trial AI budget with no visible error.
  ```bash
  firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET --project spilr-100f7
  ```

---

## 3 · Deploy rules + indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage --project spilr-100f7
```
- [ ] Rules deploy shows success. (Indexes: your new queries are single-field / auto-indexed, so this should be a no-op — fine.)
- [ ] **Storage rules deployed too** (`storage` above, alongside Firestore). This step was missing from this checklist for a while — a migration to a new project (e.g. `dailyjournal-12a35` → `spilr-100f7`) provisions a brand-new Storage bucket with a deny-all default ruleset, and `firebase.json` declaring `"storage": {"rules": "storage.rules"}` does nothing until it's actually deployed. A missed deploy here presents as "photos silently never attach" — `PhotoUploadService.uploadEntryPhoto` treats a permission-denied upload the same as any other failure (logs it via `AnalyticsManager.trackError`, returns nil) so nothing crashes or alerts, the photo just never shows up. Confirm in Firebase Console → Storage → Rules that the live ruleset matches `storage.rules`.

---

## 4 · Deploy the Cloud Functions

```bash
cd functions && npm install && cd ..
firebase deploy --only functions --project spilr-100f7
```
Expect **fifteen** functions to deploy (the "three" this checklist used to name are long gone — `generateDailyReads` was retired and replaced by the hourly-dispatch pair below):
- [ ] `geminiProxy` (on-request proxy the app calls)
- [ ] `dispatchUserWork` (the resumable per-page dispatcher every hourly/nightly job fans out through)
- [ ] `mirrorAsk`
- [ ] `computeUserDerived`
- [ ] `generateWeeklyLetters` (hourly dispatch; `dispatchUserWork`'s `weeklyLetter` branch fires `buildUserWeeklyLetter` at each user's local Sunday 18:00)
- [ ] `buildUserWeeklyLetter`
- [ ] `generateDailyReadingPush` (hourly dispatch; fires `sendDailyReadingPush` at each user's local 8am)
- [ ] `sendDailyReadingPush`
- [ ] `generateNightlyInsights` (04:00 UTC; mines hypotheses + Self-Model)
- [ ] `mineUserInsights`
- [ ] `bootstrapMirror`
- [ ] `refreshDerived`
- [ ] `revenueCatWebhook`
- [ ] `deleteAccount` (Settings → Delete account calls this; the app cannot delete an account without it)
- [ ] `runNightlyForUser` (dev-only manual trigger, gated behind `DEV_ADMIN_UIDS`)

If prompted about scheduler/pub-sub or Cloud Run permissions, accept. `generateWeeklyLetters` and `generateDailyReadingPush` each provision a new Cloud Scheduler job, and `buildUserWeeklyLetter`/`sendDailyReadingPush` each provision a new Cloud Tasks queue on first deploy — expect that prompt too. First deploy can take a few minutes.

---

## 5 · Verify end-to-end

- [ ] **App writes work now:** open the app, write an entry, confirm `users/{uid}/entries/{id}` appears in the Firestore console. `entryAnalyses/{id}` should appear shortly after (that's Prompt A running).
- [ ] **Proxy works:** the chat and per-entry reflection return AI (not just local fallback). Check function logs:
  ```bash
  firebase functions:log --only geminiProxy --project spilr-100f7
  ```
- [ ] **Daily reading push:** wait for the top of the next hour, or force-run `generateDailyReadingPush` from the Cloud Scheduler console. Confirm a doc at `users/{uid}/readings/{yyyy-MM-dd}` and check logs for `dispatch dailyReading page` → `dailyReadingPush sent` (or `dailyReadingPush skipped` with a reason, if today's reading is silent or missing).
- [ ] **Weekly letter:** force-run `generateWeeklyLetters`, or wait for a user's local Sunday 18:00. Confirm a doc at `users/{uid}/mirrorLetters/{yyyy-MM-dd}` and logs for `dispatch weeklyLetter page` → `buildUserWeeklyLetter`. In the app, the Mirror tab should show the unread-letter banner above the Today card.
- [ ] **Nightly insights:** after it runs (04:00 UTC, or force-run), confirm `users/{uid}/patternHypotheses/*` and `users/{uid}/selfModel/current` populate for a user with ≥3 `entryAnalyses`. Log line: `generateNightlyInsights done`.
- [ ] **Account deletion:** on a throwaway account, Settings → Delete account. The app should return to the sign-in screen, `users/{uid}` should be gone from the Firestore console along with `aiUsage/{uid}` and `entitlements/{uid}`, and the uid should no longer appear in Authentication. Log line: `deleteAccount`. Signing back in with the same email creates a brand-new uid.

---

## 6 · First-run notes

- A user needs a few entries before the read/insights have anything to ground on (read needs ≥1 substantial entry; nightly mining needs ≥3 `entryAnalyses`; the weekly letter needs ≥3 entries in the current week or it silently skips — that's `below_threshold`, not a bug).
- `timezone` is written to the user doc on sign-in — existing users must open the app once so `generateDailyReadingPush` and `generateWeeklyLetters` fire at their correct local hour (until then both default to **UTC**, not a US timezone).
- To backfill immediately for testing, force-run the scheduled functions from the Cloud Scheduler console, or (for the weekly letter specifically) POST to the dev-only `runNightlyForUser` HTTP function with a Firebase ID token and body `{"stages":["facts","observations","letter"]}` — gated behind `DEV_ADMIN_UIDS`, see `functions/index.js`'s `runNightlyForUser`. The response's `out.letter` says whether it wrote or why not (e.g. `below_threshold`, `lint_rejected`).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Missing or insufficient permissions" | Rules not deployed / wrong project | Step 3; confirm `firebase use spilr-100f7`. |
| App writes still fail | `(default)` DB not created | Step 1. |
| AI falls back to local everywhere | `GEMINI_KEY` secret missing in project | Step 2, then redeploy functions. |
| Daily read / weekly letter lands at wrong local hour (or UTC) | user has no `timezone` field yet | user opens app once (writes `timezone`). |
| `generateNightlyInsights` skips everyone | no user has ≥3 `entryAnalyses` yet | write more entries; `analyzeEntry` runs on save. |
| No weekly-letter banner in the Mirror tab | fewer than 3 entries this week (`below_threshold`), or the letter is already read/stale | check `buildUserWeeklyLetter` logs for the `reason`; `users/{uid}/mirrorLetters/{yyyy-MM-dd}.openedAt` non-null means already read. |
| Weekly-letter / daily-reading push never arrives on device | `aps-environment` is `development` on the build, or no APNs `.p8` key uploaded | confirm the build's provisioning matches the entitlement; Firebase Console → Project Settings → Cloud Messaging → upload the APNs Auth Key. |
| Journal entry photos never appear | `storage` rules not deployed to this project | Step 3 (`firebase deploy --only storage --project spilr-100f7`); confirm the live ruleset in Console → Storage → Rules matches `storage.rules`. |
| Paying user still budgeted as trial (or "Get Spilr Pro" throws RevenueCat error 23) | `REVENUECAT_WEBHOOK_SECRET` unset (webhook 401s every event), or RevenueCat's `app_user_id` diverged from the Firebase uid | Step 2 above; check `revenueCatWebhook` logs for 401s; see `REVENUECAT_SETUP.md` for the App Store Connect / dashboard checklist error 23 usually points at. |
