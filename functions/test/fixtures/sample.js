/* A synthetic but realistic corpus, shaped like the account in the 9 Sept
 * screenshots and sized so that EVERY Tier-1 observation type fires at least
 * once.
 *
 * Deliberately hand-built rather than captured, so every expected number can be
 * counted by hand — a fixture whose right answer you can only get by running
 * the code proves nothing.
 *
 * The shape, and what each part is here to exercise:
 *
 *   14 entries on 14 distinct local days, 2026-08-13 .. 2026-09-10 ("today").
 *   14 lifetime entries is also exactly the lag unlock threshold.
 *
 *   work           6 days   08-13, 08-19, 08-26, 09-01, 09-05, 09-10
 *   'heavy'        5 days   all of the above EXCEPT 09-05
 *     -> co-occurrence  n=6 m=8 k=5 j=0, lift 2.33
 *     -> exception      09-05 is the one work day without 'heavy'  (k/n = .83)
 *   Priya          4 days   08-13, 08-19, 08-26, 09-10, all with 'heavy'
 *     -> co-occurrence  n=4 k=4, lift 2.8      (no exception: nothing missed)
 *   rest           7 days;  'tired' on 3 of them -> co-occurrence, lift 2.0
 *                           'calm'  on 2 of them -> co-occurrence, lift 2.0
 *   Sundays        3 (~403 words) vs 11 others (~181)  -> weekday, +122%
 *   day-after-work 3 pairs, ~95 words vs ~265 baseline -> lag, -64%
 *   'heavy' entries 4 of 5 written late                -> time band
 *   "she'd do it for me" on 08-13 and again today      -> callback, 28 days
 *   'calm' last seen 08-16, returns 09-09              -> streak, 24-day gap
 *   two thought records, 7->4 then 6->3                -> delta, 2 in a row
 */

"use strict";

const TZ = "Europe/London";
const NOW = new Date("2026-09-10T21:00:00Z"); // Thu 22:00 local

const P_COVER = "she'd do it for me";
const P_LUCKY = "lucky and loved";

// hourUTC is chosen so the LOCAL band is the one named in the comment.
const DAYS = [
  { date: "2026-08-13", hourUTC: 21, band: "late", mode: "freeWrite", words: 200, mood: "bad",
    domains: ["work"], emotions: ["heavy"], phrases: [P_COVER], body: ["tight chest"],
    people: [{ name: "Priya", role: "the one I cover for" }],
    summary: "Covered Priya's shift again and felt flattened by it." },

  { date: "2026-08-14", hourUTC: 21, band: "late", mode: "freeWrite", words: 90, mood: "bad",
    domains: ["rest"], emotions: ["tired"], phrases: [], body: [], people: [],
    summary: "Too tired to write much tonight." },

  { date: "2026-08-16", hourUTC: 9, band: "morning", mode: "freeWrite", words: 400, mood: "good",
    domains: ["rest"], emotions: ["calm"], phrases: [], body: [], people: [],
    summary: "A long slow Sunday morning, calm for once." },

  { date: "2026-08-19", hourUTC: 21, band: "late", mode: "freeWrite", words: 210, mood: "bad",
    domains: ["work"], emotions: ["heavy"], phrases: [], body: ["tight chest"],
    people: [{ name: "Priya", role: "the one I cover for" }],
    summary: "Another late one after Priya asked." },

  { date: "2026-08-20", hourUTC: 21, band: "late", mode: "freeWrite", words: 95, mood: "bad",
    domains: ["rest"], emotions: ["tired"], phrases: [], body: [], people: [],
    summary: "Wiped out. Short one." },

  { date: "2026-08-23", hourUTC: 9, band: "morning", mode: "freeWrite", words: 420, mood: "good",
    domains: ["rest"], emotions: ["lucky"], phrases: [], body: [],
    people: [{ name: "Dan", role: "the one I lean on" }],
    summary: "Breakfast with Dan, a whole morning that belonged to me." },

  { date: "2026-08-26", hourUTC: 21, band: "late", mode: "freeWrite", words: 205, mood: "bad",
    domains: ["work"], emotions: ["heavy"], phrases: [P_COVER], body: ["tight chest"],
    people: [{ name: "Priya", role: "the one I cover for" }],
    summary: "Said yes again before I had thought about it." },

  { date: "2026-08-27", hourUTC: 21, band: "late", mode: "freeWrite", words: 100, mood: "neutral",
    domains: ["rest"], emotions: ["tired"], phrases: [], body: [], people: [],
    summary: "Nothing left in the tank." },

  { date: "2026-08-30", hourUTC: 9, band: "morning", mode: "freeWrite", words: 390, mood: "good",
    domains: ["rest"], emotions: ["lucky"], phrases: [], body: [], people: [],
    summary: "Slept in, read for an hour, felt lucky about it." },

  { date: "2026-09-01", hourUTC: 19, band: "evening", mode: "template", words: 260, mood: "neutral",
    domains: ["work"], emotions: ["heavy"], phrases: [], body: [], people: [],
    summary: "Worked through the decision about the extra shift.",
    templateId: "untangle-a-decision", before: 7, after: 4 },

  // THE EXCEPTION — a work day WITHOUT 'heavy'.
  { date: "2026-09-05", hourUTC: 18, band: "evening", mode: "freeWrite", words: 240, mood: "good",
    domains: ["work"], emotions: ["lucky"], phrases: [P_LUCKY], body: [],
    people: [{ name: "Dan", role: "the one I lean on" }],
    summary: "Work was fine today, honestly just lucky and loved tonight." },

  { date: "2026-09-08", hourUTC: 19, band: "evening", mode: "template", words: 255, mood: "neutral",
    domains: ["body"], emotions: ["drained"], phrases: [], body: ["tight chest"], people: [],
    summary: "Went back through the same knot on paper.",
    templateId: "untangle-a-decision", before: 6, after: 3 },

  { date: "2026-09-09", hourUTC: 21, band: "late", mode: "dailyChat", words: 160, mood: "good",
    domains: ["rest"], emotions: ["calm"], phrases: [], body: [], people: [],
    summary: "A quiet evening. Calm, which I have not written in a while." },

  // TODAY — carries the callback phrase and the 'heavy' + Priya + work stack.
  { date: "2026-09-10", hourUTC: 21, band: "late", mode: "freeWrite", words: 180, mood: "bad",
    domains: ["work"], emotions: ["heavy"], phrases: [P_COVER], body: ["tight chest"],
    people: [{ name: "Priya", role: "the one I cover for" }],
    summary: "Priya asked again and I heard myself say yes before I decided." },
];

function build() {
  const entries = [];
  const analyses = [];
  DAYS.forEach((d, i) => {
    const id = `e${String(i + 1).padStart(2, "0")}`;
    const createdAt = new Date(`${d.date}T${String(d.hourUTC).padStart(2, "0")}:00:00Z`);
    entries.push({
      id,
      createdAt,
      sessionType: d.mode,
      mood: d.mood,
      tags: [],
      wordCount: d.words,
      ...(d.templateId ? {
        templateId: d.templateId,
        templateScaleBefore: d.before,
        templateScaleAfter: d.after,
      } : {}),
    });
    analyses.push({
      entryId: id,
      createdAt: new Date(createdAt.getTime() + 60000),
      entryCreatedAt: createdAt,
      wordCount: d.words,
      surfaceSummary: d.summary,
      lifeDomains: d.domains,
      explicitEmotions: d.emotions,
      phrasesToTrack: d.phrases,
      bodySignals: d.body,
      relationshipRoles: [],
      people: d.people,
      needs: [],
      protectiveStrategies: [],
      valuesPresent: [],
      episodes: [],
      promptVersion: "mirror-extract-v2",
      ...(d.templateId ? {
        templateDelta: { templateId: d.templateId, before: d.before, after: d.after },
      } : {}),
    });
  });
  return { entries, analyses, tz: TZ, now: NOW, entriesTotal: entries.length };
}

module.exports = { build, TZ, NOW, DAYS, P_COVER, P_LUCKY };
