// Shared spots: spots people added in the app and chose to share, so others can find them on the map.
// Nothing here is linked to a phone's notifications; "owner" is a hash of a separate random key, so only
// the phone that shared a spot can change or remove it.
//
//   GET    /shared?lat=59.6&lon=10.6     -> shared spots within about 300 km, nearest first (at most 200)
//   PUT    /shared/<id>   {key, name, lat, lon, alt?, tz, sport, rule}   share or update a spot. Needs an account
//                         (Authorization: Bearer <session>); "added by" is the account's public name.
//   DELETE /shared/<id>   {key}                                          stop sharing it

import { currentUser, sha256 } from "./auth.js";

const SPORTS = ["wing", "surf", "powder"];
const MAX_PER_OWNER = 100;

export async function handleShared(request, env, url, reply) {
  const id = url.pathname.split("/")[2];

  if (request.method === "GET" && !id) {
    const lat = parseFloat(url.searchParams.get("lat")), lon = parseFloat(url.searchParams.get("lon"));
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return reply({ error: "lat and lon required" }, 400);
    const dLat = 2.7, dLon = Math.min(180, 2.7 / Math.max(0.1, Math.cos(lat * Math.PI / 180))); // about 300 km
    const { results } = await env.DB.prepare(
      "SELECT id, name, by_name AS by, lat, lon, alt, tz, sport, rule FROM shared_spots WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?")
      .bind(lat - dLat, lat + dLat, lon - dLon, lon + dLon).all();
    const km = s => Math.hypot(s.lat - lat, (s.lon - lon) * Math.cos(lat * Math.PI / 180)) * 111;
    return reply({ spots: results.map(s => ({ ...s, rule: JSON.parse(s.rule), km: Math.round(km(s) * 10) / 10 }))
      .sort((a, b) => a.km - b.km).slice(0, 200) });
  }

  if (!/^[0-9a-z-]{1,64}$/i.test(id ?? "")) return reply({ error: "spot id required" }, 400);
  const text = await request.text();
  if (text.length > 20_000) return reply({ error: "too large" }, 413);
  let b; try { b = JSON.parse(text || "{}"); } catch { return reply({ error: "JSON required" }, 400); }
  if (typeof b.key !== "string" || b.key.length < 32 || b.key.length > 200) return reply({ error: "key required" }, 400);
  const owner = await sha256(b.key);
  const existing = await env.DB.prepare("SELECT owner FROM shared_spots WHERE id = ?").bind(id).first();
  if (existing && existing.owner !== owner) return reply({ error: "this spot was shared by someone else" }, 403);

  if (request.method === "DELETE") {
    await env.DB.prepare("DELETE FROM shared_spots WHERE id = ? AND owner = ?").bind(id, owner).run();
    return reply({ ok: true });
  }

  if (request.method === "PUT") {
    const user = await currentUser(request, env);
    if (!user) return reply({ error: "sign in to share spots" }, 401);
    const name = typeof b.name === "string" ? b.name.trim().slice(0, 60) : "";
    const by = user.name || null;
    if (!name || !Number.isFinite(b.lat) || !Number.isFinite(b.lon) || Math.abs(b.lat) > 90 || Math.abs(b.lon) > 180 ||
        !SPORTS.includes(b.sport) || typeof b.rule !== "object" || !validZone(b.tz)) return reply({ error: "name, lat, lon, tz, sport and rule required" }, 400);
    if (!existing) {
      const { n } = await env.DB.prepare("SELECT count(*) AS n FROM shared_spots WHERE owner = ?").bind(owner).first();
      if (n >= MAX_PER_OWNER) return reply({ error: "too many shared spots" }, 429);
    }
    await env.DB.prepare(`INSERT INTO shared_spots (id, owner, user_id, name, by_name, lat, lon, alt, tz, sport, rule, updated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET user_id = excluded.user_id, name = excluded.name, by_name = excluded.by_name, lat = excluded.lat, lon = excluded.lon, alt = excluded.alt,
          tz = excluded.tz, sport = excluded.sport, rule = excluded.rule, updated = excluded.updated`)
      .bind(id, owner, user.id, name, by, Math.round(b.lat * 1e4) / 1e4, Math.round(b.lon * 1e4) / 1e4, Number.isFinite(b.alt) ? b.alt : null,
            b.tz, b.sport, JSON.stringify(b.rule), new Date().toISOString()).run();
    return reply({ ok: true });
  }

  return reply({ error: "not found" }, 404);
}

function validZone(tz) {
  if (typeof tz !== "string") return false;
  try { new Intl.DateTimeFormat("en", { timeZone: tz }); return true; } catch { return false; }
}
