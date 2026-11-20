import { createApp } from './app.js';
import { config } from './config.js';
import { pool } from './db.js';
import { applyMigrations } from './migrations.js';

// Bring the database up to date before answering requests, so pushing new
// code to GitHub (which redeploys Render) is all a schema change needs.
try {
  await applyMigrations(pool, () => {});
  console.log('Database is up to date.');
} catch (err) {
  // Keep serving: most routes still work, and the log says what to fix.
  console.error(`Migration failed: ${err.message}`);
}

createApp().listen(config.port, () => {
  console.log(`Pill Reminder API listening on http://localhost:${config.port}/api/v1`);
});
