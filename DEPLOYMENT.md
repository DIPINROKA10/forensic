# Deployment Guide â€” Vercel (frontend) + Render (backend)

This project is two deployables plus two managed services:

```
Browser
  â”‚
  â”œâ”€â”€ https://<app>.vercel.app        â†’ Next.js frontend (Vercel)
  â”‚        â”‚  NEXT_PUBLIC_API_URL
  â”‚        â–¼
  â””â”€â”€ https://<api>.onrender.com      â†’ FastAPI backend (Render, Docker)
           â”œâ”€â”€ PostgreSQL             â†’ Neon (managed)
           â”œâ”€â”€ Qdrant                 â†’ Qdrant Cloud (optional; in-memory fallback)
           â””â”€â”€ /app/data              â†’ Render persistent disk (uploads, clips, reports)
```

Vercel cannot run the backend: it needs ffmpeg, PyTorch, YOLO, a persistent
filesystem, background video jobs and WebSockets. Render runs it as a normal
container.

> The backend holds live-camera sessions in process memory. Run **exactly one
> instance**. Do not enable scaling or multiple replicas.

---

## 0. Prerequisites

- A GitHub account with this repo pushed (`origin` is already
  `https://github.com/DIPINROKA10/forensic.git`).
- Accounts: [Render](https://render.com), [Vercel](https://vercel.com),
  [Neon](https://neon.tech), and optionally [Qdrant Cloud](https://cloud.qdrant.io).
- Local fixes committed and pushed first:

```bash
git add -A
git commit -m "Fix frontend build + add Render deployment config"
git push origin main
```

The frontend build was broken before this commit (unbalanced JSX and a wrong
report endpoint). It now compiles: `npm run build` â†’ 19 routes, no errors.

---

## 1. PostgreSQL (Neon)

The repo is already wired to Neon through `neon.ts` plus a linked `.neon` file,
so the CLI can provision and re-pull credentials at any time.

### Option A - Neon CLI (what this repo uses)

```bash
npm i -g neon@latest          # or: npx neon@latest ...
neon login                    # opens the browser once
cd "AI Forensic Investigation System/ai-forensic-investigation"
neon init -y --org-id <org-id> --project-id <project-id> \
  --branch production --services postgres
neon config plan              # preview drift against neon.ts
neon deploy                   # apply + pull env vars into .env
```

`neon init` / `neon deploy` write three variables into the app-root `.env` and
never remove existing keys:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | **pooled** (`...-pooler...`) URL - all app traffic |
| `DATABASE_URL_UNPOOLED` | **direct** URL - Alembic migrations only |
| `NEON_BRANCH` | branch name the pulled env came from |

The backend loads the app-root `.env` (`env_file=("../.env", ".env")`), uses the
pooled URL for the SQLAlchemy engine, and the direct URL in `alembic/env.py`.
This matters because Neon's PgBouncer pool does not handle DDL/migration
transactions reliably.

### Option B - manual (console)

1. Create a project at <https://console.neon.tech>. Pick the region closest to
   your Render region (this guide uses `ohio`).
2. Copy both connection strings, pooled and direct:

```
postgresql://USER:PASSWORD@ep-xxxx-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require
postgresql://USER:PASSWORD@ep-xxxx.us-east-2.aws.neon.tech/neondb?sslmode=require
```

3. Set `DATABASE_URL` to the pooled one and `DATABASE_URL_UNPOOLED` to the
   direct one on Render. SQLAlchemy defaults to psycopg2 for `postgresql://`,
   so no driver suffix is required (adding `+psycopg2` also works).

Migrations run automatically on deploy (`alembic upgrade head`), so do not
create tables manually. To apply them from your machine:

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation/backend"
python -m alembic upgrade head
```

---

## 2. Qdrant Cloud (optional but recommended)

Without it the backend starts anyway and uses a deterministic in-memory vector
store â€” fine for a demo, but indexed evidence is lost on every restart.

1. Create a free cluster at <https://cloud.qdrant.io>.
2. Copy the cluster URL (e.g. `https://xxxx.cloud.qdrant.io:6333`) and an API key.
3. Set `QDRANT_URL` and `QDRANT_API_KEY` on Render (step 3).

---

## 3. Backend on Render

### 3a. Create the service

**Option A â€” Blueprint (uses `render.yaml` at the repo root)**

1. Render Dashboard â†’ **New â†’ Blueprint**.
2. Connect the repo, keep the default branch, click **Apply**.
3. Fill in the `sync: false` env vars when prompted (see table below).

**Option B â€” manual Docker web service**

1. **New â†’ Web Service** â†’ connect the repo.
2. **Root Directory**: `AI Forensic Investigation System/ai-forensic-investigation/backend`
3. **Runtime**: Docker. **Dockerfile Path**: `./Dockerfile`
4. **Instance type**: Starter with **2 GB RAM minimum** (4 GB recommended).
   The free 512 MB tier will OOM on `import torch`.
5. **Health Check Path**: `/health`
6. **Start Command** (overrides the image CMD):

```bash
sh -c "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips='*'"
```

7. Add a **Disk**: name `forensic-data`, mount path `/app/data`, 5 GB.
8. Add the environment variables below, then **Create Web Service**.

### 3b. Environment variables

| Key | Value | Notes |
|---|---|---|
| `DATABASE_URL` | pooled `postgresql://...-pooler...neon.tech/neondb?sslmode=require` | app traffic, from step 1 |
| `DATABASE_URL_UNPOOLED` | direct `postgresql://...neon.tech/neondb?sslmode=require` | Alembic migrations, from step 1 |
| `SECRET_KEY` | long random string | `python -c "import secrets;print(secrets.token_urlsafe(64))"` |
| `BACKEND_CORS_ORIGINS` | `https://your-app.vercel.app` | exact origin, no trailing slash; comma-separate multiple |
| `QDRANT_URL` | `https://xxxx.cloud.qdrant.io:6333` | optional |
| `QDRANT_API_KEY` | cluster API key | optional |
| `LLM_PROVIDER` | `simulation` | see "Using Gemini" below |
| `WHISPER_MODEL` | `simulation` | offline deterministic transcripts |
| `RAG_VERIFICATION_THRESHOLD` | `0.25` | required for simulation embeddings |
| `MINIO_ENDPOINT` | `localhost:9000` | forces local-disk storage fallback |
| `DATA_DIR` | `data` | resolves to `/app/data` |
| `YOLO_MODEL` | `yolov8n.pt` | weights are baked into the image |
| `ALLOW_PRIVILEGED_REGISTRATION` | `true` temporarily | set `false` after creating the admin |

Do **not** set `PORT` â€” Render injects it.

### 3c. First deploy

The image installs CPU-only PyTorch and takes ~10â€“20 minutes to build. Watch
the logs for:

```
Running upgrade  -> 0008
INFO:     Uvicorn running on http://0.0.0.0:10000
```

Then verify:

```bash
curl https://<api>.onrender.com/health
```

`status` may be `degraded` if Qdrant is not configured â€” that is expected and
still returns HTTP 200. `database` must be `ok`.

---

## 4. Frontend on Vercel

1. Vercel Dashboard â†’ **Add New â†’ Project** â†’ import the repo.
2. **Root Directory**: `AI Forensic Investigation System/ai-forensic-investigation/frontend`
   (click **Edit** next to Root Directory and select the folder).
3. **Framework Preset**: Next.js. **Node.js Version**: 20.x.
4. **Environment Variables** â€” add for *Production* **and** *Preview*:

| Key | Value |
|---|---|
| `NEXT_PUBLIC_API_URL` | `https://<api>.onrender.com` |

> `NEXT_PUBLIC_*` values are **baked in at build time**. Changing this variable
> requires a redeploy (Deployments â†’ â‹¯ â†’ Redeploy). Do not use a trailing slash.

5. **Deploy**. Note the production URL, e.g. `https://ai-forensic.vercel.app`.

If Vercel rejects the Root Directory because of the spaces in
`AI Forensic Investigation System`, rename that folder to something like
`ai-forensic` (no code references it) and push again.

---

## 5. Close the loop: CORS

1. Render â†’ your service â†’ **Environment** â†’ set:

```
BACKEND_CORS_ORIGINS=https://ai-forensic.vercel.app
```

2. Save. Render restarts the service automatically.
3. Open the Vercel URL and log in / register.

If you get `CORS policy: No 'Access-Control-Allow-Origin'`, the origin string
does not match exactly (scheme, subdomain, trailing slash). Preview deployment
URLs are random â€” add each one, or test against the stable production domain.

---

## 6. Create the first admin + seed content

### Create the admin

Either use the UI (`/register`, choose role `ADMIN`), or:

```bash
curl -X POST https://<api>.onrender.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Admin","email":"admin@example.com","password":"ChangeMe123!","role":"ADMIN"}'
```

### Seed demo cameras/videos

The seeder uses only the Python standard library, so it can run from your
machine against the public backend:

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation/backend"
python scripts/seed_sample_data.py --base-url https://<api>.onrender.com --process
```

It registers its own `sample.data@forensics-demo.com` / `sample12345` admin,
creates 5 cameras, downloads 4 public sample clips, uploads them, and (with
`--process`) triggers real YOLO processing.

You can also upload your own files from the `demo video/` folder through the
Videos page.

---

## 7. Lock down registration

Once your admin exists:

1. Render â†’ Environment â†’ `ALLOW_PRIVILEGED_REGISTRATION=false`
2. Save and let it restart.

Public registration still works, but only for `INVESTIGATOR`, `REVIEWER`.
Without this, anyone on the internet can register as `ADMIN`.

Optional but recommended: rotate `SECRET_KEY` and the Neon password after the
demo.

---

## 8. Verification checklist

- [ ] `GET /health` â†’ `database.ok = true`, HTTP 200
- [ ] Frontend loads at the Vercel URL (no blank page / CORS errors in console)
- [ ] Register + login works
- [ ] Upload a small MP4 â†’ status moves `UPLOADED â†’ PROCESSING â†’ READY`
- [ ] Clips/detections appear; thumbnails load
- [ ] Generate report â†’ download PDF
- [ ] Restart the Render service â†’ uploads and evidence still present (disk working)
- [ ] `ALLOW_PRIVILEGED_REGISTRATION=false` blocks `role: "ADMIN"`

---

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Build fails, exit 137 / OOM | Instance too small for the PyTorch build. Use â‰¥2 GB; retry the deploy. |
| App crashes on boot (`torch`, `libGL`) | Dockerfile deps missing â€” this repo installs `libgl1`/`libglib2.0-0`; make sure you did not override the Dockerfile. |
| `relation "users" does not exist` | Migrations did not run. Check the start command includes `alembic upgrade head`. |
| `could not connect to server` | `DATABASE_URL` must use `+psycopg2` and include `?sslmode=require` for Neon. |
| CORS error in browser | `BACKEND_CORS_ORIGINS` must exactly equal the Vercel origin. |
| API requests go to `localhost:8000` | `NEXT_PUBLIC_API_URL` was missing at build time. Set it, then redeploy Vercel. |
| 502 / WebSocket disconnects | Render supports WSS, but the backend must stay on one instance. Check logs for worker crashes. |
| Uploads vanish after restart | Persistent disk missing or not mounted at `/app/data`. |
| Browser camera (WebRTC) fails | Render does not expose UDP for WebRTC media. Use an IP-camera MJPEG stream (IP Webcam app) or upload files. |
| Video processing never finishes | Large file + small instance. Use 4 GB, or shorter clips; processing runs in background tasks. |
| Render free tier | No persistent disk and 512 MB. Not viable for this stack. |

---

## 10. Cost and limits

| Service | Plan | Approx. cost |
|---|---|---|
| Vercel | Hobby | $0 |
| Neon | Free | $0 (0.5 GB storage) |
| Qdrant Cloud | Free | $0 (1 GB) |
| Render | Starter, 2 GB + 5 GB disk | ~$25/mo (4 GB ~$50/mo) |

If that is too much, the alternative is a single small Linux VM
(Hetzner/DigitalOcean/Oracle Free Tier) running `docker-compose.yml` with Caddy
for TLS: ~$5â€“10/mo and no service-splitting.

---

## Using Gemini instead of simulation

Google AI Studio is not a host, but it can supply an API key. The provider layer
accepts any OpenAI-compatible endpoint:

```
LLM_PROVIDER=openai
LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/
LLM_API_KEY=<AI Studio key>
LLM_MODEL=<current Gemini model id>
VISION_MODEL=<current Gemini vision model id>
```

Set these on Render and redeploy. `WHISPER_MODEL=simulation` can stay unless you
add a real whisper backend.
