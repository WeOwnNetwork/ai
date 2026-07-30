#!/usr/bin/env bash
# supabase-dev - Skinny Backup Script
# Backs up the Supabase Postgres database (all schemas incl. pop / auth /
# public / _realtime / storage), persistent volumes, and configuration.
#
# Usage:
#   Remote mode (from your laptop):
#     ./backup.sh root@droplet-ip
#   Local mode (on the droplet, already inside `infisical run`):
#     ./backup.sh
#
# The script reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf
# (rendered by copier). Env vars override site.conf values if set.
#
# This script is designed to run WITHIN `infisical run` so that secrets
# (POSTGRES_PASSWORD, SPACES_ACCESS_KEY, SPACES_SECRET_KEY) are available as
# environment variables. Do NOT run directly on the droplet without Infisical
# injection — the backup will fail because DB credentials are not on disk.
#
# Retention policy (grandfather-father-son):
#   - Daily backups: retained for 30 days
#   - Monthly backups (1st of month): retained for 12 months
#   - Yearly backups (Jan 1st): kept forever
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load site.conf (safe reader — only accepts UPPER_CASE=value lines)
source "$SCRIPT_DIR/lib.sh"
load_site_conf "$PROJECT_DIR/site.conf"

REMOTE="${1:-}"
# Required for remote mode: the Infisical project ID for `infisical run`.
# Local mode runs inside `infisical run` already, so env is pre-set.
if [[ -n "$REMOTE" ]]; then
  : "${INFISICAL_PROJECT_ID:?INFISICAL_PROJECT_ID not set. Fill in site.conf or set as env var.}"
fi
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

# Project directory name — matches the volume prefix that compose.prod.yaml.jinja
# sets via `name: supabase_dev_<volume>`.
PROJECT_NAME="supabase_dev"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="supabase-dev_backup_$TIMESTAMP"
WORK_DIR="$BACKUP_DIR/$BACKUP_NAME"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

run_backup() {
  local host="$1"

  read -r -d '' BACKUP_CMDS <<'SCRIPT' || true
set -euo pipefail

PROJECT_NAME="supabase_dev"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="supabase-dev_backup_$TIMESTAMP"
WORK_DIR="$BACKUP_DIR/$BACKUP_NAME"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

mkdir -p "$WORK_DIR"
echo "==> Creating backup: $BACKUP_NAME"

# --- Verify Infisical secrets are available ---
if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  echo "ERROR: POSTGRES_PASSWORD is not set. Did you run this via 'infisical run'?"
  exit 1
fi

# --- Database dump (all schemas: pop, auth, public, _realtime, storage, extensions) ---
# Use `pg_dumpall` for cluster-wide dump including roles + role memberships,
# which Supabase relies on (anon, authenticated, service_role, supabase_auth_admin,
# supabase_storage_admin, supabase_realtime_admin). Fallback to pg_dump if the
# bundled image's pg_dumpall is missing extensions support.
echo "==> Dumping PostgreSQL cluster (pg_dumpall, includes roles)..."
docker compose -f "$APP_DIR/compose.yaml" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  pg_dumpall -U "${POSTGRES_USER:-postgres}" \
  --clean --if-exists --no-role-passwords \
  > "$WORK_DIR/cluster.sql"

CLUSTER_SIZE=$(wc -c < "$WORK_DIR/cluster.sql")
echo "    Cluster dump: $CLUSTER_SIZE bytes"

# Also take a focused pg_dump of the application DB so restores that don't
# need cluster-wide roles can use a smaller, safer file.
echo "==> Dumping Supabase database (pg_dump, single-tx)..."
docker compose -f "$APP_DIR/compose.yaml" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  pg_dump -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" \
  --no-owner --no-privileges \
  > "$WORK_DIR/db.sql"

DB_SIZE=$(wc -c < "$WORK_DIR/db.sql")
echo "    Database dump: $DB_SIZE bytes"

# --- Named volume backups using ephemeral alpine containers ---
# Volume names follow supabase_dev_<volume>
# as set in compose.prod.yaml.jinja `volumes.<vol>.name`.

# DB volume — note: pg_dump above is the canonical restore path; the raw
# volume tarball is a belt-and-braces second copy for catastrophic recovery
# (filesystem corruption, schema-mismatch on a future Postgres major bump).
echo "==> Backing up Postgres data volume..."
docker run --rm \
  -v "${PROJECT_NAME}_db_data:/data:ro" \
  -v "$WORK_DIR:/backup" \
  alpine:3.19 \
  tar czf /backup/db_data.tar.gz -C /data .

echo "==> Backing up Caddy data volume..."
docker run --rm \
  -v "${PROJECT_NAME}_caddy_data:/data:ro" \
  -v "$WORK_DIR:/backup" \
  alpine:3.19 \
  tar czf /backup/caddy_data.tar.gz -C /data .

echo "==> Backing up Caddy config volume..."
docker run --rm \
  -v "${PROJECT_NAME}_caddy_config:/data:ro" \
  -v "$WORK_DIR:/backup" \
  alpine:3.19 \
  tar czf /backup/caddy_config.tar.gz -C /data .

# --- Configuration snapshots ---
cp "$APP_DIR/Caddyfile" "$WORK_DIR/"
cp "$APP_DIR/compose.yaml" "$WORK_DIR/"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > "$WORK_DIR/containers.txt"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' > "$WORK_DIR/images.txt"

# --- Compress ---
echo "==> Compressing backup..."
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$WORK_DIR"

FINAL_SIZE=$(ls -lh "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | awk '{print $5}')
echo "==> Local backup complete: $BACKUP_DIR/${BACKUP_NAME}.tar.gz ($FINAL_SIZE)"

# --- Remote upload (DO Spaces) ---
# Off-box storage is the contract: if it is configured, a run without it is a
# FAILED run — and it must abort BEFORE retention prunes local copies (see
# ai #134/#136: warning-and-exit-0 let daily crons report success while no
# object ever reached the bucket).
if [[ "$REMOTE_STORAGE" == "do-spaces" ]]; then
  if [[ -z "${SPACES_ACCESS_KEY:-}" ]] || [[ -z "${SPACES_SECRET_KEY:-}" ]]; then
    echo "ERROR: REMOTE_STORAGE=do-spaces but SPACES_ACCESS_KEY / SPACES_SECRET_KEY not set." >&2
    echo "       Refusing to report success (or run retention) without the off-box copy." >&2
    exit 1
  fi
  echo "==> Uploading to DO Spaces (s3://${SPACES_BUCKET}/supabase-dev/)..."
  export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"
  aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" \
    "s3://${SPACES_BUCKET}/supabase-dev/" \
    --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" \
    --quiet
  # `cp` exiting 0 is not proof of an object — assert it exists remotely with
  # the exact local size before claiming success.
  LOCAL_BYTES=$(wc -c < "$BACKUP_DIR/${BACKUP_NAME}.tar.gz")
  REMOTE_BYTES=$(aws s3 ls "s3://${SPACES_BUCKET}/supabase-dev/$(basename "$BACKUP_DIR/${BACKUP_NAME}.tar.gz")" \
    --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" \
    | awk '{print $3}' | tail -1)
  if [[ -z "$REMOTE_BYTES" || "$REMOTE_BYTES" != "$LOCAL_BYTES" ]]; then
    echo "ERROR: remote object missing or size mismatch (local ${LOCAL_BYTES} bytes, remote '${REMOTE_BYTES:-none}')." >&2
    exit 1
  fi
  echo "==> Remote backup verified: $(basename "$BACKUP_DIR/${BACKUP_NAME}.tar.gz") (${REMOTE_BYTES} bytes in s3://${SPACES_BUCKET}/supabase-dev/)"
fi

# --- Grandfather-Father-Son retention ---
echo "==> Applying retention policy (daily 30d / monthly 12mo / yearly forever)..."
find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" | while read -r f; do
  BASENAME=$(basename "$f")
  if [[ "$BASENAME" =~ _backup_([0-9]{8})_([0-9]{6})\.tar\.gz$ ]]; then
    FILE_DATE="${BASH_REMATCH[1]}"
    YEAR="${FILE_DATE:0:4}"
    MONTH="${FILE_DATE:4:2}"
    DAY="${FILE_DATE:6:2}"

    FILE_EPOCH=$(date -d "$YEAR-$MONTH-$DAY" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - FILE_EPOCH) / 86400 ))

    KEEP=false
    if [[ $AGE_DAYS -lt 30 ]]; then
      KEEP=true
    elif [[ $AGE_DAYS -lt 365 && "$DAY" == "01" ]]; then
      KEEP=true
    elif [[ "$DAY" == "01" && "$MONTH" == "01" ]]; then
      KEEP=true
    fi

    if [[ "$KEEP" == "false" ]]; then
      echo "    Removing $BASENAME (${AGE_DAYS}d old)"
      rm -f "$f"
    fi
  fi
done
echo "==> Retention cleanup complete"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running backup on remote: ${host}"
    # Invoke the DROPLET'S backup.sh (uploaded earlier by ansible) inside
    # `infisical run` so SPACES_* + POSTGRES_PASSWORD are in env. The Machine
    # Identity creds live at /opt/<project>/.infisical-auth.env (0600 root)
    # written by cloud-init.
    ssh "$host" \
      "INFISICAL_PROJECT_ID='$INFISICAL_PROJECT_ID' INFISICAL_ENV='$INFISICAL_ENV' PROJECT_NAME='$PROJECT_NAME' bash -s" <<'EOF'
set -euo pipefail
source "/opt/$PROJECT_NAME/.infisical-auth.env"
infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --silent
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" \
  -- "/opt/$PROJECT_NAME/backup.sh"
EOF

    # Optionally pull the backup locally
    read -p "Pull backup to local machine? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      LOCAL_BACKUP_DIR="$(dirname "$SCRIPT_DIR")/backups"
      mkdir -p "$LOCAL_BACKUP_DIR"

      LATEST_BACKUP=$(ssh "$host" "ls -t ${BACKUP_DIR}/*.tar.gz 2>/dev/null | head -1")
      if [[ -n "$LATEST_BACKUP" ]]; then
        echo "==> Downloading: $(basename "$LATEST_BACKUP")"
        scp "$host:$LATEST_BACKUP" "$LOCAL_BACKUP_DIR/"
        echo "==> Saved to: $LOCAL_BACKUP_DIR/$(basename "$LATEST_BACKUP")"
      else
        echo "WARNING: No backup files found on remote"
      fi
    fi
  else
    echo "==> Running backup locally"
    eval "$BACKUP_CMDS"
  fi
}

# Main
run_backup "$REMOTE"

echo ""
echo "=== BACKUP FINISHED ==="
echo ""
echo "To restore from this backup:"
echo "  ./scripts/restore.sh ${REMOTE:-<host>} $BACKUP_NAME"
echo ""
echo "To list remote backups (DO Spaces):"
echo "  aws s3 ls s3://${SPACES_BUCKET}/supabase-dev/ --endpoint-url https://${SPACES_REGION}.digitaloceanspaces.com"
