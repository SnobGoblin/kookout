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
//   POST /analyse  {spot, units?, waveUnit?} -> the spot's forecast with the good hours marked, using the same
//                                     rules as the web page (rules.js). For the app and notifications.
//   GET /tz?lat=21.28&lon=-157.83   -> the place's time zone, e.g. {"tz":"Pacific/Honolulu"} (worked out locally)
//   PUT/DELETE /devices/<id>, POST /devices/<id>/test  -> notifications for a phone (see notify.js)
//   GET /waves?lat=58.80&lon=5.55   -> wave forecast (total height in m, period, direction) about a week ahead:
//                                     MET's Oceanforecast in Scandinavian waters, NOAA WaveWatch III elsewhere
//
// All wind speeds are returned in m/s.

import tzlookup from "@photostructure/tz-lookup";
import { analyse } from "../../rules.js"; // the same rules as the web page
import { handleDevices, notifyAll } from "./notify.js";

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
    ctx.waitUntil(event.cron === "7 * * * *" ? notifyAll(env, analyseSpot) : refreshStoredWaves(env));
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    const cors = ALLOWED_ORIGINS.includes(origin) ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {};
    const reply = (body, status = 200) => new Response(JSON.stringify(body), {
      status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...cors } });

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...cors,
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400" } });
    if (!env.FROST_CLIENT_ID) return reply({ error: "FROST_CLIENT_ID is not set" }, 500);
    const frost = path => fetch(FROST + path, {
      headers: { Authorization: "Basic " + btoa(env.FROST_CLIENT_ID + ":") },
      cf: { cacheTtl: 60 }, // stations report every 10–60 min, so one minute of sharing between users is harmless
    });

    try {
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

      if (url.pathname === "/analyse" && request.method === "POST") {
        const body = await request.json().catch(() => null);
        const spot = body?.spot;
        if (!spot || !Number.isFinite(spot.lat) || !Number.isFinite(spot.lon) || !(spot.wind || spot.surf || spot.powder))
          return reply({ error: "spot with lat, lon and a wind, surf or powder rule required" }, 400);
        return reply(await analyseSpot(spot, body.units, body.waveUnit, env, ctx));
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
async function analyseSpot(spot, units = "ms", waveUnit = "m", env, ctx) {
  const tz = spot.tz ?? tzlookup(spot.lat, spot.lon);
  const query = `lat=${spot.lat.toFixed(4)}&lon=${spot.lon.toFixed(4)}` + (spot.alt != null ? `&altitude=${Math.round(spot.alt)}` : "");
  const [forecastRes, waves] = await Promise.all([
    fetch(`https://api.met.no/weatherapi/locationforecast/2.0/complete?${query}`, { headers: NWS_HEADERS, cf: { cacheTtl: 600 } }),
    spot.surf ? surfWaves(spot.lat, spot.lon, env, ctx) : null,
  ]);
  if (!forecastRes.ok) throw new Error(`MET forecast: ${forecastRes.status}`);
  const rows = analyse(spot, await forecastRes.json(), waves, { units, waveUnit, zone: tz });

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

// The same waves as /waves: MET in Scandinavia (with NOAA's period), NOAA elsewhere.
async function surfWaves(lat, lon, env, ctx) {
  const [met, noaa] = await Promise.all([metWaves(lat, lon), storedNoaaWaves(lat, lon, env, ctx)]);
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
  if (stored && Date.now() - stored.fetched < FRESH_MS) return upcoming(stored.data);
  if (stored) { ctx.waitUntil(fetchAndStore(lat, lon, env)); return upcoming(stored.data); }
  return await fetchAndStore(lat, lon, env); // first time for this cell: we have to wait
}

async function fetchAndStore(lat, lon, env) {
  const data = await noaaWaves(lat, lon);
  if (data) await env.WAVES.put(cellKey(lat, lon), JSON.stringify({ fetched: Date.now(), lat, lon, data }),
                                { expirationTtl: 7 * 86400 }); // cells nobody asks about disappear after a week
  return data;
}

async function refreshStoredWaves(env) {
  const { keys } = await env.WAVES.list({ prefix: "noaa:" });
  for (const { name } of keys.slice(0, 10)) { // a few per run keeps us inside Cloudflare's free limits
    const stored = await env.WAVES.get(name, "json");
    if (stored && Date.now() - stored.fetched > FRESH_MS - 600e3) await fetchAndStore(stored.lat, stored.lon, env);
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
