# Memory Layer — Feature PRD

**Status:** Shipped *(2026-06-15 — extended with emotional vocabulary + coping patterns)*

**Files:** `Memory/MemoryProfile.swift`, `Memory/MemoryProfileService.swift`

---

## What it is

The memory layer is spilr's "durable sense of the person" — a small, deterministic
digest of recurring patterns, mood, cadence, and language. It is injected into
every AI prompt so the model sounds like it has been paying attention, not like
it is meeting the user for the first time.

Key design constraint: spilr should never sound smarter than the user. It should
sound like it has been paying attention. The memory layer exists to deliver that.

---

## MemoryProfile fields

| Field | Type | Description |
|---|---|---|
| `recurringThemes` | `[Theme]` | Most-frequent meaningful words (≥3× across entries, stop-words removed) |
| `recurringEntities` | `[String]` | Names/places from pattern callbacks + frequently-used tags (≥2×) |
| `emotionalVocabulary` | `[String]` | **NEW** User's non-standard emotional words (e.g. "wired", "spiralling", "numb") |
| `copingPatterns` | `[String]` | **NEW** Observed coping signals (e.g. "walks help", "screens make it worse") |
| `topMoodRaw` | `String?` | Dominant mood (last 30 days, all-time fallback) as `Mood.rawValue` |
| `totalEntries` | `Int` | Lifetime entry count |
| `activeDaysLast30` | `Int` | Distinct journaling days in last 30 |
| `activeDaysThisWeek` | `Int` | Distinct journaling days this week |
| `firstEntryDate` | `Date?` | When the user first journaled |
| `lastEntryDate` | `Date?` | When they last journaled |
| `generatedAt` | `Date` | Timestamp of last digest generation |

---

## Emotional vocabulary extraction *(New — 2026-06-15)*

**Goal:** Detect the user's own non-standard words for emotions ("wired",
"spiralling", "flat", "buzzing") so prompts mirror their vocabulary instead of
mapping everything to standard labels.

**Algorithm:** For each entry, scan for words that appear within 5 tokens after
an emotion anchor (`feel`, `felt`, `feeling`, `i'm`, `i am`, `so`, `been`). A
word qualifies if:
- `count >= 4` characters (filter noise)
- Not in `standardEmotions` (the 13 standard sentiment labels + generic words)
- Not a stop word
- Appears in at least 2 entries across the corpus

Top 8 qualifying words are stored in `emotionalVocabulary`.

**Prompt injection:** Included in `promptContext()` as:
`"Their emotional vocabulary (use these words, not standard labels): wired, spiralling, …"`

---

## Coping patterns extraction *(New — 2026-06-15)*

**Goal:** Surface observations like "walks help" or "screens make it worse"
so the AI can reference the user's own coping behaviours without sounding generic.

**Algorithm:** For each sentence in each entry:
- **Positive signals:** look for `help`/`helps`/`helped`/`calms`/`eases` etc.
  Extract the subject (3 tokens before the verb, stop-words removed). De-duplicate
  by subject. Emit as `"{subject} helps"`.
- **Negative signals:** look for `makes it worse`/`made it worse`/`doesn't help`
  etc. Emit as `"{subject} makes it worse"`.

Up to 6 coping signals stored in `copingPatterns`.

**Prompt injection:** Included in `promptContext()` as:
`"Observed coping signals: walks help; screens make it worse; …"`

---

## promptContext() injection

Injected at the END of every Gemini prompt that calls
`MemoryProfileService.shared.cachedPromptContext()`:
- Recurring themes (top 5)
- Names/places that recur (top 5)
- **Emotional vocabulary** — new field
- **Coping patterns** — new field
- Dominant mood
- Cadence stats

The block is prefaced: *"WHAT YOU ALREADY KNOW ABOUT THIS PERSON (context
only — use it to make ONE line feel personally aware … Use their own words for
emotions where possible — their vocabulary, not generic labels)"*

---

## Build cadence

`MemoryProfileService.shared.build(for:)` is called fire-and-forget from
`HomeViewModel.load()` via a `Task.detached`. It is also called lazily by the
Echoes tab. Results are cached to `UserDefaults` so all synchronous AI prompt
paths can call `cachedPromptContext()` without an async wait.

---

## What triggers a PRD update

- Adding or removing fields from `MemoryProfile`
- Changing any extraction algorithm (anchors, stop-words, thresholds)
- Changing the `promptContext()` format or framing language
- Changing the cache keys or build trigger conditions
