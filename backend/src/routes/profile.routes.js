import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';

/**
 * The user's own health profile: date of birth, gender, conditions and
 * allergies. Only the user can read or change it; admins only ever see
 * counts across all users (see /admin/analytics).
 */
export const profileRouter = Router();

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use YYYY-MM-DD.');

const profileSchema = z.object({
  dateOfBirth: isoDate
    .refine((d) => d >= '1900-01-01' && d <= new Date().toISOString().slice(0, 10), {
      message: 'Enter a real date of birth.',
    })
    .nullish()
    .transform((v) => v ?? null),
  gender: z.enum(['female', 'male', 'unspecified']).nullish().transform((v) => v ?? null),
  conditions: z
    .array(z.string().trim().min(2, 'Too short.').max(60, 'Use 60 characters or fewer.'))
    .max(20, 'Up to 20 conditions.')
    .default([])
    // Same condition typed twice ("Asthma", "asthma") is kept once, as first typed.
    .transform((list) => list.filter((c, i) =>
      list.findIndex((x) => x.toLowerCase() === c.toLowerCase()) === i)),
  allergies: z.string().trim().max(255, 'Use 255 characters or fewer.').nullish()
    .transform((v) => v || null),
});

const toProfile = (u) => ({
  dateOfBirth: u.date_of_birth, // DATE comes back as "yyyy-MM-dd" (see db.js)
  gender: u.gender,
  conditions: u.conditions ?? [],
  allergies: u.allergies,
  updatedAt: u.profile_updated_at,
});

// GET /api/v1/me/profile
profileRouter.get('/me/profile', requireAuth, async (req, res) => {
  const { rows: [u] } = await query(
    'SELECT date_of_birth, gender, conditions, allergies, profile_updated_at FROM users WHERE id = $1',
    [req.user.id],
  );
  if (!u) throw new HttpError(401, 'Account not found.');
  res.json({ profile: toProfile(u) });
});

// PUT /api/v1/me/profile — the app sends the whole profile each time.
profileRouter.put('/me/profile', requireAuth, validateBody(profileSchema), async (req, res) => {
  const p = req.body;
  const { rows: [u] } = await query(
    `UPDATE users SET date_of_birth = $2, gender = $3, conditions = $4, allergies = $5,
            profile_updated_at = now()
     WHERE id = $1
     RETURNING date_of_birth, gender, conditions, allergies, profile_updated_at`,
    [req.user.id, p.dateOfBirth, p.gender, p.conditions, p.allergies],
  );
  if (!u) throw new HttpError(401, 'Account not found.');
  res.json({ profile: toProfile(u) });
});
