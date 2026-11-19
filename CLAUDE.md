# Pill Reminder — project notes for Claude Code

Group assignment for CSS3344 Mobile Application Development (UTS Sarawak).
Android app in Flutter + Node.js backend + PostgreSQL. ITPM group constraint:
**poor internet connectivity**, so the app is offline-first.

## Repo layout
- `app/` — Flutter app (BLoC/Cubit, flutter_bloc 9, Equatable)
  - `lib/core/` — theme tokens, Dio API client + JWT refresh interceptor, SQLite (sqflite, DB version 3),
    sync outbox, notifications, validators, shared widgets (incl. `confirm_dialog.dart`)
  - `lib/features/` — auth, dashboard (Today), medications (list tab + add/edit form + photo), reminders,
    facilities (Nearby map), home (bottom nav: Today / Medications / Nearby)
  - `test/` — unit/widget tests; `medication_local_source_test.dart` and `guest_mode_test.dart` run real SQLite via
    the dev-only `sqflite_common_ffi` (each test file sets its own temp database folder)
- `release/` — exported APKs (ignored by git) + README with the build command
- `backend/` — Node 22, Express 5, pg, bcryptjs, jsonwebtoken, zod 4, multer 2 (memoryStorage), helmet
  - `src/routes/` auth, sync, medications (+ photo upload), facilities (nearby), admin (`/api/v1/admin/*`)
  - `src/services/` overpass (OpenStreetMap), facilityStore, streak
  - `db/schema.sql` + `db/migrations/` (idempotent; run with `npm run db:migrate`)
- `admin/` — Web Admin panel: React 19 + Vite 8, react-router-dom 7 (HashRouter), lucide-react icons, plain CSS, no UI library
  - `src/api.js` fetch client + token refresh, `src/auth.jsx` session state, `src/ui.jsx` shared parts (Button, Dialog, Toast, Field, Pagination)
  - `src/pages/` Login, Overview, Users, Catalog (Medications), Activity
  - `src/styles.css` — design tokens copied from `app/lib/core/theme/app_tokens.dart`; change both together
- `render.yaml` — Render Blueprint (API from `backend`, static admin site from `admin`), `DEPLOY.md` — deployment guide
- `.claude/launch.json` — starts `backend` (port 3000) and `admin` (port 5173) for local previews

## Live setup
- API: https://pill-reminder-api.onrender.com/api/v1 (Render free plan, Singapore; ~1 min cold start)
- DB: Neon PostgreSQL (Singapore). Facilities table holds 427 Sarawak places imported from OSM.
- Pushing to `main` on GitHub redeploys Render automatically.

## Commands
App (from `app/`):
- Run against the live server:
  `flutter run --dart-define=DEMO_DATA=false --dart-define=API_BASE_URL=https://pill-reminder-api.onrender.com/api/v1`
- Release APK: same flags with `flutter build apk --release`
- Tests: `flutter test`
- Default API_BASE_URL is `http://10.0.2.2:3000/api/v1` (emulator → laptop). DEMO_DATA=true uses in-memory demo repositories.

Backend (from `backend/`):
- `npm ci`, `npm run dev`, `npm run db:init`, `npm run db:migrate`,
  `npm run facilities:import -- --region Sarawak`, `npm run admin:create`, `npm run catalog:seed`
- Config comes from `.env` (see `.env.example`): DATABASE_URL, JWT_ACCESS_SECRET, ACCESS_TOKEN_TTL, REFRESH_TOKEN_TTL_DAYS, CORS_ORIGINS

Admin panel (from `admin/`):
- `npm install`, `npm run dev` (http://localhost:5173, fixed port because of CORS), `npm run build`
- `VITE_API_BASE_URL` in `admin/.env.local` picks the server; the default is `http://localhost:3000/api/v1`

## Key design decisions (keep these)
- Offline-first: the app writes SQLite first; rows carry `sync_state` pending/synced; SyncPusher uploads the outbox when online.
  Server sync uses client-generated UUIDs and upserts; dose_logs unique on (schedule_id, scheduled_at).
- Auth: 15-min access JWT, 30-day refresh tokens stored as SHA-256 hashes, rotated on use, reuse revokes all sessions.
  The app only logs the user out on a 401/403 from the refresh call — never because it is offline.
- Dio timeouts: connect 8s, receive 75s (Render cold start). Login/register show a "Waking up the server…" hint after 5s.
- Notifications: flutter_local_notifications ^22.3.3 (v23 needs AGP 9 — do not upgrade), rolling 7-day plan,
  30-min follow-up, stable FNV-1a ids, max 200 scheduled. Android needs core library desugaring and `res/raw/keep.xml`.
- Nearby: flutter_map 8 + OSM tiles, geolocator 14. Backend serves saved facilities first; live Overpass lookup
  (3 servers × 8s) only when fewer than 5 saved places are in range, and saves results. Public/private ownership is a heuristic.
- Confirmations ("double confirmation", asked for by the user on 2026-11-12): marking a dose taken, skipping a dose,
  saving an edit and deleting a medication each open `showConfirmDialog` first. Dismissing the dialog never confirms.
  The notification's own "Mark as taken" button stays one tap.
- Edit/delete medication: local rows carry `deleted` (0/1). A delete hides the row at once, uploads `deleted: true`
  through `/medications/batch`, and the row is removed locally only after that upload. On edit, a reminder time that
  stays keeps its schedule row (so today's dose log survives); removed times are soft-deleted. A saved photo can be
  replaced but not removed (the server has no photo-delete endpoint).
- Guest mode (asked for by the user on 2026-11-19): "Continue without an account" on the login screen (with a
  confirmation). `AuthUser.guest` (id `guest`) is saved in secure storage with no tokens. The dashboard repository's
  `hasAccount` check (refresh token present) makes `sync()` return `SyncOutcome.localOnly` without any network call;
  pending rows stay in the outbox, so a guest who creates an account or logs in (account sheet → `fromGuest` forms)
  keeps everything and it uploads at the next sync. "Delete guest data" wipes the phone (confirmed). Streak row is
  hidden when there is no server streak. `GET /facilities/nearby` is public (rate-limited 60 / 10 min per IP via
  `middleware/rateLimit.js`) so guests can use Nearby; everything else still needs a login.
- Photos are stored as bytea in `medication_photos` (Render's disk is ephemeral) and served at `/uploads/:file`.
- Admin API: every `/admin` request re-checks role + status in the database (not just the JWT); an admin cannot suspend,
  demote or delete themself; every change writes `admin_audit_logs` in the same transaction; admins see counts, never
  a user's medication names. Admin panel keeps the refresh token in `sessionStorage` and shares one in-flight refresh call
  (a refresh token used twice revokes every session).

## UI rules (strict — from the project brief)
- No "AI slop": no random gradients, glows, heavy shadows, filler badges, or random italics.
- One accent colour (`AppColors.accent` #0B7A5E) for primary actions; high-contrast, concise headlines.
- Tabular figures for all numbers (`.tabular` TextStyle extension).
- Group with whitespace (AppSpace), not borders. Nested radius: inner = outer − padding (`AppRadius.cardInner`).
- One icon family, uniform size/weight.
- Every async action has an explicit loading state and SnackBar feedback.
- Use the tokens in `lib/core/theme/` rather than hard-coded values.

## Security rules
- Never commit `.env`, and never print, log or paste the Neon connection string or any password.
- Schema changes go in a new file under `backend/db/migrations/`, never by editing the live DB by hand.

## Status / next work
- Done: all six brief features (JWT auth, BLoC dashboard, GPS Nearby, camera/gallery + validation, SQLite offline cache, notifications); backend deployed.
  Web Admin Panel built and tested locally (users, global medication database, activity log).
- To do: deploy the admin panel (push, then sync the Render Blueprint; see DEPLOY.md step 7), let the app's
  "Add medication" form search the catalog (needs a user-facing `GET /catalog` endpoint), admin screen for facilities,
  technical report, optional Play Store release (needs a real upload key; release currently signs with the debug key),
  fix import so names starting with "Klinik" are always typed as clinics.

## Writing preferences (for reports/docs)
- Middle-school vocabulary with complex sentence structures; figure references like "Figure 3.1.6".
