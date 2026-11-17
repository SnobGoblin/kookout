// Kookout relay: lets the page read live wind observations from official weather services.
// The browser can't call MET's Frost API directly (no CORS, and the client ID must stay secret),
// so the page asks this Worker, which asks the services right away and passes the answer back.
//
//   GET /near?lat=59.43&lon=10.58  -> official stations within 50 km that measure wind, with their latest
//                                     reading (MET's Frost; Kystverket's coastal stations (Kystvær);
//                                     NOAA's buoys and coastal stations (NDBC);
//                                     in the US also NOAA's National Weather Service),
//                                     plus Holfuy stations within 50 km (number, name, distance)
//   GET /obs?ids=SN17280,KV:8925059,NWS:KDLS,NDBC:FTPC1  -> the latest reading for the given stations
//   POST /analyse  {spot, units?, waveUnit?, waves?} -> the spot's forecast with the good hours marked, using the same
//                                     rules as the web page (rules.js). For the app and notifications.
//   GET /tz?lat=21.28&lon=-157.83   -> the place's time zone, e.g. {"tz":"Pacific/Honolulu"} (worked out locally)
//   PUT/DELETE /devices/<id>, POST /devices/<id>/test  -> notifications for a phone (see notify.js)
//   PUT /following, GET /spots, POST /spots/<id>, …    -> community spots: following, editing, the log (see community.js)
//   POST /auth/apple, GET/PUT/DELETE /me              -> accounts, Sign in with Apple (see auth.js)
//   POST /reports                                      -> report a spot or a change (see reports.js)
//   POST /founders                                     -> a founding user's number in line (see founders.js)
//   POST /widget  {spots, units?, waveUnit?, country?}  -> the good periods of the widget's spots (see widget.js)
//   GET /stats                      -> {riders, spots}: riders active in the last 30 days and the spots they follow,
//                                     for the counter on kookout.no. Public (any origin), cached an hour in KV.
//   GET /waves?lat=58.80&lon=5.55   -> wave forecast (total height in m, period, direction) about a week ahead:
//                                     MET's Oceanforecast in Scandinavian waters, NOAA WaveWatch III elsewhere
//
// All wind speeds are returned in m/s.

import tzlookup from "@photostructure/tz-lookup";
import { analyse } from "../../rules.js"; // the same rules as the web page
import { handleDevices, notifyAll } from "./notify.js";
import { handleCommunity } from "./community.js";
import { handleAuth } from "./auth.js";
import { handleReports } from "./reports.js";
import { handleFounders } from "./founders.js";
import { handleWidget } from "./widget.js";
import catalogue from "../../ios/Kookout/Catalogue.json"; // the app's built-in spots

const FROST = "https://frost.met.no";
const ALLOWED_ORIGINS = ["https://kookout.no", "https://www.kookout.no", "https://sternell.com",
                         "http://localhost:8000", "http://192.168.1.21:8000"];
const MAX_KM = 50; // further away than this, a station says little about the wind at the spot
// NWS and MET ask every app to identify itself with a way to contact us.
const NWS_HEADERS = { "User-Agent": "KookoutRelay/1.0 (kookout.no, hi@kookout.no)", Accept: "application/geo+json" };
const WIND = ["wind_speed", "wind_from_direction", "max(wind_speed_of_gust PT10M)", "max(wind_speed_of_gust PT1H)"];

export default {
  // Every 3 hours (see wrangler.toml): refresh the stored NOAA wave forecasts. Every hour: notifications.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(event.cron === "7 * * * *" ? notifyAll(env, analyseSpot)
      : Promise.all([refreshStoredWaves(env), refreshGfsWaves(env)]));
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    const cors = ALLOWED_ORIGINS.includes(origin) ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {};
    const reply = (body, status = 200) => new Response(JSON.stringify(body), {
      status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...cors } });

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...cors,
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE", "Access-Control-Allow-Headers": "Content-Type, Authorization", "Access-Control-Max-Age": "86400" } });
    if (!env.FROST_CLIENT_ID) return reply({ error: "FROST_CLIENT_ID is not set" }, 500);
    const frost = path => fetch(FROST + path, {
      headers: { Authorization: "Basic " + btoa(env.FROST_CLIENT_ID + ":") },
      cf: { cacheTtl: 60 }, // stations report every 10–60 min, so one minute of sharing between users is harmless
    });

    try {
      if (url.pathname === "/stats" && request.method === "GET") return stats(env, ctx);
      if (url.pathname === "/obs") {
        const ids = (url.searchParams.get("ids") || "").split(",").slice(0, 20);
        const frostIds = ids.filter(id => /^SN\d+$/.test(id));
        const nwsIds = ids.filter(id => /^NWS:[A-Z0-9]{3,6}$/.test(id));
        const ndbcIds = ids.filter(id => /^NDBC:[A-Z0-9]{4,7}$/.test(id)).map(id => id.slice(5));
        const kvIds = ids.filter(id => /^KV:\d+$/.test(id));
        if (!frostIds.length && !nwsIds.length && !ndbcIds.length && !kvIds.length)
          return reply({ error: "ids=SN…, KV:…, NWS:… or NDBC:… required" }, 400);
        const [a, b, c, d] = await Promise.all([latest(frost, frostIds),
          Promise.all(nwsIds.map(id => nwsLatest(id.slice(4)))),
          ndbcIds.length ? ndbcReadings().then(all => all.filter(r => ndbcIds.includes(r.code))) : [],
          kvIds.length ? kvReadings().then(all => all.filter(r => kvIds.includes(r.id))) : []]);
        return reply({ stations: [...a, ...b.filter(Boolean), ...c.map(({ code, ...r }) => r), ...d] });
      }

      if (url.pathname === "/near") {
        const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400); // also catches empty values
        const query = new URLSearchParams({ types: "SensorSystem", geometry: `nearest(POINT(${lon} ${lat}))`,
          nearestmaxcount: "50", fields: "id,name,geometry,distance" });
        const res = await frost(`/sources/v0.jsonld?${query}`);
        if (!res.ok) return reply({ error: `Frost sources: ${res.status}` }, 502);
        // Frost is mostly Norwegian: outside Norway the "nearest" stations can be thousands of km away.
        const sources = ((await res.json()).data ?? []).filter(s => s.distance <= MAX_KM);
        const readings = await latest(frost, sources.map(s => s.id));
        const byId = Object.fromEntries(readings.map(r => [r.id, r]));
        const stations = sources
          .filter(s => byId[s.id]) // only stations that actually have a recent wind reading
          .map(s => ({ ...byId[s.id], name: tidy(s.name), km: round(s.distance, 1),
                       lat: s.geometry?.coordinates?.[1], lon: s.geometry?.coordinates?.[0] }));
        const [us, buoys, coastal, holfuy] = await Promise.all(
          [nwsNear(lat, lon), ndbcNear(lat, lon), kvNear(lat, lon), holfuyNear(lat, lon)]);
        // NWS also lists some of NOAA's coastal stations; keep the NDBC copy, which has gusts.
        const buoyCodes = new Set(buoys.map(b => b.id.slice(5)));
        const all = [...stations, ...coastal, ...us.filter(u => !buoyCodes.has(u.id.slice(4))), ...buoys]
          .sort((a, b) => a.km - b.km);
        return reply({ stations: all, holfuy });
      }

      if (url.pathname.startsWith("/devices/")) return handleDevices(request, env, url, reply);
      if (url.pathname === "/auth/apple" || url.pathname === "/me") return handleAuth(request, env, url, reply);
      if (url.pathname === "/reports") return handleReports(request, env, url, reply);
      if (url.pathname === "/founders") return handleFounders(request, env, url, reply);
      if (url.pathname === "/widget") return handleWidget(request, env, ctx, reply, analyseSpot);
      if (/^\/(shared|spots|following|edits)(\/|$)/.test(url.pathname)) return handleCommunity(request, env, url, reply);

      if (url.pathname === "/analyse" && request.method === "POST") {
        const body = await request.json().catch(() => null);
        const spot = body?.spot;
        if (!spot || !Number.isFinite(spot.lat) || !Number.isFinite(spot.lon) || !(spot.wind || spot.surf || spot.powder))
          return reply({ error: "spot with lat, lon and a wind, surf or powder rule required" }, 400);
        return reply(await analyseSpot(spot, body.units, body.waveUnit, env, ctx, body.country, { waves: body.waves === true }));
      }

      if (url.pathname === "/tz") {
        const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400);
        return reply({ tz: tzlookup(lat, lon) });
      }

      if (url.pathname === "/waves") {
        const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400);
        // MET has the better wave heights in Scandinavia but no wave period, so we borrow NOAA's period there.
        return reply(await surfWaves(lat, lon, env, ctx) ?? { source: null, points: [] });
      }

      return reply({ error: "Not found. Use /near, /obs or /waves" }, 404);
    } catch (err) {
      return reply({ error: String(err) }, 502);
    }
  },
};

// ---- NOAA's National Weather Service (US only) -------------------------------------------
// Rough boxes around the US (mainland, Alaska, Hawaii, Puerto Rico), so we don't ask NWS about Norway.
const inUS = (lat, lon) =>
  (lat > 24 && lat < 50 && lon > -125 && lon < -66) || (lat > 51 && lat < 72 && lon > -180 && lon < -129) ||
  (lat > 18 && lat < 23 && lon > -161 && lon < -154) || (lat > 17.5 && lat < 18.6 && lon > -67.5 && lon < -65);

const nws = path => fetch("https://api.weather.gov" + path, { headers: NWS_HEADERS, cf: { cacheTtl: 60 } });

async function nwsNear(lat, lon) {
  if (!inUS(lat, lon)) return [];
  try {
    const point = await nws(`/points/${lat.toFixed(4)},${lon.toFixed(4)}`);
    if (!point.ok) return [];
    const stationsUrl = (await point.json()).properties?.observationStations;
    if (!stationsUrl) return [];
    const res = await fetch(stationsUrl + "?limit=12", { headers: NWS_HEADERS, cf: { cacheTtl: 3600 } });
    if (!res.ok) return [];
    const near = ((await res.json()).features ?? [])
      .map(f => ({ code: f.properties.stationIdentifier,
                   name: f.properties.name === f.properties.name.toUpperCase() ? tidy(f.properties.name) : f.properties.name,
                   lat: f.geometry.coordinates[1], lon: f.geometry.coordinates[0] }))
      .map(s => ({ ...s, km: round(distanceKm(lat, lon, s.lat, s.lon), 1) }))
      .filter(s => s.km <= MAX_KM);
    const readings = await Promise.all(near.map(s => nwsLatest(s.code)));
    return near.map((s, i) => readings[i] && { ...readings[i], name: s.name, km: s.km, lat: s.lat, lon: s.lon })
      .filter(Boolean);
  } catch {
    return []; // NWS being unavailable shouldn't break the other sources
  }
}

// The latest reading from one NWS station, if it's from the last 3 hours and has wind. NWS reports km/h.
async function nwsLatest(code) {
  try {
    const res = await nws(`/stations/${code}/observations/latest`);
    if (!res.ok) return null;
    const p = (await res.json()).properties;
    if (!p?.timestamp || Date.now() - Date.parse(p.timestamp) > 3 * 3600e3) return null;
    const ms = v => v?.value == null ? undefined : round(v.unitCode?.endsWith("km_h-1") ? v.value / 3.6 : v.value, 1);
    const r = { id: "NWS:" + code, time: p.timestamp, wind: ms(p.windSpeed), gust: ms(p.windGust),
                dir: p.windDirection?.value ?? undefined };
    return r.wind == null ? null : r;
  } catch {
    return null;
  }
}

// ---- Kystverket (Norwegian Coastal Administration): Kystvær coastal stations --------------
// Open API (NLOD licence), no key needed. Readings arrive every few minutes, in m/s.
// We only take Kystverket's own stations; the "external" ones are MET's, which we already get from Frost.
const KV = "https://api.coastal-weather.kystverket.cloud/v1";
const nearNorway = (lat, lon) => lat > 55 && lat < 82 && lon > -10 && lon < 35;

async function kvReadings() {
  try {
    const [stations, data] = await Promise.all([
      fetch(KV + "/stations", { cf: { cacheTtl: 86400 } }).then(r => r.json()),
      fetch(KV + "/stations/measurements/nca", { cf: { cacheTtl: 60 } }).then(r => r.json()),
    ]);
    const info = Object.fromEntries(stations.map(s => [s.id, s]));
    const out = [];
    for (const { stationId, measurements } of data.stationMeasurements ?? []) {
      const st = info[stationId];
      const m = Object.fromEntries((measurements ?? []).map(x => [x.type, x]));
      if (!st || m["wind-speed"]?.value == null) continue;
      const time = m["wind-speed"].timestamp;
      if (Date.now() - Date.parse(time) > 3 * 3600e3) continue;
      out.push({ id: "KV:" + stationId, name: st.name + " (Kystverket)", time, lat: st.latitude, lon: st.longitude,
                 wind: m["wind-speed"].value, gust: m["gust-speed"]?.value, dir: m["wind-direction"]?.value });
    }
    return out;
  } catch {
    return []; // Kystverket being unavailable shouldn't break the other sources
  }
}

async function kvNear(lat, lon) {
  if (!nearNorway(lat, lon)) return [];
  return (await kvReadings())
    .map(r => ({ ...r, km: round(distanceKm(lat, lon, r.lat, r.lon), 1) }))
    .filter(r => r.km <= MAX_KM);
}

// ---- Working out a spot (the forecast, waves, time zone and the shared rules) -------------
// waves: also fetch waves for a wind spot, just to show them (the app asks, from 1.2, only where wave height is
// switched on). Surf spots always get them. The same sources as surf: MET in Scandinavian waters, NOAA elsewhere.
// NOAA's 0.5° grid answers from open sea up to ~50 km away, which would put ocean swell on a flat-water lagoon; the
// per-spot switch (off by default, the community's vote) keeps it off where that's wrong. A wind spot isn't judged
// on waves, so it waits at most 2.5 s for NOAA: a new place gets its waves from the next request on.
async function analyseSpot(spot, units = "ms", waveUnit = "m", env, ctx, country, { waves: wantWaves = false } = {}) {
  const tz = spot.tz ?? tzlookup(spot.lat, spot.lon);
  const query = `lat=${spot.lat.toFixed(4)}&lon=${spot.lon.toFixed(4)}` + (spot.alt != null ? `&altitude=${Math.round(spot.alt)}` : "");
  const [forecastRes, waves, daysOff] = await Promise.all([
    fetch(`https://api.met.no/weatherapi/locationforecast/2.0/complete?${query}`, { headers: NWS_HEADERS, cf: { cacheTtl: 600 } }),
    spot.surf ? surfWaves(spot.lat, spot.lon, env, ctx)
      : wantWaves && spot.wind ? surfWaves(spot.lat, spot.lon, env, ctx, 2500).catch(() => null) : null,
    spot.weekend ? daysOffFor(country, env).catch(() => undefined) : undefined,
  ]);
  if (!forecastRes.ok) throw new Error(`MET forecast: ${forecastRes.status}`);
  const rows = analyse(spot, await forecastRes.json(), waves, { units, waveUnit, zone: tz, daysOff });

  // The good periods, joined up: e.g. [{ start: "…T10:00Z", end: "…T14:00Z" }]
  const periods = [];
  for (const r of rows) {
    if (!r.good) continue;
    const start = r.time.getTime(), end = start + r.hours * 3600e3, last = periods.at(-1);
    if (last && last.end === start) last.end = end; else periods.push({ start, end });
  }
  const iso = t => new Date(t).toISOString();
  return {
    tz, units, waveUnit,
    good: periods.map(p => ({ start: iso(p.start), end: iso(p.end) })),
    powderDays: [...new Set(rows.filter(r => r.powderDay).map(r => r.day))],
    rows: rows.map(r => ({ time: r.time.toISOString(), hours: r.hours, symbol: r.symbol, temp: r.temp, rain: r.rain,
      wind: r.wind, gust: r.gust, dir: r.dir, deg: r.deg, wave: r.wave, period: r.period,
      daylight: r.daylight, good: !!r.good, snow: !!r.snow })),
  };
}

// Days off for weekend spots: Saturdays, Sundays and the public holidays of the person's country (from Nager.Date,
// date.nager.at, free and open; kept for a week), for the next two weeks. Without a country: just weekends.
export async function daysOffFor(country, env) {
  const days = [];
  for (let i = 0; i < 15; i++) {
    const d = new Date(Date.now() + i * 86400e3);
    if ([0, 6].includes(d.getUTCDay())) days.push(d.toISOString().slice(0, 10));
  }
  if (!/^[A-Z]{2}$/.test(country ?? "")) return days;
  const years = [...new Set([0, 15].map(i => new Date(Date.now() + i * 86400e3).getUTCFullYear()))];
  for (const year of years) {
    const key = `holidays:${country}:${year}`;
    let list = await env.WAVES.get(key, "json");
    if (!list) {
      const res = await fetch(`https://date.nager.at/api/v3/PublicHolidays/${year}/${country}`, { signal: AbortSignal.timeout(5000) });
      list = res.ok ? (await res.json()).filter(h => h.global !== false).map(h => h.date) : [];
      await env.WAVES.put(key, JSON.stringify(list), { expirationTtl: 7 * 86400 });
    }
    days.push(...list);
  }
  return [...new Set(days)];
}

// The same waves as /waves: MET in Scandinavia (with NOAA's period), NOAA elsewhere.
// maxWait: how long to wait for NOAA where MET has no waves (8 s for surf spots, which are judged on them).
async function surfWaves(lat, lon, env, ctx, maxWait = 8000) {
  // Where NOAA's 0.5° grid has nothing (the Mediterranean …): GFS-Wave 0.25°, as stored by the 3-hourly job
  const noaaFetch = storedNoaaWaves(lat, lon, env, ctx).catch(() => null)
    .then(d => d ?? storedGfsWaves(lat, lon, env).catch(() => null));
  const met = await metWaves(lat, lon);
  // Where MET has the heights, NOAA only adds the period: don't keep the user waiting for NOAA's slow first
  // fetch of a new place (it finishes in the background and is used from the next request on).
  // Elsewhere NOAA is all we have, but its server is sometimes down: show the forecast without waves after 8 s
  // rather than keep the app spinning. Either way the fetch finishes in the background for the next request.
  ctx.waitUntil(noaaFetch);
  const noaa = await Promise.race([noaaFetch, new Promise(resolve => setTimeout(() => resolve(null), met ? 2500 : maxWait))]);
  if (met && noaa) {
    const periods = noaa.points.map(pt => ({ t: Date.parse(pt.time), period: pt.period }));
    for (const pt of met.points) {
      const t = Date.parse(pt.time);
      const near = periods.reduce((b, x) => !b || Math.abs(x.t - t) < Math.abs(b.t - t) ? x : b, null);
      if (near && Math.abs(near.t - t) <= 3 * 3600e3) pt.period = near.period;
    }
  }
  return met ?? noaa;
}

// ---- Wave forecasts ------------------------------------------------------------------------
// Wave forecasts only update every few hours, so Cloudflare may keep a copy for an hour.

// MET's Oceanforecast: detailed, but only covers Scandinavian waters (it answers 422 elsewhere).
async function metWaves(lat, lon) {
  const res = await fetch(`https://api.met.no/weatherapi/oceanforecast/2.0/complete?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}`,
    { headers: NWS_HEADERS, cf: { cacheTtl: 3600 } });
  if (!res.ok) return null;
  const points = ((await res.json()).properties?.timeseries ?? [])
    .map(t => ({ time: t.time, height: t.data.instant.details.sea_surface_wave_height,
                 dir: t.data.instant.details.sea_surface_wave_from_direction }))
    .filter(p => p.height != null);
  return points.length ? { source: "MET", points } : null;
}

// NOAA answers are kept in KV per 0.5° cell. Fresh for 3 hours; older ones are still served
// (the forecast reaches a week ahead) while a new copy is fetched in the background.
const cellKey = (lat, lon) => `noaa:${(Math.round(lat * 2) / 2).toFixed(1)}:${(Math.round(lon * 2) / 2).toFixed(1)}`;
const FRESH_MS = 3 * 3600e3;

async function storedNoaaWaves(lat, lon, env, ctx) {
  const key = cellKey(lat, lon);
  const stored = await env.WAVES.get(key, "json");
  const upcoming = d => ({ ...d, points: d.points.filter(pt => Date.parse(pt.time) > Date.now() - 3600e3) });
  if (stored && !stored.data) return null; // NOAA failed for this cell within the last hour: don't wait again
  if (stored && Date.now() - stored.fetched < FRESH_MS) return upcoming(stored.data);
  if (stored) { ctx.waitUntil(fetchAndStore(lat, lon, env)); return upcoming(stored.data); }
  return await fetchAndStore(lat, lon, env); // first time for this cell: we have to wait
}

async function fetchAndStore(lat, lon, env) {
  const data = await noaaWaves(lat, lon);
  if (data) await env.WAVES.put(cellKey(lat, lon), JSON.stringify({ fetched: Date.now(), lat, lon, data }),
                                { expirationTtl: 7 * 86400 }); // cells nobody asks about disappear after a week
  else if (!(await env.WAVES.get(cellKey(lat, lon)))) // remember a failure for an hour (NOAA's server is sometimes down)
    await env.WAVES.put(cellKey(lat, lon), JSON.stringify({ fetched: Date.now(), lat, lon, data: null }), { expirationTtl: 3600 });
  return data;
}

async function refreshStoredWaves(env) {
  const { keys } = await env.WAVES.list({ prefix: "noaa:" });
  // The app's built-in surf spots are fetched ahead of time, so they are quick the first time too.
  const stored = new Set(keys.map(k => k.name));
  const missing = catalogue.filter(s => s.sport === "surf" && !stored.has(cellKey(s.lat, s.lon)));
  for (const s of missing.slice(0, 4)) await fetchAndStore(s.lat, s.lon, env).catch(() => null);
  for (const { name } of keys.slice(0, 10)) { // a few per run keeps us inside Cloudflare's free limits
    const stored = await env.WAVES.get(name, "json");
    if (stored?.data && Date.now() - stored.fetched > FRESH_MS - 600e3) await fetchAndStore(stored.lat, stored.lon, env);
  }
}

// NOAA WaveWatch III: global, 0.5° grid (~50 km). Cells along the coast often count as land,
// so we use the nearest cell at sea within about 1°.
// The same NOAA model is published by several data servers. PacIOOS (University of Hawai'i, part of NOAA's
// coastal observing system) is fast; NOAA's own CoastWatch server is the backup, as it is often slow.
const WW3_SERVERS = [
  "https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ww3_global.json",
  "https://coastwatch.pfeg.noaa.gov/erddap/griddap/NWW3_Global_Best.json",
];
// Ask each server in turn (with a time limit), and don't let Cloudflare keep a copy of a bad answer.
async function erddap(query) {
  for (const server of WW3_SERVERS) {
    try {
      const res = await fetch(`${server}?${encodeURI(query)}`, { headers: NWS_HEADERS, signal: AbortSignal.timeout(15000) });
      if (res.ok) return (await res.json()).table;
    } catch {}
  }
  return null;
}
async function noaaWaves(lat, lon) {
  try { return await noaaWavesRaw(lat, lon); } catch { return null; }
}

// ---- Enclosed seas: NOAA GFS-Wave 0.25° -------------------------------------------------------------------
// NOAA's 0.5° grid leaves out enclosed seas (the whole Mediterranean). There we use NOAA's newer GFS-Wave on a 0.25°
// grid (~25 km), from the IOOS data server (OPeNDAP, answered as text; NOAA itself only publishes GRIB files).
// That server is slow per time step (~0.3 s) but not per area, so a request never waits for it: a spot asking for
// waves goes on a list (one KV key per spot, `gfsw-want:…`, gone after 14 days without a request; one shared list
// would lose spots, as KV doesn't promise that a read sees a write made seconds before), and the 3-hourly job fetches one box per region, every 3 hours for a week ahead, and stores
// each spot's series in KV. A new spot there gets its waves within 3 hours; they're renewed every 6.
const GFSW = "https://eds.ioos.us/thredds/dodsC/ioos/gfswave/global/Best";
const GFSW_H = "Significant_height_of_combined_wind_waves_and_swell_surface", GFSW_P = "Primary_wave_mean_period_surface";
const GFSW_WANT = "gfsw-want:";                // + the spot's key; metadata { lat, lon, asked }
const GFSW_FRESH_MS = 6 * 3600e3;
const gfswKey = (lat, lon) => `gfsw:${lat.toFixed(2)}:${lon.toFixed(2)}`;

export async function storedGfsWaves(lat, lon, env) {
  [lat, lon] = [Math.round(lat * 100) / 100, Math.round(lon * 100) / 100];
  const key = gfswKey(lat, lon);
  const [stored, want] = await Promise.all([env.WAVES.get(key, "json"), env.WAVES.getWithMetadata(GFSW_WANT + key)]);
  if (!want?.metadata || Date.now() - want.metadata.asked > 86400e3) // on the list, renewed at most once a day
    await env.WAVES.put(GFSW_WANT + key, "", { metadata: { lat, lon, asked: Date.now() }, expirationTtl: 14 * 86400 });
  if (!stored?.data) return null;
  return { ...stored.data, points: stored.data.points.filter(pt => Date.parse(pt.time) > Date.now() - 3600e3) };
}

async function opendap(query) {
  const res = await fetch(`${GFSW}${query}`, { headers: NWS_HEADERS, signal: AbortSignal.timeout(120000) });
  if (!res.ok) throw new Error(`GFS-Wave: ${res.status}`);
  return res.text();
}
// "-----\nName.Name[3][1][1]\n[0][0], 0.81, …" → { Name: [0.81, …], time: […] } (values in [time][lat][lon] order)
export function parseAscii(text) {
  const out = {};
  for (const block of (text.split(/^-{10,}$/m)[1] ?? "").split(/\n\s*\n/)) {
    const [head, ...lines] = block.trim().split("\n");
    const name = head?.match(/^(\w+)(?:\.(\w+))?\[/);
    if (!name) continue;
    const key = name[2] && name[2] !== name[1] ? `${name[1]}.${name[2]}` : name[1];
    out[key] = lines.join(",").split(",").map(v => v.trim()).filter(v => v && !v.startsWith("["))
      .map(v => v === "NaN" ? null : Number(v));
  }
  return out;
}

// The 3-hourly job: fetch the wanted spots that are due, one box per region.
export async function refreshGfsWaves(env) {
  const { keys } = await env.WAVES.list({ prefix: GFSW_WANT });
  const now = Date.now(), due = [];
  for (const { name, metadata } of keys) {
    if (!metadata) continue;
    const key = name.slice(GFSW_WANT.length), stored = await env.WAVES.get(key, "json");
    if (!stored || now - stored.fetched > GFSW_FRESH_MS - 600e3) due.push({ key, lat: metadata.lat, lon: metadata.lon });
  }
  for (const box of gfswBoxes(due)) await fetchGfsBox(box, env).catch(e => console.log("GFS-Wave:", e.message));
}

// Spots grouped into boxes of at most 15° × 30° (the Mediterranean is two or three).
export function gfswBoxes(spots) {
  const boxes = [];
  for (const s of spots) {
    const fits = b => Math.max(b.n, s.lat) - Math.min(b.s, s.lat) <= 15 && Math.max(b.e, s.lon) - Math.min(b.w, s.lon) <= 30;
    const b = boxes.find(fits);
    if (b) Object.assign(b, { n: Math.max(b.n, s.lat), s: Math.min(b.s, s.lat), e: Math.max(b.e, s.lon), w: Math.min(b.w, s.lon) }).spots.push(s);
    else boxes.push({ n: s.lat, s: s.lat, e: s.lon, w: s.lon, spots: [s] });
  }
  return boxes;
}

async function fetchGfsBox(box, env) {
  // Time: "hours since" a start that moves as the archive rolls on, so read it each time.
  const since = (await opendap(".das")).match(/\btime \{[^}]*?units "Hour since ([^"]+)"/)?.[1];
  const hours = parseAscii(await opendap(".ascii?time")).time ?? [];
  if (!since || !hours.length) return;
  const t0 = Date.parse(since), at = i => t0 + hours[i] * 3600e3;
  // Every 3 hours from now to a week ahead, as index runs (hourly near the start, 3-hourly further on)
  const picked = [];
  for (let i = 0; i < hours.length; i++) {
    if (at(i) < Date.now() - 3 * 3600e3 || at(i) > Date.now() + 7.5 * 86400e3) continue;
    if (!picked.length || hours[i] - hours[picked.at(-1)] >= 3) picked.push(i);
  }
  const runs = [];
  for (const i of picked) {
    const r = runs.at(-1);
    if (r && (r.n === 1 || i - r.last === r.step)) { if (r.n === 1) r.step = i - r.last; r.last = i; r.n++; }
    else runs.push({ first: i, last: i, step: 1, n: 1 });
  }
  // The box with a 0.75° margin (to find a cell at sea); split where it crosses 0° (the data runs 0–360°)
  const rows = [Math.max(0, Math.floor((90 - box.n - 0.75) * 4)), Math.min(720, Math.ceil((90 - box.s + 0.75) * 4))];
  const [w, e] = [box.w - 0.75, box.e + 0.75];
  const cols = w < 0 && e >= 0 ? [[Math.floor((360 + w) * 4), 1439], [0, Math.ceil(e * 4)]]
             : [[Math.floor((((w % 360) + 360) % 360) * 4), Math.ceil((((e % 360) + 360) % 360) * 4)]];
  const series = box.spots.map(() => ({ cell: null, h: [], p: [] }));
  for (const [c0, c1] of cols) {
    const width = c1 - c0 + 1, height = rows[1] - rows[0] + 1, slab = `[${rows[0]}:1:${rows[1]}][${c0}:1:${c1}]`;
    const grids = [];
    for (const r of runs) {
      const t = `[${r.first}:${r.step}:${r.last}]`;
      const d = parseAscii(await opendap(`.ascii?${GFSW_H}${t}${slab},${GFSW_P}${t}${slab}`));
      for (let k = 0; k < r.n; k++) grids.push({ h: d[GFSW_H]?.slice(k * width * height, (k + 1) * width * height) ?? [],
                                                  p: d[GFSW_P]?.slice(k * width * height, (k + 1) * width * height) ?? [] });
    }
    // Each spot: the nearest cell at sea (within 0.75°) in this part of the box
    box.spots.forEach((s, n) => {
      const lon360 = ((s.lon % 360) + 360) % 360, cosLat = Math.cos(s.lat * Math.PI / 180);
      for (let k = 0; k < width * height; k++) {
        if (grids[0]?.h[k] == null) continue;
        const cLat = 90 - (rows[0] + Math.floor(k / width)) / 4, cLon = (c0 + k % width) / 4;
        const dLon = Math.min(Math.abs(cLon - lon360), 360 - Math.abs(cLon - lon360));
        const dist = Math.hypot(cLat - s.lat, dLon * cosLat);
        if (dist <= 0.75 && (!series[n].cell || dist < series[n].cell.dist)) series[n] = {
          cell: { dist, lat: cLat, lon: cLon > 180 ? cLon - 360 : cLon },
          h: grids.map(g => g.h[k]), p: grids.map(g => g.p[k]) };
      }
    });
  }
  const now = Date.now();
  await Promise.all(box.spots.map((s, n) => {
    const { cell, h, p } = series[n];
    const points = cell ? picked.map((i, k) => ({ time: new Date(at(i)).toISOString().replace(".000", ""),
      height: h[k] == null ? null : round(h[k], 2), period: p[k] == null ? null : round(p[k], 1) })).filter(pt => pt.height != null) : [];
    const data = points.length ? { source: "NOAA GFS-Wave", km: round(distanceKm(s.lat, s.lon, cell.lat, cell.lon), 0), points } : null;
    return env.WAVES.put(s.key, JSON.stringify({ fetched: now, lat: s.lat, lon: s.lon, data }), { expirationTtl: 7 * 86400 });
  }));
}
async function noaaWavesRaw(lat, lon) {
  if (Math.abs(lat) > 77) return null;
  {
    const lon360 = ((lon % 360) + 360) % 360;
    const snap = v => Math.round(v * 2) / 2;
    const [la, lo] = [snap(lat), snap(lon360)];
    // Start from the previous whole hour: right after the hour turns, NOAA may not have the new hour yet.
    const now = new Date(Date.now() - 3600e3); now.setUTCMinutes(0, 0, 0);
    const t = now.toISOString().replace(".000", "");
    const box = `Thgt[(${t})][(0.0)][(${la - 1}):(${la + 1})][(${Math.max(0, lo - 1)}):(${Math.min(359.5, lo + 1)})]`;
    const near = await erddap(box);
    if (!near) return null;
    const cells = near.rows.filter(r => r[4] != null);
    if (!cells.length) return null;
    const cosLat = Math.cos(lat * Math.PI / 180);
    const [, , cLat, cLon] = cells.reduce((best, r) =>
      Math.hypot(r[2] - lat, (r[3] - lon360) * cosLat) < Math.hypot(best[2] - lat, (best[3] - lon360) * cosLat) ? r : best);
    const at = `[(${t}):1:(last)][(0.0)][(${cLat})][(${cLon})]`;
    const series = await erddap(`Thgt${at},Tper${at},Tdir${at}`);
    if (!series) return null;
    const { columnNames: c, rows } = series;
    const [iT, iH, iP, iD] = ["time", "Thgt", "Tper", "Tdir"].map(n => c.indexOf(n));
    const points = rows.filter(r => r[iH] != null)
      .map(r => ({ time: r[iT], height: round(r[iH], 2), period: round(r[iP], 1), dir: round(r[iD], 0) }));
    const cellLon = cLon > 180 ? cLon - 360 : cLon;
    return points.length ? { source: "NOAA", km: round(distanceKm(lat, lon, cLat, cellLon), 0), points } : null;
  }
}

// ---- NOAA's National Data Buoy Center: buoys and coastal/harbour stations ------------------
// One small text file holds the latest reading from every station, already in m/s.
async function ndbcReadings() {
  const res = await fetch("https://www.ndbc.noaa.gov/data/latest_obs/latest_obs.txt",
    { headers: NWS_HEADERS, cf: { cacheTtl: 60 } });
  if (!res.ok) return [];
  const out = [];
  for (const line of (await res.text()).split("\n")) {
    if (!line || line.startsWith("#")) continue;
    // STN LAT LON YYYY MM DD hh mm WDIR WSPD GST ...   ("MM" means missing)
    const [code, lat, lon, y, mo, d, h, mi, wdir, wspd, gst] = line.trim().split(/\s+/);
    if (wspd === "MM" || wspd == null) continue;
    const time = new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi));
    if (Date.now() - time > 3 * 3600e3) continue;
    out.push({ code, id: "NDBC:" + code, time: time.toISOString(), lat: +lat, lon: +lon,
               wind: +wspd, gust: gst === "MM" ? undefined : +gst, dir: wdir === "MM" ? undefined : +wdir });
  }
  return out;
}

// Station names, from NOAA's station list (changes rarely, so cached for a day).
async function ndbcNames() {
  try {
    const res = await fetch("https://www.ndbc.noaa.gov/activestations.xml", { headers: NWS_HEADERS, cf: { cacheTtl: 86400 } });
    const names = {};
    for (const m of (await res.text()).matchAll(/<station id="([^"]+)"[^>]*\bname="([^"]*)"/g)) {
      names[m[1].toUpperCase()] = m[2].replace(/^\d+ - /, "").replace(/&amp;/g, "&");
    }
    return names;
  } catch {
    return {};
  }
}

async function ndbcNear(lat, lon) {
  try {
    const near = (await ndbcReadings())
      .map(r => ({ ...r, km: round(distanceKm(lat, lon, r.lat, r.lon), 1) }))
      .filter(r => r.km <= MAX_KM);
    if (!near.length) return [];
    const names = await ndbcNames();
    return near.map(({ code, ...r }) => ({ ...r, name: (names[code] ?? code) + " (NOAA)" }));
  } catch {
    return [];
  }
}

// Holfuy's public station directory. It changes rarely, so Cloudflare keeps a copy for a day.
async function holfuyNear(lat, lon) {
  try {
    const res = await fetch("https://api.holfuy.com/stations/stations.json", { cf: { cacheTtl: 86400 } });
    if (!res.ok) return [];
    const list = (await res.json()).holfuyStationsList ?? [];
    return list
      .filter(s => s.location?.latitude != null && s.location?.longitude != null)
      .map(s => ({ holfuy: s.id, name: (s.name ?? "").trim(), type: s.type,
                   km: round(distanceKm(lat, lon, s.location.latitude, s.location.longitude), 1) }))
      .filter(s => s.km <= MAX_KM)
      .sort((a, b) => a.km - b.km)
      .slice(0, 10);
  } catch {
    return []; // Holfuy being unavailable shouldn't break the MET stations
  }
}

// Distance in km between two points (accurate enough for "how far away is this station").
function distanceKm(lat1, lon1, lat2, lon2) {
  const r = Math.PI / 180;
  const x = (lon2 - lon1) * r * Math.cos((lat1 + lat2) / 2 * r), y = (lat2 - lat1) * r;
  return 6371 * Math.hypot(x, y);
}

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

// Two counts for the web page, nothing per rider or per spot. KV keeps the answer an hour, so page loads don't reach D1.
async function stats(env, ctx) {
  const headers = { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600", "Access-Control-Allow-Origin": "*" };
  let body = await env.WAVES.get("stats");
  if (!body) {
    const row = await env.DB.prepare(`SELECT COUNT(DISTINCT follower) AS riders, COUNT(DISTINCT spot_id) AS spots
      FROM followers WHERE last_active > datetime('now', '-30 days')`).first();
    body = JSON.stringify({ riders: row?.riders ?? 0, spots: row?.spots ?? 0 });
    ctx.waitUntil(env.WAVES.put("stats", body, { expirationTtl: 3600 }));
  }
  return new Response(body, { headers });
}
