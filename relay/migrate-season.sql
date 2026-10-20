-- Seasons (Kookout 1.1, src/season.js): when a spot gives notifications. The community's season per spot (null: all
-- year), and each follower's own dates. Starting default: wing and surf at 50° N and up, 15 March to 24 December.
ALTER TABLE spots ADD COLUMN season TEXT;
ALTER TABLE followers ADD COLUMN season TEXT;
UPDATE spots SET season = '{"from":"03-15","to":"12-24"}' WHERE sport != 'powder' AND lat >= 50;
