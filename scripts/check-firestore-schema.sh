#!/usr/bin/env bash
#
# check-firestore-schema.sh
#
# Guards against the drift that caused a real privacy bug: the account-deletion
# list in AuthService named "reads" and "moods" while the services wrote to
# "dailyReads" and "moodLogs", and "riverMarks"/"pushTokens" were never listed at
# all. Four collections — one of them holding verbatim phrases from entries —
# survived "permanently delete my account".
#
# This script finds every user-subcollection name the Swift code actually opens
# and asserts it is enumerated in FirestoreSchema.userSubcollections, which is
# what eraseFirestoreData iterates.
#
# Exit 0 = every written collection is deletable. Exit 1 = something would leak.
#
# Run locally:  ./scripts/check-firestore-schema.sh
# Run in CI:    add as a build step before archive.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT/DailyJournal"
SCHEMA="$SWIFT_DIR/App/FirestoreSchema.swift"

if [[ ! -f "$SCHEMA" ]]; then
  echo "FAIL: $SCHEMA not found." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. The declared list: string literals inside the userSubcollections array.
#    We read the constant names in the array, then resolve each to its literal.
# ---------------------------------------------------------------------------
declared="$(
  awk '/static let userSubcollections/,/^    \]/' "$SCHEMA" \
    | grep -oE '^\s+[a-zA-Z]+,' \
    | tr -d ' ,' \
    | while read -r const; do
        grep -oE "static let $const = \"[^\"]+\"" "$SCHEMA" \
          | sed -E 's/.*"([^"]+)".*/\1/'
      done \
    | sort -u
)"

# ---------------------------------------------------------------------------
# 2. The actual list: every .collection("literal") in the Swift sources, minus
#    the root "users" collection (deleted separately as a document) and minus
#    FirestoreSchema.swift itself.
# ---------------------------------------------------------------------------
written="$(
  grep -rhoE '\.collection\("[^"]+"\)' "$SWIFT_DIR" \
    --include='*.swift' \
    --exclude='FirestoreSchema.swift' \
    2>/dev/null \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | grep -vx 'users' \
    | sort -u || true
)"

# ---------------------------------------------------------------------------
# 3. Compare.
# ---------------------------------------------------------------------------
missing="$(comm -23 <(echo "$written") <(echo "$declared") || true)"

echo "Declared in FirestoreSchema.userSubcollections:"
echo "$declared" | sed 's/^/  - /'
echo
echo "Opened by .collection(\"…\") in Swift sources:"
if [[ -z "$written" ]]; then
  echo "  (none — services now use FirestoreSchema constants)"
else
  echo "$written" | sed 's/^/  - /'
fi
echo

if [[ -n "$missing" ]]; then
  echo "FAIL: these collections are written but NOT in userSubcollections," >&2
  echo "      so account deletion will leave their documents behind:" >&2
  echo "$missing" | sed 's/^/  ✗ /' >&2
  echo >&2
  echo "Fix: add them to FirestoreSchema.userSubcollections." >&2
  exit 1
fi

echo "PASS: every written collection is covered by account deletion."
