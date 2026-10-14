// Reports: anyone can report a community spot (wrong, private, offensive…) or a change someone made to one.
// They're stored in the reports table and, when RESEND_API_KEY is set, emailed to REPORT_EMAIL (Resend, resend.com).
//
//   POST /reports  {key, spot, edit?, reason, note?}

import { currentUser, sha256 } from "./auth.js";

const REASONS = ["wrong", "private", "offensive", "other"];
const MAX_PER_DAY = 20; // per phone

export async function handleReports(request, env, url, reply) {
  if (request.method !== "POST") return reply({ error: "not found" }, 404);
  const text = await request.text();
  if (text.length > 5000) return reply({ error: "too large" }, 413);
  let b; try { b = JSON.parse(text); } catch { return reply({ error: "JSON required" }, 400); }
  if (typeof b.key !== "string" || b.key.length < 32 || b.key.length > 200) return reply({ error: "key required" }, 400);
  if (typeof b.spot !== "string" || !REASONS.includes(b.reason)) return reply({ error: "spot and reason required" }, 400);
  const reporter = await sha256(b.key);
  const since = new Date(Date.now() - 86400e3).toISOString();
  const { n } = await env.DB.prepare("SELECT count(*) AS n FROM reports WHERE reporter = ? AND at >= ?").bind(reporter, since).first();
  if (n >= MAX_PER_DAY) return reply({ error: "that's a lot of reports for one day" }, 429);

  const spot = await env.DB.prepare("SELECT * FROM spots WHERE id = ?").bind(b.spot).first();
  if (!spot) return reply({ error: "no such spot" }, 404);
  const editID = Number.isInteger(b.edit) ? b.edit : null;
  const change = editID ? await env.DB.prepare(`SELECT edits.*, users.name AS by FROM edits LEFT JOIN users ON users.id = edits.user_id
      WHERE edits.id = ? AND spot_id = ?`).bind(editID, spot.id).first() : null;
  const user = await currentUser(request, env);
  const note = typeof b.note === "string" ? b.note.trim().slice(0, 1000) : "";
  const now = new Date().toISOString();
  const { meta } = await env.DB.prepare(`INSERT INTO reports (spot_id, edit_id, reason, note, reporter_user, reporter, at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`).bind(spot.id, change?.id ?? null, b.reason, note || null, user?.id ?? null, reporter, now).run();

  const lines = [
    `Spot: ${spot.name} (${spot.sport}), ${spot.lat}, ${spot.lon}`,
    `https://www.openstreetmap.org/?mlat=${spot.lat}&mlon=${spot.lon}#map=15/${spot.lat}/${spot.lon}`,
    `Reason: ${b.reason}`, note ? `Note: ${note}` : null,
    change ? `About the change #${change.id} (${change.field}) by ${change.by ?? "a former rider"} (user ${change.user_id ?? "deleted"}) at ${change.at}: ${change.old} → ${change.new}` : null,
    `Reported by ${user ? `${user.name || "(no name)"} (user ${user.id})` : "someone not signed in"} at ${now}`,
    `Report #${meta?.last_row_id ?? "?"}, spot id ${spot.id}`,
  ].filter(Boolean);
  await email(env, `Kookout report: ${spot.name}`, lines.join("\n")).catch(e => console.log("Report email failed:", e.message));
  return reply({ ok: true });
}

async function email(env, subject, text) {
  if (!env.RESEND_API_KEY || !env.REPORT_EMAIL) { console.log("Report (no email set up):", subject); return; }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env.REPORT_FROM || "Kookout <reports@kookout.no>", to: [env.REPORT_EMAIL], subject, text }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${await res.text()}`);
}
