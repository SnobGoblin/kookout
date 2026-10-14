-- One-off: today's shared spots become community spots, each with its sharer as follower and a "created" log entry.
INSERT OR IGNORE INTO spots (id, sport, tz, name, lat, lon, alt, rule, created_by, created, updated, status, catalogue)
  SELECT id, sport, tz, name, lat, lon, alt, rule, user_id, updated, updated, 'active', 0 FROM shared_spots;
INSERT OR IGNORE INTO followers (spot_id, follower, rule, last_active) SELECT id, owner, NULL, updated FROM shared_spots;
INSERT INTO edits (spot_id, user_id, at, field, old, new)
  SELECT id, user_id, updated, 'created', NULL, json_object('name', name, 'lat', lat, 'lon', lon) FROM shared_spots;
