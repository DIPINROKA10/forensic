# AI Forensic Investigation System (application)

This folder contains the actual application: a FastAPI backend, a Next.js frontend, the
Alembic migrations, the test suite and the demo/verification scripts.

- Deployment (Render + Netlify + Neon, CORS, limits): see the [root README](../../README.md)
  and [DEPLOYMENT.md](../../DEPLOYMENT.md).
- Deep dives: [`docs/`](docs).

---

## What is in here

```
backend/
  app/            FastAPI application
    api/          REST routers (auth, videos, cameras, live, evidence, reports, ...)
    core/         settings, security, logging
    database/     SQLAlchemy models + session
    vision/       YOLO detection and IoU tracking
    video/        ffmpeg pipeline, scene detection, clips
    ai/           embeddings, LLM clients, Qdrant service
    investigator/ LangGraph investigation agents
    live/         camera sources (webcam, USB, IP, RTSP, simulation) and session manager
  alembic/        migrations 0001 -> 0010
  scripts/        seeds and verify_*.py end-to-end checks
  Dockerfile      CPU-only PyTorch image
  docker-entrypoint.sh   runs migrations, then uvicorn on $PORT
frontend/
  app/            19 routes (App Router)
  components/     UI building blocks
  lib/api.ts      typed API client, reads NEXT_PUBLIC_API_URL
tests/            pytest suite (auth, cameras, detection, investigation, reporting)
docs/             architecture, demo guide, operations, security, troubleshooting
docker-compose.yml  postgres + minio + qdrant + backend + frontend
.env.example      every supported setting
WEBCAM_SETUP.md   USB / DroidCam / phone camera setup for local runs
```

---

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Python | 3.11+ | backend |
| Node.js | 20+ | frontend |
| ffmpeg | any recent | video probing, clip and frame extraction |
| Docker Desktop | optional | the one-command stack |

Without Qdrant the backend uses an in-memory vector store; without MinIO it writes to
`data/storage`. Both fallbacks are logged at startup and are fine for a demo.

---

## 1. Configure

```bash
cp .env.example .env
```

Then set at least `SECRET_KEY`. Everything else has a working default:

| Variable | Default behaviour |
|---|---|
| `DATABASE_URL` | local Postgres (`docker compose` provides one) |
| `DATABASE_URL_UNPOOLED` | optional; used by Alembic when present (Neon) |
| `LLM_PROVIDER=simulation` | no external LLM calls |
| `WHISPER_MODEL=simulation` | deterministic transcripts |
| `BACKEND_CORS_ORIGINS` | `http://localhost:3000` |

---

## 2. Run the backend

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --port 8000
```

- API: <http://127.0.0.1:8000>
- Swagger UI: <http://127.0.0.1:8000/docs>
- Health: <http://127.0.0.1:8000/health>

The backend reads the `.env` in this folder (and a `backend/.env` if you create one).

## 3. Run the frontend

```bash
cd frontend
npm install
npm run dev
```

Set `NEXT_PUBLIC_API_URL` first - in PowerShell:

```powershell
$env:NEXT_PUBLIC_API_URL="http://127.0.0.1:8000"
npm run dev
```

Or copy `frontend/.env.example` to `frontend/.env.local`.

> `NEXT_PUBLIC_*` is inlined at build time. Restart the dev server after changing it.

Open <http://localhost:3000> and register.

## 4. Or run everything with Docker

```bash
docker compose up --build
```

| Service | URL |
|---|---|
| Frontend | <http://localhost:3000> |
| API | <http://localhost:8000> |
| MinIO console | <http://localhost:9001> |
| Qdrant | <http://localhost:6333> |

---

## 5. Database

```bash
cd backend
python -m alembic current        # applied revision
python -m alembic upgrade head   # apply pending
python -m alembic downgrade -1   # step back one revision
```

There are ten revisions, `0001_initial` through `0010_camera_pairings`. On Neon, point
`DATABASE_URL_UNPOOLED` at the direct endpoint so migrations do not run through PgBouncer.

---

## 6. Tests

From this folder:

```bash
pytest
```

From `frontend/`:

```bash
npm run build
```

End-to-end checks against a running API (run from `backend/`):

```bash
python scripts/verify_final_system.py
python scripts/verify_ipcam.py --help
```

---

## 7. Demo data

All seeders live in `backend/scripts/` and are run from `backend/`:

```bash
python scripts/seed_sample_data.py --base-url http://127.0.0.1:8000 --process
python scripts/seed_demo_videos.py
python scripts/seed_demo_evidence.py
python scripts/seed_demo_investigation.py
```

They create `sample.data@forensics-demo.com` / `sample12345` (ADMIN). Delete that account
before exposing the app publicly.

---

## 8. Common commands

| Task | Command |
|---|---|
| Backend dev server | `python -m uvicorn app.main:app --reload --port 8000` in `backend/` |
| Frontend dev server | `npm run dev` in `frontend/` |
| Production frontend build | `npm run build` in `frontend/` |
| Migrations | `python -m alembic upgrade head` in `backend/` |
| Tests | `pytest` here |
| Full stack | `docker compose up --build` here |
| Seed demo data | `python scripts/seed_sample_data.py --base-url http://127.0.0.1:8000` in `backend/` |

---

## 9. Troubleshooting quick hits

| Symptom | Cause / fix |
|---|---|
| Browser says "Login failed" but `curl` works | Origin not in `BACKEND_CORS_ORIGINS`. It must match scheme + host + port exactly. |
| Requests go to `127.0.0.1:8000` on a deployed site | `NEXT_PUBLIC_API_URL` was missing at build time - set it and rebuild. |
| `cannot open camera device index N` | No camera at that index. In a container that is always true; use the Simulation or IP-camera source. |
| `relation "users" does not exist` | Migrations not applied - `python -m alembic upgrade head`. |
| Backend restarts while processing a video | Out of memory (512 MB instances). Use a larger instance or shorter clips. |
| Qdrant/MinIO warnings at startup | Expected fallbacks (memory vectors, local disk). |

More: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) and [`WEBCAM_SETUP.md`](WEBCAM_SETUP.md).

---

## 10. Where to go next

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | components, data flow, module boundaries |
| [`docs/DEMO_GUIDE.md`](docs/DEMO_GUIDE.md) | seeded demo walkthrough |
| [`docs/OPERATIONS.md`](docs/OPERATIONS.md) | backups, health, restarts |
| [`docs/SECURITY.md`](docs/SECURITY.md) | authn/authz, secrets, hardening |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | failure playbook |
| [`../../DEPLOYMENT.md`](../../DEPLOYMENT.md) | Render + Netlify + Neon |
