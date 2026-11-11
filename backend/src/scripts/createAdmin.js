// npm run admin:create -- admin@example.com "Admin Name" "StrongPassw0rd"
// Creates an admin account (or promotes an existing user) for the web admin panel.
import bcrypt from 'bcryptjs';
import { pool } from '../db.js';

const [email, fullName, password] = process.argv.slice(2);
if (!email || !fullName || !password || password.length < 8) {
  console.error('Usage: npm run admin:create -- <email> "<full name>" <password (8+ chars)>');
  process.exit(1);
}

try {
  const hash = await bcrypt.hash(password, 10);
  await pool.query(
    `INSERT INTO users (email, password_hash, full_name, role)
     VALUES (lower($1), $2, $3, 'admin')
     ON CONFLICT (email) DO UPDATE SET role = 'admin', password_hash = EXCLUDED.password_hash`,
    [email, hash, fullName],
  );
  console.log(`Admin ready: ${email.toLowerCase()}`);
} finally {
  await pool.end();
}
