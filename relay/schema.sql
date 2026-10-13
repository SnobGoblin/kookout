-- Kookout's notification database (Cloudflare D1). Apply with:
--   npx wrangler d1 execute kookout --remote --file schema.sql
-- One row per phone that wants notifications. No accounts and no personal details: the id is a random
-- number the app makes up, the token is Apple's address for pushing to the app on that phone.
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,            -- random id made by the app
  token TEXT NOT NULL,            -- APNs device token (hex)
  sandbox INTEGER NOT NULL,       -- 1 for builds from Xcode (Apple's sandbox push service)
  lang TEXT NOT NULL,             -- the app's language: en, nb, sv, da, de, fr, es
  units TEXT NOT NULL,            -- "ms" or "kn": how the rules round wind, as in the app
  wave_unit TEXT NOT NULL,        -- "m" or "ft"
  h12 INTEGER NOT NULL,           -- 1 for a 12-hour clock in the texts
  tz TEXT NOT NULL,               -- the phone's time zone, for quiet hours at night
  window_hours INTEGER NOT NULL,  -- how far ahead to notify, e.g. 48
  spots TEXT NOT NULL,            -- JSON: the spots with notifications on, with their rules
  state TEXT NOT NULL DEFAULT '{}', -- JSON: what we last told this phone, per spot
  updated TEXT NOT NULL
);

-- Spots people chose to share, shown on everyone's map in the app. No link to the phone or its notifications:
-- owner is a hash of a separate random key the app keeps, so only that phone can change or remove the spot.
CREATE TABLE IF NOT EXISTS shared_spots (
  id TEXT PRIMARY KEY,   -- the app's id for the spot
  owner TEXT NOT NULL,   -- SHA-256 of the app's sharing key
  name TEXT NOT NULL,
  by_name TEXT,          -- who added it: the name the person chose in the app's Settings (optional)
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  alt REAL,
  tz TEXT NOT NULL,
  sport TEXT NOT NULL,   -- wing, surf or powder
  rule TEXT NOT NULL,    -- JSON: the spot's rule for its sport (directions and limits)
  updated TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS shared_spots_lat ON shared_spots (lat);
-- Added later (for databases made before by_name existed):
--   ALTER TABLE shared_spots ADD COLUMN by_name TEXT;
