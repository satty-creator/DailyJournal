/* time.js — local-calendar arithmetic for the derived jobs.
 *
 * Pure. Everything Mirror v3 says about a person's days ("3 after 9pm",
 * "Sunday entries", "the day after you write about X") is a claim in THEIR
 * timezone, not UTC. Getting this wrong doesn't produce an error, it produces
 * a confidently wrong number — which is the one failure mode Mirror v3 exists
 * to eliminate.
 */

"use strict";

const DAY_MS = 86400000;
const DAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** Time-of-day bands. `late` deliberately wraps midnight: an entry written at
 *  01:30 belongs to the night that started the evening before, which is how a
 *  person describes it ("I was up late") even though the calendar disagrees. */
function bandForHour(hour) {
  if (hour >= 5 && hour <= 11) return "morning";
  if (hour >= 12 && hour <= 16) return "afternoon";
  if (hour >= 17 && hour <= 20) return "evening";
  return "late"; // 21-23 and 0-4
}

/**
 * Local date parts for `instant` in IANA `tz`.
 *
 * Returns `{ dateKey: "yyyy-MM-dd", weekday: 0..6 (0=Sun), hour: 0..23,
 * band, label }` — all in the user's local calendar.
 *
 * Falls back to UTC on an unknown/absent timezone rather than throwing: a bad
 * tz string must degrade to slightly-off buckets, never take down the nightly
 * job for that user.
 */
function localDateParts(instant, tz) {
  const d = instant instanceof Date ? instant : new Date(instant);
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz || "UTC",
      year: "numeric", month: "2-digit", day: "2-digit",
      weekday: "short", hour: "2-digit", hour12: false,
    }).formatToParts(d);
    const get = (type) => (parts.find((p) => p.type === type) || {}).value;
    const year = get("year");
    const month = get("month");
    const day = get("day");
    const weekday = DAYS_SHORT.indexOf(get("weekday"));
    // Intl can return "24" for midnight under hour12:false in some ICU builds.
    const hour = (parseInt(get("hour"), 10) || 0) % 24;
    if (!year || !month || !day) throw new Error("incomplete parts");
    const dateKey = `${year}-${month}-${day}`;
    return {
      dateKey,
      weekday: weekday >= 0 ? weekday : d.getUTCDay(),
      hour,
      band: bandForHour(hour),
      label: DAYS_SHORT[weekday >= 0 ? weekday : d.getUTCDay()],
    };
  } catch (e) {
    const hour = d.getUTCHours();
    return {
      dateKey: d.toISOString().slice(0, 10),
      weekday: d.getUTCDay(),
      hour,
      band: bandForHour(hour),
      label: DAYS_SHORT[d.getUTCDay()],
    };
  }
}

/** Back-compat shim for the weekly-letter dispatcher, which only ever wanted
 *  these two fields. */
function localWeekdayAndHour(instant, tz) {
  const p = localDateParts(instant, tz);
  return { weekday: p.weekday, hour: p.hour };
}

/** "yyyy-MM-dd" keys for the last `days` local days, oldest first, ending on
 *  the local day containing `now`. This is the x-axis of the 30-day dot strip
 *  and the window every observation is computed over. */
function recentDateKeys(now, days, tz) {
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    out.push(localDateParts(new Date(now.getTime() - i * DAY_MS), tz).dateKey);
  }
  return out;
}

/** Local-week bounds (Sunday-start) containing `now`, as dateKeys. */
function weekBounds(now, tz) {
  const today = localDateParts(now, tz);
  const start = new Date(now.getTime() - today.weekday * DAY_MS);
  return {
    start: localDateParts(start, tz).dateKey,
    end: today.dateKey,
  };
}

/** Whole days between two "yyyy-MM-dd" keys (b - a). Calendar arithmetic, so
 *  DST-safe in a way subtracting epoch millis is not. */
function daysBetweenKeys(a, b) {
  const pa = Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10));
  const pb = Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10));
  return Math.round((pb - pa) / DAY_MS);
}

/** "2 days ago" / "yesterday" / "today" — the relative label on a receipt. */
function relativeLabel(dateKey, todayKey) {
  const diff = daysBetweenKeys(dateKey, todayKey);
  if (diff <= 0) return "today";
  if (diff === 1) return "yesterday";
  if (diff < 7) return `${diff} days ago`;
  if (diff < 14) return "last week";
  if (diff < 60) return `${Math.round(diff / 7)} weeks ago`;
  return `${Math.round(diff / 30)} months ago`;
}

/** "12 Aug" — the absolute date form used in letters and proof sheets. */
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function shortDate(dateKey) {
  if (!dateKey || dateKey.length < 10) return "";
  return `${parseInt(dateKey.slice(8, 10), 10)} ${MONTHS[parseInt(dateKey.slice(5, 7), 10) - 1]}`;
}

module.exports = {
  DAY_MS,
  DAYS_SHORT,
  bandForHour,
  localDateParts,
  localWeekdayAndHour,
  recentDateKeys,
  weekBounds,
  daysBetweenKeys,
  relativeLabel,
  shortDate,
};
