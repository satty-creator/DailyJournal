# ninety — Gemini backend (Cloud Function)

`geminiProxy` is the only thing that ever sees the Gemini API key. The iOS app
calls it with the signed-in user's Firebase Auth token; the function verifies the
token, calls Gemini server-side, and returns Gemini's response unchanged.

The app **never** holds a key, and users are **never** asked for one.

---

## One-time setup

1. **Get a Gemini key.** Go to <https://aistudio.google.com/apikey>, sign in,
   "Create API key", let it use your Google Cloud project, copy the key.
   Free tier covers `gemini-3.5-flash-lite` (≈10 requests/min, 250/day — fine for a beta).

   > **Important (deadline):** from **June 19, 2026** Google no longer allows
   > "unrestricted" keys. In AI Studio / Google Cloud Console → Credentials, open
   > the key and add an **API restriction** limiting it to the *Generative Language
   > API*. That satisfies the requirement without needing a static egress IP.

   > **Privacy note:** on the **free** tier Google may use submitted content to
   > improve its products. ninety processes private journal entries — for launch,
   > strongly consider the **paid** tier (data is not used for training) or disclose
   > free-tier AI processing in your privacy policy.

2. **Install tooling** (once):
   ```bash
   npm install -g firebase-tools
   firebase login
   cd functions && npm install && cd ..
   ```

3. **Store the key as a secret** (never in code or .env that ships):
   ```bash
   firebase functions:secrets:set GEMINI_KEY
   # paste the key when prompted
   ```

4. **Deploy:**
   ```bash
   firebase deploy --only functions
   ```
   The CLI prints the URL, e.g.
   `https://us-central1-dailyjournal-12a35.cloudfunctions.net/geminiProxy`

5. **Point the app at it.** Confirm `AIService.proxyURLString` (in
   `DailyJournal/Home/AIService.swift`) matches that URL. The default is already set
   to the `dailyjournal-12a35` / `us-central1` URL above.

---

## How it's secured

- **Auth required.** Every request must carry `Authorization: Bearer <Firebase ID
  token>`; the function rejects anything it can't verify. Not an open relay.
- **Key isolation.** The key lives in Secret Manager, injected only at runtime.
- **Cost guardrail.** `maxInstances: 10` caps runaway usage.
- **Future hardening:** add a per-uid rate limit (Firestore counter) and an
  App Check assertion before going wide.

## Test after deploy
```bash
# Should return 401 (no token) — proves auth is enforced:
curl -X POST <your-function-url> -H "Content-Type: application/json" -d '{"contents":[]}'
```
