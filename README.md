# Pill Reminder — CSS3344 Mobile Application Development

Offline-first pill reminder for Android (Flutter) with a Node.js + PostgreSQL
REST API and a React web admin panel.

```
pill-reminder/
├── app/       Flutter Android app      (done: all 6 features)
├── backend/   Express REST API         (done: auth, sync, medications, photos, nearby places, admin)
└── admin/     React + Vite web admin   (done: users, global medication database, activity log)
```

## 1. Run the app with demo data (no backend needed)

```bash
cd app
flutter create --org my.edu.uts --platforms android .   # only the first time
flutter pub get
flutter test
flutter run
```

Delete `app/test/widget_test.dart` after `flutter create`, because it tests a
`MyApp` class this project does not have.

Demo login rules:

| Try | What happens |
|---|---|
| Any valid email + password | Logs in |
| Password `wrongpass1` | "Incorrect email or password." |
| Register `taken@example.com` | "Already registered" under the email box |
| Email `offline@example.com` | The no-internet message |

`flutter run --dart-define=DEMO_OFFLINE=true` previews the dashboard's offline line.

Needs the current Flutter stable (Dart 3.11). Run `flutter upgrade` if
`pub get` complains about the SDK version.

## 1b. One-time Android setup for dose alarms

Dose alarms use `flutter_local_notifications`, which needs three small edits
inside `app/android/`. Do them once; `flutter create` does not do them for you.

**A. `android/app/build.gradle.kts`** — add the two marked lines:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true          // ← add
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {                                         // ← add this block
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

(Keep everything else in the file. If your file is `build.gradle` without
`.kts`, use `coreLibraryDesugaringEnabled true` and
`coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`.)

**B. `android/app/src/main/AndroidManifest.xml`** — permissions go right after
`<manifest …>`, receivers go inside `<application …>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.INTERNET"/>

    <application ...>
        <!-- existing <activity> etc. stays here -->

        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
    </application>
</manifest>
```

**C. Notification icon** — copy `app/android/app/src/main/res/drawable/ic_stat_pill.xml`
from this zip into the same folder of your project (only that one file — do
not replace the whole `android` folder). Without it the app falls back to its
launcher icon, which Android shows as a grey square.

### How dose alarms work

- On login, and every time medications or doses change, the app schedules
  the next **7 days** of reminders: one at each dose time and a follow-up
  **30 minutes** later ("Did you take Metformin?").
- Taking or skipping a dose cancels its follow-up and clears its alert.
- The alert has a **Mark as taken** button. Tapping it opens the app and
  records the dose; the dashboard updates straight away.
- Alarms are kept by Android, so they fire with the app closed and are
  restored after a reboot (`RECEIVE_BOOT_COMPLETED`).
- Medication names are hidden on a locked screen (`visibility: private`),
  because they are health information.
- If notifications or "Alarms & reminders" are turned off, a banner on the
  dashboard explains it and opens the right setting. Without exact alarms,
  reminders still come, just up to a few minutes late.
- **Test:** Account (person icon) → Reminders → **Test** sends a sample alert
  10 seconds later. Close the app to see it arrive anyway.

## 1c. One-time Android setup for the Nearby map

**A. `AndroidManifest.xml`** — add next to the other permissions:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

and inside the `<queries>` block near the bottom of the file (Flutter already
created one; add these `<intent>`s next to the existing one). Without them
Android 11+ hides the maps and phone apps from us, so **Directions** and
**Call** would do nothing:

```xml
<queries>
    <!-- existing PROCESS_TEXT intent stays -->
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <data android:scheme="geo"/>
    </intent>
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <data android:scheme="https"/>
    </intent>
    <intent>
        <action android:name="android.intent.action.DIAL"/>
        <data android:scheme="tel"/>
    </intent>
</queries>
```

**B.** If the build says a plugin needs a higher `compileSdk`, set
`compileSdk = 36` inside `android { … }` in `android/app/build.gradle.kts`.

**Testing on the emulator:** the emulator pretends to be in California. Open
the emulator's **⋯ (Extended controls) → Location**, search for a place such
as *Sibu* or *Kapit*, and press **Set location**, then pull down to refresh
the Nearby tab.

### How "Nearby" works

- Places come from **OpenStreetMap** (free, no API key) plus places added by
  admins — useful where OpenStreetMap is thin, e.g. rural Sarawak.
- OpenStreetMap places are **saved in our database**, because the free
  public servers are often overloaded:
  - `npm run facilities:import -- --region Sarawak` saves a whole state
    (also `Sabah`, `Malaysia`, …), or `-- <lat> <lng> <km>` saves one area.
  - Any area that wasn't imported is searched live the first time someone
    opens Nearby there, and the results are **saved automatically**, so every
    area needs only one successful search, ever.
  - Live searches try 3 servers × 8 s; the app waits up to 30 s.
- Each place is labelled **government** or **private**, because that decides
  where a prescription is collected in Malaysia: government hospitals and
  clinics hand out medicine at their own pharmacy counter, private clinics
  usually dispense directly, and pharmacies fill written prescriptions.
- Filters: Pharmacies · Gov. clinics · Private clinics · Hospitals · Open 24 hours.
- The last search is saved on the phone. Offline, the list still shows, with
  distances worked out from your current GPS position (GPS needs no internet);
  only the map tiles need a connection.
- **Directions** opens Android's app chooser (Waze, Google Maps, …).
- Location is asked for only when the Nearby tab is first opened.

## 2. Run the backend

1. Install **PostgreSQL** (Windows installer from postgresql.org) and create an
   empty database called `pill_reminder` in pgAdmin. A free hosted database
   (Neon or Supabase) also works; copy its connection string.
2. In `backend/`:

```bash
npm install
cp .env.example .env          # Windows: copy .env.example .env
# edit .env: DATABASE_URL and a long random JWT_ACCESS_SECRET
npm run db:init               # creates all tables (run once)
npm run db:migrate            # updates an older database (safe to run any time)
npm run admin:create -- admin@uts.edu.my "Admin" "Admin1234"
npm run facilities:import -- --region Sarawak  # save every pharmacy/clinic/hospital in Sarawak once
npm run dev                   # http://localhost:3000/api/v1/health → {"ok":true}
```

## 3. Connect the app to the backend

```bash
flutter run --dart-define=DEMO_DATA=false \
            --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

In Android Studio, put the two `--dart-define` flags in
**Run → Edit Configurations → Additional run args**.

`10.0.2.2` is the emulator's name for your computer (for a real phone, use your
computer's Wi-Fi IP address). Android blocks plain `http://` by default, so for
local testing add `android:usesCleartextTraffic="true"` to the `<application>`
tag in `android/app/src/debug/AndroidManifest.xml`. For the release APK use
HTTPS, and make sure `<uses-permission android:name="android.permission.INTERNET"/>`
is in `android/app/src/main/AndroidManifest.xml`.

## 4. Run the web admin panel

The backend must be running first (section 2), and you need an admin account
(`npm run admin:create …` in `backend/`).

```bash
cd backend
npm run catalog:seed          # optional: 15 common medications, so the list is not empty
cd ../admin
npm install
npm run dev                   # http://localhost:5173
```

Sign in with the admin email and password. A normal user's login is refused
with "This account is not an admin."

To point the panel at the live server instead of your laptop, copy
`admin/.env.example` to `admin/.env.local` and set `VITE_API_BASE_URL`. The
server only accepts browsers from the addresses in its `CORS_ORIGINS` setting.

| Page | What an admin can do |
|---|---|
| **Overview** | Accounts, suspended accounts, size of the medication database, doses taken in the last 7 days, latest changes |
| **Users** | Search and filter; edit a name; make someone an admin; suspend or reactivate; sign a user out of every device; delete an account |
| **Medications** | The global medication database: add, edit, hide from users, delete; search by generic or brand name; filter by form |
| **Activity** | Every change made in the panel: who, what and when (`admin_audit_logs`) |

### How the admin panel stays safe

- Every `/admin` request checks the database, not only the token, so an admin
  who is demoted or suspended loses access at once (the token alone would
  keep saying "admin" for up to 15 minutes).
- An admin cannot suspend, demote or delete their own account, so there is
  always at least one working admin.
- Suspending a user ends all their sessions. The phone returns to the login
  screen at its next token refresh (15 minutes at most).
- Admins see how many medications and doses a user has, never the medication
  names, because that is health information the job does not need.
- Every change is written to the audit trail in the same database
  transaction, so a change can never happen without its record. An admin who
  already has records cannot be deleted, only suspended.
- In the browser, the access token lives only in memory and the refresh token
  in `sessionStorage`: a page reload stays signed in, closing the tab signs out.

## API so far

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/auth/register` | — | `{fullName, email, password}` → `{user, accessToken, refreshToken}` |
| `POST` | `/api/v1/auth/login` | — | `{email, password}` → same as register |
| `POST` | `/api/v1/auth/refresh` | — | `{refreshToken}` → new pair (old one stops working) |
| `POST` | `/api/v1/auth/logout` | — | `{refreshToken}` → 204 |
| `GET`  | `/api/v1/auth/me` | Bearer | Current user |
| `GET`  | `/api/v1/sync?since=<ISO>` | Bearer | Everything that changed since `since`, plus the streak |
| `POST` | `/api/v1/dose-logs/batch` | Bearer | Upload doses saved offline (safe to resend) |
| `POST` | `/api/v1/medications/batch` | Bearer | Upload medications + their times saved offline (safe to resend) |
| `POST` | `/api/v1/medications/:id/photo` | Bearer | Multipart field `photo`: JPEG/PNG/WebP, max 5 MB |
| `GET`  | `/uploads/<file>` | — | Uploaded pill-bottle photos |
| `GET`  | `/api/v1/facilities/nearby?lat=&lng=&radius=` | — (60 per 10 min per IP) | Pharmacies, clinics and hospitals nearby (OpenStreetMap + admin-added), nearest first |
| `GET`  | `/api/v1/me/profile` | Bearer | The user's health profile |
| `PUT`  | `/api/v1/me/profile` | Bearer | `{dateOfBirth, gender, conditions[], allergies}` |
| `GET`  | `/api/v1/admin/overview` | Admin | Totals for the admin panel's first screen |
| `GET`  | `/api/v1/admin/analytics` | Admin | Totals by age group, gender, condition, day, week, skip reason, form |
| `GET`  | `/api/v1/admin/users?search=&status=&role=&page=` | Admin | Users, newest first, 20 per page |
| `GET`  | `/api/v1/admin/users/:id` | Admin | One user with counts (medications, sessions, doses) |
| `PATCH` | `/api/v1/admin/users/:id` | Admin | `{fullName?, role?, status?}`: edit, promote, suspend, reactivate |
| `POST` | `/api/v1/admin/users/:id/sign-out` | Admin | End every session of that user |
| `DELETE` | `/api/v1/admin/users/:id` | Admin | Delete the account and all its data → 204 |
| `GET`  | `/api/v1/admin/catalog?search=&form=&status=&page=` | Admin | Global medication database |
| `POST` | `/api/v1/admin/catalog` | Admin | Add a medication (409 if it already exists) |
| `PUT`  | `/api/v1/admin/catalog/:id` | Admin | Replace a medication's details, or hide it (`isActive: false`) |
| `DELETE` | `/api/v1/admin/catalog/:id` | Admin | Delete a medication → 204 |
| `GET`  | `/api/v1/admin/activity?page=` | Admin | Audit trail, newest first |

"Admin" means a Bearer token whose user is an active admin; anyone else gets 403.

Errors always look like `{"error": "message", "fields": {"email": "message"}}`.
Status codes: 401 not logged in / wrong password, 403 suspended, 409 email
taken, 422 invalid fields.

### Health profile, history and safer skipping

- **Health profile** (Account → Health profile): date of birth, gender,
  long-term conditions and allergies. Saved on the phone first and synced like
  everything else; guests keep it on the phone.
- **History tab**: the last 30 days, day by day, with the share of doses taken
  in the last 7 and 30 days. A dose that was never marked counts as missed.
- **Skipping a dose** shows a short safety warning and asks why (side effects,
  ran out, doctor's advice, too late, other). The reason shows in History.
- **"Other" form**: choosing Other in the medication form asks what the form
  is (e.g. Patch, Powder), and that text shows wherever the medicine appears.
- **Admin → Analytics**: users by age group (with their adherence), gender,
  most common conditions, doses taken per day, new accounts per week, why
  doses are skipped and medication forms. Only totals are sent to the browser.

### Reminders when the app is closed

Some phones (realme, OPPO, Xiaomi, vivo…) hold back other apps' alarms to save
battery, so reminders only appeared after opening the app. The app now:

- schedules reminders as **alarm-clock alarms** (exact, rings in deep sleep),
  with `USE_EXACT_ALARM`, which Android 13+ grants without asking;
- shows a banner asking to **let Pill Reminder run in the background** when
  battery optimisation is on, and opens Android's dialog for it;
- on those phone brands, tells the user in Account to also turn on
  **Auto launch / Autostart** and opens the app's settings page.

Use Account → Reminders → **Test**, then close the app: the alert arrives
about a minute later. (On Google Play, `USE_EXACT_ALARM` needs a short
justification; the sideloaded APK doesn't.)

### Guest mode (no account)

- On the login screen, **Continue without an account** → confirm. The app
  opens straight to the dashboard and remembers guest mode after a restart.
- Everything works on the phone: adding, editing and deleting medications,
  marking doses and reminders. **Nearby** works too.
- Nothing is sent to the server, so there is nothing to back up: losing or
  resetting the phone loses the data. The dashboard says
  "Guest · saved on this phone only", and there is no streak (the server
  works it out).
- Account (person icon) → **Create an account** or **I already have an
  account**: what the guest saved stays and is uploaded to that account.
- Account → **Delete guest data** (confirmed) wipes the phone and returns to
  the login screen.
- Guests are not users on the server, so they don't appear in the admin panel.

### Confirmations (two steps for anything easy to do by accident)

| Action | First tap | Second step |
|---|---|---|
| Mark a dose as taken | The circle on a dose row, or **Mark as taken** | "Mark as taken?" with the medication, time and dose |
| Skip a dose | **Skip** | "Skip this dose?" |
| Edit a medication | **Medications** tab → a row (or ⋮ → Edit) → **Save changes** | "Save changes?" |
| Delete a medication | **Medications** tab → ⋮ → Delete | "Delete Metformin?" (cannot be undone) |

Tapping outside a dialog or pressing Back never confirms. A taken or skipped
dose can still be undone from the snack bar or by tapping its tick. The
**Mark as taken** button on a notification stays one tap, because pressing a
button on an alert is already a deliberate act.

### How editing and deleting work offline

- Both are saved on the phone first and uploaded at the next sync, like adding.
- **Edit:** a reminder time that stays keeps its history, so a dose already
  taken today stays taken. A removed time disappears from the schedule; a new
  time gets its own reminders.
- **Delete:** the medication leaves the Today list and its alarms are
  cancelled at once. The phone keeps a hidden "deleted" row until the server
  has been told, so a delete made with no signal is never lost. After the
  sync it also disappears from the user's other devices.
- A saved photo can be replaced, not removed.

### How "Add medication" works offline

1. The form checks every field on the phone (same rules as the server).
2. The photo is shrunk to ≤1600 px (about 200 KB) and copied into the app's
   own folder, because the camera's temporary file can be deleted by Android.
3. The medication and its times are saved to SQLite as `pending` and appear
   on the dashboard immediately — no signal needed.
4. The next sync uploads, in order: medications → photos → dose logs, then
   downloads changes. Anything that fails stays `pending` and retries.

Uploaded photos are saved in `backend/uploads/`. Free hosts such as Render
wipe that folder on every deploy; for a long-lived server, store photos in a
service like Cloudinary or Supabase Storage instead.

### Security choices (for the technical report)

- Passwords hashed with bcrypt (cost 10); login gives the same message for a
  wrong email and a wrong password.
- Access token: JWT valid for 15 minutes, kept only in memory and the
  Android Keystore (`flutter_secure_storage`).
- Refresh token: random 48 bytes, valid 30 days, stored on the server only as
  a SHA-256 hash. Each refresh replaces it; if an old one is ever used again,
  every session for that user is ended (theft detection).
- When the phone is offline the app keeps the session, so reminders and the
  dashboard keep working; it only logs out when the server rejects the token.
- Logging out wipes the phone's SQLite cache so the next user sees nothing.
