// Wingfoil relay: lets the page read live wind observations from MET's Frost API.
// The browser can't call Frost directly (no CORS, and the client ID must stay secret),
// so the page asks this Worker, which asks Frost right away and passes the answer back.
//
//   GET /near?lat=59.43&lon=10.58  -> the nearest stations that measure wind, with their latest reading
//   GET /obs?ids=SN17280,SN17000   -> the latest reading for the given stations

const FROST = "https://frost.met.no";
const ALLOWED_ORIGINS = ["https://sternell.com", "http://localhost:8000", "http://192.168.1.21:8000"];
const WIND = ["wind_speed", "wind_from_direction", "max(wind_speed_of_gust PT10M)", "max(wind_speed_of_gust PT1H)"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    const cors = ALLOWED_ORIGINS.includes(origin) ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {};
    const reply = (body, status = 200) => new Response(JSON.stringify(body), {
      status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...cors } });

    if (!env.FROST_CLIENT_ID) return reply({ error: "FROST_CLIENT_ID is not set" }, 500);
    const frost = path => fetch(FROST + path, {
      headers: { Authorization: "Basic " + btoa(env.FROST_CLIENT_ID + ":") },
      cf: { cacheTtl: 60 }, // stations report every 10–60 min, so one minute of sharing between users is harmless
    });

    try {
      if (url.pathname === "/obs") {
        const ids = (url.searchParams.get("ids") || "").split(",").filter(id => /^SN\d+$/.test(id)).slice(0, 20);
        if (!ids.length) return reply({ error: "ids=SN… required" }, 400);
        return reply({ stations: await latest(frost, ids) });
      }

      if (url.pathname === "/near") {
        const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400); // also catches empty values
        const query = new URLSearchParams({ types: "SensorSystem", geometry: `nearest(POINT(${lon} ${lat}))`,
          nearestmaxcount: "50", fields: "id,name,geometry,distance" });
        const res = await frost(`/sources/v0.jsonld?${query}`);
        if (!res.ok) return reply({ error: `Frost sources: ${res.status}` }, 502);
        const sources = (await res.json()).data ?? [];        const readings = await latest(frost, sources.map(s => s.id));
        const byId = Object.fromEntries(readings.map(r => [r.id, r]));
        const stations = sources
          .filter(s => byId[s.id]) // only stations that actually have a recent wind reading
          .map(s => ({ ...byId[s.id], name: tidy(s.name), km: round(s.distance, 1),
                       lat: s.geometry?.coordinates?.[1], lon: s.geometry?.coordinates?.[0] }));
        return reply({ stations });
      }

      return reply({ error: "Not found. Use /near?lat=&lon= or /obs?ids=" }, 404);
    } catch (err) {
      return reply({ error: String(err) }, 502);
    }
  },
};

// The latest wind reading (within the last 3 hours) for each station.
async function latest(frost, ids) {
  if (!ids.length) return [];
  const res = await frost(`/observations/v0.jsonld?sources=${ids.join(",")}` +
    `&referencetime=latest&maxage=PT3H&elements=${encodeURIComponent(WIND.join(","))}`);
  if (res.status === 404 || res.status === 412) return []; // Frost's way of saying "no data"
  if (!res.ok) throw new Error(`Frost observations: ${res.status}`);
  const out = {};
  for (const item of (await res.json()).data ?? []) {
    const id = item.sourceId.split(":")[0];
    const r = out[id] ??= { id, time: item.referenceTime };
    if (item.referenceTime > r.time) r.time = item.referenceTime;
    for (const o of item.observations) {
      if (o.elementId === "wind_speed") r.wind = o.value;
      if (o.elementId === "wind_from_direction") r.dir = o.value;
      if (o.elementId.startsWith("max(wind_speed_of_gust")) r.gust = Math.max(r.gust ?? 0, o.value);
    }
  }
  return Object.values(out).filter(r => r.wind != null);
}

const round = (n, d) => n == null ? null : Math.round(n * 10 ** d) / 10 ** d;
// Frost names are in capitals ("GULLHOLMEN"); make them read normally ("Gullholmen").
const tidy = s => (s || "").toLowerCase().replace(/(^|[\s\-–(\/])(\p{L})/gu, (m, a, b) => a + b.toUpperCase());
