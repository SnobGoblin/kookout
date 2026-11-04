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

// ---- Digests and several spots in one notification (plan) ----
const { plan } = _test;
const Z = "Europe/Oslo", dev = { tz: Z, window_hours: 120, lang: "en", h12: 0 };
const L = s => Date.parse(s + "+01:00"); // Oslo local time in November
const spot = (id, name) => ({ id, name, wind: {} });
const M = spot("movik", "Møvik"), K = spot("larkollen", "Larkollen"), B = spot("brattesto", "Brattestø"), T = spot("torkild", "Torkild");
const fri = (a, b) => ({ start: L(`2026-11-06T${a}:00`), end: L(`2026-11-06T${b}:00`) });
const thu = (a, b) => ({ start: L(`2026-11-05T${a}:00`), end: L(`2026-11-05T${b}:00`) });
const empty = now => ({ periods: [], horizon: now + 120 * H });
const run = (now, old, list) => plan(dev, list.map(([s, periods]) => ({ spot: s, zone: Z, periods })), old, now);
const text = r => r.payload ? `${r.payload.aps.alert.title} | ${r.payload.aps.alert.body}` : null;

let now = L("2026-11-05T18:07"), old = { movik: empty(now), larkollen: empty(now), brattesto: empty(now) };
let r = run(now, old, [[M, [fri("14", "18")]], [K, [fri("14", "18")]], [B, [fri("14", "20")]]]);
check("2a: three spots, one notification", text(r), "Good tomorrow | 14–18: Møvik, Larkollen\n14–20: Brattestø");
check("2a: opens the list (no single spot)", [r.payload.spot, r.payload.spots], [undefined, ["movik", "larkollen", "brattesto"]]);

// 4.1: changes arriving at 13, 14 and 16 wait and go out together at 18
let state = { movik: empty(L("2026-11-05T12:07")), larkollen: empty(L("2026-11-05T12:07")), brattesto: empty(L("2026-11-05T12:07")) };
const steps = [["13", [[B, [fri("14", "20")]], [M, []], [K, []]]], ["14", [[B, [fri("14", "20")]], [M, [fri("14", "18")]], [K, []]]],
               ["16", [[B, [fri("14", "20")]], [M, [fri("14", "18")]], [K, [fri("14", "18")]]]], ["18", [[B, [fri("14", "20")]], [M, [fri("14", "18")]], [K, [fri("14", "18")]]]]];
const sentAt = [];
for (const [h, list] of steps) { const x = run(L(`2026-11-05T${h}:07`), state, list); if (x.payload) sentAt.push(`${h}: ${text(x)}`); state = x.sent; }
check("4.1: one notification at the 18:00 digest", sentAt, ["18: Good tomorrow | 14–18: Møvik, Larkollen\n14–20: Brattestø"]);

// 4.2.3: flapping between digests says nothing
state = { movik: { periods: [fri("14", "18")], horizon: L("2026-11-10T12:00") } };
const flaps = [];
for (const [h, p] of [["13", []], ["14", []], ["15", [fri("14", "18")]], ["18", [fri("14", "18")]]]) {
  const x = run(L(`2026-11-05T${h}:07`), state, [[M, p]]); if (x.payload) flaps.push(h); state = x.sent;
}
check("4.2.3: gone and back between digests: nothing", flaps, []);

// 4.2.1: near news (within 12 h) goes out at once, not waiting for a digest
now = L("2026-11-05T10:07");
r = run(now, { torkild: { periods: [thu("14", "18")], horizon: now + 100 * H } }, [[T, []]]);
check("4.2.1: today's session gone, sent at once", [text(r), r.payload?.aps.sound], ["Torkild | No longer good today 14–18", "gong.caf"]);

// near sent now, far held for the digest, in the same spot
now = L("2026-11-05T10:07");
r = run(now, { torkild: { periods: [thu("14", "18")], horizon: now + 100 * H } }, [[T, [fri("14", "18")]]]);
check("near sent, far held", text(r), "Torkild | No longer good today 14–18");
const x2 = run(L("2026-11-05T12:07"), r.sent, [[T, [fri("14", "18")]]]);
check("held one comes at 12:00", text(x2), "Torkild | Good tomorrow 14–18");
check("and isn't repeated", text(run(L("2026-11-05T13:07"), x2.sent, [[T, [fri("14", "18")]]])), null);

// Night: nothing, then at 07 (a digest) everything
now = L("2026-11-06T03:07");
r = run(now, { torkild: { periods: [fri("14", "18")], horizon: now + 100 * H } }, [[T, []]]);
check("night: nothing", text(r), null);
check("07: sent", text(run(L("2026-11-06T07:07"), r.sent, [[T, []]])), "Torkild | No longer good today 14–18");

// A failed push keeps the old state, so it is tried again
now = L("2026-11-05T18:07");
r = run(now, { movik: empty(now), torkild: empty(now) }, [[M, [fri("14", "18")]], [T, [thu("20", "23")]]]);
check("different news: one notification, one line each", text(r), "Kookout | Good today 20–23: Torkild\nGood tomorrow 14–18: Møvik");
check("failed push keeps old state", JSON.stringify(r.kept.movik.periods), "[]");

// Many lines: the rest as "+N more"
now = L("2026-11-05T18:07");
const many = ["a", "b", "c", "d", "e"].map((id, i) => [spot(id, id.toUpperCase()), [{ start: L(`2026-11-${String(6 + i).padStart(2, "0")}T10:00`), end: L(`2026-11-${String(6 + i).padStart(2, "0")}T12:00`) }]]);
r = run(now, Object.fromEntries(many.map(([s]) => [s.id, empty(now)])), many);
check("+N more", text(r).split("\n").at(-1), "+2 more");
console.log(text(r));

// Seasons: out-of-season periods don't count, and leaving the season isn't "no longer good"
import { inSeason } from "./src/season.js";
const season = { from: "03-15", to: "12-24" }, dec = Date.parse("2026-12-24T10:00:00Z");
const D = (a, b) => ({ start: dec + a * H, end: dec + b * H });
const inside = ps => ps.filter(p => inSeason(season, p.start, "Europe/Oslo"));
const told = { periods: inside([D(0, 4), D(24, 28)]), horizon: dec + 48 * H };
check("season ends: nothing to say", show(compare(told, inside([D(0, 4), D(24, 28)]), dec - H, dec + 47 * H)), []);
// Through plan(): a spot told about 25 Dec, then given a season ending 24 Dec, says nothing (no "gone")
const S = { ...spot("s", "Seasonal"), season };
now = Date.parse("2026-12-24T08:07:00+01:00");
r = run(now, { s: { periods: [D(0, 4), D(24, 28)], horizon: now + 120 * H } }, [[S, [D(0, 4), D(24, 28)]]]);
check("plan: out-of-season period drops out quietly", [text(r), r.sent.s.periods.length], [null, 1]);
r = run(now, { s: { periods: [], horizon: now + 120 * H } }, [[S, [D(0, 4), D(24, 28)]]]);
check("plan: only the in-season period is news", text(r), "Seasonal | Good today 11–15");
