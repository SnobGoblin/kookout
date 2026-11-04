// Seasons: the part of the year a spot gives notifications (and shows in the widget). Outside it the forecast still
// shows in the app, but good conditions don't count. A season is {from: "MM-DD", to: "MM-DD"}, both days included;
// from after to goes over New Year (e.g. Nov–Mar). All year is ALL_YEAR (stored as NULL).
//
// Each spot starts with a default from its place and sport; from 3 active followers the community's season is the
// majority's (a day is in season if more than half have it in theirs). Each follower can set their own dates.

import { dayKey } from "../../rules.js";

export const ALL_YEAR = { from: "01-01", to: "12-31" };
// Wing and surf in the north (about 50° N and up: Scandinavia, the UK, northern Germany…): mid-March to Christmas Eve.
// Further south, and powder (its rule only fires in winter anyway): all year.
const NORTH = { from: "03-15", to: "12-24" };

export function defaultSeason(lat, sport) {
  return sport !== "powder" && lat >= 50 ? NORTH : null;
}

const DAYS = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const validDay = md => {
  const m = /^(\d\d)-(\d\d)$/.exec(md ?? "");
  return !!m && +m[1] >= 1 && +m[1] <= 12 && +m[2] >= 1 && +m[2] <= DAYS[+m[1] - 1];
};

/// A season as sent by the app, checked: {from, to}, or null for all year (or when it's not a season).
export function cleanSeason(s) {
  if (!s || typeof s !== "object" || !validDay(s.from) || !validDay(s.to)) return null;
  return isAllYear(s) ? null : { from: s.from, to: s.to };
}

const isAllYear = s => !s || allDays.every(d => contains(s, d));
const contains = (s, md) => s.from <= s.to ? md >= s.from && md <= s.to : md >= s.from || md <= s.to;

/// Whether a moment (ms) falls in the season, by the calendar day in the spot's time zone. No season: all year.
export function inSeason(season, t, zone) {
  return !season || contains(season, dayKey(new Date(t), zone).slice(5));
}

// Every day of a (leap) year, "01-01" … "12-31".
const allDays = DAYS.flatMap((n, m) => Array.from({ length: n }, (_, d) => `${String(m + 1).padStart(2, "0")}-${String(d + 1).padStart(2, "0")}`));

/// The majority's season: the days more than half the votes have in theirs, as one stretch (the longest, in the
/// unlikely case there are several). Votes are seasons or null (all year). Null: all year. Exported for tests.
export function majoritySeason(votes, current) {
  const inside = allDays.map(d => votes.filter(v => !v || contains(v, d)).length * 2 > votes.length);
  if (inside.every(Boolean)) return null;
  if (!inside.some(Boolean)) return current ?? null;
  // The longest run of days in season, going round New Year: start counting just after a day out of season.
  const n = allDays.length, start = inside.indexOf(false);
  let best = null, run = null;
  for (let k = 1; k <= n; k++) {
    const i = (start + k) % n;
    if (inside[i]) { run = run ? { ...run, to: i, length: run.length + 1 } : { from: i, to: i, length: 1 }; }
    else run = null;
    if (run && (!best || run.length > best.length)) best = run;
  }
  return { from: allDays[best.from], to: allDays[best.to] };
}
