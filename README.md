# Pill Reminder — CSS3344 Mobile Application Development

Offline-first pill reminder for Android (Flutter) with a Node.js + PostgreSQL
REST API and a React web admin panel.

```
pill-reminder/
├── app/       Flutter Android app      (done: all 6 features)
├── backend/   Express REST API         (done: auth, sync, medications, photos, nearby places)
└── admin/     React + Vite web admin   (later step)
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
| `GET`  | `/api/v1/facilities/nearby?lat=&lng=&radius=` | Bearer | Pharmacies, clinics and hospitals nearby (OpenStreetMap + admin-added), nearest first |

Errors always look like `{"error": "message", "fields": {"email": "message"}}`.
Status codes: 401 not logged in / wrong password, 403 suspended, 409 email
taken, 422 invalid fields.

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
