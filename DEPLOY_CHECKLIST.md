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
Expect **three** functions to deploy:
- [ ] `geminiProxy` (on-request proxy the app calls)
- [ ] `generateDailyReads` (hourly; sends the read at each user's local morning hour)
- [ ] `generateNightlyInsights` (04:00 UTC; mines hypotheses + Self-Model)

If prompted about scheduler/pub-sub or Cloud Run permissions, accept. First deploy can take a few minutes.

---

## 5 · Verify end-to-end

- [ ] **App writes work now:** open the app, write an entry, confirm `users/{uid}/entries/{id}` appears in the Firestore console. `entryAnalyses/{id}` should appear shortly after (that's Prompt A running).
- [ ] **Proxy works:** the chat and per-entry reflection return AI (not just local fallback). Check function logs:
  ```bash
  firebase functions:log --only geminiProxy --project spilr-100f7
  ```
- [ ] **Daily read:** wait for the top of the next hour, or trigger a run for testing (Console → Functions → `generateDailyReads` → run, or via Cloud Scheduler "Force run"). Confirm a doc at `users/{uid}/dailyReads/{yyyy-MM-dd}` and check logs for `generateDailyReads done`.
- [ ] **Nightly insights:** after it runs (04:00 UTC, or force-run), confirm `users/{uid}/patternHypotheses/*` and `users/{uid}/selfModel/current` populate for a user with ≥3 `entryAnalyses`. Log line: `generateNightlyInsights done`.

---

## 6 · First-run notes

- A user needs a few entries before the read/insights have anything to ground on (read needs ≥1 substantial entry; nightly mining needs ≥3 `entryAnalyses`).
- `timezone` is written to the user doc on sign-in — existing users must open the app once so `generateDailyReads` sends at their correct local hour (until then it defaults to America/New_York).
- To backfill immediately for testing, force-run both scheduled functions from the Cloud Scheduler console.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Missing or insufficient permissions" | Rules not deployed / wrong project | Step 3; confirm `firebase use spilr-100f7`. |
| App writes still fail | `(default)` DB not created | Step 1. |
| AI falls back to local everywhere | `GEMINI_KEY` secret missing in project | Step 2, then redeploy functions. |
| Read lands at wrong local hour | user has no `timezone` field yet | user opens app once (writes `timezone`). |
| `generateNightlyInsights` skips everyone | no user has ≥3 `entryAnalyses` yet | write more entries; `analyzeEntry` runs on save. |
| Journal entry photos never appear | `storage` rules not deployed to this project | Step 3 (`firebase deploy --only storage --project spilr-100f7`); confirm the live ruleset in Console → Storage → Rules matches `storage.rules`. |
