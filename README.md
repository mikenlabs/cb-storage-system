# CB Storage System — Hosted Build

Production-ready copy of the CB Storage System. The frontend is served by
Flask, so a single web service runs everything. The database, file storage
and authentication all live on **Supabase** — set it up there once, then
point this app at it.

```
cb hosted/
├── backend/            # Flask API + gunicorn entry (wsgi.py)
│   ├── app.py          # All API routes + frontend serving
│   ├── wsgi.py         # Gunicorn entry point (starts backup scheduler)
│   ├── requirements.txt
│   ├── config.py
│   ├── supabase_client.py
│   └── seed_admin.py   # Creates the default admin account
├── frontend/           # Landing page + SPA (css/js/images)
├── supabase/migrations/  # All SQL migrations 001–011 + fixes
├── Procfile            # gunicorn start command (single worker!)
├── runtime.txt         # Python version for Render
├── .env.example        # Environment variable template
└── README.md
```

## 1. Supabase setup (once)

1. Create a free project at https://supabase.com.
2. In the **SQL Editor**, run every file in `supabase/migrations/` in order
   (`001_initial_schema.sql` → `011_pg_cron_automated_backup.sql`, then
   `fix_functions.sql`). This creates the tables, RLS policies, the storage
   bucket, the auto-categorization trigger **and the pg_cron automated
   backup job**. `011` also enables the `pg_cron` extension (you can enable
   it manually under Database → Extensions if your project requires it).
3. Create an admin user under **Authentication → Users** with the email and
   password you want (e.g. `admin@silas.com`), then set its role:

```bash
# from the backend/ folder (run once, locally, with your Supabase env vars set)
python seed_admin.py
```

> `seed_admin.py` promotes the user matching `ADMIN_EMAIL` to `admin`. Change
> the email/password constants at the top of the file first if you want.

## 2. Deploy (Render — recommended)

1. Push this folder to a GitHub repo.
2. On https://render.com → **New → Web Service** → pick the repo.
3. Settings:
   - **Build Command:** `pip install -r backend/requirements.txt`
   - **Start Command:** (leave blank — the `Procfile` runs `gunicorn wsgi:app`)
   - **Environment variables** (from `.env.example`):
     `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`
4. Deploy. You're live at `https://<your-app>.onrender.com`.
   - Landing page: `/`
   - App / sign-in: `/index.html` or `/app`

### Railway (alternative)
Same pattern: link the repo, set the build/start commands above, and add the
three `SUPABASE_*` env vars.

## Automated backups (Supabase pg_cron)

Automated backups run **inside Supabase** (pg_cron), not in the web process.
Migration `011` creates a `cb-automated-backup` job that fires every minute;
the job reads the saved schedule from `system_settings` and only snapshots
when one is due (interval / daily / disabled — all still controlled from the
Backup & Recovery page in the app).

This means:
- Backups keep running even when the web service is asleep or scaled to zero.
- **Always-on is no longer required for backups** (free-tier sleep is fine).
- Multiple web instances are safe — there is no in-process scheduler to
  duplicate. (`--workers 1` remains a fine default.)
- The web service only calls `ensure_backup_cron()` once at boot to make sure
  the pg_cron job exists.

## 3. Local testing of this build

```bash
cd backend
pip install -r requirements.txt
cp ../.env.example .env        # fill in your Supabase values
python app.py                  # local dev (debug on)
# open http://localhost:5000
```

## API surface

Full API reference lives in the main project README. The hosted build serves
`/api/*` (auth, files, categories, keywords, suggest, backup/recovery, admin)
plus the frontend at `/`, `/index.html`, `/app`.
