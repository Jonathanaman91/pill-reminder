import pg from 'pg';
import { config } from './config.js';

// Return DATE ("2026-11-11") and NUMERIC ("500.000") columns as plain strings.
// Without this, pg turns DATE into a JS Date at the SERVER's midnight, which
// shifts the day when the server and the user are in different timezones.
pg.types.setTypeParser(1082, (v) => v); // DATE

/**
 * Neon gives connection strings ending in `?sslmode=require&channel_binding=require`.
 * pg already treats `require` as full certificate checking; saying so
 * explicitly avoids a warning on every start. `channel_binding` isn't used by pg.
 */
export function normaliseDatabaseUrl(raw) {
  try {
    const url = new URL(raw);
    if (url.searchParams.get('sslmode') === 'require') url.searchParams.set('sslmode', 'verify-full');
    url.searchParams.delete('channel_binding');
    return url.toString();
  } catch {
    return raw; // not a URL we understand: pass it through unchanged
  }
}

export const pool = new pg.Pool({
  connectionString: normaliseDatabaseUrl(config.databaseUrl),
  // Hosted databases (Neon) close idle connections; don't hold them forever.
  idleTimeoutMillis: 30_000,
  max: 10,
});

// A dropped idle connection must not crash the server.
pool.on('error', (err) => console.warn(`Database connection dropped: ${err.message}`));

export const query = (text, params) => pool.query(text, params);

/** Runs `work(client)` inside BEGIN/COMMIT, rolling back on any error. */
export async function withTransaction(work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
