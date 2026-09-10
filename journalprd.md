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
navigation bar hidden. This guarantees the title colour renders correctly. (The
app's colour scheme is now driven per-theme by `ThemeManager` — see
`themesprd.md` — replacing the old hard `.preferredColorScheme(.light)` pin in
`RootView`. Light themes render light; Moon renders dark.)

- Title: "Your **journal**" (`AppTheme.ink`).
- Subtitle: `"{N} entries"`, plus `" · {M}-day best streak"` when the best streak
  is ≥ 2. Best streak = longest run of consecutive calendar days with ≥ 1 entry
  (`bestStreakDays`).

### Week-streak row on Home (Spilr "resilience week")

`HomeView.streakSection` renders a row of 7 day-pills (Mon–Sun of the current
week) under the Home header, mirroring the prototype's streak row. A pill is
"done" (terracotta→sun gradient) when a recently-loaded entry falls on that day,
and the current day gets a terracotta outline. It is a **light, decorative
signal** derived from `vm.recentEntries` (capped at 5) — *not* the source of
truth for streaks; `bestStreakDays` above remains authoritative. Framed as
resilience, not pressure.
- Custom search field (book icon + clear button) bound to `searchText`.
- **Tag filter chips (2026-06-11):** "All" + one chip per tag that actually
  appears in the user's entries (`availableTags`, most-used first). Tapping
  toggles `tagFilter`; the selected chip fills with `AppTheme.ink`; the row hides
  when there are no tags. This replaced the old mood-based chips so the filters
  always reflect the real tags in the journal. `filteredEntries` filters by
  `tagFilter` (then `searchText`).

### Sorting

`groupedEntries` groups by calendar **year+month components** (not the localized
label string, which sorted alphabetically and put "June" before "May"). Groups
are ordered newest-month-first; entries within a group are newest-first.

### Filtering

`filteredEntries` applies `moodFilter` then `searchText` (title / content / tags).

### Compose

A floating circular pencil FAB (bottom-trailing, terracotta) opens
**`SpillWriteView`** for a new entry (2026-06-11 — was `JournalEditorView`), so
the pencil matches the Home write actions and opens with a starter "question."
The same FAB is added to the **River** and **Patterns** tabs via the reusable
`.composeFAB(userId:)` modifier (`Components/ComposeFAB.swift`); Home is excluded
(it has its own write entry). Editing an existing entry still pushes
`JournalEditorView` (full editor with mood / tags / future-self / attached photo).

### Attached photo in the editor

When viewing an existing entry, `JournalEditorView` renders `entry.photoURL` as a
220 pt `AsyncImage` (with loading / failure states) below the content.

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

## Photos (Firebase Storage)

**Files:** `Journal/PhotoUploadService.swift`, `Journal/JournalService.swift`,
`Journal/JournalEntry.swift`, `Home/SpillWriteView.swift`, `Home/NinetySecondSessionView.swift`,
`Journal/JournalCardView.swift`, `storage.rules`, `firebase.json`.

Entries can carry one optional attached photo.

- **Model:** `JournalEntry.photoURL: String?` — the Storage download URL, persisted
  to Firestore (default-safe for older entries).
- **Upload:** `PhotoUploadService.uploadEntryPhoto(_:userId:entryId:)` downscales
  (longest edge ≤ 1600 pt) and re-encodes to JPEG (q 0.7), uploads to
  `users/{uid}/entryPhotos/{entryId}.jpg` in Firebase Storage via the
  `FirebaseStorage` SDK, and returns the download URL. There is **no custom
  server** — Storage is a managed bucket; this is client Swift only.
- **Flow:** `SpillWriteView` keeps the picked `UIImage` and passes it to
  `NinetySecondViewModel.saveEntry(photo:)`. Save is never blocked: the entry is
  created immediately, then a **detached** task uploads the photo and patches the
  doc via `JournalService.updateEntryPhotoURL(entryId:userId:url:)` (same
  fire-and-forget pattern as Gemini insights). A failed/slow upload is silent.
- **Display:** `JournalCardView` shows the photo as a 120 pt `AsyncImage`
  thumbnail when `photoURL` is set.
- **Security:** `storage.rules` locks `users/{userId}/entryPhotos/**` to the
  owning user (mirrors the Firestore entry rules). Registered in `firebase.json`.
- **Dependency:** `FirebaseStorage` added to `Package.swift` and the app target in
  `DailyJournal.xcodeproj` (SPM product).

## What triggers a PRD update

- Change the list sorting, grouping, search, or mood-filter behaviour
- Change the best-streak definition or header copy
- Change the optimistic-save / `upsert` contract
- Change `LocalAI.extractTopics` topics/keywords or the tag-merge rules (cap, order)
- Change `LocalAI.sentimentLabels`, the sentiment keyword groups, or the Gemini
  sentiment validation
- Add/remove user controls on the Journal screen
