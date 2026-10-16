// Founding users: the first FOUNDERS people to use the App Store app use Kookout for free (see CLAUDE.md, Pricing).
// Each install of the App Store version tells the relay once that it exists, with Apple's first-download date, and
// gets its number in line. Numbers are handed out in the order phones first report, and never change.
//
//   POST /founders  {key, transaction?, first}  -> {number, founding}
//
// `transaction` is Apple's app transaction id (iOS 18.4 and newer): the same for an Apple ID across reinstalls and
// devices, so a reinstall keeps its number. Older iOS only has the app's random key, which a reinstall replaces.
// Only a hash of either is stored, with the first-download date; nothing links it to a name, account or phone.

import { sha256 } from "./auth.js";

export const FOUNDERS = 2000;

export async function handleFounders(request, env, url, reply) {
  if (request.method !== "POST") return reply({ error: "not found" }, 404);
  const text = await request.text();
  if (text.length > 2000) return reply({ error: "too large" }, 413);
  let b; try { b = JSON.parse(text); } catch { return reply({ error: "JSON required" }, 400); }
  if (typeof b.key !== "string" || b.key.length < 32 || b.key.length > 200) return reply({ error: "key required" }, 400);
  const transaction = typeof b.transaction === "string" && b.transaction.length > 0 && b.transaction.length <= 200
    ? b.transaction : null;
  const first = typeof b.first === "string" ? Date.parse(b.first) : NaN;
  if (!Number.isFinite(first) || first > Date.now() + 86400e3) return reply({ error: "first download date required" }, 400);

  const who = await sha256(transaction ? `tx:${transaction}` : `key:${b.key}`);
  // Look first, so asking again (a reinstall) doesn't use up a number; rows are never deleted, so n has no gaps.
  let row = await env.DB.prepare("SELECT n FROM founders WHERE who = ?").bind(who).first();
  if (!row) {
    await env.DB.prepare("INSERT OR IGNORE INTO founders (who, first, at) VALUES (?, ?, ?)")
      .bind(who, new Date(first).toISOString(), new Date().toISOString()).run();
    row = await env.DB.prepare("SELECT n FROM founders WHERE who = ?").bind(who).first();
  }
  return reply({ number: row.n, founding: row.n <= FOUNDERS });
}
