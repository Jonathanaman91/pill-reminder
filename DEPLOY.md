# Putting the backend online (Neon + Render, both free)

After this, the app talks to a fixed `https://` address that works on any
phone, anywhere — your laptop doesn't need to be on.

```
Phone app ──https──▶ Render (runs backend/)  ──▶ Neon (PostgreSQL database)
```

| Service | What it does | Free plan limits that matter |
|---|---|---|
| **Neon** | The database | 1 GB storage, sleeps after 5 min idle (wakes in under a second) |
| **Render** | Runs the Node.js API | Sleeps after 15 min idle; the next request waits up to ~1 min. Files on the server are wiped on restart (so photos are stored in the database) |

---

## 1. Put the project on GitHub

Your brief needs a public GitHub link anyway.

1. Install **GitHub Desktop** (desktop.github.com) and sign in.
2. **File → Add local repository…** → choose the `pill-reminder` folder
   (the one containing `app`, `backend`, `render.yaml`).
   If it says it isn't a repository, click **create a repository** → **Create**.
3. Check the **Changes** list does **not** include any `.env` file
   (`.gitignore` hides it — your database password must never be on GitHub).
4. Write a summary like "Initial version" → **Commit to main** →
   **Publish repository**. Untick **Keep this code private** (the brief asks
   for a public link) → **Publish**.

## 2. Create the Neon database

1. Sign up at **neon.tech** (Sign up with GitHub is quickest).
2. **Create project**: name `pill-reminder`, region **AWS Asia Pacific
   (Singapore)**, other options as they are.
3. Click **Connect**, copy the connection string. It looks like:
   ```
   postgresql://neondb_owner:xxxx@ep-xxxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
   ```

## 3. Create the tables (from your laptop)

In a Terminal in the `backend` folder. `$env:` only lasts for this Terminal
tab, so your local `.env` keeps pointing at your laptop's database.

```powershell
$env:DATABASE_URL = "paste-the-Neon-string-here"
npm run db:init
npm run db:migrate
npm run facilities:import -- --region Sarawak
npm run admin:create -- your-email@example.com "Your Name" "AStrongPassw0rd"
Remove-Item Env:DATABASE_URL
```

You should see `Database tables created.`, `Database is up to date.`, the
import summary, and `Admin ready`. In Neon → **Tables** you'll see them.

## 4. Deploy the API on Render

1. Sign up at **render.com** with GitHub.
2. **New → Blueprint** → pick your `pill-reminder` repository → Render finds
   `render.yaml`.
3. It asks for **DATABASE_URL** → paste the Neon string → **Apply**
   (`JWT_ACCESS_SECRET` is generated for you).
4. Wait until the service shows **Live** (first build ≈ 2–4 min). Its address
   is at the top, e.g. `https://pill-reminder-api.onrender.com`
   (Render may add letters if the name is taken).
5. Open `https://YOUR-ADDRESS.onrender.com/api/v1/health` → `{"ok":true}`.

From now on, every **Push origin** in GitHub Desktop redeploys automatically.

## 5. Build the release APK

```powershell
cd ..\app
flutter build apk --release --dart-define=DEMO_DATA=false --dart-define=API_BASE_URL=https://YOUR-ADDRESS.onrender.com/api/v1
```

APK: `app\build\app\outputs\flutter-apk\app-release.apk` (much smaller and
faster than the debug one). Install it on any phone — no laptop, no hotspot.

This is the APK to submit. It's signed with Flutter's debug key, which is
fine for installing by hand; publishing on Google Play (the +5% bonus) needs
your own upload key — ask before doing that.

## 6. Before a demo: keep the server awake

The first request after 15 idle minutes takes up to a minute (the app shows
"Waking up the server…"). Before a presentation:

- open the `/api/v1/health` address in a browser 2 minutes earlier, **or**
- at **cron-job.org** (free), create a job that opens that address every
  10 minutes during your demo day, and switch it off afterwards.

One always-awake service uses ~720 of Render's 750 free hours a month.

## Troubleshooting

| You see | Fix |
|---|---|
| Render build fails at `npm ci` | Make sure `backend/package-lock.json` is committed |
| Render log: `Missing environment variable DATABASE_URL` | Service → **Environment** → add it → **Save** |
| Render log: `password authentication failed` | Copy the Neon string again (Neon → Connect) |
| App: "Couldn't reach the server" | Open the health address in the phone's browser; check the APK was built with the right address (`/api/v1` at the end) |
| Nearby shows nothing | Run the Sarawak import against Neon (step 3) |
