-- Wave heights on wind spots (Kookout 1.2): shown or not, by majority of followers like the wind station.
-- Christian's starting choice: on for Ørekroken, Larkollen, Apelviken and Träslövsläge (open to waves); off elsewhere.
ALTER TABLE spots ADD COLUMN waves INTEGER NOT NULL DEFAULT 0;
ALTER TABLE followers ADD COLUMN waves INTEGER;
UPDATE spots SET waves = 1 WHERE id IN ('orekroken', 'larkollen', 'apelviken', 'traslovslage');
