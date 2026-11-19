import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAdmin, requireAuth } from '../middleware/auth.js';
import { validateBody } from '../middleware/validate.js';
import { DOSAGE_FORMS, DOSAGE_UNITS } from './medications.routes.js';

/**
 * Everything the Web Admin panel needs, under /api/v1/admin.
 *   Users    — list, view, edit, suspend, sign out everywhere, delete
 *   Catalog  — the global medication database (create, edit, delete)
 *   Activity — who changed what (admin_audit_logs)
 * Every change is written to admin_audit_logs in the same transaction.
 */
export const adminRouter = Router();

// The access token says "admin" for up to 15 minutes after it was issued.
// Asking the database on every admin request means an admin who was demoted
// or suspended a minute ago is locked out immediately, not 15 minutes later.
async function requireActiveAdmin(req, res, next) {
  const { rows: [me] } = await query('SELECT role, status FROM users WHERE id = $1', [req.user.id]);
  if (!me || me.role !== 'admin' || me.status !== 'active') throw new HttpError(403, 'Admins only.');
  next();
}

adminRouter.use(requireAuth, requireAdmin, requireActiveAdmin);

// A malformed id can never match a row, so answer 404 before touching the database.
adminRouter.param('id', (req, res, next, id) => {
  if (!z.string().uuid().safeParse(id).success) throw new HttpError(404, 'Not found.');
  next();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const pageQuery = {
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().trim().max(100).default(''),
};

function parseQuery(schema, req) {
  const result = schema.safeParse(req.query);
  if (!result.success) throw new HttpError(422, 'Invalid filter.');
  return result.data;
}

/** "50%" typed in the search box must match a literal %, not "anything". */
const likePattern = (search) => `%${search.replace(/[\\%_]/g, '\\$&')}%`;

const paged = (rows, { page, pageSize }, map) => ({
  items: rows.map(map),
  total: rows[0]?.total ?? 0,
  page,
  pageSize,
});

function audit(db, adminId, action, targetTable, targetId, details) {
  return db.query(
    `INSERT INTO admin_audit_logs (admin_id, action, target_table, target_id, details)
     VALUES ($1, $2, $3, $4, $5)`,
    [adminId, action, targetTable, targetId, details],
  );
}

// ---------------------------------------------------------------------------
// GET /admin/overview — the numbers on the first screen
// ---------------------------------------------------------------------------
adminRouter.get('/overview', async (req, res) => {
  const { rows: [n] } = await query(`
    SELECT
      (SELECT count(*)::int FROM users)                                              AS accounts,
      (SELECT count(*)::int FROM users WHERE created_at > now() - interval '7 days') AS new_accounts_7d,
      (SELECT count(*)::int FROM users WHERE status = 'suspended')                   AS suspended,
      (SELECT count(*)::int FROM medication_catalog)                                 AS catalog_total,
      (SELECT count(*)::int FROM medication_catalog WHERE is_active)                 AS catalog_active,
      (SELECT count(*)::int FROM user_medications WHERE deleted_at IS NULL)          AS medications_tracked,
      (SELECT count(*)::int FROM dose_logs
        WHERE deleted_at IS NULL AND scheduled_at > now() - interval '7 days')       AS doses_7d,
      (SELECT count(*)::int FROM dose_logs
        WHERE deleted_at IS NULL AND scheduled_at > now() - interval '7 days'
          AND status = 'taken')                                                      AS taken_7d`);
  res.json({
    accounts: n.accounts,
    newAccounts7d: n.new_accounts_7d,
    suspended: n.suspended,
    catalogTotal: n.catalog_total,
    catalogActive: n.catalog_active,
    medicationsTracked: n.medications_tracked,
    doses7d: n.doses_7d,
    taken7d: n.taken_7d,
  });
});

// ---------------------------------------------------------------------------
// Users
// Admins see counts (medications, doses), never the medication names: what a
// person takes is health information the admin does not need to do this job.
// ---------------------------------------------------------------------------
const USER_COLUMNS = `
  u.id, u.email, u.full_name, u.role, u.status, u.timezone, u.last_login_at, u.created_at,
  (SELECT count(*)::int FROM user_medications m
    WHERE m.user_id = u.id AND m.deleted_at IS NULL)                               AS medication_count,
  (SELECT count(*)::int FROM refresh_tokens t
    WHERE t.user_id = u.id AND t.revoked_at IS NULL AND t.expires_at > now())      AS session_count,
  (SELECT count(*)::int FROM dose_logs d
    WHERE d.user_id = u.id AND d.deleted_at IS NULL
      AND d.scheduled_at > now() - interval '30 days')                             AS doses_30d,
  (SELECT count(*)::int FROM dose_logs d
    WHERE d.user_id = u.id AND d.deleted_at IS NULL
      AND d.scheduled_at > now() - interval '30 days' AND d.status = 'taken')      AS taken_30d`;

const toAdminUser = (u) => ({
  id: u.id,
  email: u.email,
  fullName: u.full_name,
  role: u.role,
  status: u.status,
  timezone: u.timezone,
  lastLoginAt: u.last_login_at,
  createdAt: u.created_at,
  medicationCount: u.medication_count,
  sessionCount: u.session_count,
  doses30d: u.doses_30d,
  taken30d: u.taken_30d,
});

async function loadUser(db, id) {
  const { rows: [user] } = await db.query(`SELECT ${USER_COLUMNS} FROM users u WHERE u.id = $1`, [id]);
  if (!user) throw new HttpError(404, 'User not found.');
  return toAdminUser(user);
}

const userListQuery = z.object({
  ...pageQuery,
  status: z.enum(['active', 'suspended']).optional(),
  role: z.enum(['user', 'admin']).optional(),
});

// GET /admin/users?search=&status=&role=&page=&pageSize=
adminRouter.get('/users', async (req, res) => {
  const q = parseQuery(userListQuery, req);
  const { rows } = await query(
    `SELECT ${USER_COLUMNS}, count(*) OVER()::int AS total
     FROM users u
     WHERE ($1::text = '' OR u.email ILIKE $2 OR u.full_name ILIKE $2)
       AND ($3::account_status IS NULL OR u.status = $3::account_status)
       AND ($4::user_role IS NULL OR u.role = $4::user_role)
     ORDER BY u.created_at DESC, u.id
     LIMIT $5 OFFSET $6`,
    [q.search, likePattern(q.search), q.status ?? null, q.role ?? null,
      q.pageSize, (q.page - 1) * q.pageSize],
  );
  res.json(paged(rows, q, toAdminUser));
});

// GET /admin/users/:id
adminRouter.get('/users/:id', async (req, res) => {
  res.json({ user: await loadUser({ query }, req.params.id) });
});

const userPatchSchema = z
  .object({
    fullName: z.string().trim().min(2, 'Enter the full name.').max(120, 'Use 120 characters or fewer.').optional(),
    role: z.enum(['user', 'admin']).optional(),
    status: z.enum(['active', 'suspended']).optional(),
  })
  .refine((p) => Object.values(p).some((v) => v !== undefined), { message: 'Nothing to change.' });

// PATCH /admin/users/:id — edit the name, change the role, suspend or reactivate.
adminRouter.patch('/users/:id', validateBody(userPatchSchema), async (req, res) => {
  const { id } = req.params;
  const patch = req.body;

  // Stops the last admin locking everyone out: there is always at least the
  // admin who is making this request.
  const hurtsSelf = (patch.role && patch.role !== 'admin') || patch.status === 'suspended';
  if (id === req.user.id && hurtsSelf) {
    throw new HttpError(409, "You can't suspend or demote your own account.");
  }

  const user = await withTransaction(async (db) => {
    const { rows: [before] } = await db.query('SELECT * FROM users WHERE id = $1 FOR UPDATE', [id]);
    if (!before) throw new HttpError(404, 'User not found.');

    const { rows: [after] } = await db.query(
      `UPDATE users SET
         full_name = COALESCE($2, full_name),
         role      = COALESCE($3::user_role, role),
         status    = COALESCE($4::account_status, status)
       WHERE id = $1 RETURNING *`,
      [id, patch.fullName ?? null, patch.role ?? null, patch.status ?? null],
    );

    const changes = {};
    for (const column of ['full_name', 'role', 'status']) {
      if (before[column] !== after[column]) changes[column] = { from: before[column], to: after[column] };
    }

    if (changes.status?.to === 'suspended') {
      // End every session now. The phone finds out at its next token refresh
      // (15 minutes at most) and returns to the login screen.
      await db.query(
        'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [id],
      );
    }

    if (Object.keys(changes).length > 0) {
      const action = changes.status
        ? (changes.status.to === 'suspended' ? 'user.suspend' : 'user.reactivate')
        : changes.role ? 'user.role' : 'user.update';
      await audit(db, req.user.id, action, 'users', id, { label: after.email, changes });
    }
    return loadUser(db, id);
  });

  res.json({ user });
});

// POST /admin/users/:id/sign-out — ends every session (e.g. a lost phone).
adminRouter.post('/users/:id/sign-out', async (req, res) => {
  const { id } = req.params;
  const result = await withTransaction(async (db) => {
    const { rows: [target] } = await db.query('SELECT email FROM users WHERE id = $1', [id]);
    if (!target) throw new HttpError(404, 'User not found.');
    const { rowCount } = await db.query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()',
      [id],
    );
    await audit(db, req.user.id, 'user.sign_out', 'users', id, { label: target.email, sessions: rowCount });
    return { sessionsEnded: rowCount, user: await loadUser(db, id) };
  });
  res.json(result);
});

// DELETE /admin/users/:id — permanent: removes the account and all its data.
adminRouter.delete('/users/:id', async (req, res) => {
  const { id } = req.params;
  if (id === req.user.id) throw new HttpError(409, "You can't delete your own account.");

  await withTransaction(async (db) => {
    const { rows: [target] } = await db.query('SELECT email FROM users WHERE id = $1 FOR UPDATE', [id]);
    if (!target) throw new HttpError(404, 'User not found.');

    // The audit trail must outlive the people in it, so an admin who has
    // already made changes can be suspended but not erased.
    const { rows: [history] } = await db.query(
      'SELECT 1 FROM admin_audit_logs WHERE admin_id = $1 LIMIT 1',
      [id],
    );
    if (history) {
      throw new HttpError(409, 'This admin has activity on record. Suspend the account instead.');
    }

    await db.query('DELETE FROM users WHERE id = $1', [id]); // cascades to medications, doses, sessions
    await audit(db, req.user.id, 'user.delete', 'users', id, { label: target.email });
  });
  res.status(204).end();
});

// ---------------------------------------------------------------------------
// Global medication database (medication_catalog)
// ---------------------------------------------------------------------------
const optionalText = (max) =>
  z.string().trim().max(max, `Use ${max} characters or fewer.`).nullish()
    .transform((v) => v || null); // '' and undefined are stored as NULL

const catalogSchema = z
  .object({
    genericName: z.string({ error: 'Enter the generic name.' }).trim()
      .min(2, 'Enter the generic name.').max(150, 'Use 150 characters or fewer.'),
    brandName: optionalText(150),
    form: z.enum(DOSAGE_FORMS, { error: 'Choose a form.' }),
    strength: z.number({ error: 'Enter a number.' }).positive('Strength must be more than 0.')
      .max(100000, 'That strength is too large.').nullish().transform((v) => v ?? null),
    strengthUnit: z.enum(DOSAGE_UNITS, { error: 'Choose a unit.' }).nullish().transform((v) => v ?? null),
    description: optionalText(2000),
    warnings: optionalText(2000),
    isActive: z.boolean().default(true),
  })
  .refine((m) => m.strength === null || m.strengthUnit !== null, {
    message: 'Choose a unit.', path: ['strengthUnit'],
  })
  .refine((m) => m.strengthUnit === null || m.strength !== null, {
    message: 'Enter the strength.', path: ['strength'],
  });

const toCatalogItem = (c) => ({
  id: c.id,
  genericName: c.generic_name,
  brandName: c.brand_name,
  form: c.form,
  strength: c.strength === null ? null : Number(c.strength), // NUMERIC arrives as "500.000"
  strengthUnit: c.strength_unit,
  description: c.description,
  warnings: c.warnings,
  isActive: c.is_active,
  updatedAt: c.updated_at,
});

const catalogLabel = (m) =>
  [m.genericName, m.strength === null ? null : `${m.strength} ${m.strengthUnit}`, m.form]
    .filter(Boolean).join(' · ');

/** The table's UNIQUE key ignores rows with an empty brand, so check here too. */
async function assertNotDuplicate(db, m, ownId = null) {
  const { rows: [clash] } = await db.query(
    `SELECT 1 FROM medication_catalog
     WHERE lower(generic_name) = lower($1)
       AND lower(brand_name) IS NOT DISTINCT FROM lower($2::text)
       AND form = $3::dosage_form
       AND strength IS NOT DISTINCT FROM $4::numeric
       AND strength_unit IS NOT DISTINCT FROM $5::text
       AND id IS DISTINCT FROM $6::uuid`,
    [m.genericName, m.brandName, m.form, m.strength, m.strengthUnit, ownId],
  );
  if (clash) {
    throw new HttpError(409, 'That medication is already in the database.', {
      genericName: 'An entry with the same name, brand, form and strength already exists.',
    });
  }
}

const catalogListQuery = z.object({
  ...pageQuery,
  form: z.enum(DOSAGE_FORMS).optional(),
  status: z.enum(['active', 'hidden']).optional(),
});

// GET /admin/catalog?search=&form=&status=&page=&pageSize=
adminRouter.get('/catalog', async (req, res) => {
  const q = parseQuery(catalogListQuery, req);
  const isActive = q.status === undefined ? null : q.status === 'active';
  const { rows } = await query(
    `SELECT *, count(*) OVER()::int AS total
     FROM medication_catalog
     WHERE ($1::text = '' OR generic_name ILIKE $2 OR brand_name ILIKE $2)
       AND ($3::dosage_form IS NULL OR form = $3::dosage_form)
       AND ($4::boolean IS NULL OR is_active = $4::boolean)
     ORDER BY lower(generic_name), strength NULLS FIRST, id
     LIMIT $5 OFFSET $6`,
    [q.search, likePattern(q.search), q.form ?? null, isActive, q.pageSize, (q.page - 1) * q.pageSize],
  );
  res.json(paged(rows, q, toCatalogItem));
});

// POST /admin/catalog
adminRouter.post('/catalog', validateBody(catalogSchema), async (req, res) => {
  const m = req.body;
  const item = await withTransaction(async (db) => {
    await assertNotDuplicate(db, m);
    const { rows: [row] } = await db.query(
      `INSERT INTO medication_catalog
         (generic_name, brand_name, form, strength, strength_unit, description, warnings, is_active, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [m.genericName, m.brandName, m.form, m.strength, m.strengthUnit, m.description, m.warnings,
        m.isActive, req.user.id],
    );
    await audit(db, req.user.id, 'catalog.create', 'medication_catalog', row.id, { label: catalogLabel(m) });
    return toCatalogItem(row);
  });
  res.status(201).json({ item });
});

// PUT /admin/catalog/:id — the edit form sends every field.
adminRouter.put('/catalog/:id', validateBody(catalogSchema), async (req, res) => {
  const m = req.body;
  const item = await withTransaction(async (db) => {
    await assertNotDuplicate(db, m, req.params.id);
    const { rows: [row] } = await db.query(
      `UPDATE medication_catalog SET
         generic_name = $2, brand_name = $3, form = $4, strength = $5, strength_unit = $6,
         description = $7, warnings = $8, is_active = $9
       WHERE id = $1 RETURNING *`,
      [req.params.id, m.genericName, m.brandName, m.form, m.strength, m.strengthUnit,
        m.description, m.warnings, m.isActive],
    );
    if (!row) throw new HttpError(404, 'Medication not found.');
    await audit(db, req.user.id, 'catalog.update', 'medication_catalog', row.id, { label: catalogLabel(m) });
    return toCatalogItem(row);
  });
  res.json({ item });
});

// DELETE /admin/catalog/:id — users who picked this entry keep their own copy
// (user_medications.catalog_id is simply cleared).
adminRouter.delete('/catalog/:id', async (req, res) => {
  await withTransaction(async (db) => {
    const { rows: [row] } = await db.query(
      'DELETE FROM medication_catalog WHERE id = $1 RETURNING *',
      [req.params.id],
    );
    if (!row) throw new HttpError(404, 'Medication not found.');
    await audit(db, req.user.id, 'catalog.delete', 'medication_catalog', row.id,
      { label: catalogLabel(toCatalogItem(row)) });
  });
  res.status(204).end();
});

// ---------------------------------------------------------------------------
// GET /admin/activity?page=&pageSize= — the audit trail, newest first
// ---------------------------------------------------------------------------
adminRouter.get('/activity', async (req, res) => {
  const q = parseQuery(z.object(pageQuery), req);
  const { rows } = await query(
    `SELECT l.id, l.action, l.target_table, l.details, l.created_at,
            a.full_name AS admin_name, count(*) OVER()::int AS total
     FROM admin_audit_logs l JOIN users a ON a.id = l.admin_id
     ORDER BY l.created_at DESC, l.id DESC
     LIMIT $1 OFFSET $2`,
    [q.pageSize, (q.page - 1) * q.pageSize],
  );
  res.json(paged(rows, q, (l) => ({
    id: Number(l.id),
    action: l.action,
    targetTable: l.target_table,
    label: l.details?.label ?? null,
    details: l.details,
    adminName: l.admin_name,
    createdAt: l.created_at,
  })));
});
