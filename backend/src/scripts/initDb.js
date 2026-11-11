// npm run db:init — creates all tables from db/schema.sql (run once on an empty database).
import { readFile } from 'node:fs/promises';
import { pool } from '../db.js';

const sql = await readFile(new URL('../../db/schema.sql', import.meta.url), 'utf8');
try {
  await pool.query(sql);
  console.log('Database tables created.');
} catch (err) {
  console.error(`Could not create tables: ${err.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
