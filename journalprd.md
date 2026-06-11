# Journal — Feature PRD

**Last updated:** 2026-06-09
**Status:** Shipped — list, editor, sorting, mood filter, best-streak header, floating compose FAB, topical tagging, sentiment labelling.

---

## What it is

The Journal tab is the user's full archive of entries: a searchable, mood-filterable,
month-grouped list with a custom header, plus the entry editor (free-write and
90-second sessions both write here).

---

## Journal list

**Files:** `Journal/JournalListView.swift`, `Journal/JournalListViewModel.swift`

### Header (custom, not the system large title)

The list uses an inline custom header instead of `.navigationTitle`, with the
navigation bar hidden. This guarantees the title colour (it previously rendered
white/invisible in dark mode because the palette is fixed-light; the app is now
also pinned to `.preferredColorScheme(.light)` in `RootView`).

- Title: "Your **journal**" (`AppTheme.ink`).
- Subtitle: `"{N} entries"`, plus `" · {M}-day best streak"` when the best streak
  is ≥ 2. Best streak = longest run of consecutive calendar days with ≥ 1 entry
  (`bestStreakDays`).
- Custom search field (book icon + clear button) bound to `searchText`.
- Mood filter chips: "All" + one chip per mood the user has actually logged
  (`availableMoods`). Each chip shows a coloured dot (`AppTheme.moodColor`) and a
  short scale label (`Great / Good / Okay / Low / Tough`). Tapping toggles
  `moodFilter`; the selected chip fills with `AppTheme.ink`.

### Sorting

`groupedEntries` groups by calendar **year+month components** (not the localized
label string, which sorted alphabetically and put "June" before "May"). Groups
are ordered newest-month-first; entries within a group are newest-first.

### Filtering

`filteredEntries` applies `moodFilter` then `searchText` (title / content / tags).

### Compose

A floating circular pencil FAB (bottom-trailing, terracotta) opens the editor for
a new entry. Editing an existing entry is a push via `NavigationLink`.

### Optimistic save

To make a saved entry appear immediately (no wait on a Firestore cache
round-trip), `JournalEditorView` exposes an `onSaveEntry: ((JournalEntry) -> Void)?`
closure that fires with the freshly-saved entry. The list calls
`JournalListViewModel.upsert(_:)` to insert/replace it locally; a subsequent
`loadEntries()` reconciles against the source of truth.

---

## Topical tags + sentiment

**Files:** `Home/LocalAI.swift`, `Home/AIService.swift`, `Journal/JournalEditorViewModel.swift`, `Home/NinetySecondSessionView.swift`

Entries used to surface only a handful of labels. Two changes widen this:

- **Topical tags.** `LocalAI.extractTopics(from:limit:)` derives up to 3
  content-based subject tags (work, sleep, people, money, food, health, exercise,
  home, love, study, creativity, nature) by keyword match, ordered by strength.
  On a **new** entry these are merged into the user's own tags (user tags first,
  deduped, capped at 5) in both `JournalEditorViewModel.save()` and
  `NinetySecondViewModel.saveEntry()`. Existing entries' tags are never rewritten.
- **Sentiment variety.** `LocalAI.detectSentiment` expands the keyword groups and
  adds `Tired`, `Grateful`, `Lonely`, `Proud`; `"Reflective"` is only the
  last-resort fallback when nothing emotional registers. The Gemini insight prompt
  lists the same expanded set, and `AIService.parseGeminiResponse` clamps the
  model's returned label to the known vocabulary via `LocalAI.normalizedSentiment`
  (the model sometimes returned off-list words like "Receptive").

`LocalAI.sentimentLabels` is the single source of truth for the recognised set.

---

## What triggers a PRD update

- Change the list sorting, grouping, search, or mood-filter behaviour
- Change the best-streak definition or header copy
- Change the optimistic-save / `upsert` contract
- Change `LocalAI.extractTopics` topics/keywords or the tag-merge rules (cap, order)
- Change `LocalAI.sentimentLabels`, the sentiment keyword groups, or the Gemini
  sentiment validation
- Add/remove user controls on the Journal screen
