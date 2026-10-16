-- Kookout's notification database (Cloudflare D1). Apply with:
--   npx wrangler d1 execute kookout --remote --file schema.sql
-- One row per phone that wants notifications. No accounts and no personal details: the id is a random
-- number the app makes up, the token is Apple's address for pushing to the app on that phone.
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,            -- random id made by the app
  token TEXT NOT NULL,            -- APNs device token (hex)
  sandbox INTEGER NOT NULL,       -- 1 for builds from Xcode (Apple's sandbox push service)
  lang TEXT NOT NULL,             -- the app's language: en, nb, sv, da, de, fr, es
  country TEXT,                   -- the phone's region (NO, SE…): whose public holidays count for weekend spots
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

-- Accounts (Sign in with Apple), only for sharing and editing spots. See src/auth.js.
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,          -- our own id
  apple_sub TEXT NOT NULL UNIQUE, -- Apple's stable id for this person and app
  name TEXT,                    -- the public name they chose (shown on shared spots and in the log)
  created TEXT NOT NULL,
  last_active TEXT,
  refresh_token TEXT,           -- Apple's, so we can revoke the sign-in when they delete the account
  blocked INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,  -- SHA-256 of the app's session token
  user_id TEXT NOT NULL,
  created TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id);
-- Added with accounts (for databases made before):
--   ALTER TABLE shared_spots ADD COLUMN user_id TEXT;

-- Community spots (src/community.js). Name and position are fixed by anyone signed in (logged in edits, can be
-- undone); the rules are the majority of the followers' versions.
CREATE TABLE IF NOT EXISTS spots (
  id TEXT PRIMARY KEY,           -- the app's id (a UUID, or the catalogue's id like "saltstein")
  sport TEXT NOT NULL,           -- wing, surf or powder
  tz TEXT NOT NULL,
  name TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  alt REAL,
  rule TEXT NOT NULL,            -- JSON: the community version of the rule for its sport
  created_by TEXT,               -- users.id (null for the built-in spots, or once the account is deleted)
  created TEXT NOT NULL,
  updated TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active', -- 'gone' when nobody follows it any more
  catalogue INTEGER NOT NULL DEFAULT 0,  -- 1 for the app's built-in spots (they never go away)
  station TEXT,                  -- the community's wind station for "Measured now" (null: the nearest); majority of followers
  station_name TEXT
);
CREATE INDEX IF NOT EXISTS spots_lat ON spots (lat);
CREATE TABLE IF NOT EXISTS followers (
  spot_id TEXT NOT NULL,
  follower TEXT NOT NULL,        -- SHA-256 of the app's random key (works without an account)
  rule TEXT,                     -- JSON: their own version, or null when they follow the community's
  station TEXT,                  -- the wind station they chose, or null for "Automatic"
  station_name TEXT,
  last_active TEXT NOT NULL,
  PRIMARY KEY (spot_id, follower)
);
CREATE INDEX IF NOT EXISTS followers_follower ON followers (follower);
CREATE TABLE IF NOT EXISTS edits (  -- the log: who changed what, when
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  spot_id TEXT NOT NULL,
  user_id TEXT,                  -- users.id (null once the account is deleted: "a former rider")
  at TEXT NOT NULL,
  field TEXT NOT NULL,           -- 'created', 'name' or 'position'
  old TEXT,                      -- JSON
  new TEXT,                      -- JSON
  undoes INTEGER                 -- edits.id this one undid
);
CREATE INDEX IF NOT EXISTS edits_spot ON edits (spot_id);
CREATE INDEX IF NOT EXISTS edits_user ON edits (user_id, at);

-- Reports about a spot, or about a change someone made (src/reports.js). Sent to REPORT_EMAIL when RESEND_API_KEY is set.
CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  spot_id TEXT NOT NULL,
  edit_id INTEGER,              -- the change it's about (and so the person who made it), if any
  reason TEXT NOT NULL,         -- wrong, private, offensive, other
  note TEXT,
  reporter_user TEXT,           -- users.id if signed in
  reporter TEXT NOT NULL,       -- SHA-256 of the app's random key
  at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open'
);

-- Founding users (src/founders.js): one row per App Store install that reported, numbered in the order they came.
CREATE TABLE IF NOT EXISTS founders (
  n INTEGER PRIMARY KEY,         -- the founding-user number (the next free one; rows are never deleted)
  who TEXT NOT NULL UNIQUE,      -- SHA-256 of Apple's app transaction id, or of the app's random key on older iOS
  first TEXT NOT NULL,           -- Apple's first-download date
  at TEXT NOT NULL               -- when it first reported
);
