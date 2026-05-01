#!/usr/bin/env bash
# burnedout-xyz — Pull production DB + wp-content to local dev
#
# Usage:
#   ./pull-prod.sh [OPTIONS] [prod-host]
#
# Options:
#   --db-only        Pull database only (skip wp-content sync)
#   --content-only   Pull wp-content only (skip database)
#   --no-import      Download files only; do not import into local stack
#   --port PORT      Local HTTP port (default: 8080)
#
# What it does:
#   1. SSH to production, dump the DB using the REAL container password
#      (reads from docker inspect — .env may be stale)
#   2. Downloads the dump to ./wordpress.sql (gitignored)
#   3. Streams wp-content directly from prod container to local container
#   4. Imports the DB into the local burnedout-local stack
#   5. Updates siteurl + home to http://localhost:PORT
#
# When to use:
#   - Starting local development and you want real production data
#   - Debugging a prod issue locally
#   - Validating a plugin update before applying to production
#
# Prerequisites:
#   - SSH access to prod host (default: root@burnedout.xyz)
#   - Local stack running OR it will be started automatically
#
# See also:
#   backup.sh   — full snapshot backup to ~/backups/ (schedule this via cron)
#   restore.sh  — restore from a backup archive

set -euo pipefail

PROD_HOST="${PROD_HOST:-root@burnedout.xyz}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
PROJECT_NAME="burnedout"
LOCAL_PROJECT="burnedout-local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/../docker"
DUMP_FILE="${SCRIPT_DIR}/../wordpress.sql"  # gitignored via *.sql in .gitignore

DB_ONLY=false
CONTENT_ONLY=false
NO_IMPORT=false

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-only)       DB_ONLY=true;      shift ;;
    --content-only)  CONTENT_ONLY=true; shift ;;
    --no-import)     NO_IMPORT=true;    shift ;;
    --port)          LOCAL_PORT="$2";   shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0 ;;
    -*)
      echo "Unknown flag: $1  (try --help)"
      exit 1 ;;
    *)
      PROD_HOST="$1"
      shift ;;
  esac
done

echo "╔══════════════════════════════════════════════════╗"
echo "║  burnedout-xyz — Pull Production to Local        ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  Prod host:     ${PROD_HOST}"
echo "  Local port:    ${LOCAL_PORT}"
echo "  DB only:       ${DB_ONLY}"
echo "  Content only:  ${CONTENT_ONLY}"
echo "  No import:     ${NO_IMPORT}"
echo ""
echo "  ⚠️  This will OVERWRITE your local database and wp-content."
echo ""
read -rp "Continue? [y/N] " -n 1
echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Step 1: Dump DB on production ─────────────────────────────────────────────
if [[ "$CONTENT_ONLY" == "false" ]]; then
  echo "==> Dumping production database..."

  # shellcheck disable=SC2087
  ssh "$PROD_HOST" bash << 'REMOTE'
set -euo pipefail
PROJECT_NAME="burnedout"

# Read credentials from the RUNNING container — not .env (they may differ)
DB_ROOT_PASS=$(docker inspect "${PROJECT_NAME}-db-1" \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -E '^MARIADB_ROOT_PASSWORD=|^MYSQL_ROOT_PASSWORD=' | head -1 | cut -d= -f2-)

DB_NAME=$(docker inspect "${PROJECT_NAME}-db-1" \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep '^MYSQL_DATABASE=' | head -1 | cut -d= -f2-)
DB_NAME="${DB_NAME:-wordpress}"

if [[ -z "$DB_ROOT_PASS" ]]; then
  echo "ERROR: Could not read DB password from container ${PROJECT_NAME}-db-1"
  echo "       Is the container running? Try: docker ps | grep ${PROJECT_NAME}-db"
  exit 1
fi

echo "  Database: ${DB_NAME}"
docker exec "${PROJECT_NAME}-db-1" mariadb-dump \
  -u root -p"${DB_ROOT_PASS}" \
  --single-transaction --routines --triggers \
  "${DB_NAME}" > /tmp/wordpress-pull.sql

DUMP_SIZE=$(wc -c < /tmp/wordpress-pull.sql)
echo "  Dump size: ${DUMP_SIZE} bytes"

if [[ "$DUMP_SIZE" -lt 1000 ]]; then
  echo "ERROR: Dump is suspiciously small — aborting"
  cat /tmp/wordpress-pull.sql
  rm -f /tmp/wordpress-pull.sql
  exit 1
fi
REMOTE

  echo "==> Downloading database dump..."
  scp "${PROD_HOST}:/tmp/wordpress-pull.sql" "${DUMP_FILE}"
  ssh "${PROD_HOST}" "rm -f /tmp/wordpress-pull.sql"
  echo "    Saved: ${DUMP_FILE} ($(du -sh "${DUMP_FILE}" | cut -f1))"
fi

# ── Step 2: Ensure local stack is up ──────────────────────────────────────────
if [[ "$NO_IMPORT" == "false" ]]; then
  cd "$DOCKER_DIR"
  echo "==> Checking local stack..."
  if ! COMPOSE_PROJECT_NAME="${LOCAL_PROJECT}" docker compose -f compose.local.yaml ps -q db 2>/dev/null | grep -q .; then
    echo "    Starting local stack..."
    COMPOSE_PROJECT_NAME="${LOCAL_PROJECT}" docker compose -f compose.local.yaml up -d
    echo "    Waiting for DB to be healthy (30s)..."
    sleep 30
  else
    echo "    Local stack is running ✓"
  fi
  # Load local credentials
  set -a; source .env; set +a
fi

# ── Step 3: Import DB locally ──────────────────────────────────────────────────
if [[ "$CONTENT_ONLY" == "false" ]] && [[ "$NO_IMPORT" == "false" ]]; then
  if [[ ! -s "$DUMP_FILE" ]]; then
    echo "ERROR: Dump file is empty or missing: ${DUMP_FILE}"
    exit 1
  fi
  echo "==> Importing database into local stack..."
  COMPOSE_PROJECT_NAME="${LOCAL_PROJECT}" docker compose -f compose.local.yaml exec -T db \
    mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < "${DUMP_FILE}"
  echo "    ✓ Database imported"

  echo "==> Fixing URLs (https://burnedout.xyz → http://localhost:${LOCAL_PORT})..."
  COMPOSE_PROJECT_NAME="${LOCAL_PROJECT}" docker compose -f compose.local.yaml exec -T db \
    mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" \
    -e "UPDATE wp_options SET option_value='http://localhost:${LOCAL_PORT}' WHERE option_name IN ('siteurl','home');"
  echo "    ✓ siteurl + home → http://localhost:${LOCAL_PORT}"
fi

# ── Step 4: Stream wp-content from prod ───────────────────────────────────────
if [[ "$DB_ONLY" == "false" ]]; then
  echo "==> Pulling wp-content from production..."
  if [[ "$NO_IMPORT" == "true" ]]; then
    echo "    --no-import set: skipping wp-content sync (use backup.sh for offline archives)"
  else
    WP_CONTAINER=$(COMPOSE_PROJECT_NAME="${LOCAL_PROJECT}" docker compose -f compose.local.yaml ps -q wordpress 2>/dev/null || true)
    if [[ -z "$WP_CONTAINER" ]]; then
      echo "ERROR: WordPress container not running — start the local stack first"
      exit 1
    fi
    # Stream directly: prod container → local container (no large temp file on disk)
    ssh "${PROD_HOST}" \
      "docker exec ${PROJECT_NAME}-wordpress-1 tar czf - -C /var/www/html wp-content" \
      | docker exec -i "$WP_CONTAINER" tar xzf - -C /var/www/html/
    echo "    ✓ wp-content synced"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  PULL COMPLETE                                   ║"
echo "╚══════════════════════════════════════════════════╝"
if [[ "$NO_IMPORT" == "true" ]]; then
  [[ "$CONTENT_ONLY" == "false" ]] && echo "  DB dump:  ${DUMP_FILE}"
  echo "  To import manually, see: scripts/restore.sh local <backup>"
else
  echo "  Local site: http://localhost:${LOCAL_PORT}"
  echo "  wp-admin:   http://localhost:${LOCAL_PORT}/wp-admin/"
  echo "  Credentials: use your production admin username/password"
fi
