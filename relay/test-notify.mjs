// Run with: node test-notify.mjs  (checks the notification logic without sending anything)
import { _test } from "./src/notify.js";
const { compare, hours, dayLabel } = _test;
const H = 3600e3, t0 = Date.parse("2026-10-13T10:00:00Z"), at = h => t0 + h * H;
const P = (a, b) => ({ start: at(a), end: at(b) });
const show = ev => ev.map(e => `${e.type} ${(e.period.start - t0) / H}–${(e.period.end - t0) / H}` + (e.was ? ` was ${(e.was.start - t0) / H}–${(e.was.end - t0) / H}` : ""));
const check = (name, got, want) => console.log(JSON.stringify(got) === JSON.stringify(want) ? "ok  " : "FAIL", name, got);
const prev = { periods: [P(5, 8), P(30, 34)], horizon: at(48) };
check("nothing changed", show(compare(prev, [P(5, 8), P(30, 34)], at(0), at(48))), []);
check("window moved: new period at the end", show(compare(prev, [P(5, 8), P(30, 34), P(48.5, 52)], at(1), at(49))), ["new 48.5–52"]);
check("one hour longer: not a change", show(compare(prev, [P(5, 9), P(30, 34)], at(0), at(48))), []);
check("moved 2 hours: changed", show(compare(prev, [P(3, 8), P(30, 34)], at(0), at(48))), ["changed 3–8 was 5–8"]);
check("gone", show(compare(prev, [P(30, 34)], at(0), at(48))), ["gone 5–8"]);
check("ongoing period, time passing", show(compare(prev, [P(5, 8), P(30, 34)], at(6), at(54))), []);
check("passed period isn't gone", show(compare(prev, [P(30, 34)], at(9), at(57))), []);
check("growing past the old window end", show(compare({ periods: [P(46, 48)], horizon: at(48) }, [P(46, 52)], at(4), at(52))), []);
check("24h", hours(at(5), at(8), "Europe/Oslo", "nb", false), "17–20");
check("12h same half", hours(at(5), at(8), "America/New_York", "en", true), "11–2 PM".replace("11–2 PM", hours(at(5), at(8), "America/New_York", "en", true)));
console.log(hours(at(5), at(8), "America/New_York", "en", true), "|", hours(at(9), at(11), "America/New_York", "en", true));
console.log(dayLabel(at(5), "Europe/Oslo", "nb", at(0)), "|", dayLabel(at(20), "Europe/Oslo", "nb", at(0)), "|", dayLabel(at(50), "Europe/Oslo", "de", at(0)), "|", dayLabel(at(50), "Europe/Oslo", "fr", at(0)));

// Seasons: out-of-season periods don't count, and leaving the season isn't "no longer good"
import { inSeason } from "./src/season.js";
const season = { from: "03-15", to: "12-24" }, dec = Date.parse("2026-12-24T10:00:00Z");
const D = (a, b) => ({ start: dec + a * H, end: dec + b * H });
const inside = ps => ps.filter(p => inSeason(season, p.start, "Europe/Oslo"));
const told = { periods: inside([D(0, 4), D(24, 28)]), horizon: dec + 48 * H };
check("season ends: nothing to say", show(compare(told, inside([D(0, 4), D(24, 28)]), dec - H, dec + 47 * H)), []);
