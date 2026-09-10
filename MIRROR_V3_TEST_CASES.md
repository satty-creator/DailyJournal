# Mirror v3 — deploy and test plan

**For:** Satakshi · 2026-09-10
**Covers:** everything in `mirror-v3-prd-2026-09-10.md` weeks 1–6, as implemented.
**Automated coverage already passing:** `cd functions && npm test` → **56/56**.

That suite is worth knowing the shape of, because it changes what you need to
test by hand:

- **38 unit tests** over the pure logic — timezone bucketing, every observation
  type and threshold, the copy lint against the real failing lines from the
  screenshots, dedup clustering.
- **18 integration tests** that run the actual `computeUserDerived` handler
  against an in-memory Firestore (`test/fixtures/mockFirestore.js`), which is
  strict where Firestore is strict: it rejects `undefined`, nested arrays, map
  keys containing `.`, and batches over 500 writes.

So the arithmetic and the write shapes are already covered. **What you are
testing by hand is the half a test cannot check: whether the numbers are true
about YOUR life, and whether the sentences are worth reading.**

---

## 0. Read this first — what your account will actually look like

Your existing `entryAnalyses` were written by `mirror-extract-v1`. They have no
`people`, no `wordCount`, and no `entryCreatedAt`. Those three fields only start
appearing on entries analysed by the **new build**, and the content-hash
short-circuit means old entries are deliberately **never re-analysed** (that
would re-run a 1,200-token call over your whole history at once).

So on night one, expect this and do not treat it as breakage:

| Surface | Expected tonight | Why |
|---|---|---|
| This week strip | cadence + emotion rows populated; people row shows **domains or roles**, not names | `people` coverage is 0 until you write new entries |
| Weekday observation | **absent** | needs ≥80% wordCount coverage; yours is 0% |
| Lag observation | **absent** | same, plus needs 14 lifetime entries |
| Co-occurrence / time-band / exception / callback / streak | **should appear** if you have ≥6 active days | computed from fields v1 already wrote |
| Threads | **very likely 0** | needs n≥3 + contrast + a passed audit |
| Today | an observation (not a model line) on the first pass | the deterministic worker has no model key |
| Patterns list | **gone** | replaced by Threads |

**Zero threads on night one is the correct result, not a bug.** §7: "the correct
v3 state is one reading or observation today, three fact rows, zero threads."

To get the new fields flowing: write 2–3 new entries after installing the build.
Those get `mirror-extract-v2` and will carry names + word counts.

---

## 1. Pre-deploy (run these now, before touching Firebase)

| # | Command | Expect |
|---|---|---|
| 1.1 | `cd functions && npm test` | `pass 56`, `fail 0` |
| 1.2 | `node --check functions/index.js` | no output |
| 1.3 | `bash scripts/check-firestore-schema.sh` | `PASS: every written collection is covered by account deletion.` |
| 1.4 | `xcodebuild -scheme DailyJournal -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` | `** BUILD SUCCEEDED **` |
| 1.5 | `git status` | only the files you expect; nothing untracked you didn't mean |

**Stop if any of these fail.** They all pass as of this writing.

---

## 2. Deploy — order matters

> **The one hard rule:** task handlers deploy BEFORE dispatchers. The first
> scheduled run otherwise enqueues into a queue that does not exist yet
> (`functions/index.js` header, lines 62–63).

### 2.1 Set the dev-admin uid (needed for every manual test below)

```bash
firebase functions:config:unset dev 2>/dev/null   # if you have stale config
# Set as an env var on deploy instead — .env in functions/ works:
echo 'DEV_ADMIN_UIDS=<your-firebase-uid>' >> functions/.env
echo 'DEDUP_DRY_RUN=1' >> functions/.env          # night one: dedup plans only, writes nothing
```

`DEDUP_DRY_RUN=1` is deliberate for the first night — see test 5.1.

### 2.2 Deploy in this sequence

```bash
# (a) the new task handler FIRST
firebase deploy --only functions:computeUserDerived

# (b) the dev runner, so you can test without waiting for 04:00 UTC
firebase deploy --only functions:runNightlyForUser

# (c) the reworked workers
firebase deploy --only functions:mineUserInsights,functions:buildUserWeeklyLetter,functions:bootstrapMirror

# (d) the dispatcher LAST — this is what starts routing to computeUserDerived
firebase deploy --only functions:dispatchUserWork,functions:generateNightlyInsights

# (e) indexes (safe any time, builds in background)
firebase deploy --only firestore:indexes

# (f) RULES LAST, and on their own — see §7, this is the risky one
#     firebase deploy --only firestore:rules
```

**Do NOT deploy rules yet.** Run every test in §3–§6 first, on the current
permissive rules. Rules go last so that if a client write starts failing you
know it was the rules and can revert one file.

### 2.3 Install the app build on your device

TestFlight or a direct Xcode run — either is fine.

---

## 3. Day 1 · manual pipeline run (no waiting for the cron)

**Getting the token — the app now has a button for this.** In a Debug build,
open the **Profile** tab → scroll down to a **Debug** section (only visible in
Debug builds, not on TestFlight/App Store) → tap **"Copy ID token for
testing"**. It copies a token straight to your clipboard, good for about an
hour, no matter how you signed in (email, Google, or Apple all work the same
way). Paste it as `TOKEN` below.

(If you'd rather not touch the app: Firebase Console → Authentication → your
user → you cannot get an ID token from the console directly, only a uid — the
in-app button is the actual supported path.)

Then:

```bash
TOKEN='<firebase id token>'
URL='https://us-central1-spilr-100f7.cloudfunctions.net/runNightlyForUser'

curl -s -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"stages":["facts","observations","threads","reading"]}' | python3 -m json.tool
```

### T3.1 — FactsJob produces true counts
**Expect** in the response under `facts`:
- `entriesTotal` matches your real entry count (cross-check against the Journal tab)
- `coverage.entriesInWindow` ≤ `entriesTotal`
- `coverage.wordCountKnown` is **0** (expected — old analyses)
- `week.byBand` sums to `week.entries`
- `unlock.next.hint` is a sentence naming a specific number

**Fail if:** `entriesTotal` is 0 while you have entries → the `rollups/stats`
doc is missing; check `users/{uid}/rollups/stats` exists.

### T3.2 — the day-bucketing is in YOUR timezone
In Firestore, open `users/{uid}/derived/facts` and check `entryDates`.
**Expect** each entry's date to match the date you actually wrote it, in local
time — including any entry written after 21:00, which must NOT roll to the next
day unless it genuinely crossed local midnight.

**Fail if:** a 22:00 entry shows the following day's date → `timezone` on your
user doc is wrong or absent. Set `users/{uid}.timezone` to an IANA string
(`Europe/London`).

### T3.3 — observations fire, with checkable numbers
**Expect** in the response under `observations`:
- `count` ≥ 1 (assuming ≥6 active days)
- `byType` contains at least one of `cooccurrence` / `timeband`
- every entry in `top[]` has a `text` that reads as a complete sentence with
  real numbers in it
- **no** `weekday` and **no** `lag` (word-count coverage is 0)

**Now verify one by hand.** Take the top co-occurrence, e.g.
`"On the 6 days you wrote about work, 'heavy' appeared in 5. On the other 8 days: 0."`
Open the Journal tab and count. The numbers must match exactly. **This is the
single most important test in this document** — the entire v3 premise is that
these counts are true.

**Fail if:** any number is off by even one → stop and report it. A wrong count
here is worse than no feature.

> For reference, the automated suite runs this exact shape against a
> hand-counted 14-entry fixture and asserts `n=6 m=8 k=5 j=0, lift 2.33`. If
> your real numbers are wrong while that test passes, the bug is in how your
> data is being read (timezone, `entryCreatedAt`), not in the arithmetic.

### T3.3b — an exception carries your own words from the day it *didn't* happen
If `byType` contains an `exception`, this is the money shot of the whole
redesign. **Expect** something shaped like:

```
line:    5 Sep is the only day this month you wrote about work without 'heavy'.
receipt: "honestly just lucky and loved tonight"  (5 days ago)
```

The receipt must come from the **exception day itself** — what you actually
wrote on the day the pattern broke.

**Fail if:** the receipt is missing or comes from a different date. (This one
shipped broken the first time: the quotes were being looked up by the *absent*
term, which by definition has none. There is now a regression test for it.)

### T3.4 — no two observations say the same thing
**Expect:** every `text` in `top[]` is distinct.
**Fail if:** two rows render identically → the dedup pass in
`computeObservations` regressed.

### T3.5 — threads are empty and say so honestly
**Expect** `threads: []` (very likely), and in the app the Threads section
reads *"None yet — threads need the same thing on three different days."*
**Fail if:** a thread appears with `n` < 3 and no `userStatus: this_is_me`.

### T3.6 — Today picks something and shows its provenance
**Expect** under `reading`:
- `silence: false` and a `line`, **or** `silence: true` with an `unlockHint`
- if not silent: `lintPassed: false` and `line == templateText`
  (the deterministic worker has no model key — this is correct)
- `receipt.quote` is text you actually wrote

**Fail if:** `line` is empty while `silence` is false.

---

## 4. Day 1 · the app itself

Open the Mirror tab. Pull to refresh.

### T4.1 — the tab is four things, in order
**Expect, top to bottom:** Ask pill (if ≥5 entries) → weekly-letter banner (only
if fresh) → **Today card** → **This week, in your words** → **Threads** → Go
deeper.

**Fail if:** you see a "Your patterns" row → the old list survived; it should be
deleted.

### T4.2 — the strip is never empty and never wrong
**Expect:** 2–3 rows, each leading with a **bolded number or quoted phrase**.
Cross-check the entry count against the Journal tab.

**Fail if:** the strip is missing entirely → `derived/facts` didn't load; check
the read in `DerivedService.load` and that rules allow reading `derived`.

### T4.3 — "more…" opens the proof sheet
Tap **more…** on the Today card.
**Expect:** a two-tile comparison (`k of n` vs `j of m`), up to 3 quotes with
dates, an `Exception:` row (a date or "none yet"), *Ask Spilr about this*,
*Teach Spilr*, two feedback buttons, and the honesty line
(`2 numbers · N quotes · 0 labels`).

**Fail if:** the sheet is blank → `reading.proof` is missing.

### T4.4 — "That's me" actually confirms (this was broken before)
Tap **That's me** on the Today card. Then in Firestore check
`users/{uid}/readings/{today}` → `userStatus: "this_is_me"`, and
`users/{uid}/observations/{sourceId}` → same.

**Then** the Week-1 fix: on the *profile* screen (Go deeper → Your living
profile), tap **That's me** on any card, and check
`users/{uid}/patternHypotheses/{id}` → `userStatus: "this_is_me"`.

**Why this matters:** before v3, "This is me" on the daily card wrote only a
soft `.shown` status, so the confidence floor, the `user_confirmed` lifecycle
and the 45-day decay exemption were unreachable from the surface most people
actually use.

### T4.5 — "Not quite" asks what missed
Tap **Not quite**. **Expect** three chips: *Too much · Wrong · Already knew*.
Tap **Wrong**. Check `readings/{today}.followUp == "wrong"` and
`observations/{id}.notQuiteCount == 1`.

Then check `users/{uid}/stylePreferences/current` → `sharpness` must be
**unchanged**. Only *Too much* lowers it. (Repeat with *Too much* on another
day to confirm `sharpness` drops by 1.)

### T4.6 — the profile is quiet and honest
Go deeper → Your living profile.
**Expect:** the maturity ring (kept), sections renamed to *Rules you seem to run
on* / *What you do when it gets hard* / *What helps* / *People and the part you
play* / *Your words*, **two** buttons per card plus a `…` menu, and **no**
"A hunch" or "Not checked against other entries yet" caption anywhere.
Most sections will be empty with the "Nothing here yet" card — correct at your
entry count.

**Fail if:** you see "Not checked against other entries yet" → that string
should now be unreachable.

### T4.7 — the four-button row is gone but the eraser survives
On any profile card, tap `…`. **Expect** *This is done* and *Hide from profile*.
Tap *This is done*, then check `patternHypotheses/{id}.status == "closed"`.

### T4.8 — First Sketch no longer truncates or fakes a question
Only testable if you have ≥7 entries and haven't dismissed it.
**Expect:** no mid-word truncation (the old `"maybe to fend o"`), and **no**
question card at all unless the text genuinely ends in `?`.

---

## 5. Day 1 · dedup (the six-variants fix)

### T5.1 — dry run first, read the plan, then enable
With `DEDUP_DRY_RUN=1` still set:

```bash
curl -s -X POST "$URL" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"stages":["dedup"]}' | python3 -m json.tool
```

Then read the log:
```bash
firebase functions:log --only runNightlyForUser | grep dedupPlan
```

**Expect** a `dedupPlan` entry listing clusters, each with a `survivor`, how
many it `absorbs`, a `timesSeen` transition like `4 -> 9`, and `via` entries
showing what matched (`evidence:1.00`, `title:0.67`).

**Read this before enabling writes.** Specifically check: are any two
hypotheses being merged that you think are genuinely *different*? If yes, tell
me and we raise the threshold before this ever writes.

### T5.2 — enable and verify the merge
Remove `DEDUP_DRY_RUN` from `functions/.env`, redeploy `runNightlyForUser`, run
the same call again.

**Expect:**
- the survivor's `timesSeen` is now the **union** of the cluster's distinct entries
- each loser has `mergedInto: <survivorId>`, `status: "merged"`, `stability: "retired"`
- the losers' `mirrorCards` docs are deleted
- the app's Threads/profile no longer show the duplicates

### T5.3 — closing one variant closes all of them
Find a merged cluster. Before v3, closing one of six left five alive.
**Expect:** if any cluster member had `status: closed`, the survivor inherits it.
(Covered by an automated test too: *"dedup propagates a kill"*.)

### T5.4 — cross-type merge actually happens
**Expect** at least one cluster where `mergedPatternTypes` has more than one
entry (e.g. `["protective_loop", "values_conflict"]`). That merge was
*impossible* before — the old code refused to compare across patternType.

> **Note on how much it collapses:** the deterministic pass merges variants that
> share evidence entries or overlapping titles. Variants that share *neither*
> will survive as separate docs — that is expected, and is exactly the residue
> the embeddings step (`DEDUP_USE_EMBEDDINGS=1`) exists for. Decide from the
> §5.1 plan output whether it's worth turning on.

---

## 6. Day 2 · the real nightly run

Do nothing overnight. The cron fires at **04:00 UTC**.

### T6.1 — the fan-out reached you
```bash
firebase functions:log --only dispatchUserWork | grep "dispatch derived page"
firebase functions:log --only computeUserDerived | grep factsJob
```
**Expect** a `factsJob` line for your uid, with `entries`, `analyses`,
`wordCountKnown`, `peopleKnown`, `stage`.

**Fail if:** no `computeUserDerived` invocation → the dispatcher is still
enqueuing to `mineUserInsights`; confirm step 2.2(d) deployed.

### T6.2 — the tail-chain into the mine happened
```bash
firebase functions:log --only mineUserInsights | grep mineUserInsights
```
**Expect** either a real mine, or `skipped: true, reason: "below_cadence_threshold"`.
**Both are correct.** The point of the split is that facts are fresh *either way*.

### T6.3 — the model line appeared (only if the mine ran)
If the mine ran, check `users/{uid}/readings/{today}`.
**Expect** `lintPassed: true` and `line != templateText` — a model sentence on
top of the observation. If `lintPassed: false`, check `lintReason` and:

```bash
firebase functions:log | grep mirrorLintReject
```

**This log is the feature, not the failure.** `{rule, term, observationType}`
tells you exactly which §6 rule the model tripped. A few rejects is healthy; the
same rule rejecting every night means the prompt needs work.

### T6.4 — the line obeys the copy contract
Read today's line and check by eye:
- one sentence, ≤140 characters
- contains a number from the observation **or** a phrase you actually wrote
- no "you are someone who", "you always", "you tend to"
- no metaphor — no *armor*, *terror*, *ledger*, *landscape*, *nervous system*
- not ALL CAPS

**Fail if any of these are violated** → the lint has a hole; send me the line.

### T6.5 — decay now runs for everyone
```bash
firebase functions:log --only computeUserDerived | grep decayJob
```
**Expect** a `decayJob` line if you have hypotheses older than 45 days with no
new evidence. Previously decay only ran inside a *successful mine*, so a dormant
account never decayed at all.

### T6.6 — today's line is not yesterday's
Compare `readings/{yesterday}.line` and `readings/{today}.line`.
**Expect:** different, and ideally not even about the same terms.
**Fail if identical** → the novelty penalty isn't reading `mirrorShown`; check
that yesterday's doc has `observationId` and `terms` (the app writes these on
card appear).

### T6.7 — silence-day rate
Over several days, expect **15–35%** of days to be silent. A surface that always
has something to say is one that is making things up.

---

## 7. Rules deploy (do this LAST, on its own)

This is the highest-blast-radius step in the whole change: a missed collection
becomes a **silent** production write failure, because every write in this app
is fire-and-forget with no error path.

```bash
firebase deploy --only firestore:rules
```

Then immediately, in the app, exercise every write path:

| # | Action | Then check |
|---|---|---|
| 7.1 | Write a new journal entry | it appears in the Journal tab after a restart |
| 7.2 | Finish a Daily Chat | `chatSessions` doc written |
| 7.3 | Log a mood | `moodLogs` doc written |
| 7.4 | Tap "That's me" on Today | `readings/{today}.userStatus` updated |
| 7.5 | Tap "Not quite" → "Too much" | `stylePreferences/current.sharpness` drops |
| 7.6 | Open the weekly letter | `mirrorLetters/{week}.openedAt` set |
| 7.7 | Profile → `…` → This is done | `patternHypotheses/{id}.status == "closed"` |
| 7.8 | Teach Spilr → save | `profileCorrections` doc written |

**And confirm the deny side works.** In the Firestore console, signed in as
your user, try to edit `users/{uid}/derived/facts` → **must be denied**. Same for
changing `observations/{id}.n`.

### Rollback (if any write above silently fails)
```bash
git checkout HEAD~1 -- firestore.rules && firebase deploy --only firestore:rules
```
The rules file is independent of everything else — reverting it does not touch
the pipeline.

---

## 8. Edge cases worth deliberately triggering

| # | Case | How | Expect |
|---|---|---|---|
| 8.1 | Brand-new account | new user, write 3 entries | `bootstrapMirror` runs; facts + observations + a Today card without waiting for 04:00 |
| 8.2 | Zero entries | fresh account, open Mirror | strip says "No entries yet"; no crash; unlock hint shown |
| 8.3 | One entry | write exactly one | `1 entry · <band>. <hint>` — the §5.3 one-entry copy |
| 8.4 | Offline | airplane mode, open Mirror | falls back to cached derived docs; no spinner hang |
| 8.5 | Timezone change | change device TZ, refresh | dates stay correct — server uses `users/{uid}.timezone`, not the device |
| 8.6 | Two "Not quite" on one observation | tap it twice across two days | `notQuiteCount == 2`, and it stops being selected |
| 8.7 | Weekly letter below threshold | fewer than 3 entries this week | no letter; at most one unlock-hint push per 14 days |
| 8.8 | Crisis content | write an entry with crisis language | mine returns `safety_gate`; no observations built from it surface |

**8.8 is not optional.** Verify the safety gate still short-circuits before any
model call — `functions/index.js` `containsCrisisSignal`.

---

## 9. What to watch in the logs

Saved queries worth keeping:

```
jsonPayload.message="factsJob"           -- did Tier 0 run, and what coverage
jsonPayload.message="observationsJob"    -- how many, by type
jsonPayload.message="readingSelect"      -- which step (1-5) chose today
jsonPayload.message="mirrorLintReject"   -- the prompt-quality dashboard
jsonPayload.message="dedupPlan"          -- what dedup wants to merge
jsonPayload.message="threadsJob"         -- eligible vs chosen
jsonPayload.message="unlockNudge"        -- the rate-limited push
```

`readingSelect.step` tells you the health of the whole surface:
- **1** exception/delta — the best outcome (R6: exceptions outrank problems)
- **2** callback — the "it remembers" moment
- **3** a model line passed lint
- **4** observation shown alone — fine, and expected often
- **5** silence — healthy at 15–35%

---

## 10. Known gaps (deliberate, not bugs)

1. **Strip rows aren't tappable.** §5.3 wants each row to open the entries it
   counts; that needs a filtered journal list that doesn't exist. Deferred.
2. **`ends_negative` lint is log-only.** It's the fuzziest §6 rule and will
   produce false rejects. It logs `mirrorLintObserve` for a week; flip
   `enforceEndsNegative: true` in `writeReadingFor` once the rate looks sane.
3. **Embeddings are off.** `DEDUP_USE_EMBEDDINGS=1` enables them. Decide from
   the §5.1 dry-run output whether the residue justifies the cost.
4. **Legacy `mirrorCards` deck still writes.** `MIRROR_LEGACY_DECK = true` keeps
   pre-v3 clients rendering for one release. Flipping it to `false` is where the
   promised cost reduction actually lands (3 write + 3 guard calls → 1 + 1).
5. **`voice` entry mode is unrecoverable.** Dictation saves as `.freeWrite`;
   there is no flag distinguishing it. The PRD's four-way mode taxonomy is
   3-of-4 buildable.
6. **No Xcode test target.** Deliberate — mid-feature project surgery is a risk
   multiplier. The 38 Node tests cover the arithmetic, which is ~90% of v3.
