# Themes — PRD

Owner feature: user-selectable visual themes ("vibes") for ninety.
Status: v1 implemented (engine + 5 palettes + picker + persistence).

---

## Goal

Let every user make ninety feel like theirs by choosing a colour vibe, without
gendered framing. Mirrors the Spilr prototype's theme picker. A theme change
re-skins the entire app instantly and persists across launches.

Design principle preserved: **local-first, zero-risk**. Theming is a pure
client concern — no network, no Firestore, no AI. Default look is unchanged.

---

## Themes

Five palettes, exposed via `ThemeID` (`Theme/AppTheme.swift`):

| ID | Title | Subtitle | Scheme | Notes |
|---|---|---|---|---|
| `bloom` | Bloom | soft + cute | light | **Default.** Byte-for-byte the original ninety pastel palette. |
| `moon` | Moon | night + calm | **dark** | The one dark palette. See caveat below. |
| `forest` | Forest | grounded | light | Greens + warm sand. |
| `graphite` | Graphite | data-first | light | Cool blue/slate, white cards. |
| `sunset` | Sunset | warm | light | Warm orange/peach. |

Palette values are derived from the Spilr prototype's CSS custom properties,
mapped onto ninety's existing token vocabulary.

---

## Architecture

### `ThemePalette` (`Theme/AppTheme.swift`)
A value type holding every design token as a concrete `Color`
(`paper`, `paperWarm`, `cream`, `ink`, `inkSoft`, `terracotta`,
`terracottaDeep`, `rose`, `rose2`, `peach`, `mint`, `blue`, `lav`, `sun`,
`moss`, `dusk`, `gold`, `slate`, `valenceCold`, `cardShadow`). Five static
instances: `.bloom`, `.moon`, `.forest`, `.graphite`, `.sunset`.

### `AppTheme` (`Theme/AppTheme.swift`)
The public design-system surface. **Every original property name and
typography signature is preserved**; the colour properties changed from fixed
`let`s to computed `static var`s that read from `AppTheme.active` (the current
palette). Because of this, **no per-screen edits were required** — all ~37
files that reference `AppTheme.*` automatically adopt the active palette.

`AppTheme.active` defaults to `.bloom`, so the app looks identical until the
user picks another theme.

New internal token: `valenceCold` (the cold lavender at the bottom of the
valence scale) — previously a hardcoded hex inside `moodColor`/`valenceColor`;
now per-theme so dark/warm themes stay coherent.

### `ThemeManager` (`Theme/ThemeManager.swift`)
`@MainActor final class ThemeManager: ObservableObject`, singleton
(`ThemeManager.shared`).
- `@Published var themeID: ThemeID` — on change, updates `AppTheme.active` and
  persists `rawValue` to `UserDefaults` key `ninety.selectedTheme`.
- `palette` / `colorScheme` convenience accessors.
- `select(_:)` setter used by the picker.
- On init, restores the saved theme (falling back to `.bloom`) and sets
  `AppTheme.active` **before** any view body runs.

### Wiring (`App/DailyJournalApp.swift`, `App/RootView.swift`)
- `ThemeManager.shared` is injected as an `@EnvironmentObject` at the app root.
- `RootView` applies:
  - `.id(themeManager.themeID)` — re-identifies the tree so every screen
    rebuilds with the new palette (the live-switch mechanism).
  - `.preferredColorScheme(themeManager.colorScheme)` — replaces the old hard
    `.light` pin; driven by the palette (Moon = dark, others = light).
  - a 0.45s ease animation on `themeID`.

### Picker (`Theme/ThemePickerView.swift`)
"Choose your vibe" screen: a live preview card (Today's-Read style) plus a
2-column grid of tiles. Each tile shows a 3-colour swatch, title, subtitle, and
a selected checkmark/ring. Tapping triggers a soft haptic and an animated
switch. Reads/writes `ThemeManager` via `@EnvironmentObject`.

### Entry point (`App/RootView.swift` → `ProfileView`)
`ProfileView` gained an **Appearance** section with a `NavigationLink` to
`ThemePickerView` (manager injected explicitly at the destination so it works
regardless of sheet environment inheritance). `ProfileView` is presented from
`HomeView` via the existing `showProfile` sheet.

---

## Known caveat — Moon (dark)

The `cream` token is intentionally overloaded in the original design system:
it is used both as a light **card background** (~40 call sites) and as light
**inverse text on dark surfaces** (~25 call sites). For the four light themes
this dual role is valid. For Moon, `cream` becomes a dark card surface and
`ink` flips to near-white text — correct for the dominant cases — but any spot
that draws `cream`-coloured text on an `ink`-coloured surface can be
low-contrast. Moon is therefore "best-effort dark" pending a device build pass.

**Proper fix (future):** split the overloaded token into `surface` (card bg)
and `onDark` (inverse text), then migrate the ~25 text call sites. Until then,
the four light themes are the fully-verified set.

---

## Future / v2

- Token split to make Moon fully robust (above).
- Offer the picker during onboarding (set the first vibe before first entry),
  matching the Spilr prototype's onboarding modal.
- "Follow system" option that maps light/dark automatically.
- Per-theme app icon / share-card accents.
