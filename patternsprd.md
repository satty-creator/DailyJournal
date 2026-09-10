# Patterns — Feature PRD

**Status:** Shipped — resilience score, 30-day activity grid, AI insight cards,
mood distribution, stats, word cloud, recurring tags, weekly recap + share.

---

## What it is

The Patterns tab is the analytics surface: a calm, pastel read of how the user
has been showing up. No streak counter — the headline metric is **resilience**
(days journaled out of the last 30), framed as "no streak to break."

**Files:** `Patterns/PatternsView.swift`, `Patterns/WeeklyWrappedCard.swift`.

---

## Sections (top → bottom)

1. **Weekly recap** (`WeeklyWrappedCard` + share) — when there are entries this week.
2. **Resilience card** — conic-gradient ring, `resilienceScore` of 30 + label.
3. **Activity grid** — last 30 days as pastel "pebbles" (journaled vs quiet).
4. **AI insights** — see below. *(Added 2026-06-11.)*
5. **Mood distribution** — last-30 moods as gradient bars.
6. **Stats row** — entries / words / this week / 90-sec.
7. **Word cloud** — words returned to (≥3×).
8. **Recurring tags** — tags used ≥2×.

---

## AI insights (the prototype's "AI" / insight-grid)

`PatternsView.aiInsightsSection`, below the 30-day activity grid, renders the
prototype's insight cards: a left accent stripe, an icon + title, a one-line
"gentle mirror", and a **confidence bar**. A "safe AI" tag and the subtitle
"Gentle mirrors, not therapy claims." head the section.

Cards come from `PatternsViewModel.aiInsights: [PatternInsight]`
(`icon`, `title`, `detail`, `confidence` 0–100), **derived only from real
signals already computed** — never invented:

| Card | Source | Confidence |
|---|---|---|
| "'{word}' keeps coming back" | `frequentWords.first` | `min(92, 55 + count·6)` |
| "Your month leans {mood}" | `moodDistribution.first` | mood's share of total (min 45) |
| "'{tag}' threads through your writing" | `frequentTags.first` | `min(88, 50 + count·7)` |

The "You return more than you skip" resilience card **removed (2026-06-17)** —
it was universally true and carried no meaningful signal. Resilience is still
shown in the ring card at the top of the view.

**Stopword list extended (2026-06-17):** `frequentWords` now filters a broader
set including generic vague words (`something`, `anything`, `everything`,
`nothing`, `maybe`, `basically`, `literally`, `thing`, `things`, `stuff`, etc.).
Minimum word length raised from >3 to >4 characters. This prevents meaningless
filler from surfacing as "'{word}' keeps coming back" insights.

**Section label renamed (2026-06-17):** "Words you return to" → **"Thoughts you return to"**.

The section is shown only when `aiInsights` is non-empty. Under 14 total entries
a gating note ("Early clues. Deeper patterns unlock as you pass ~14 entries.")
appears, matching the prototype's "gate deeper claims until enough data" rule.
Language stays probabilistic and non-clinical.

---

---

## Pattern Detection Gate *(Updated 2026-06-15)*

`PatternDetectionService` gates pattern callbacks behind **two** conditions:

1. **Entry count:** ≥ 6 entries within the 60-day window.
2. **Maturity:** The user's **first ever entry** (all-time, not just the 60-day
   window) must be at least **14 days old**.

The 14-day maturity gate prevents a burst of entries in the first week from
triggering premature callbacks. Both conditions must pass; either failure returns
`.skipped`.

**Implementation:** `PatternDetectionService.minJournalingDays = 14`. Checked
after the 60-day window is built, using `all.min(by: { $0.createdAt < $1.createdAt })`.

---

## What triggers a PRD update

- Change the resilience definition, label bands, or the 30-day grid
- Add/remove/reorder a Patterns section
- Change `aiInsights` sources, copy, confidence formulas, or the gating threshold
- Change the weekly-recap inputs or the share card
- Change either detection gate (entry count or maturity days)
