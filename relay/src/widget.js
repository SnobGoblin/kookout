// The app's widget: which of the phone's spots are good, and when. The widget sends its spots (position and rules,
// like /analyse; no names or ids) about once an hour and gets back each spot's good periods, judged by the same rules
// as the app and notifications (rules.js). Nothing is stored. The widget picks and orders the spots itself.
//
//   POST /widget  {spots: [{lat, lon, alt?, tz, wind?|surf?|powder?, weekend?}], units?, waveUnit?, country?}
//     -> {spots: [{periods: [{start, end, lo?, hi?, wave?}]} | {error}]}   (same order as asked)
//
// A period's lo and hi are the lowest mean wind and highest gust in it (m/s, as MET gives them; the app rounds them
// in its own units), wave the highest wave (m) for surf spots. Powder spots get their powder days as periods.

import { goodPeriods } from "./notify.js";

const MAX_SPOTS = 30;
const HOUR = 3600e3;

export async function handleWidget(request, env, ctx, reply, analyseSpot) {
  if (request.method !== "POST") return reply({ error: "not found" }, 404);
  const text = await request.text();
  if (text.length > 100_000) return reply({ error: "too large" }, 413);
  let b; try { b = JSON.parse(text); } catch { return reply({ error: "JSON required" }, 400); }
  if (!Array.isArray(b?.spots) || b.spots.length > MAX_SPOTS) return reply({ error: `spots: a list of at most ${MAX_SPOTS}` }, 400);
  if (!b.spots.every(s => Number.isFinite(s?.lat) && Number.isFinite(s?.lon) && (s.wind || s.surf || s.powder)))
    return reply({ error: "each spot needs lat, lon and a wind, surf or powder rule" }, 400);
  const units = b.units === "kn" ? "kn" : "ms", waveUnit = b.waveUnit === "ft" ? "ft" : "m";
  const country = /^[A-Z]{2}$/.test(b.country ?? "") ? b.country : undefined;

  const spots = await Promise.all(b.spots.map(async spot => {
    try {
      const f = await analyseSpot({ ...spot }, units, waveUnit, env, ctx, country);
      return { periods: widgetPeriods(spot, f, Date.now()) };
    } catch (e) {
      return { error: String(e.message ?? e) };
    }
  }));
  return reply({ spots });
}

// The good periods that haven't ended, with the wind (and waves) in them; for powder spots, the powder days.
export function widgetPeriods(spot, f, now) {
  const rows = f.rows.map(r => ({ ...r, t: Date.parse(r.time) }));
  const round1 = x => Math.round(x * 10) / 10;
  return goodPeriods(spot, f).filter(p => p.end > now).map(p => {
    const inside = rows.filter(r => r.t >= p.start && r.t + r.hours * HOUR <= p.end);
    const out = { start: new Date(p.start).toISOString(), end: new Date(p.end).toISOString() };
    if (spot.powder && !spot.wind && !spot.surf) return out;
    if (inside.length) {
      out.lo = round1(Math.min(...inside.map(r => r.wind)));
      out.hi = round1(Math.max(...inside.map(r => r.gust ?? r.wind)));
      const waves = inside.map(r => r.wave).filter(Number.isFinite);
      if (spot.surf && waves.length) out.wave = round1(Math.max(...waves));
    }
    return out;
  });
}
