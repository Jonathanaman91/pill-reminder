-- Adds government/private ownership to facilities.
-- Safe to run more than once, and safe on a database created from the new schema.sql.
DO $$
BEGIN
    CREATE TYPE facility_ownership AS ENUM ('public', 'private');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE facilities
    ADD COLUMN IF NOT EXISTS ownership facility_ownership NOT NULL DEFAULT 'private';
