// Writes seed-catalogue.sql: the app's built-in spots (ios/Kookout/Catalogue.json) as community spots, with the
// same standard rules the app gives them (Catalogue.swift). INSERT OR IGNORE, so running it again only adds new ones.
//   node seed-catalogue.mjs && npx wrangler d1 execute kookout --remote --file seed-catalogue.sql
import { readFileSync, writeFileSync } from "node:fs";

const catalogue = JSON.parse(readFileSync(new URL("../ios/Kookout/Catalogue.json", import.meta.url)));
const all = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
const now = new Date().toISOString();
const q = v => v == null ? "NULL" : typeof v === "number" ? String(v) : `'${String(v).replaceAll("'", "''")}'`;

function rule(s) {
  if (s.sport === "powder") return { mm: 10, maxTemp: 2, maxWind: 8 };
  if (s.sport === "surf") return { minWave: s.minWave ?? 0.8, minPeriod: 0, maxWind: s.maxWind ?? 6, hours: 2, daylight: true, dirs: s.dirs ?? all };
  const r = { min: 5, gust: 9, steady: 6, hours: 2, daylight: true, dirs: s.dirs ?? all };
  if (s.sunny?.length === 3) r.sunny = { min: s.sunny[0], gust: s.sunny[1], steady: s.sunny[2] };
  return r;
}

const rows = catalogue.map(s => "INSERT OR IGNORE INTO spots (id, sport, tz, name, lat, lon, alt, rule, created_by, created, updated, status, catalogue) VALUES (" +
  [s.id, s.sport, s.tz, s.name, s.lat, s.lon, s.altitude ?? null, JSON.stringify(rule(s)), null, now, now, "active", 1].map(q).join(", ") + ");");
writeFileSync(new URL("seed-catalogue.sql", import.meta.url),
  "-- The app built-in spots (ios/Kookout/Catalogue.json) as community spots. Regenerate with seed-catalogue.mjs.\n" + rows.join("\n") + "\n");
console.log(`${rows.length} spots`);
