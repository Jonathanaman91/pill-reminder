-- Lecturer feedback (Nov 2026): a health app should know a little about its
-- user, and a skipped dose should say why. Safe to run more than once.

-- Health profile (shown in the app; counted, never listed, in admin analytics)
ALTER TABLE users ADD COLUMN IF NOT EXISTS date_of_birth      DATE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS gender             VARCHAR(20);   -- female | male | unspecified
ALTER TABLE users ADD COLUMN IF NOT EXISTS conditions         TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE users ADD COLUMN IF NOT EXISTS allergies          VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_updated_at TIMESTAMPTZ;

-- "Other" medication form, typed by the user, e.g. "Patch" or "Powder"
ALTER TABLE user_medications ADD COLUMN IF NOT EXISTS form_detail VARCHAR(40);

-- Why a dose was skipped, e.g. "Ran out of medicine"
ALTER TABLE dose_logs ADD COLUMN IF NOT EXISTS skip_reason VARCHAR(60);
