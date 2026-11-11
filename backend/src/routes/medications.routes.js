import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';
import { publicUrl } from '../uploads.js';

export const medicationsRouter = Router();

// ---------------------------------------------------------------------------
// Validation — the same rules as the Flutter form (lib/core/validation).
// ---------------------------------------------------------------------------
export const DOSAGE_FORMS = ['tablet', 'capsule', 'liquid', 'injection', 'inhaler', 'drops', 'cream', 'other'];
export const DOSAGE_UNITS = ['mg', 'mcg', 'g', 'ml', 'IU', 'units', 'puffs', 'drops', '%'];
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use YYYY-MM-DD.');

const scheduleSchema = z.object({
  id: z.string().uuid(),
  timeOfDay: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:mm (24-hour).'),
  daysMask: z.number().int().min(1, 'Pick at least one day.').max(127),
  quantity: z.number().positive().max(100),
  deleted: z.boolean().default(false),
});

const medicationSchema = z
  .object({
    id: z.string().uuid(),
    name: z.string().trim().min(2, 'Enter the medication name.').max(150),
    dosageAmount: z.number().positive('Strength must be more than 0.').max(100000),
    dosageUnit: z.enum(DOSAGE_UNITS),
    form: z.enum(DOSAGE_FORMS),
    instructions: z.string().trim().max(255).nullish(),
    startDate: isoDate,
    endDate: isoDate.nullish(),
    isActive: z.boolean().default(true),
    deleted: z.boolean().default(false),
    schedules: z.array(scheduleSchema).max(12, 'Up to 12 times a day.'),
  })
  .refine((m) => !m.endDate || m.endDate >= m.startDate, {
    message: 'End date cannot be before the start date.',
    path: ['endDate'],
  })
  .refine((m) => m.deleted || m.schedules.some((s) => !s.deleted), {
    message: 'Add at least one time.',
    path: ['schedules'],
  });

const batchSchema = z.object({ medications: z.array(medicationSchema).max(100) });

// ---------------------------------------------------------------------------
// POST /api/v1/medications/batch — upload medications created/edited offline.
// Safe to send twice: rows are upserted by the id the phone generated.
// ---------------------------------------------------------------------------
medicationsRouter.post('/medications/batch', requireAuth, validateBody(batchSchema), async (req, res) => {
  const userId = req.user.id;

  const result = await withTransaction(async (db) => {
    let saved = 0;
    const rejected = [];

    for (const m of req.body.medications) {
      // "WHERE user_id = EXCLUDED.user_id" stops anyone overwriting another
      // user's medication by guessing its id: the update simply does nothing.
      const upsert = await db.query(
        `INSERT INTO user_medications
           (id, user_id, name, dosage_amount, dosage_unit, form, instructions,
            start_date, end_date, is_active, deleted_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CASE WHEN $11 THEN now() END)
         ON CONFLICT (id) DO UPDATE SET
           name = EXCLUDED.name, dosage_amount = EXCLUDED.dosage_amount,
           dosage_unit = EXCLUDED.dosage_unit, form = EXCLUDED.form,
           instructions = EXCLUDED.instructions, start_date = EXCLUDED.start_date,
           end_date = EXCLUDED.end_date, is_active = EXCLUDED.is_active,
           deleted_at = EXCLUDED.deleted_at
         WHERE user_medications.user_id = EXCLUDED.user_id`,
        [m.id, userId, m.name, m.dosageAmount, m.dosageUnit, m.form, m.instructions ?? null,
          m.startDate, m.endDate ?? null, m.isActive, m.deleted],
      );
      if (upsert.rowCount === 0) {
        rejected.push(m.id);
        continue;
      }

      for (const s of m.schedules) {
        await db.query(
          `INSERT INTO medication_schedules (id, user_medication_id, time_of_day, days_mask, quantity, deleted_at)
           VALUES ($1, $2, $3, $4, $5, CASE WHEN $6 THEN now() END)
           ON CONFLICT (id) DO UPDATE SET
             time_of_day = EXCLUDED.time_of_day, days_mask = EXCLUDED.days_mask,
             quantity = EXCLUDED.quantity, deleted_at = EXCLUDED.deleted_at
           WHERE medication_schedules.user_medication_id = EXCLUDED.user_medication_id`,
          [s.id, m.id, s.timeOfDay, s.daysMask, s.quantity, s.deleted || m.deleted],
        );
      }
      saved += 1;
    }
    return { saved, rejected };
  });

  res.json(result);
});

// ---------------------------------------------------------------------------
// POST /api/v1/medications/:id/photo — multipart field "photo" (JPEG/PNG/WebP, ≤ 5 MB)
// The image is kept in the medication_photos table, not on disk, because
// free hosts (Render) wipe the server's files on every restart.
// ---------------------------------------------------------------------------
const EXTENSIONS = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) =>
    EXTENSIONS[file.mimetype]
      ? cb(null, true)
      : cb(new HttpError(415, 'Photo must be a JPEG, PNG or WebP image.')),
});

const idParam = z.string().uuid();

medicationsRouter.post('/medications/:id/photo', requireAuth, async (req, res, next) => {
  if (!idParam.safeParse(req.params.id).success) throw new HttpError(404, 'Medication not found.');
  // Check ownership BEFORE reading the file, so strangers can't upload to someone else's medication.
  const { rows } = await query(
    'SELECT 1 FROM user_medications WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
    [req.params.id, req.user.id],
  );
  if (!rows[0]) throw new HttpError(404, 'Medication not found.');
  next();
}, upload.single('photo'), async (req, res) => {
  if (!req.file) throw new HttpError(422, 'Attach the image in a field called "photo".');

  const relative = await withTransaction(async (db) => {
    // One photo per medication: the new one replaces the old.
    await db.query('DELETE FROM medication_photos WHERE user_medication_id = $1', [req.params.id]);
    const { rows: [photo] } = await db.query(
      `INSERT INTO medication_photos (user_medication_id, mime_type, data)
       VALUES ($1, $2, $3) RETURNING id`,
      [req.params.id, req.file.mimetype, req.file.buffer],
    );
    const path = `/uploads/${photo.id}.${EXTENSIONS[req.file.mimetype]}`;
    await db.query('UPDATE user_medications SET photo_url = $1 WHERE id = $2', [path, req.params.id]);
    return path;
  });

  res.status(201).json({ photoUrl: publicUrl(req, relative) });
});

// ---------------------------------------------------------------------------
// GET /uploads/<photo id>.<ext> — serves a stored photo. Not behind login, so
// the app's image widget and the admin panel can load it directly; the id is
// a random UUID that can't be guessed.
// ---------------------------------------------------------------------------
export const photosRouter = Router();

photosRouter.get('/uploads/:file', async (req, res) => {
  const id = req.params.file.replace(/\.(jpg|png|webp)$/, '');
  if (!idParam.safeParse(id).success) throw new HttpError(404, 'Photo not found.');
  const { rows: [photo] } = await query(
    'SELECT mime_type, data FROM medication_photos WHERE id = $1',
    [id],
  );
  if (!photo) throw new HttpError(404, 'Photo not found.');
  res.set('Cache-Control', 'public, max-age=604800, immutable'); // a photo id never changes content
  res.type(photo.mime_type).send(photo.data);
});
