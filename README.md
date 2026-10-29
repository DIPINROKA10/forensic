# AI Forensic Investigation System

An end-to-end platform for video forensics: ingest footage (upload or live camera), detect
and track objects, build a searchable evidence index, run an agentic investigation over the
findings, and export a reviewable PDF report.

Live deployment:

| Layer | URL |
|---|---|
| Frontend (Next.js) | https://forensic10.netlify.app |
| API (FastAPI) | https://forensic-uel9.onrender.com |
| API docs (Swagger) | https://forensic-uel9.onrender.com/docs |
| Health check | https://forensic-uel9.onrender.com/health |
| Database | Neon Postgres 18 (`aws-us-east-2`) |

`/health` reports each dependency (`database`, `qdrant`, `storage`) separately. The API is
considered healthy when `database.ok` is `true`, even if the optional vector store is
running in its in-memory fallback.

---

## Features

- **Video ingest** - upload MP4/MKV/AVI, probe with ffmpeg, extract scenes, clips and keyframes.
- **Detection and tracking** - YOLOv8 object detection with a ByteTrack-style IoU tracker that
  keeps stable IDs (e.g. `Person-003`) across frames.
- **Live camera sources** - browser WebRTC, USB/DroidCam, phone IP camera (MJPEG), RTSP,
  synthetic simulation, and file playback. QR pairing for phone cameras.
- **Evidence index** - clips, detections, transcripts and observations are embedded into a
  vector store (Qdrant, or an in-memory fallback) for semantic and hybrid search.
- **Agentic investigation** - LangGraph agents reason over evidence, produce findings and
  claims, and attach supporting evidence to each claim.
- **Policy RAG** - upload policy documents and ground findings against them.
- **Reports** - generate a PDF report, review decisions, and download the artifact.
- **Audit trail** - every mutating action is written to `audit_logs`.
- **Roles** - `ADMIN`, `SECURITY_OFFICER`, `INVESTIGATOR`, `REVIEWER`.

Detection output is a visual tracking identifier only. The system does not perform facial
recognition, name identification, or biometric identification.

---

## Architecture

```
Browser
  |
  +--> https://forensic10.netlify.app      Next.js 14 frontend (static + SSR routes)
  |         NEXT_PUBLIC_API_URL
  v
  +--> https://forensic-uel9.onrender.com  FastAPI backend (Docker, single instance)
            |-- Neon Postgres         (users, videos, evidence, audit, runs)
            |-- Qdrant                (optional; in-memory fallback)
            |-- local disk / MinIO    (uploads, clips, keyframes, reports)
            +-- YOLOv8 / OpenCV / ffmpeg (CPU inference)
```

The frontend and backend are deployed separately on purpose: the backend needs ffmpeg,
PyTorch, a persistent filesystem and long-running background jobs, which a static/edge host
cannot provide. It also keeps live-camera sessions in process memory, so it must run as a
**single instance** - do not enable horizontal scaling.

---

## Tech stack

| Layer | Stack |
|---|---|
| Frontend | Next.js 14.2 (App Router), React 18, TypeScript, Tailwind CSS, lucide-react |
| Backend | Python 3.11, FastAPI 0.111, SQLAlchemy 2.0, Pydantic v2, Alembic |
| Vision | Ultralytics YOLOv8, OpenCV, NumPy, scenedetect, ffmpeg |
| Agents / RAG | LangGraph, LangChain core, Qdrant client |
| Storage | Postgres (Neon), MinIO or local disk, Qdrant |
| Auth | JWT (PyJWT) with bcrypt password hashing |

---

## Repository layout

```
.
|-- DEPLOYMENT.md              Render + Netlify + Neon deployment guide
|-- netlify.toml               Netlify build config for the frontend
|-- render.yaml                Render Blueprint for the backend
|-- README.md                  this file
`-- AI Forensic Investigation System/
    `-- ai-forensic-investigation/
        |-- README.md              app-level setup, commands, troubleshooting
        |-- backend/
        |   |-- app/
        |   |   |-- api/           REST routers (auth, videos, live, reports, ...)
        |   |   |-- core/          settings, security, logging
        |   |   |-- database/      SQLAlchemy models and session
        |   |   |-- vision/        detection + tracking
        |   |   |-- video/         ffmpeg pipeline, scene detection
        |   |   |-- ai/            embeddings, LLM clients, Qdrant service
        |   |   |-- investigator/  LangGraph investigation agents
        |   |   `-- live/          camera sources and session manager
        |   |-- alembic/           migrations (0001 -> 0010)
        |   |-- scripts/           demo seeds and verification helpers
        |   |-- docker-entrypoint.sh
        |   `-- Dockerfile
        |-- frontend/
        |   |-- app/               route segments (19 routes)
        |   |-- components/
        |   |-- lib/api.ts         typed API client
        |   `-- Dockerfile         standalone Next server
        |-- docs/                  architecture, demo, operations, security, troubleshooting
        |-- tests/                 pytest suite
        |-- docker-compose.yml     local stack (postgres, minio, qdrant, backend, frontend)
        `-- .env.example           every supported setting
```

---

## Quick start (Docker, recommended)

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation"
cp .env.example .env          # then edit secrets if you like
docker compose up --build
```

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| API | http://localhost:8000 |
| API docs | http://localhost:8000/docs |
| MinIO console | http://localhost:9001 |
| Qdrant | http://localhost:6333 |

Migrations run automatically from the backend container entrypoint.

## Quick start (manual)

Backend:

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation/backend"
python -m venv .venv
# Windows: .venv\Scripts\activate ; macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --port 8000
```

Frontend (second terminal):

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation/frontend"
npm install
# PowerShell:
$env:NEXT_PUBLIC_API_URL="http://127.0.0.1:8000"
npm run dev
```

Open http://localhost:3000 and register an account.

> `NEXT_PUBLIC_*` values are inlined at build time. Change the variable, then restart
> `npm run dev` (or redeploy) - editing it while the server runs has no effect.

---

## Configuration

All settings live in `.env` (see `.env.example` for the full list). The backend loads the
app-root `.env` first and then an optional `backend/.env`, which takes precedence.

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | SQLAlchemy URL. On Neon use the **pooled** (`-pooler`) string. |
| `DATABASE_URL_UNPOOLED` | Direct Neon string, used by Alembic only. |
| `SECRET_KEY` | JWT signing key. Generate: `python -c "import secrets;print(secrets.token_urlsafe(64))"` |
| `BACKEND_CORS_ORIGINS` | Comma-separated exact origins allowed to call the API. |
| `ALLOW_PRIVILEGED_REGISTRATION` | `true` lets anyone self-register as `ADMIN`/`SECURITY_OFFICER`. Set `false` after creating your admin. |
| `LLM_PROVIDER` / `WHISPER_MODEL` | `simulation` runs fully offline with deterministic output. |
| `QDRANT_URL` / `QDRANT_API_KEY` | Optional. Without them the vector store is in-memory and resets on restart. |
| `MINIO_ENDPOINT` | Leave unreachable to force local-disk storage under `DATA_DIR`. |
| `NEXT_PUBLIC_API_URL` | Frontend build-time API base URL (no trailing slash). |

The frontend only needs `NEXT_PUBLIC_API_URL`. Everything else is backend-side.

---

## Database and migrations

Alembic lives in `backend/alembic`, with ten revisions (`0001_initial` through
`0010_camera_pairings`). Migrations use `DATABASE_URL_UNPOOLED` when present, because
PgBouncer (the pooled Neon endpoint) does not handle DDL reliably.

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation/backend"
python -m alembic current        # show applied revision
python -m alembic upgrade head   # apply all pending
```

### Neon CLI

The repo is linked to a Neon project through `neon.ts` + `.neon`:

```bash
npm i -g neon@latest
neon login
cd "AI Forensic Investigation System/ai-forensic-investigation"
neon init -y --org-id <org-id> --project-id <project-id> \
  --branch production --services postgres
neon config plan     # preview drift
neon deploy          # apply policy + pull DATABASE_URL, DATABASE_URL_UNPOOLED, NEON_BRANCH
```

`neon deploy` adds variables to `.env` without removing anything already there.

---

## Tests

```bash
cd "AI Forensic Investigation System/ai-forensic-investigation"
pytest                       # config in pytest.ini, suite in tests/
cd frontend && npm run build # production build must stay green
```

The suite includes auth, camera, detection, investigation, reporting and live-source tests.
`backend/scripts/verify_*.py` are end-to-end checks that run against a live API; for example,
from `backend/`, `python scripts/verify_final_system.py` (defaults to http://127.0.0.1:8000).

---

## Deployment

Full instructions (with the exact fields and pitfalls) are in [DEPLOYMENT.md](DEPLOYMENT.md).
Short version:

1. **Neon** - project + `production` branch; pooled URL for the app, direct URL for Alembic.
2. **Render** - Docker web service from `AI Forensic Investigation System/ai-forensic-investigation/backend`.
   Health check `/health`. Leave the Docker Command **empty**: the image entrypoint runs
   `alembic upgrade head` and then uvicorn on `$PORT`.
3. **Netlify** - import the repo; `netlify.toml` sets the base directory, build command and
   the Next.js runtime. Add `NEXT_PUBLIC_API_URL` in the site environment.
4. **Close the loop** - set `BACKEND_CORS_ORIGINS` to the frontend's exact origin and save.

Start commands that are known to work:

```bash
# backend (already in the image entrypoint)
sh docker-entrypoint.sh

# frontend (Netlify runs this automatically)
npm run build
```

---

## Known limitations

- **Free tiers are small.** Render's 512 MB instance boots and serves the API, but object
  detection on a real video (PyTorch + OpenCV) can exhaust memory and restart the service.
  Use the 2 GB plan, or keep demos to the simulation provider.
- **No persistent disk on free plans.** Uploads, clips and reports are lost when the instance
  restarts or spins down. Free instances also spin down after 15 minutes of inactivity, so
  the first request afterwards takes ~50 s.
- **Live cameras need local hardware.** A container has no `/dev/video*`, and the cloud
  backend cannot reach `192.168.x.x`. Use the browser/IP-camera path with a public tunnel,
  the simulation source, or run the stack locally.
- **WebRTC needs UDP**, which Render does not route; prefer MJPEG/RTSP sources in the cloud.
- **Single instance only.** Live sessions are held in process memory.

---

## Documentation

| File | Contents |
|---|---|
| [DEPLOYMENT.md](DEPLOYMENT.md) | Render, Netlify, Neon, CORS, troubleshooting |
| `docs/ARCHITECTURE.md` | components, data flow, module boundaries |
| `docs/DEMO_GUIDE.md` | seeded demo walkthrough |
| `docs/OPERATIONS.md` | backups, restarts, health |
| `docs/SECURITY.md` | authn/authz, secrets, hardening |
| `docs/TROUBLESHOOTING.md` | common failures and fixes |
| `WEBCAM_SETUP.md` | DroidCam / phone camera setup for local runs |

Demo data helpers live in `backend/scripts/` (`seed_sample_data.py`, `seed_demo_videos.py`,
`seed_demo_evidence.py`, ...). They create their own account
(`sample.data@forensics-demo.com` / `sample12345`) - delete it before any real deployment.

---

## Security notes

- Change `SECRET_KEY` and the Neon password before exposing the app publicly.
- Set `ALLOW_PRIVILEGED_REGISTRATION=false` once an admin exists.
- Keep `.env` out of git (already ignored). Rotate any credential that was pasted into a
  chat, screenshot, or ticket.
