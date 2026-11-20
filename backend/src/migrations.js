import { readdir, readFile } from 'node:fs/promises';

const dir = new URL('../db/migrations/', import.meta.url);

/**
 * Applies every file in db/migrations in name order. Each one is written to
 * be safe to run again, so no tracking table is needed. The server runs this
 * at start-up, so a deploy never serves code that expects a column the
 * database doesn't have yet.
 */
export async function applyMigrations(pool, log = console.log) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    await pool.query(await readFile(new URL(file, dir), 'utf8'));
    log(`Applied ${file}`);
  }
}
