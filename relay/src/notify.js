// Notifications. The app tells the relay which spots a phone wants notifications for (with their rules and
// the phone's settings). Every hour the relay works out those spots, compares the good periods inside the
// phone's time window (e.g. the next 48 hours) with what it last told the phone, and sends a notification
// through Apple's push service (APNs) when:
//   - good conditions come into the window (new forecast, or the window moving forward), or
//   - good conditions in the window change (start or end moved by 2+ hours, or no longer good).
// Nothing is sent between 22 and 07 on the phone's clock: the changes wait until the morning.
//
//   PUT    /devices/<id>       {token, sandbox, lang, units, waveUnit, h12, tz, windowHours, spots}
//   DELETE /devices/<id>       stop all notifications for this phone
//   POST   /devices/<id>/test  send a test notification

import { dayKey, hourOf } from "../../rules.js";

const HOUR = 3600e3;
const LANGS = ["en", "nb", "sv", "da", "de", "fr", "es"];
const MAX_SPOTS = 30;
const MAX_PUSHES = 5;
const SOUND = "kookout.caf"; // a kung-fu-movie gong, in the app (brand/gong.swift) // per phone per hour, so a big forecast change doesn't flood it

// The texts, in the app's languages ({when}: e.g. "Thu 15–18", {was}: what it said before).
const TEXT = {
  en: { new: "Good {when}", changed: "Now good {when} (was {was})", gone: "No longer good {when}",
        powder: "Powder {when}", powderGone: "No more powder {when}",
        test: "Notifications are on. Kookout will tell you when your spots look good." },
  nb: { new: "Bra {when}", changed: "Nå bra {when} (var {was})", gone: "Ikke lenger bra {when}",
        powder: "Pudder {when}", powderGone: "Ikke lenger pudder {when}",
        test: "Varsler er på. Kookout sier fra når spotene dine ser bra ut." },
  sv: { new: "Bra {when}", changed: "Nu bra {when} (var {was})", gone: "Inte längre bra {when}",
        powder: "Puder {when}", powderGone: "Inte längre puder {when}",
        test: "Notiser är på. Kookout säger till när dina spots ser bra ut." },
  da: { new: "Godt {when}", changed: "Nu godt {when} (var {was})", gone: "Ikke længere godt {when}",
        powder: "Pulver {when}", powderGone: "Ikke længere pulver {when}",
        test: "Notifikationer er slået til. Kookout siger til, når dine spots ser gode ud." },
  de: { new: "Gut {when}", changed: "Jetzt gut {when} (vorher {was})", gone: "Nicht mehr gut {when}",
        powder: "Powder {when}", powderGone: "Kein Powder mehr {when}",
        test: "Mitteilungen sind an. Kookout sagt dir, wenn deine Spots gut aussehen." },
  fr: { new: "Bon {when}", changed: "Bon maintenant {when} (avant {was})", gone: "Plus bon {when}",
        powder: "Poudreuse {when}", powderGone: "Plus de poudreuse {when}",
        test: "Les notifications sont activées. Kookout vous préviendra quand vos spots seront bons." },
  es: { new: "Bueno {when}", changed: "Ahora bueno {when} (antes {was})", gone: "Ya no es bueno {when}",
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
    await env.DB.prepare(`INSERT INTO devices (id, token, sandbox, lang, units, wave_unit, h12, tz, window_hours, spots, updated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET token = excluded.token, sandbox = excluded.sandbox, lang = excluded.lang,
          units = excluded.units, wave_unit = excluded.wave_unit, h12 = excluded.h12, tz = excluded.tz,
          window_hours = excluded.window_hours, spots = excluded.spots, updated = excluded.updated`)
      .bind(id, device.token, device.sandbox, device.lang, device.units, device.waveUnit, device.h12, device.tz,
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
                 tz: validZone(s.tz) ? s.tz : undefined, wind: s.wind ?? undefined, surf: s.surf ?? undefined, powder: s.powder ?? undefined });
  }
  return {
    token: b.token.toLowerCase(), sandbox: b.sandbox ? 1 : 0, lang: LANGS.includes(b.lang) ? b.lang : "en",
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
  const forecast = (spot, units, waveUnit) => {
    const key = JSON.stringify([spot.lat, spot.lon, spot.alt, spot.wind, spot.surf, spot.powder, units, waveUnit]);
    if (!forecasts.has(key)) forecasts.set(key, analyseSpot({ ...spot }, units, waveUnit, env, { waitUntil() {} })
      .catch(e => { console.log("Forecast failed:", spot.name, e.message); return null; }));
    return forecasts.get(key);
  };
  for (const device of results) {
    try { await notifyDevice(device, env, forecast); }
    catch (e) { console.log("Notifications failed for a device:", e.message); }
  }
}

async function notifyDevice(device, env, forecast) {
  const now = Date.now(), horizon = now + device.window_hours * HOUR;
  const spots = JSON.parse(device.spots), old = JSON.parse(device.state || "{}");
  const quiet = (h => h >= 22 || h < 7)(hourOf(new Date(now), device.tz));
  const state = {};
  let pushes = 0;

  for (const spot of spots) {
    const prev = old[spot.id];
    const f = await forecast(spot, device.units, device.wave_unit);
    if (!f) { if (prev) state[spot.id] = prev; continue; }
    const periods = goodPeriods(spot, f).filter(p => p.end > now && p.start < horizon);
    // A spot we haven't seen before (just turned on): remember what's good now without notifying.
    if (!prev) { state[spot.id] = { periods, horizon }; continue; }

    const events = compare(prev, periods, now, horizon);
    if (!events.length) { state[spot.id] = samePeriods(prev.periods, periods) ? prev : { periods, horizon }; continue; }
    if (quiet || pushes >= MAX_PUSHES) { state[spot.id] = prev; continue; } // tell them later

    const zone = f.tz;
    const t = TEXT[device.lang] ?? TEXT.en;
    const powder = !!spot.powder && !spot.wind && !spot.surf;
    const when = p => powder ? dayLabel(p.start, zone, device.lang, now)
                             : `${dayLabel(p.start, zone, device.lang, now)} ${hours(p.start, p.end, zone, device.lang, device.h12)}`;
    const lines = events.map(e =>
      e.type === "new" ? (powder ? t.powder : t.new).replace("{when}", when(e.period)) :
      e.type === "gone" ? (powder ? t.powderGone : t.gone).replace("{when}", when(e.period)) :
      t.changed.replace("{when}", when(e.period)).replace("{was}", when(e.was)));
    const result = await push(env, device, {
      aps: { alert: { title: spot.name, body: lines.join("\n") }, sound: SOUND, "thread-id": spot.id },
      spot: spot.id,
    });
    if (result === "gone") { // the app was deleted or the token is no longer valid
      await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device.id).run();
      return;
    }
    pushes++;
    state[spot.id] = result === "sent" ? { periods, horizon } : prev; // try again next hour if it failed
  }

  const json = JSON.stringify(state);
  if (json !== device.state) await env.DB.prepare("UPDATE devices SET state = ? WHERE id = ?").bind(json, device.id).run();
}

// The good periods as [{start, end}] in ms. Powder: the whole powder day.
function goodPeriods(spot, f) {
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
    if (Math.abs(a.start - b.start) + Math.abs(a.end - b.end) >= 2 * HOUR) events.push({ type: "changed", period: p, was });
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
export const _test = { compare, hours, dayLabel };
