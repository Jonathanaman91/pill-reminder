import { Router } from 'express';
import { z } from 'zod';
import { pool } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';
import { computeStreak } from '../services/streak.js';
import { publicUrl } from '../uploads.js';

export const syncRouter = Router();

/**
 * GET /api/v1/sync?since=<ISO time>
 * Everything this user owns that changed after `since` (or everything, on the
 * first sync), including soft-deleted rows so the phone can remove them.
 */
syncRouter.get('/sync', requireAuth, async (req, res) => {
  const since = req.query.since ? new Date(String(req.query.since)) : new Date(0);
  if (Number.isNaN(since.getTime())) throw new HttpError(400, '`since` must be an ISO date.');

  const client = await pool.connect();
  try {
    // REPEATABLE READ: every query below sees the same moment in time, and
    // now() is fixed at the start, so no change can slip between two syncs.
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const userId = req.user.id;

    // serverTime is set 2 minutes in the past on purpose. A row saved by a
    // transaction that started before this one but finished after it gets an
    // updated_at slightly older than now(); the margin makes sure the next
    // sync still picks it up. Re-sending a few rows is harmless.
    const { rows: [user] } = await client.query(
      `SELECT timezone, now() - interval '2 minutes' AS server_time
       FROM users WHERE id = $1`,
      [userId],
    );
    if (!user) throw new HttpError(401, 'Account not found.');

    const medications = await client.query(
      `SELECT id, catalog_id AS "catalogId", name, dosage_amount AS "dosageAmount",
              dosage_unit AS "dosageUnit", form, instructions, photo_url AS "photoUrl",
              start_date AS "startDate", end_date AS "endDate", stock_count AS "stockCount",
              refill_threshold AS "refillThreshold", is_active AS "isActive",
              updated_at AS "updatedAt", deleted_at AS "deletedAt"
       FROM user_medications
       WHERE user_id = $1 AND updated_at > $2`,
      [userId, since],
    );

    const schedules = await client.query(
      `SELECT s.id, s.user_medication_id AS "userMedicationId", s.time_of_day AS "timeOfDay",
              s.days_mask AS "daysMask", s.quantity, s.updated_at AS "updatedAt",
              s.deleted_at AS "deletedAt"
       FROM medication_schedules s
       JOIN user_medications m ON m.id = s.user_medication_id
       WHERE m.user_id = $1 AND s.updated_at > $2`,
      [userId, since],
    );

    // Dose history is only useful on the phone for recent days.
    const doseLogs = await client.query(
      `SELECT id, schedule_id AS "scheduleId", user_medication_id AS "userMedicationId",
              scheduled_at AS "scheduledAt", status, taken_at AS "takenAt",
              updated_at AS "updatedAt", deleted_at AS "deletedAt"
       FROM dose_logs
       WHERE user_id = $1 AND updated_at > $2 AND scheduled_at > now() - interval '30 days'`,
      [userId, since],
    );

    const streak = await computeStreak(client, userId, user.timezone);
    await client.query('COMMIT');

    res.json({
      serverTime: user.server_time,
      medications: medications.rows.map((m) => ({ ...m, photoUrl: publicUrl(req, m.photoUrl) })),
      schedules: schedules.rows,
      doseLogs: doseLogs.rows,
      streak,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
});

// ---------------------------------------------------------------------------
// POST /api/v1/dose-logs/batch — upload doses saved while offline.
// ---------------------------------------------------------------------------
const doseLogSchema = z.object({
  id: z.string().uuid(),
  scheduleId: z.string().uuid(),
  userMedicationId: z.string().uuid(),
  scheduledAt: z.string().datetime({ offset: true }),
  status: z.enum(['taken', 'skipped', 'missed']),
  takenAt: z.string().datetime({ offset: true }).nullable(),
  updatedAt: z.string().datetime({ offset: true }),
  deleted: z.boolean().default(false),
});
const batchSchema = z.object({ logs: z.array(doseLogSchema).max(500) });

syncRouter.post('/dose-logs/batch', requireAuth, validateBody(batchSchema), async (req, res) => {
  const userId = req.user.id;
  const { logs } = req.body;
  if (logs.length === 0) return res.json({ saved: 0 });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Only accept logs for schedules this user actually owns.
    const { rows: owned } = await client.query(
      `SELECT s.id FROM medication_schedules s
       JOIN user_medications m ON m.id = s.user_medication_id
       WHERE m.user_id = $1 AND s.id = ANY($2::uuid[])`,
      [userId, [...new Set(logs.map((l) => l.scheduleId))]],
    );
    const ownedIds = new Set(owned.map((r) => r.id));

    let saved = 0;
    for (const log of logs) {
      if (!ownedIds.has(log.scheduleId)) continue;
      // The same slot sent twice (e.g. a retry after a dropped connection)
      // updates the existing row instead of creating a duplicate.
      await client.query(
        `INSERT INTO dose_logs (id, user_id, schedule_id, user_medication_id, scheduled_at,
                                status, taken_at, deleted_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, CASE WHEN $8 THEN now() END)
         ON CONFLICT (schedule_id, scheduled_at) DO UPDATE
           SET status = EXCLUDED.status,
               taken_at = EXCLUDED.taken_at,
               deleted_at = EXCLUDED.deleted_at`,
        [log.id, userId, log.scheduleId, log.userMedicationId, log.scheduledAt,
          log.status, log.takenAt, log.deleted],
      );
      saved += 1;
    }

    await client.query('COMMIT');
    res.json({ saved, rejected: logs.length - saved });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
});
