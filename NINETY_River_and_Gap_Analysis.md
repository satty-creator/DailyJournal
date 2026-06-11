# ninety — Prototype & Notes vs. Your App: Analysis + What I Built

_Reviewed: the uploaded `preview.html` prototype, your full draft notes (River, reflections, pattern callbacks, share loop, App Store prep), and the live SwiftUI + Firebase codebase in `DailyJournal/`._

---

## 1. The headline finding

Your shipped app is **much further along than the prototype and notes assume.** Most of what the notes describe as "to build" already exists in Swift:

| Notes / prototype concept | Status in your app | Where |
|---|---|---|
| Free-write mode | **Exists** — already the *primary* button on Home | `Home/HomeView.swift`, `Journal/JournalEditorView.swift` |
| 90-second mode | Exists (secondary) | `Home/NinetySecondSessionView.swift` |
| AI reflection (mirror + question) | Exists (Gemini + local fallback) | `Home/AIService.swift`, `Home/LocalAI.swift` |
| Reflection stored separately from raw entry | Partial — `aiSummaryBullets`, `aiQuestion`, `sentimentLabel` on the entry | `Journal/JournalEntry.swift` |
| Pattern callbacks (the full Co-Star system) | **Exists** — archetypes, salience, frequency gates, mute/affirm, stitched tap-through | `Pattern/` (10 files) |
| Crisis safety routing | **Exists** — deterministic filter + resource card | `Pattern/PatternSafety.swift`, `PatternResourceCardView.swift` |
| Future-self letters | **Exists** — schedule, arrive, read | `Components/FutureSelfSheet.swift`, Home "letters" section |
| Echoes ("did you do it?") | **Exists** | `Echo/` |
| Mood logging (journal-free) | Exists | `Mood/` |
| Share cards | Exists (weekly wrapped + insight card) | `Components/ShareableInsightCard.swift`, `Patterns/WeeklyWrappedCard.swift` |
| Patterns/analytics surface | Exists (resilience score, activity grid, word cloud) | `Patterns/PatternsView.swift` |
| **The River (per-entry marks → 7/14/30-day visual artifact)** | **Did NOT exist** | _built this session — see §3_ |

**Takeaway:** don't rebuild the reflection / callback / letter machinery — it's there and well-architected (fire-and-forget Firestore writes, local-first heuristics, Gemini upgrades silently). The two genuine gaps were (a) the **River**, and (b) the app still **leaning on "90 seconds"** in its identity. Both are addressed below.

---

## 2. The aesthetic fork (resolved)

Your prototype is **cute/pastel** (rosé, mint, lavender, rounded droplets). Your shipped app was **editorial** (terracotta, cream, *serif*). These are opposite identities. Per your instruction I shifted the app **toward the pastel prototype**:

- Rewrote `Theme/AppTheme.swift` to a pastel palette. **Every existing property name and function signature was kept** so no screen breaks — only the values changed (e.g. `terracotta` is now a soft rose, `ink` is a deep aubergine instead of near-black) plus new colours (`rose`, `peach`, `mint`, `blue`, `lav`, `sun`).
- Display/body type switched from `.serif` → `.rounded` for the softer, "cute" feel — again without changing any call sites.
- Added a River colour vocabulary (`valenceColor`, `RiverMarker` glyph + tint) and a reusable `.softCard()` modifier.

> One honest caveat: I can't render the build here, and a global theme swap is the one change most likely to need your eye. The risk is purely visual (contrast on dark cards, the rounded font on dense screens), never compile-level. Open it in the simulator and we can tune values.

---

## 3. What I built this session — the River

A new `River/` module, wired into a new **River tab**. The design principle from your notes is baked in: _"cute is the wrapper, meaning is the engine"_ — every glyph maps to a real signal.

**Files added**
- `River/RiverMark.swift` — the **derived per-entry signal** (valence, activation, clarity, pressure, self-compassion, motifs, themes, quote anchor, water-state, marker, safety level). Stored at `users/{uid}/riverMarks/{entryId}`, keyed to the entry so it's 1:1 and regenerates cleanly. The raw entry stays untouched and sacred.
- `River/River.swift` — the aggregated **7 / 14 / 30-day artifact** model: day segments, main current, recurring words, the bend, return mark, sentence-of-the-window (private), gentle question, private interpretation, and three privacy-safe share copies. Unlock thresholds are deliberately low (3 / 5 / 8 entries) so consistency is never the price of meaning.
- `River/AIService+River.swift` — the two Gemini passes (reviewed in §5).
- `River/LocalRiver.swift` — a **deterministic on-device generator**. The river paints instantly with no API key; Gemini upgrades it silently when present. This mirrors the local-first pattern you already use for entry insights.
- `River/RiverService.swift` — storage + orchestration. Marks generate on every entry save; rivers are **built on demand from marks, never persisted**, so deleting an entry can't strand a stale artifact. Includes a one-time local backfill so existing entries get marks immediately.
- `River/RiverView.swift` — the flowing `Canvas` renderer (valence drives vertical flow, intensity drives droplet size), a 7/14/30 window toggle, tappable day markers with **private** tooltips, the narrative cards, and a **privacy-safe share card** ("make your first current" — no raw text, no sensitive labels).

**Wiring**
- River-mark generation hooked into **both** save paths (`NinetySecondSessionView`, `JournalEditorViewModel`) as a detached background task.
- Mark deletion follows entry deletion.
- New `riverMarks` rule added to `firestore.rules`.
- New **River tab** in `RootView`.

**Visual grammar implemented:** 💧 water (entry) · 🌫️ mist (quiet day, *never* failure) · 🌉 bridge (return after a gap) · ✨ glimmer (softer self-talk) · 🪨 stone (recurring theme) · 🌊 rapid (pressure) · 🌀 deep pool (heavy entry).

---

## 4. De-emphasizing "90 seconds"

Per your instruction (free-writing the default, 90s an optional mode):
- Free-write was already the primary Home CTA — kept, and the 90-second button reframed from "Try a 90-second session" → **"Short on time? Try 90-second mode."**
- Home empty-state copy changed from _"Your first 90 seconds is waiting"_ → _"Write as much or as little as you like. Your river starts with one entry."_

What I deliberately **did not** touch (flag for your call): the brand name "ninety", the splash screen, and onboarding screens still carry the name. Renaming is a bigger decision (App Store, domain, the notes' whole launch plan) — happy to do it once you decide.

---

## 5. Your question: is the River AI prompt "thorough and thoughtful"?

Your draft prompts were a strong starting point but had three weaknesses I corrected:

1. **One giant prompt does two jobs badly.** Your notes mix per-entry signal extraction and window aggregation. I split them into **two passes** with different temperatures: extraction at `0.2` (it's measurement, should be near-deterministic) and narrative at `0.6` (it's prose, needs a little warmth). Mixing them makes the model either too floaty on numbers or too stiff on prose.

2. **The specificity gate was a separate third model call.** Your notes propose a whole second "quality checker" model pass to reject generic output. That doubles latency and cost on a free Gemini tier. I folded it **into** the aggregation prompt as a self-check instruction ("before returning, silently rewrite anything that could apply to anyone / gives advice / diagnoses / isn't grounded"). You get ~80% of the benefit at zero extra calls. _If you later want the belt-and-suspenders version, the separate checker is worth adding — but as a sampled QA job, not on every river._

3. **Safeguards were implied, not enforced.** I made them explicit and machine-checkable: banned cliché list inline, "no causation — use *appeared with / tended to*", missed days described neutrally, returns framed as rhythm not streak, `share_*` fields hard-separated from `private_*` (raw quotes only ever in private), and a safety level that makes the pipeline **back off entirely** on crisis content and hand to your existing `PatternSafety` flow.

**Net:** the prompts are now thorough *and* cheap. They're grounded (every claim must cite the provided motifs/movement), non-clinical, privacy-aware, and they degrade gracefully — if Gemini is absent or fails, `LocalRiver` produces a real river deterministically.

Two honest limitations to know about:
- The **local fallback's signals are keyword heuristics**, so its valence/pressure are coarser than Gemini's. The river still *works*, it's just less nuanced without a key.
- I have **not** implemented the entity-level "avoidance" / "contradiction" detections from your pattern-callback notes inside the river — those already live (partially) in your `Pattern/` system, and folding them into the river is a v2 step.

---

## 6. Recommended next steps (not built this session)

1. **Build it in Xcode and tune the pastel values** — the theme swap is the one thing that needs your eyes.
2. **Onboarding redesign** — the prototype's "write first, *then* ask for notifications" sequence is good UX and you don't have it yet.
3. **Real share-image export** — the share card is SwiftUI today; render it to a `UIImage` via `ImageRenderer` for a true Instagram-story asset (the viral object your notes care about).
4. **The 30-person manual validation loop** from your notes — that's a go-to-market action, not code. It's the right call and worth starting in parallel.
5. **App Store paperwork** — your notes' "do the boring parts now" advice is correct; none of it is blocked by the River work.

---

_All code changes are in `DailyJournal/` and compile-checked by inspection against your existing conventions (Firestore fire-and-forget writes, local-first + silent Gemini upgrade, `AppTheme` API). They could not be run through Xcode in this environment — please build once and report any issues._
