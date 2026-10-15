-- Wind stations by majority (15 Oct 2026): the community's station per spot, and each follower's choice.
ALTER TABLE spots ADD COLUMN station TEXT;
ALTER TABLE spots ADD COLUMN station_name TEXT;
ALTER TABLE followers ADD COLUMN station TEXT;
ALTER TABLE followers ADD COLUMN station_name TEXT;
-- Christian's starting stations for some Oslofjord spots (until the followers vote for others)
UPDATE spots SET station = 'holfuy:1815', station_name = 'Drøbak Fluid.no' WHERE id = 'drobak';
UPDATE spots SET station = 'holfuy:1542', station_name = 'Rolfstangen LBK' WHERE id = 'lysaker';
UPDATE spots SET station = 'KV:12045059', station_name = 'Gullholmen (Kystverket)' WHERE id IN ('larkollen', 'movik');
-- Drøbaksundet is called Torkild (renamed by Christian; logged like any other rename, so it can be undone)
INSERT INTO edits (spot_id, user_id, at, field, old, new)
  SELECT 'drobak', '01f5e1c0-19d1-4d44-b66c-3d4c03b75356', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 'name', json_quote(name), json_quote('Torkild')
  FROM spots WHERE id = 'drobak' AND name != 'Torkild';
UPDATE spots SET name = 'Torkild', updated = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = 'drobak';
