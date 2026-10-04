# Testing Spilr

See `USER_SCENARIOS.md` for the full scenario catalogue — every user-visible
flow, mapped to the test (if any) that covers it, with gaps and priorities
marked. This file is about the four layers themselves; that one is about
what's actually tested. `MIRROR_V3_TEST_CASES.md` covers a level below
either: whether Mirror's generated *sentences* are worth reading, which no
automated test can check.

Four layers. The first three run on every push (`.github/workflows/ci.yml`);
the fourth runs on `main`, nightly, and on PRs labelled `e2e`.

| Layer | Where | Run locally | What it guards |
|---|---|---|---|
| Server unit | `functions/test/*.test.js` | `cd functions && npm test` | Mirror pipeline, lint, prompts, **Spilr Pro access policy** (`entitlement.test.js`) |
| Security rules | `tests/rules/` | `cd tests/rules && npm install && npm test` | Nobody can write `aiUsage`/`entitlements` (make themselves "paid") or read another user's journal |
| iOS unit | `DailyJournalTests/` | Xcode → scheme **DailyJournal** → ⌘U | Paywall copy + App Review disclosure, owner bypass, crisis gate, Gemini parsing |
| End-to-end UI | `DailyJournalUITests/` | `./scripts/run-e2e.sh` | Onboarding intake → guided first entry → Second look → paywall, skip goes straight to Today with no paywall, Daily Chat entries, purchase, 402 → paywall, owner bypass |

Also on every push: `scripts/check-firestore-schema.sh` (every collection the app writes is erased by account deletion).

## How the end-to-end tests stay hermetic

- The app runs against the **Firebase Emulator Suite** (Auth, Firestore, Functions), never production — launch argument `-UseFirebaseEmulator` (DEBUG builds only, see `DailyJournal/App/TestLaunchConfig.swift`).
- **Gemini is stubbed inside the emulator** (`functions/lib/geminiStub.js`, only when `FUNCTIONS_EMULATOR=true` *and* `SPILR_GEMINI_STUB=1`). Auth and the Spilr Pro gate still run for real.
- **The paywall uses fixture plans** (`-UITestFixturePaywall`) matching App Store Connect, so no StoreKit sandbox account is needed.
- `scripts/e2e/seed.js` wipes the emulator and creates one account per test.

Requirements once: Xcode, Java 17+, `npm install` in `functions/`.

## Rule for every new feature

A change isn't done until it has a test at the lowest layer that can catch it:

- Pure logic (copy, thresholds, parsing, policy) → unit test.
- Anything touching who can read/write what → rules test.
- A user-visible flow that crosses screens or the server → one UI test in `DailyJournalUITests`, using `accessibilityIdentifier`s (never copy text that might change).

## Manual checks that can't be automated

- **Real purchase:** TestFlight build + sandbox Apple ID → Profile → Get Spilr Pro → Start 2 weeks free. Then check Firestore `aiUsage/{uid}.entitlement == "paid"` (the RevenueCat webhook wrote it).
- **Push:** Profile → Developer → *Check push setup*, then *Send me a test push* (owner accounts only).
