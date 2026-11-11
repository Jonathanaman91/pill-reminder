// npm run db:migrate — applies every file in db/migrations in name order.
// Each migration is written to be safe to run again, so this needs no tracking table.
import { readdir, readFile } from 'node:fs/promises';
import { pool } from '../db.js';

const dir = new URL('../../db/migrations/', import.meta.url);
try {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    await pool.query(await readFile(new URL(file, dir), 'utf8'));
    console.log(`Applied ${file}`);
  }
  console.log('Database is up to date.');
} catch (err) {
  console.error(`Migration failed: ${err.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
