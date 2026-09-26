#!/usr/bin/env bash
#
# run-e2e.sh — end-to-end UI tests against the Firebase Emulator Suite.
#
#   ./scripts/run-e2e.sh                          # all UI tests
#   SIMULATOR="iPhone 17 Pro" ./scripts/run-e2e.sh
#   ONLY=DailyJournalUITests/AIAccessTests ./scripts/run-e2e.sh
#
# Needs (once): Xcode, Java 17+, and `npm install` in functions/.
# Uses npx firebase-tools, so no global install is required.
#
# `firebase emulators:exec` starts Auth + Firestore + Functions, waits until
# ALL of them are ready (the first run also downloads the Firestore emulator,
# which takes a minute), runs scripts/e2e/inside-emulators.sh — seed accounts,
# then xcodebuild — and shuts everything down afterwards, pass or fail.
# Gemini is stubbed inside the emulator; nothing touches production.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="spilr-100f7"
FUNCS="$ROOT/functions"

# Emulator-only config. .env.local and .secret.local are read ONLY by the
# emulator and are git-ignored; deploys never see them.
touch "$FUNCS/.env.local"
grep -q '^SPILR_GEMINI_STUB=' "$FUNCS/.env.local" || echo 'SPILR_GEMINI_STUB=1' >> "$FUNCS/.env.local"
if [[ ! -f "$FUNCS/.secret.local" ]]; then
  printf 'GEMINI_KEY=emulator-stub\nREVENUECAT_WEBHOOK_SECRET=emulator-stub\n' > "$FUNCS/.secret.local"
fi

export SIMULATOR="${SIMULATOR:-iPhone 17}"
export ONLY="${ONLY:-}"
export XCODEBUILD_EXTRA="${XCODEBUILD_EXTRA:-}"

echo "▶ Starting emulators (log: .e2e-emulators.log)…"
npx --yes firebase-tools emulators:exec \
  --only auth,firestore,functions \
  --project "$PROJECT" \
  "bash scripts/e2e/inside-emulators.sh" 2>&1 | tee "$ROOT/.e2e-emulators.log"
exit "${PIPESTATUS[0]}"
