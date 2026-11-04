// Notifications. The app tells the relay which spots a phone wants notifications for (with their rules and
// the phone's settings). Every hour the relay works out those spots, compares the good periods inside the
// phone's time window (e.g. the next 48 hours) with what it last told the phone, and sends a notification
// through Apple's push service (APNs) when:
//   - good conditions come into the window (new forecast, or the window moving forward), or
//   - good conditions in the window change (start or end moved by 2+ hours, or no longer good).
// Changes within the next 12 hours are sent at once. Changes further ahead wait for a digest at 07, 12 or 18 on the
// phone's clock, compared with what the phone was last told, so a forecast that flips back and forth in between says
// nothing, and changes that arrive in different hours go out together.
// All changes in one run go into one notification; spots with the same news (same kind, day, overlapping times) share
// a line: "14–18: Møvik, Larkollen".
// Only good conditions inside the spot's season count (season.js); leaving the season isn't "no longer good".
// Nothing is sent between 22 and 07 on the phone's clock: the changes wait until the morning.
//
//   PUT    /devices/<id>       {token, sandbox, lang, country, units, waveUnit, h12, tz, windowHours, spots}
//                              (a spot may set its own windowHours, e.g. weekend spots looking further ahead,
//                              and a season {from: "MM-DD", to: "MM-DD"}; none: all year)
//   DELETE /devices/<id>       stop all notifications for this phone
//   POST   /devices/<id>/test  send a test notification

import { dayKey, hourOf } from "../../rules.js";
import { cleanSeason, inSeason } from "./season.js";

const HOUR = 3600e3;
const LANGS = ["en", "nb", "sv", "da", "de", "fr", "es"];
const MAX_SPOTS = 30;
const NEAR = 12 * HOUR;            // changes starting sooner than this are sent at once
const DIGEST_HOURS = [7, 12, 18];  // on the phone's clock: when changes further ahead are sent
const MAX_LINES = 4;               // in a notification for several spots, then "+2 more"
const PARALLEL = 6;   // phones checked at the same time in the hourly run
// Sounds in the app: a wind swoosh for good news, a kung-fu gong when good conditions are gone (brand/).
const SOUND = "kookout.caf", BAD_NEWS_SOUND = "gong.caf";

// The texts, in the app's languages ({when}: e.g. "Thu 15–18", {was}: what it said before).
const TEXT = {
  en: { more: "+{n} more", new: "Good {when}", changed: "Now good {when} (was {was})", gone: "No longer good {when}",
        powder: "Powder {when}", powderGone: "No more powder {when}",
        test: "Notifications are on. Kookout will tell you when your spots look good." },
  nb: { more: "+{n} til", new: "Bra {when}", changed: "Nå bra {when} (var {was})", gone: "Ikke lenger bra {when}",
        powder: "Pudder {when}", powderGone: "Ikke lenger pudder {when}",
        test: "Varsler er på. Kookout sier fra når spotene dine ser bra ut." },
  sv: { more: "+{n} till", new: "Bra {when}", changed: "Nu bra {when} (var {was})", gone: "Inte längre bra {when}",
        powder: "Puder {when}", powderGone: "Inte längre puder {when}",
        test: "Notiser är på. Kookout säger till när dina spots ser bra ut." },
  da: { more: "+{n} mere", new: "Godt {when}", changed: "Nu godt {when} (var {was})", gone: "Ikke længere godt {when}",
        powder: "Pulver {when}", powderGone: "Ikke længere pulver {when}",
        test: "Notifikationer er slået til. Kookout siger til, når dine spots ser gode ud." },
  de: { more: "+{n} weitere", new: "{when} gut", changed: "Jetzt gut {when} (vorher {was})", gone: "Nicht mehr gut {when}",
        powder: "Powder {when}", powderGone: "Kein Powder mehr {when}",
        test: "Mitteilungen sind an. Kookout sagt dir, wenn deine Spots gut aussehen." },
  fr: { more: "+{n} autres", new: "Bon {when}", changed: "Bon maintenant {when} (avant {was})", gone: "Plus bon {when}",
        powder: "Poudreuse {when}", powderGone: "Plus de poudreuse {when}",
        test: "Les notifications sont activées. Kookout vous préviendra quand vos spots seront bons." },
  es: { more: "+{n} más", new: "Bueno {when}", changed: "Ahora bueno {when} (antes {was})", gone: "Ya no es bueno {when}",
        powder: "Nieve polvo {when}", powderGone: "Ya no hay nieve polvo {when}",
        test: "Las notificaciones están activadas. Kookout te avisará cuando tus spots estén buenos." },
};

// ---- The app's requests ---------------------------------------------------------------------------

export async function handleDevices(request, env, url, reply) {
  const [, , id, action] = url.pathname.split("/");
  if (!/^[0-9a-f-]{36}$/i.test(id ?? "")) return reply({ error: "device id required" }, 400);

  if (request.method === "DELETE" && !action) {
    await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(id).run();
    return reply({ ok: true });
  }

  if (request.method === "POST" && action === "test") {
    const device = await env.DB.prepare("SELECT * FROM devices WHERE id = ?").bind(id).first();
    if (!device) return reply({ error: "unknown device" }, 404);
    if (!env.APNS_KEY) return reply({ error: "push isn't set up on the relay yet (APNS_KEY)" }, 503);
    const result = await push(env, device, { aps: { alert: { title: "Kookout", body: TEXT[device.lang].test }, sound: SOUND } });
    return reply({ result }, result === "sent" ? 200 : 502);
  }

  if (request.method === "PUT" && !action) {
    const text = await request.text();
    if (text.length > 100_000) return reply({ error: "too large" }, 413);
    let b; try { b = JSON.parse(text); } catch { return reply({ error: "JSON required" }, 400); }
    const device = cleanDevice(b);
    if (typeof device === "string") return reply({ error: device }, 400);
    if (!device.spots.length) {
      await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(id).run();
      return reply({ ok: true });
    }
    // Keep what we last told the phone (state), so changing a setting doesn't repeat old notifications.
    await env.DB.prepare(`INSERT INTO devices (id, token, sandbox, lang, country, units, wave_unit, h12, tz, window_hours, spots, updated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET token = excluded.token, sandbox = excluded.sandbox, lang = excluded.lang,
          country = excluded.country,
          units = excluded.units, wave_unit = excluded.wave_unit, h12 = excluded.h12, tz = excluded.tz,
          window_hours = excluded.window_hours, spots = excluded.spots, updated = excluded.updated`)
      .bind(id, device.token, device.sandbox, device.lang, device.country, device.units, device.waveUnit, device.h12, device.tz,
            device.windowHours, JSON.stringify(device.spots), new Date().toISOString()).run();
    return reply({ ok: true });
  }

  return reply({ error: "not found" }, 404);
}

// The device as sent by the app, checked; or an error message.
function cleanDevice(b) {
  if (!/^[0-9a-f]{64,200}$/i.test(b?.token ?? "")) return "token required";
  if (!validZone(b.tz)) return "tz required";
  if (!Array.isArray(b.spots) || b.spots.length > MAX_SPOTS) return `spots: a list of at most ${MAX_SPOTS}`;
  const spots = [];
  for (const s of b.spots) {
    if (typeof s?.id !== "string" || s.id.length > 64 || typeof s.name !== "string" ||
        !Number.isFinite(s.lat) || !Number.isFinite(s.lon) || !(s.wind || s.surf || s.powder)) return "spot with id, name, lat, lon and a rule required";
    spots.push({ id: s.id, name: s.name.slice(0, 80), lat: s.lat, lon: s.lon, alt: Number.isFinite(s.alt) ? s.alt : undefined,
                 tz: validZone(s.tz) ? s.tz : undefined, wind: s.wind ?? undefined, surf: s.surf ?? undefined, powder: s.powder ?? undefined,
                 weekend: s.weekend === true || undefined, season: cleanSeason(s.season) ?? undefined,
                 windowHours: Number.isFinite(s.windowHours) ? Math.min(240, Math.max(1, Math.round(s.windowHours))) : undefined });
  }
  return {
    token: b.token.toLowerCase(), sandbox: b.sandbox ? 1 : 0, lang: LANGS.includes(b.lang) ? b.lang : "en",
    country: /^[A-Z]{2}$/.test(b.country ?? "") ? b.country : null,
    units: b.units === "kn" ? "kn" : "ms", waveUnit: b.waveUnit === "ft" ? "ft" : "m", h12: b.h12 ? 1 : 0, tz: b.tz,
    windowHours: Math.min(168, Math.max(1, Math.round(Number(b.windowHours) || 48))), spots,
  };
}

function validZone(tz) {
  if (typeof tz !== "string") return false;
  try { new Intl.DateTimeFormat("en", { timeZone: tz }); return true; } catch { return false; }
}

// ---- Every hour --------------------------------------------------------------------------------------

export async function notifyAll(env, analyseSpot) {
  if (!env.APNS_KEY) { console.log("Notifications: APNS_KEY isn't set, nothing sent"); return; }
  const { results } = await env.DB.prepare("SELECT * FROM devices").all();
  // Phones with the same spot and rules share one forecast.
  const forecasts = new Map();
  const forecast = (spot, units, waveUnit, country) => {
    const key = JSON.stringify([spot.lat, spot.lon, spot.alt, spot.wind, spot.surf, spot.powder, spot.weekend, units, waveUnit,
                                spot.weekend ? country : null]);
    if (!forecasts.has(key)) forecasts.set(key, analyseSpot({ ...spot }, units, waveUnit, env, { waitUntil() {} }, country)
      .catch(e => { console.log("Forecast failed:", spot.name, e.message); return null; }));
    return forecasts.get(key);
  };
  // Several phones at a time, so the run stays well inside Cloudflare's 15 minutes as phones are added. (Cloudflare
  // keeps at most 6 connections open per run and queues the rest, so more than this gains little.)
  const queue = [...results];
  let sent = 0;
  const worker = async () => {
    for (let device; (device = queue.shift()); ) {
      try { if (await notifyDevice(device, env, forecast)) sent++; }
      catch (e) { console.log("Notifications failed for a device:", e.message); }
    }
  };
  const started = Date.now();
  await Promise.all(Array.from({ length: PARALLEL }, worker));
  console.log(`Notifications: ${results.length} phones, ${sent} sent, ${forecasts.size} forecasts, ${Math.round((Date.now() - started) / 1000)} s`);
}

async function notifyDevice(device, env, forecast) {
  const spots = JSON.parse(device.spots), old = JSON.parse(device.state || "{}");
  const items = [];
  for (const spot of spots) {
    const f = await forecast(spot, device.units, device.wave_unit, device.country);
    items.push({ spot, zone: f?.tz, periods: f ? goodPeriods(spot, f) : null });
  }
  const run = plan(device, items, old, Date.now());
  let state = run.sent;
  if (run.payload) {
    const result = await push(env, device, run.payload);
    if (result === "gone") { // the app was deleted or the token is no longer valid
      await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device.id).run();
      return;
    }
    if (result !== "sent") state = run.kept; // try again next hour
  }
  const json = JSON.stringify(state);
  if (json !== device.state) await env.DB.prepare("UPDATE devices SET state = ? WHERE id = ?").bind(json, device.id).run();
  return state === run.sent && !!run.payload; // true when a notification went out
}

// One run for one phone, without sending anything: the notification (or null), the state to keep if it is sent,
// and the state to keep if it isn't. items: [{spot, zone, periods}] (periods null when the forecast failed).
function plan(device, items, old, now) {
  const hour = hourOf(new Date(now), device.tz);
  const quiet = hour >= 22 || hour < 7, digest = DIGEST_HOURS.includes(hour);
  const sent = {}, kept = {}, out = [];
  for (const { spot, zone, periods: all } of items) {
    if (!all) { if (old[spot.id]) sent[spot.id] = kept[spot.id] = old[spot.id]; continue; }
    const horizon = now + (spot.windowHours ?? device.window_hours) * HOUR;
    // Out of season: as if it weren't good, and what we told before quietly drops out (no "no longer good")
    const seasonal = p => inSeason(spot.season, p.start, zone);
    const prev = old[spot.id] && { ...old[spot.id], periods: old[spot.id].periods.filter(seasonal) };
    const periods = all.filter(p => p.end > now && p.start < horizon).filter(seasonal);
    // A spot we haven't seen before (just turned on): remember what's good now without notifying.
    if (!prev) { sent[spot.id] = kept[spot.id] = { periods, horizon }; continue; }
    const events = compare(prev, periods, now, horizon);
    if (!events.length) { sent[spot.id] = kept[spot.id] = samePeriods(prev.periods, periods) ? prev : { periods, horizon }; continue; }
    const near = e => Math.min(e.period.start, e.was?.start ?? Infinity) < now + NEAR;
    const go = quiet ? [] : digest ? events : events.filter(near);
    kept[spot.id] = prev;
    if (!go.length) { sent[spot.id] = prev; continue; } // tell them later
    // Changes further ahead that wait for the digest stay as they were told; the rest is now told.
    sent[spot.id] = go.length === events.length ? { periods, horizon } : { periods: told(prev, go, now), horizon: prev.horizon };
    out.push(...go.map(e => ({ ...e, spot, zone })));
  }
  return { payload: out.length ? render(out, device, now) : null, sent, kept };
}

// What the phone has been told after the given events were sent (the others still as before).
function told(prev, events, now) {
  const dropped = new Set(events.flatMap(e => e.type === "gone" ? [e.period] : e.before ?? []));
  const added = events.filter(e => e.type !== "gone").map(e => e.period);
  return [...prev.periods.filter(p => p.end > now && !dropped.has(p)), ...added].sort((a, b) => a.start - b.start);
}

// The notification for a run's events (from one or more spots).
function render(events, device, now) {
  const t = TEXT[device.lang] ?? TEXT.en;
  events.sort((a, b) => a.period.start - b.period.start || a.period.end - b.period.end);
  const isPowder = e => !!e.spot.powder && !e.spot.wind && !e.spot.surf;
  const day = (time, zone) => dayLabel(time, zone, device.lang, now);
  const span = (p, zone) => hours(p.start, p.end, zone, device.lang, device.h12);
  const when = (p, e) => isPowder(e) ? day(p.start, e.zone) : `${day(p.start, e.zone)} ${span(p, e.zone)}`;
  const template = e => e.type === "new" ? (isPowder(e) ? t.powder : t.new) :
                        e.type === "gone" ? (isPowder(e) ? t.powderGone : t.gone) : t.changed;
  const sound = events[0].type === "gone" ? BAD_NEWS_SOUND : SOUND; // the top line (nearest in time) decides
  const at = Math.round(events[0].period.start / 1000); // seconds since 1970: the app scrolls to the top line's period
  const ids = [...new Set(events.map(e => e.spot.id))];
  const cap = line => line.charAt(0).toLocaleUpperCase(device.lang) + line.slice(1); // German: {when} comes first

  if (ids.length === 1) { // one spot: as before, one line per change
    const spot = events[0].spot;
    const body = events.map(e => template(e).replace("{when}", when(e.period, e)).replace("{was}", e.was ? when(e.was, e) : "")).map(cap).join("\n");
    return { aps: { alert: { title: spot.name, body }, "thread-id": spot.id, sound }, spot: spot.id, at };
  }

  // Several spots: news of the same kind on the same day with overlapping times is one cluster; inside it,
  // spots with exactly the same times share a line.
  const clusters = [];
  for (const e of events) {
    const key = `${e.type} ${isPowder(e)} ${dayKey(new Date(e.period.start), e.zone)}`;
    const c = clusters.findLast(c => c.key === key && e.period.start < c.end);
    if (c) { c.events.push(e); c.end = Math.max(c.end, e.period.end); }
    else clusters.push({ key, end: e.period.end, events: [e] });
  }
  const one = clusters.length === 1;
  const lines = [];
  for (const c of clusters) {
    const groups = new Map();
    for (const e of c.events) {
      const sameDay = e.was && dayKey(new Date(e.was.start), e.zone) === dayKey(new Date(e.period.start), e.zone);
      const was = e.was ? (sameDay && !isPowder(e) ? span(e.was, e.zone) : when(e.was, e)) : "";
      // In a notification about one cluster the day is in the title, so the lines only need the times.
      const label = one ? (isPowder(e) ? "" : e.type === "changed" ? t.changed.replace("{when}", span(e.period, e.zone)).replace("{was}", was)
                                                                    : span(e.period, e.zone))
                        : template(e).replace("{when}", when(e.period, e)).replace("{was}", was);
      if (!groups.has(label)) groups.set(label, []);
      if (!groups.get(label).includes(e.spot.name)) groups.get(label).push(e.spot.name);
    }
    for (const [label, names] of groups) lines.push(label ? `${label}: ${names.join(", ")}` : names.join(", "));
  }
  const first = clusters[0].events[0];
  const headline = (first.type === "gone" ? (isPowder(first) ? t.powderGone : t.gone) : (isPowder(first) ? t.powder : t.new))
    .replace("{when}", day(first.period.start, first.zone));
  const shown = lines.length > MAX_LINES ? [...lines.slice(0, MAX_LINES - 1), t.more.replace("{n}", lines.length - MAX_LINES + 1)] : lines;
  return { aps: { alert: { title: one ? cap(headline) : "Kookout", body: shown.map(cap).join("\n") }, "thread-id": "kookout", sound },
           spots: ids, at };
}

// The good periods as [{start, end}] in ms. Powder: the whole powder day.
export function goodPeriods(spot, f) {
  if (spot.wind || spot.surf) return f.good.map(p => ({ start: Date.parse(p.start), end: Date.parse(p.end) }));
  return f.powderDays.map(day => {
    const rows = f.rows.filter(r => dayKey(new Date(r.time), f.tz) === day);
    return { start: Date.parse(rows[0].time), end: Date.parse(rows.at(-1).time) + rows.at(-1).hours * HOUR };
  }).filter(p => Number.isFinite(p.start));
}

// What changed since we last told the phone: new periods, periods that moved, periods that are gone.
// Only the part of the window both forecasts covered counts as a change; a period growing past the old
// window's end is just coming into view, and a period that has started isn't "changed" by time passing.
function compare(prev, periods, now, horizon) {
  const told = prev.periods.filter(p => p.end > now);
  const cut = Math.min(prev.horizon, horizon);
  const clip = p => ({ start: Math.max(p.start, now), end: Math.min(p.end, cut) });
  const overlaps = (a, b) => a.start < b.end && a.end > b.start;
  const events = [];
  for (const p of periods) {
    const before = told.filter(o => overlaps(o, p));
    if (!before.length) { events.push({ type: "new", period: p }); continue; }
    const was = { start: Math.min(...before.map(o => o.start)), end: Math.max(...before.map(o => o.end)) };
    const a = clip(p), b = clip(was);
    if (Math.abs(a.start - b.start) + Math.abs(a.end - b.end) >= 2 * HOUR) events.push({ type: "changed", period: p, was, before });
  }
  for (const o of told) {
    if (o.start < cut && !periods.some(p => overlaps(o, p))) events.push({ type: "gone", period: o });
  }
  return events.sort((x, y) => x.period.start - y.period.start);
}

const samePeriods = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// "today", "tomorrow" or the weekday ("Thu"), in the phone's language and the spot's time zone.
function dayLabel(t, zone, lang, now) {
  const day = dayKey(new Date(t), zone);
  const rel = n => new Intl.RelativeTimeFormat(lang, { numeric: "auto" }).format(n, "day");
  if (day === dayKey(new Date(now), zone)) return rel(0);
  if (day === dayKey(new Date(now + 24 * HOUR), zone)) return rel(1);
  return new Intl.DateTimeFormat(lang, { weekday: "short", timeZone: zone }).format(t);
}

// "15–18", or with a 12-hour clock "3–6 PM" / "11 AM–2 PM", like the app.
function hours(start, end, zone, lang, h12) {
  if (!h12) {
    const f = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hourCycle: "h23", timeZone: zone });
    return `${f.format(start)}–${f.format(end)}`;
  }
  const f = new Intl.DateTimeFormat(lang, { hour: "numeric", hour12: true, timeZone: zone });
  const part = t => { const p = f.formatToParts(t); return { h: p.find(x => x.type === "hour").value, a: p.find(x => x.type === "dayPeriod")?.value ?? "" }; };
  const s = part(start), e = part(end);
  return s.a === e.a ? `${s.h}–${e.h} ${e.a}` : `${s.h} ${s.a}–${e.h} ${e.a}`;
}

// ---- Apple's push service ------------------------------------------------------------------------------

// Apple wants a signed token (JWT, ES256) with each push, made from our .p8 key; it may be reused for up
// to an hour but not made more often than every 20 minutes.
let jwt = null;
async function apnsJwt(env) {
  if (jwt && Date.now() - jwt.made < 40 * 60e3) return jwt.token;
  const der = Uint8Array.from(atob(env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const part = obj => b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const body = `${part({ alg: "ES256", kid: env.APNS_KEY_ID })}.${part({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(body));
  jwt = { token: `${body}.${b64url(new Uint8Array(signature))}`, made: Date.now() };
  return jwt.token;
}

// "sent", "gone" (the phone no longer has the app, or the token is wrong) or "failed".
async function push(env, device, payload) {
  const host = device.sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: { authorization: `bearer ${await apnsJwt(env)}`, "apns-topic": env.APNS_TOPIC,
               "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (res.ok) return "sent";
  const reason = (await res.json().catch(() => ({}))).reason;
  console.log("APNs refused a push:", res.status, reason);
  return res.status === 410 || ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(reason) ? "gone" : "failed";
}

// For tests (test-notify.mjs).
export const _test = { compare, hours, dayLabel, plan };
