#!/usr/bin/env bash
# Runs INSIDE `firebase emulators:exec` (see scripts/run-e2e.sh), which has
# already started every emulator and exported FIREBASE_AUTH_EMULATOR_HOST /
# FIRESTORE_EMULATOR_HOST for us.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "▶ Seeding test accounts…"
node scripts/e2e/seed.js

echo "▶ Running UI tests on ${SIMULATOR}…"
mkdir -p build
ARGS=(-project DailyJournal.xcodeproj -scheme DailyJournalE2E
      -destination "platform=iOS Simulator,name=${SIMULATOR}"
      -resultBundlePath "build/e2e-$(date +%Y%m%d-%H%M%S).xcresult")
if [[ -n "${ONLY:-}" ]]; then ARGS+=(-only-testing:"$ONLY"); fi
# XCODEBUILD_EXTRA lets CI add e.g. signing overrides without editing this file.
# shellcheck disable=SC2086
xcodebuild test "${ARGS[@]}" ${XCODEBUILD_EXTRA:-}
