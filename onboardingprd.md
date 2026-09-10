# Onboarding — Feature PRD

**Status:** Shipped *(2026-06-15)*

**Files:** `Onboarding/OnboardingView.swift`, `App/RootView.swift`,
`Home/HomeView.swift`

---

## What it is

A two-step onboarding flow shown to new users immediately after sign-in.
Returning users who already completed it skip straight to `MainTabView`.

Completion is tracked in `UserDefaults` under key `"spilr.onboardingCompleted"`,
driven by `@AppStorage` in `RootView`. The flow is non-skippable — every new
account must pass through it once.

---

## Routing logic

`RootView` checks `onboardingCompleted` when `authState == .authenticated`:
- `false` → `OnboardingView` (with `ThemeManager` environment injected)
- `true`  → `MainTabView`

The transition animates via `@AppStorage` value change.

---

## Step 1 — "Pick your vibe"

**Goal:** Make the app feel personal before the user writes a single word.

- Progress dots: 2 dots, dot 1 active.
- Headline: *"Pick your vibe."*
- Sub-copy: *"Make spilr feel like yours. Change it any time from your profile."*
- Live preview card showing a sample AI observation in the selected theme's colours.
- 2×2 theme grid (`ThemeID.allCases`) — same tap-to-select mechanic as
  `ThemePickerView`. Tapping applies the theme live via `ThemeManager.select(_:)`.
- CTA: **"This feels right"** → Step 2.

**No skip.** The user must pick before advancing (default `.bloom` is pre-selected,
so tapping the CTA immediately is valid).

---

## Step 2 — "The 7-day promise"

**Goal:** Set correct expectations; surface a low-stakes commitment so the
user frames their first week as a trial, not a lifetime obligation.

- Progress dots: dot 2 active.
- Headline: *"The 7-day promise."*
- Three promise cards (icon + title + body):
  - **Write freely** — no word counts, no streaks, just a 90-second drop.
  - **Watch patterns emerge** — patterns surface after 14 days.
  - **It learns your language** — uses your words, not ours.
- **Weekly commitment picker** — 1×, 2×, 3×, Daily pills. Purely motivational;
  not enforced by any logic gate. Default is 3×.
- Encouragement copy updates as the user changes the selection.
- CTA: **"Let's start"** — sets `UserDefaults.standard.onboardingCompleted = true`,
  calls `onComplete()`, which causes `RootView` to switch to `MainTabView`.

---

## First-entry celebration

**Goal:** Deliver an immediate "aha" moment — proof that the AI is actually
paying attention — the first time the user saves an entry.

**Trigger:** After any write session completes (`SpillWriteView.onSave` or
`JournalEditorView` dismiss), `HomeView.checkFirstEntry()` runs. It shows the
`FirstEntryCelebrationSheet` once if:
- `vm.recentEntries.count == 1` (first ever entry), AND
- `!firstEntryCelebrationShown` (`@AppStorage("spilr.firstEntryCelebrationShown")`).

**Sheet content (updated):**
- Congratulations headline: *"First entry. That took courage."*
- **Instant topical insight** (`topicInsightCard`) — a plain-language sentence
  built from `entry.tags` (up to 3) and/or `entry.sentimentLabel`. Available
  immediately, no API wait. Example: *"This entry seems related to work, stress,
  and planning."* Shown under label **"SPILR NOTICED"**.
- Reflection card (`insightCard`) — `entry.aiSummaryBullets` (Gemini if ready)
  or `NinetyVoice.localReflection` fallback. Shown under **"SPILR HEARD"**.
- Reflective question from `entry.aiQuestion` (if present).
- **7-day promise card** — headline "The 7-day promise", body: *"Write 3 times
  this week and we'll show your first reflection pattern."* + explanation of
  pattern timeline.
- CTA: **"Start journaling"** — dismisses and sets `firstEntryCelebrationShown = true`.

Dismissing the sheet (via drag or back gesture) also sets the flag via
`sheet(item:onDismiss:)`.

---

## In-app feedback & support

Added to `ProfileView` (in `RootView.swift`):
- **"Send feedback"** row → `mailto:support@spilr.app?subject=Spilr%20Feedback`
- **"Help & support"** row → `https://spilr.app/support`

Both are `Link` elements inside a "Feedback" section above Sign out.

---

## What triggers a PRD update

- Adding or removing an onboarding step
- Changing the commitment picker options or their copy
- Changing the `UserDefaults` key(s) used for completion tracking
- Changing the first-entry trigger conditions or celebration content
- Changing the feedback/support URLs
