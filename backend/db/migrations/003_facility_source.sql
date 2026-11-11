-- Lets OpenStreetMap places be saved in the facilities table (imported once by
-- `npm run facilities:import`) next to places added by admins.
-- Safe to run more than once.
ALTER TABLE facilities ADD COLUMN IF NOT EXISTS source VARCHAR(10) NOT NULL DEFAULT 'admin';
ALTER TABLE facilities ADD COLUMN IF NOT EXISTS osm_id VARCHAR(40);
CREATE UNIQUE INDEX IF NOT EXISTS facilities_osm_id_key ON facilities (osm_id);
