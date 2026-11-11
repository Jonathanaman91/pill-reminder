import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';

export const authRouter = Router();

// ---------------------------------------------------------------------------
// Validation rules — the Flutter app checks the same rules before sending.
// ---------------------------------------------------------------------------
const email = z
  .string({ error: 'Enter your email.' })
  .trim()
  .toLowerCase()
  .email('Enter a valid email address.')
  .max(255);

const password = z
  .string({ error: 'Enter a password.' })
  .min(8, 'Use at least 8 characters.')
  .max(72, 'Use 72 characters or fewer.') // bcrypt only reads the first 72 bytes
  .regex(/[A-Za-z]/, 'Include at least one letter.')
  .regex(/[0-9]/, 'Include at least one number.');

const registerSchema = z.object({
  fullName: z
    .string({ error: 'Enter your name.' })
    .trim()
    .min(2, 'Enter your full name.')
    .max(120, 'Use 120 characters or fewer.'),
  email,
  password,
  timezone: z.string().max(64).optional(),
});

const loginSchema = z.object({
  email,
  password: z.string({ error: 'Enter your password.' }).min(1, 'Enter your password.'),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(20),
  deviceName: z.string().max(120).optional(),
});

// ---------------------------------------------------------------------------
// Token helpers
// ---------------------------------------------------------------------------
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

const toPublicUser = (u) => ({
  id: u.id,
  email: u.email,
  fullName: u.full_name,
  role: u.role,
  timezone: u.timezone,
});

/**
 * Access token: short-lived JWT, never stored on the server.
 * Refresh token: random string; only its SHA-256 hash is stored, so a leaked
 * database cannot be used to log in.
 */
async function issueTokens(db, user, deviceName) {
  const accessToken = jwt.sign({ sub: user.id, role: user.role }, config.jwtAccessSecret, {
    expiresIn: config.accessTokenTtl,
  });
  const refreshToken = crypto.randomBytes(48).toString('base64url');
  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device_name, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(days => $4))`,
    [user.id, sha256(refreshToken), deviceName ?? null, config.refreshTokenTtlDays],
  );
  return { accessToken, refreshToken };
}

// Compared against when the email does not exist, so a wrong email and a wrong
// password take the same time (attackers cannot discover who is registered).
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password-1', 10);

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// POST /api/v1/auth/register
authRouter.post('/register', validateBody(registerSchema), async (req, res) => {
  const { fullName, email, password, timezone } = req.body;
  const passwordHash = await bcrypt.hash(password, 10);

  const result = await withTransaction(async (db) => {
    const inserted = await db.query(
      `INSERT INTO users (email, password_hash, full_name, timezone)
       VALUES ($1, $2, $3, COALESCE($4, 'Asia/Kuala_Lumpur'))
       ON CONFLICT (email) DO NOTHING
       RETURNING *`,
      [email, passwordHash, fullName, timezone ?? null],
    );
    if (inserted.rowCount === 0) {
      throw new HttpError(409, 'That email is already registered.', {
        email: 'That email is already registered. Try logging in.',
      });
    }
    const user = inserted.rows[0];
    return { user: toPublicUser(user), ...(await issueTokens(db, user)) };
  });

  res.status(201).json(result);
});

// POST /api/v1/auth/login
authRouter.post('/login', validateBody(loginSchema), async (req, res) => {
  const { rows } = await query('SELECT * FROM users WHERE email = $1', [req.body.email]);
  const user = rows[0];
  const ok = await bcrypt.compare(req.body.password, user?.password_hash ?? DUMMY_HASH);

  if (!user || !ok) throw new HttpError(401, 'Incorrect email or password.');
  if (user.status === 'suspended') {
    throw new HttpError(403, 'This account has been suspended. Contact support.');
  }

  await query('UPDATE users SET last_login_at = now() WHERE id = $1', [user.id]);
  res.json({ user: toPublicUser(user), ...(await issueTokens({ query }, user)) });
});

// POST /api/v1/auth/refresh — swap a refresh token for a NEW pair (rotation).
authRouter.post('/refresh', validateBody(refreshSchema), async (req, res) => {
  const tokenHash = sha256(req.body.refreshToken);

  const result = await withTransaction(async (db) => {
    const { rows } = await db.query(
      `SELECT rt.*, u.status, u.role, u.email, u.full_name, u.timezone
       FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1
       FOR UPDATE OF rt`,
      [tokenHash],
    );
    const token = rows[0];
    if (!token) throw new HttpError(401, 'Session expired. Please log in again.');

    if (token.revoked_at) {
      // An old token was used again. Either the app retried, or someone
      // stole it. To be safe, end every session for this user.
      await db.query(
        'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [token.user_id],
      );
      return null;
    }
    if (token.expires_at < new Date() || token.status !== 'active') return null;

    await db.query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [token.id]);
    const user = { id: token.user_id, role: token.role, email: token.email,
      full_name: token.full_name, timezone: token.timezone };
    return {
      user: toPublicUser(user),
      ...(await issueTokens(db, user, req.body.deviceName ?? token.device_name)),
    };
  });

  if (!result) throw new HttpError(401, 'Session expired. Please log in again.');
  res.json(result);
});

// POST /api/v1/auth/logout — ends this device's session.
authRouter.post('/logout', validateBody(refreshSchema), async (req, res) => {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL',
    [sha256(req.body.refreshToken)],
  );
  res.status(204).end();
});

// GET /api/v1/auth/me
authRouter.get('/me', requireAuth, async (req, res) => {
  const { rows } = await query('SELECT * FROM users WHERE id = $1', [req.user.id]);
  if (!rows[0]) throw new HttpError(401, 'Account not found.');
  res.json({ user: toPublicUser(rows[0]) });
});
