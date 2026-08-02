#!/bin/sh
# Runs INSIDE `infisical run` (compose entrypoint) — secrets are in env here.
set -eu
python manage.py migrate --noinput
python manage.py collectstatic --noinput
# Break-glass local superuser (idempotent). Own email per break-glass rule —
# never a human's (Gitea auto-link incident, board row 19).
python manage.py ensure_break_glass
exec gunicorn billing.wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 60
