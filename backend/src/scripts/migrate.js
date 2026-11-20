// npm run db:migrate — applies every file in db/migrations in name order.
// (The server also does this at start-up; this script is for a new database.)
import { pool } from '../db.js';
import { applyMigrations } from '../migrations.js';

try {
  await applyMigrations(pool);
  console.log('Database is up to date.');
} catch (err) {
  console.error(`Migration failed: ${err.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
