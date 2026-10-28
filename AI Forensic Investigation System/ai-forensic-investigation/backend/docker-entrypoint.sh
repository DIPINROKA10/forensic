#!/bin/sh
# Container entrypoint.
#
# Some Docker hosts (Render included) re-quote the image's CMD, which breaks
# `sh -c "long command"` one-liners: the whole string is treated as a single
# program name and the container exits with status 127. Running this script
# instead keeps the start command a single executable token, so nothing can be
# re-quoted or word-split.
set -e

PORT="${PORT:-8000}"

# Migrations are idempotent. Failures are logged but do not block startup:
# Alembic here needs the direct (unpooled) Neon URL, which may be unset on
# environments that never run migrations.
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    echo "==> alembic upgrade head"
    python -m alembic upgrade head || echo "WARN: migrations failed, starting API anyway"
fi

echo "==> uvicorn on 0.0.0.0:${PORT}"
exec python -m uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --proxy-headers \
    --forwarded-allow-ips="${FORWARDED_ALLOW_IPS:-*}"
