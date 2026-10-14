// Community spots. A spot someone shares (or one of the app's built-in spots) belongs to everyone who follows it:
//   - name and position are facts: anyone signed in can fix them, every change is logged, and any change can be undone;
//   - the rules (wind directions, limits) are preferences: each follower has their own, and the spot's community
//     version is the majority's (a direction counts if more than half include it; limits are the median).
// A phone follows the spots in its list that are community spots. Followers are known by a hash of a random key the
// app makes (not their account), so following works without signing in. See schema.sql for the tables.
//
//   PUT  /following            {key, spots: [{id, rule|null}]}  the community spots this phone has (rule: its own
//                              version, or null when it follows the community's). Returns their community versions.
//   GET  /spots?lat&lon        community spots within ~300 km (not the built-in ones, which the app has itself)
//   POST /spots/<id>           {name?, lat?, lon?}  fix the name or position for everyone (signed in)
//   GET  /spots/<id>/history   the log
//   POST /edits/<n>/undo       undo a change (signed in)
//   PUT/DELETE /shared/<id>, GET /shared   the same for apps from before community spots (build 1-4)

import { currentUser, sha256 } from "./auth.js";

const SPORTS = ["wing", "surf", "powder"];
const MAX_MOVE_KM = 2;          // further than this it's a different spot
const VOTES_FROM = 3;           // the majority decides the rules from this many active followers
const ACTIVE_DAYS = 180;        // followers who haven't opened the app for this long stop counting
const MAX_EDITS_PER_DAY = 50;   // per person

export async function handleCommunity(request, env, url, reply) {
  const parts = url.pathname.split("/").filter(Boolean); // e.g. ["spots", "<id>", "history"]
  if (parts[0] === "following" && request.method === "PUT") return following(request, env, reply);
  if (parts[0] === "spots" && !parts[1] && request.method === "GET") return near(env, url, reply, false);
  if (parts[0] === "spots" && parts[1] && !parts[2] && request.method === "POST") return edit(request, env, parts[1], reply);
  if (parts[0] === "spots" && parts[2] === "history" && request.method === "GET") return history(env, parts[1], reply);
  if (parts[0] === "edits" && parts[2] === "undo" && request.method === "POST") return undo(request, env, Number(parts[1]), reply);
  if (parts[0] === "shared") return legacyShared(request, env, parts[1], url, reply);
  return reply({ error: "not found" }, 404);
}

// ---- Following ---------------------------------------------------------------------------------------------

async function following(request, env, reply) {
  const b = await readJSON(request, 200_000);
  if (typeof b?.key !== "string" || b.key.length < 32 || b.key.length > 200) return reply({ error: "key required" }, 400);
  if (!Array.isArray(b.spots) || b.spots.length > 300) return reply({ error: "spots: a list" }, 400);
  const follower = await sha256(b.key);
  const now = new Date().toISOString();
  const wanted = new Map(b.spots.filter(s => typeof s?.id === "string" && s.id.length <= 64)
                                 .map(s => [s.id, s.rule && typeof s.rule === "object" ? JSON.stringify(s.rule) : null]));
  const ids = [...wanted.keys()];
  const known = ids.length ? (await env.DB.prepare(`SELECT * FROM spots WHERE status = 'active' AND id IN (${ids.map(() => "?").join(",")})`)
    .bind(...ids).all()).results : [];
  const before = (await env.DB.prepare("SELECT spot_id, rule FROM followers WHERE follower = ?").bind(follower).all()).results;
  const had = new Map(before.map(f => [f.spot_id, f.rule]));

  const writes = [], touched = new Set();
  for (const spot of known) {
    const rule = wanted.get(spot.id);
    if (!had.has(spot.id) || had.get(spot.id) !== rule) touched.add(spot.id);
    writes.push(env.DB.prepare(`INSERT INTO followers (spot_id, follower, rule, last_active) VALUES (?, ?, ?, ?)
        ON CONFLICT(spot_id, follower) DO UPDATE SET rule = excluded.rule, last_active = excluded.last_active`)
      .bind(spot.id, follower, rule, now));
  }
  for (const f of before) if (!known.some(s => s.id === f.spot_id)) { // no longer in their list: unfollowed
    writes.push(env.DB.prepare("DELETE FROM followers WHERE spot_id = ? AND follower = ?").bind(f.spot_id, follower));
    touched.add(f.spot_id);
  }
  if (writes.length) await env.DB.batch(writes);
  for (const id of touched) await settle(env, id);

  const fresh = ids.length ? (await env.DB.prepare(`SELECT * FROM spots WHERE status = 'active' AND id IN (${ids.map(() => "?").join(",")})`)
    .bind(...ids).all()).results : [];
  return reply({ spots: await Promise.all(fresh.map(s => describe(env, s))) });
}

/// After followers change: recount the community rules, and retire a spot nobody follows any more.
async function settle(env, id) {
  const spot = await env.DB.prepare("SELECT * FROM spots WHERE id = ?").bind(id).first();
  if (!spot) return;
  const since = new Date(Date.now() - ACTIVE_DAYS * 86400e3).toISOString();
  const { results } = await env.DB.prepare("SELECT rule FROM followers WHERE spot_id = ? AND last_active >= ?").bind(id, since).all();
  if (!results.length && !spot.catalogue) {
    await env.DB.prepare("UPDATE spots SET status = 'gone', updated = ? WHERE id = ?").bind(new Date().toISOString(), id).run();
    return;
  }
  if (results.length < VOTES_FROM) return; // small spots keep the version they have
  const current = JSON.parse(spot.rule);
  const votes = results.map(r => r.rule ? JSON.parse(r.rule) : current); // no own version: agrees with the current one
  const majority = majorityRule(votes, current);
  if (JSON.stringify(majority) !== JSON.stringify(current))
    await env.DB.prepare("UPDATE spots SET rule = ?, updated = ? WHERE id = ?").bind(JSON.stringify(majority), new Date().toISOString(), id).run();
}

/// The majority's rule: compass points included by more than half, the median of each number, the majority's yes/no,
/// and settings only some have (the sunny-day limits, powder days) when more than half have them. Exported for tests.
export function majorityRule(votes, current) {
  const POINTS = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"];
  const half = n => n * 2 > votes.length;
  const median = xs => { xs = xs.slice().sort((a, b) => a - b); const m = xs.length >> 1;
                         return xs.length % 2 ? xs[m] : (xs[m - 1] + xs[m]) / 2; };
  const keys = new Set([...Object.keys(current), ...votes.flatMap(v => Object.keys(v ?? {}))]);
  const out = {};
  for (const key of keys) {
    const sample = current[key] ?? votes.map(v => v[key]).find(x => x != null);
    const values = votes.map(v => v[key]);
    if (Array.isArray(sample)) {                                  // directions
      out[key] = POINTS.filter(p => half(values.filter(x => Array.isArray(x) && x.includes(p)).length));
    } else if (typeof sample === "number") {                      // limits, hours, powder days
      const xs = values.filter(Number.isFinite);
      if (!half(xs.length)) { if (key in current) out[key] = current[key]; continue; }
      out[key] = Number.isInteger(sample) && xs.every(Number.isInteger) ? Math.round(median(xs)) : median(xs);
    } else if (typeof sample === "boolean") {                     // daylight, powder "sunny days only"
      out[key] = half(values.filter(x => x === true).length);
    } else if (sample && typeof sample === "object") {            // the wind rule's sunny-day limits
      const objects = values.filter(x => x && typeof x === "object");
      if (half(objects.length)) out[key] = majorityRule(objects, objects[0]);
    }
  }
  return out;
}

async function describe(env, s) {
  const followers = (await env.DB.prepare("SELECT count(*) AS n FROM followers WHERE spot_id = ?").bind(s.id).first()).n;
  const last = await env.DB.prepare(`SELECT edits.field, edits.at, users.name FROM edits LEFT JOIN users ON users.id = edits.user_id
      WHERE spot_id = ? AND field != 'created' ORDER BY edits.id DESC LIMIT 1`).bind(s.id).first();
  const by = s.created_by ? (await env.DB.prepare("SELECT name FROM users WHERE id = ?").bind(s.created_by).first())?.name : null;
  return { id: s.id, name: s.name, lat: s.lat, lon: s.lon, alt: s.alt, tz: s.tz, sport: s.sport, rule: JSON.parse(s.rule),
           by: by || null, followers, catalogue: !!s.catalogue,
           lastEdit: last ? { field: last.field, at: last.at, by: last.name || null } : null };
}

async function near(env, url, reply) {
  const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400);
  const dLat = 2.7, dLon = Math.min(180, 2.7 / Math.max(0.1, Math.cos(lat * Math.PI / 180))); // about 300 km
  const { results } = await env.DB.prepare(`SELECT spots.*, users.name AS by FROM spots LEFT JOIN users ON users.id = spots.created_by
      WHERE status = 'active' AND catalogue = 0 AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?`)
    .bind(lat - dLat, lat + dLat, lon - dLon, lon + dLon).all();
  const km = s => Math.hypot(s.lat - lat, (s.lon - lon) * Math.cos(lat * Math.PI / 180)) * 111;
  return reply({ spots: results.map(s => ({ id: s.id, name: s.name, by: s.by || null, lat: s.lat, lon: s.lon, alt: s.alt, tz: s.tz,
                                             sport: s.sport, rule: JSON.parse(s.rule), km: Math.round(km(s) * 10) / 10 }))
    .sort((a, b) => a.km - b.km).slice(0, 200) });
}

// ---- Editing (wiki) -----------------------------------------------------------------------------------------

async function edit(request, env, id, reply) {
  const user = await currentUser(request, env);
  if (!user) return reply({ error: "sign in to change spots" }, 401);
  const spot = await env.DB.prepare("SELECT * FROM spots WHERE id = ? AND status = 'active'").bind(id).first();
  if (!spot) return reply({ error: "no such spot" }, 404);
  if (await tooBusy(env, user)) return reply({ error: "that's a lot of changes for one day; try again tomorrow" }, 429);
  const b = await readJSON(request, 5_000) ?? {};
  const changes = [];
  if (typeof b.name === "string") {
    const name = b.name.trim().replace(/\s+/g, " ").slice(0, 60);
    if (!name) return reply({ error: "a name is needed" }, 400);
    if (name !== spot.name) changes.push(["name", spot.name, name]);
  }
  if (Number.isFinite(b.lat) && Number.isFinite(b.lon)) {
    const lat = Math.round(b.lat * 1e4) / 1e4, lon = Math.round(b.lon * 1e4) / 1e4;
    if (km(spot.lat, spot.lon, lat, lon) > MAX_MOVE_KM)
      return reply({ error: `that's more than ${MAX_MOVE_KM} km away, so it's a different spot: add it as a new one` }, 409);
    if (lat !== spot.lat || lon !== spot.lon) changes.push(["position", { lat: spot.lat, lon: spot.lon }, { lat, lon }]);
  }
  for (const [field, from, to] of changes) await apply(env, spot.id, user.id, field, from, to);
  const fresh = await env.DB.prepare("SELECT * FROM spots WHERE id = ?").bind(id).first();
  return reply({ spot: await describe(env, fresh) });
}

async function apply(env, spotID, userID, field, from, to, undoes = null) {
  const now = new Date().toISOString();
  const set = field === "name" ? env.DB.prepare("UPDATE spots SET name = ?, updated = ? WHERE id = ?").bind(to, now, spotID)
                               : env.DB.prepare("UPDATE spots SET lat = ?, lon = ?, updated = ? WHERE id = ?").bind(to.lat, to.lon, now, spotID);
  await env.DB.batch([set, env.DB.prepare(`INSERT INTO edits (spot_id, user_id, at, field, old, new, undoes) VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .bind(spotID, userID, now, field, JSON.stringify(from), JSON.stringify(to), undoes)]);
}

async function history(env, id, reply) {
  const { results } = await env.DB.prepare(`SELECT edits.id, edits.field, edits.at, edits.old, edits.new, edits.undoes, users.name AS by,
      (SELECT count(*) FROM edits u WHERE u.undoes = edits.id) AS undone
      FROM edits LEFT JOIN users ON users.id = edits.user_id WHERE spot_id = ? ORDER BY edits.id DESC LIMIT 100`).bind(id).all();
  return reply({ edits: results.map(e => ({ id: e.id, field: e.field, at: e.at, by: e.by || null,
                                             old: e.old ? JSON.parse(e.old) : null, new: e.new ? JSON.parse(e.new) : null,
                                             undoes: e.undoes, undone: e.undone > 0 })) });
}

async function undo(request, env, editID, reply) {
  const user = await currentUser(request, env);
  if (!user) return reply({ error: "sign in to change spots" }, 401);
  if (await tooBusy(env, user)) return reply({ error: "that's a lot of changes for one day; try again tomorrow" }, 429);
  const e = await env.DB.prepare("SELECT * FROM edits WHERE id = ?").bind(editID).first();
  if (!e || !["name", "position"].includes(e.field)) return reply({ error: "nothing to undo" }, 404);
  const spot = await env.DB.prepare("SELECT * FROM spots WHERE id = ? AND status = 'active'").bind(e.spot_id).first();
  if (!spot) return reply({ error: "no such spot" }, 404);
  const current = e.field === "name" ? spot.name : { lat: spot.lat, lon: spot.lon };
  await apply(env, spot.id, user.id, e.field, current, JSON.parse(e.old), e.id);
  const fresh = await env.DB.prepare("SELECT * FROM spots WHERE id = ?").bind(spot.id).first();
  return reply({ spot: await describe(env, fresh) });
}

async function tooBusy(env, user) {
  const since = new Date(Date.now() - 86400e3).toISOString();
  const { n } = await env.DB.prepare("SELECT count(*) AS n FROM edits WHERE user_id = ? AND at >= ?").bind(user.id, since).first();
  return n >= MAX_EDITS_PER_DAY;
}

// ---- Sharing a new spot (and the old /shared endpoints, which apps from build 1-4 use) ----------------------

async function legacyShared(request, env, id, url, reply) {
  if (request.method === "GET" && !id) return near(env, url, reply);
  if (!/^[0-9a-z-]{1,64}$/i.test(id ?? "")) return reply({ error: "spot id required" }, 400);
  const b = await readJSON(request, 20_000) ?? {};
  if (typeof b.key !== "string" || b.key.length < 32 || b.key.length > 200) return reply({ error: "key required" }, 400);
  const follower = await sha256(b.key);
  const spot = await env.DB.prepare("SELECT * FROM spots WHERE id = ?").bind(id).first();

  if (request.method === "DELETE") { // stop sharing = stop following; the spot stays if others follow it
    await env.DB.prepare("DELETE FROM followers WHERE spot_id = ? AND follower = ?").bind(id, follower).run();
    if (spot) await settle(env, id);
    return reply({ ok: true });
  }

  if (request.method === "PUT") {
    const user = await currentUser(request, env);
    if (!user) return reply({ error: "sign in to share spots" }, 401);
    const name = typeof b.name === "string" ? b.name.trim().slice(0, 60) : "";
    if (!name || !Number.isFinite(b.lat) || !Number.isFinite(b.lon) || Math.abs(b.lat) > 90 || Math.abs(b.lon) > 180 ||
        !SPORTS.includes(b.sport) || typeof b.rule !== "object" || !validZone(b.tz)) return reply({ error: "name, lat, lon, tz, sport and rule required" }, 400);
    const now = new Date().toISOString();
    const lat = Math.round(b.lat * 1e4) / 1e4, lon = Math.round(b.lon * 1e4) / 1e4;
    if (!spot || spot.status === "gone") {
      const { n } = await env.DB.prepare("SELECT count(*) AS n FROM spots WHERE created_by = ? AND status = 'active'").bind(user.id).first();
      if (n >= 100) return reply({ error: "too many shared spots" }, 429);
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO spots (id, sport, tz, name, lat, lon, alt, rule, created_by, created, updated, status, catalogue)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 0)
            ON CONFLICT(id) DO UPDATE SET sport = excluded.sport, tz = excluded.tz, name = excluded.name, lat = excluded.lat,
              lon = excluded.lon, alt = excluded.alt, rule = excluded.rule, created_by = excluded.created_by,
              updated = excluded.updated, status = 'active'`)
          .bind(id, b.sport, b.tz, name, lat, lon, Number.isFinite(b.alt) ? b.alt : null, JSON.stringify(b.rule), user.id, now, now),
        env.DB.prepare(`INSERT INTO edits (spot_id, user_id, at, field, old, new) VALUES (?, ?, ?, 'created', NULL, ?)`)
          .bind(id, user.id, now, JSON.stringify({ name, lat, lon })),
        env.DB.prepare(`INSERT INTO followers (spot_id, follower, rule, last_active) VALUES (?, ?, NULL, ?)
            ON CONFLICT(spot_id, follower) DO UPDATE SET last_active = excluded.last_active`).bind(id, follower, now),
      ]);
      return reply({ ok: true });
    }
    // Already a community spot: the sharer is a follower like everyone else. While nobody else follows it, the creator
    // still sets its rules; name and position changes go through the log either way.
    const others = (await env.DB.prepare("SELECT count(*) AS n FROM followers WHERE spot_id = ? AND follower != ?").bind(id, follower).first()).n;
    if (others === 0 && spot.created_by === user.id)
      await env.DB.prepare("UPDATE spots SET rule = ?, updated = ? WHERE id = ?").bind(JSON.stringify(b.rule), now, id).run();
    if (name !== spot.name) await apply(env, id, user.id, "name", spot.name, name);
    if ((lat !== spot.lat || lon !== spot.lon) && km(spot.lat, spot.lon, lat, lon) <= MAX_MOVE_KM)
      await apply(env, id, user.id, "position", { lat: spot.lat, lon: spot.lon }, { lat, lon });
    await env.DB.prepare(`INSERT INTO followers (spot_id, follower, rule, last_active) VALUES (?, ?, NULL, ?)
        ON CONFLICT(spot_id, follower) DO UPDATE SET last_active = excluded.last_active`).bind(id, follower, now).run();
    return reply({ ok: true });
  }
  return reply({ error: "not found" }, 404);
}

// ---- Helpers ------------------------------------------------------------------------------------------------

async function readJSON(request, max) {
  const text = await request.text();
  if (text.length > max) return null;
  try { return JSON.parse(text || "{}"); } catch { return null; }
}

function km(lat1, lon1, lat2, lon2) {
  const r = Math.PI / 180;
  return 6371 * 2 * Math.asin(Math.sqrt(Math.sin((lat2 - lat1) * r / 2) ** 2 +
    Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2));
}

function validZone(tz) {
  if (typeof tz !== "string") return false;
  try { new Intl.DateTimeFormat("en", { timeZone: tz }); return true; } catch { return false; }
}
