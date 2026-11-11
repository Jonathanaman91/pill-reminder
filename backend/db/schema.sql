-- =====================================================================
-- Pill Reminder — server database schema (PostgreSQL 15+)
-- CSS3344 Mobile Application Development
--
-- Design notes
--   * UUID primary keys so the phone can create rows while offline
--     (client generates the id, server accepts it) without id clashes.
--   * Every syncable table has updated_at + deleted_at (soft delete) so
--     the app can ask "what changed since <timestamp>?" after being offline.
--   * dose_logs has a UNIQUE (schedule_id, scheduled_at) key, which makes
--     offline re-uploads idempotent: sending the same dose twice is harmless.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
CREATE TYPE user_role       AS ENUM ('user', 'admin');
CREATE TYPE account_status  AS ENUM ('active', 'suspended');
CREATE TYPE dosage_form     AS ENUM ('tablet', 'capsule', 'liquid', 'injection',
                                     'inhaler', 'drops', 'cream', 'other');
CREATE TYPE dose_status     AS ENUM ('taken', 'skipped', 'missed');
CREATE TYPE facility_type   AS ENUM ('pharmacy', 'clinic', 'hospital');
CREATE TYPE facility_ownership AS ENUM ('public', 'private');   -- government vs private

-- ---------------------------------------------------------------------
-- 1. Users & authentication (Feature a: JWT token management)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255)   NOT NULL UNIQUE,
    password_hash   VARCHAR(255)   NOT NULL,              -- bcrypt, cost >= 10
    full_name       VARCHAR(120)   NOT NULL,
    phone           VARCHAR(20),
    role            user_role      NOT NULL DEFAULT 'user',
    status          account_status NOT NULL DEFAULT 'active',
    timezone        VARCHAR(64)    NOT NULL DEFAULT 'Asia/Kuala_Lumpur',
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- Short-lived access token (JWT, ~15 min) is NOT stored.
-- Long-lived refresh token (~30 days) is stored as a SHA-256 hash so a
-- leaked database cannot be used to log in, and so admins can revoke it.
CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      CHAR(64)     NOT NULL UNIQUE,
    device_name     VARCHAR(120),
    expires_at      TIMESTAMPTZ  NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);

-- Device tokens for push notifications (Feature f, optional FCM route)
CREATE TABLE device_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fcm_token       TEXT         NOT NULL UNIQUE,
    platform        VARCHAR(16)  NOT NULL DEFAULT 'android',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. Global medication database (managed in the Web Admin panel)
-- ---------------------------------------------------------------------
CREATE TABLE medication_catalog (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generic_name    VARCHAR(150) NOT NULL,                -- e.g. Metformin
    brand_name      VARCHAR(150),                         -- e.g. Glucophage
    form            dosage_form  NOT NULL,
    strength        NUMERIC(10,3),                        -- e.g. 500
    strength_unit   VARCHAR(16),                          -- e.g. mg
    description     TEXT,
    warnings        TEXT,
    image_url       TEXT,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by      UUID         REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (generic_name, brand_name, form, strength, strength_unit)
);
CREATE INDEX idx_catalog_search ON medication_catalog (lower(generic_name), lower(brand_name));

-- ---------------------------------------------------------------------
-- 3. A user's own medications (Feature d: photo upload + validation)
-- ---------------------------------------------------------------------
CREATE TABLE user_medications (
    id               UUID PRIMARY KEY,                    -- generated on the phone
    user_id          UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    catalog_id       UUID          REFERENCES medication_catalog(id) ON DELETE SET NULL,
    name             VARCHAR(150)  NOT NULL,
    dosage_amount    NUMERIC(10,3) NOT NULL CHECK (dosage_amount > 0),
    dosage_unit      VARCHAR(16)   NOT NULL,              -- mg, ml, mcg, IU, puff
    form             dosage_form   NOT NULL,
    instructions     VARCHAR(255),                        -- e.g. "After food"
    photo_url        TEXT,                                -- pill bottle photo
    start_date       DATE          NOT NULL,
    end_date         DATE          CHECK (end_date IS NULL OR end_date >= start_date),
    stock_count      INTEGER       CHECK (stock_count IS NULL OR stock_count >= 0),
    refill_threshold INTEGER       CHECK (refill_threshold IS NULL OR refill_threshold >= 0),
    is_active        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
CREATE INDEX idx_user_meds_user_updated ON user_medications(user_id, updated_at);

-- One medication can be taken several times a day, e.g. 08:00 and 20:00.
-- days_mask is a 7-bit set: Mon = 1, Tue = 2, Wed = 4, Thu = 8,
-- Fri = 16, Sat = 32, Sun = 64. Every day = 127.
CREATE TABLE medication_schedules (
    id               UUID PRIMARY KEY,                    -- generated on the phone
    user_medication_id UUID        NOT NULL REFERENCES user_medications(id) ON DELETE CASCADE,
    time_of_day      TIME          NOT NULL,
    days_mask        SMALLINT      NOT NULL DEFAULT 127 CHECK (days_mask BETWEEN 1 AND 127),
    quantity         NUMERIC(6,2)  NOT NULL DEFAULT 1 CHECK (quantity > 0), -- tablets per dose
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
CREATE INDEX idx_schedules_med ON medication_schedules(user_medication_id);

-- Pill-bottle photos, stored in the database (not on disk) because hosts
-- like Render wipe the server's files on every restart.
CREATE TABLE medication_photos (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_medication_id UUID        NOT NULL REFERENCES user_medications(id) ON DELETE CASCADE,
    mime_type          VARCHAR(20) NOT NULL,
    data               BYTEA       NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_medication_photos_med ON medication_photos (user_medication_id);

-- ---------------------------------------------------------------------
-- 4. Dose history (Feature b: dashboard + adherence streak)
-- ---------------------------------------------------------------------
CREATE TABLE dose_logs (
    id               UUID PRIMARY KEY,                    -- generated on the phone
    user_id          UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    schedule_id      UUID          NOT NULL REFERENCES medication_schedules(id) ON DELETE CASCADE,
    user_medication_id UUID        NOT NULL REFERENCES user_medications(id) ON DELETE CASCADE,
    scheduled_at     TIMESTAMPTZ   NOT NULL,              -- the slot this log answers
    status           dose_status   NOT NULL,
    taken_at         TIMESTAMPTZ,                         -- real time the button was pressed
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,                         -- set when the user taps "Undo"
    UNIQUE (schedule_id, scheduled_at)
);
CREATE INDEX idx_dose_logs_user_time ON dose_logs(user_id, scheduled_at);

-- ---------------------------------------------------------------------
-- 5. Pharmacies & 24-hour clinics (Feature c: nearest facility locator)
--    Admin-curated, because map providers have thin data for rural
--    Sarawak. The app can merge these with OpenStreetMap results.
-- ---------------------------------------------------------------------
CREATE TABLE facilities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(150)  NOT NULL,
    type            facility_type NOT NULL,
    -- Where prescriptions are collected differs: government clinics/hospitals
    -- dispense from their own pharmacy, private clinics usually dispense directly.
    ownership       facility_ownership NOT NULL DEFAULT 'private',
    is_24_hours     BOOLEAN       NOT NULL DEFAULT FALSE,
    latitude        NUMERIC(9,6)  NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude       NUMERIC(9,6)  NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    address         VARCHAR(255),
    phone           VARCHAR(20),
    opening_hours   VARCHAR(120),                         -- e.g. "Mon–Sat 08:00–21:00"
    source          VARCHAR(10)   NOT NULL DEFAULT 'admin', -- 'admin' or 'osm' (imported)
    osm_id          VARCHAR(40)   UNIQUE,                 -- e.g. 'node/123' for imported places
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_facilities_geo ON facilities(latitude, longitude);

-- ---------------------------------------------------------------------
-- 6. Admin audit trail (who changed what in the Web Admin panel)
-- ---------------------------------------------------------------------
CREATE TABLE admin_audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    admin_id        UUID         NOT NULL REFERENCES users(id),
    action          VARCHAR(40)  NOT NULL,                -- e.g. 'user.suspend'
    target_table    VARCHAR(40)  NOT NULL,
    target_id       UUID,
    details         JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Keep updated_at honest on every UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_touch      BEFORE UPDATE ON users                FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_catalog_touch    BEFORE UPDATE ON medication_catalog   FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_user_meds_touch  BEFORE UPDATE ON user_medications     FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_schedules_touch  BEFORE UPDATE ON medication_schedules FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_dose_logs_touch  BEFORE UPDATE ON dose_logs            FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_facilities_touch BEFORE UPDATE ON facilities           FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
