// Run with: node test-widget.mjs  (checks the widget's answer on a made-up forecast, without the network)
import { analyse } from "../rules.js";
import { handleWidget, widgetPeriods } from "./src/widget.js";
const H = 3600e3, t0 = Date.parse("2026-10-17T00:00:00Z"); // a Saturday
const check = (name, got, want) => console.log(JSON.stringify(got) === JSON.stringify(want) ? "ok  " : "FAIL", name, JSON.stringify(got));

// MET's forecast, 48 hours: wind from the south, strong from 10 to 15 UTC on both days; snow on Sunday.
const met = { properties: { timeseries: Array.from({ length: 48 }, (_, h) => {
  const strong = h % 24 >= 10 && h % 24 < 15;
  return { time: new Date(t0 + h * H).toISOString(), data: {
    instant: { details: { air_temperature: h >= 24 ? -3 : 5, wind_speed: strong ? 8 + (h % 24 - 10) : 3,
                          wind_speed_of_gust: strong ? 12 + (h % 24 - 10) : 5, wind_from_direction: 180 } },
    next_1_hours: { summary: { symbol_code: "cloudy" }, details: { precipitation_amount: h >= 24 && h < 36 ? 2 : 0 } } } };
}) } };

// What the relay's analyseSpot answers (the same joining of good rows into periods).
function forecast(spot, daysOff) {
  const rows = analyse(spot, met, null, { units: "ms", zone: "UTC", daysOff });
  const good = [];
  for (const r of rows) {
    if (!r.good) continue;
    const start = r.time.getTime(), end = start + r.hours * H, last = good.at(-1);
    if (last && last.end === start) last.end = end; else good.push({ start, end });
  }
  return { tz: "UTC", good: good.map(p => ({ start: new Date(p.start).toISOString(), end: new Date(p.end).toISOString() })),
           powderDays: [...new Set(rows.filter(r => r.powderDay).map(r => r.day))],
           rows: rows.map(r => ({ time: r.time.toISOString(), hours: r.hours, wind: r.wind, gust: r.gust, wave: r.wave })) };
}
const wing = { lat: 59.6, lon: 10.6, tz: "UTC", wind: { min: 5, gust: 9, steady: 6, hours: 2, daylight: false, dirs: ["S"] } };
const hours = ps => ps.map(p => `${(Date.parse(p.start) - t0) / H}–${(Date.parse(p.end) - t0) / H}` + (p.lo != null ? ` ${p.lo}/${p.hi}` : ""));

check("wing: both days, with wind", hours(widgetPeriods(wing, forecast(wing), t0)), ["10–15 8/16", "34–39 8/16"]);
check("wing: the first is over", hours(widgetPeriods(wing, forecast(wing), t0 + 16 * H)), ["34–39 8/16"]);
check("wing: still good during one", hours(widgetPeriods(wing, forecast(wing), t0 + 12 * H)), ["10–15 8/16", "34–39 8/16"]);
check("wrong direction: nothing", widgetPeriods({ ...wing, wind: { ...wing.wind, dirs: ["N"] } }, forecast({ ...wing, wind: { ...wing.wind, dirs: ["N"] } }), t0), []);
const weekend = { ...wing, weekend: true };
check("weekend spot: Sunday isn't a day off here", hours(widgetPeriods(weekend, forecast(weekend, ["2026-10-17"]), t0)), ["10–15 8/16"]);
const powder = { lat: 61, lon: 8, tz: "UTC", powder: { mm: 10, maxTemp: 0, maxWind: 20, days: 1 } };
check("powder: the whole powder day, no wind", hours(widgetPeriods(powder, forecast(powder), t0)), ["24–48"]);

// The endpoint: answers in the same order, an error for a spot that failed, bad requests refused.
const reply = (body, status = 200) => ({ body, status });
const req = body => ({ method: "POST", text: async () => JSON.stringify(body) });
const fake = async spot => { if (spot.lat === 0) throw new Error("MET forecast: 500"); return forecast(spot); };
const answer = await handleWidget(req({ spots: [wing, { ...wing, lat: 0 }] }), {}, {}, reply, fake);
check("endpoint: order and errors", [answer.status, answer.body.spots.length, !!answer.body.spots[0].periods, answer.body.spots[1].error], [200, 2, true, "MET forecast: 500"]);
check("endpoint: a spot without a rule", (await handleWidget(req({ spots: [{ lat: 1, lon: 2 }] }), {}, {}, reply, fake)).status, 400);
check("endpoint: too many spots", (await handleWidget(req({ spots: Array(31).fill(wing) }), {}, {}, reply, fake)).status, 400);
check("endpoint: GET", (await handleWidget({ method: "GET" }, {}, {}, reply, fake)).status, 404);
