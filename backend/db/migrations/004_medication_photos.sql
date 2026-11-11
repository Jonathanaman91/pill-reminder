-- Pill-bottle photos are stored in the database instead of on disk, because
-- hosts like Render wipe the server's files on every restart.
-- Safe to run more than once.
CREATE TABLE IF NOT EXISTS medication_photos (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_medication_id UUID        NOT NULL REFERENCES user_medications(id) ON DELETE CASCADE,
    mime_type          VARCHAR(20) NOT NULL,           -- image/jpeg, image/png, image/webp
    data               BYTEA       NOT NULL,           -- the image itself (≤ 5 MB)
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_medication_photos_med ON medication_photos (user_medication_id);
