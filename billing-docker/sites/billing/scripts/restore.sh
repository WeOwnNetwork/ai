#!/usr/bin/env bash
# weown-billing - Restore Script
# Restores PostgreSQL database and Keycloak data volumes from backup.
#
# Usage:
#   Remote mode (from your laptop):
#     ./restore.sh root@droplet-ip <backup-name-or-s3-url>
#   Local mode (on the droplet, already inside `infisical run`):
#     ./restore.sh <backup-name-or-s3-url>
#
# The script reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf
# (rendered by copier). Env vars override site.conf values if set.
#
# This script MUST be run WITHIN `infisical run` so that secrets
# (POSTGRES_PASSWORD, SPACES_ACCESS_KEY, SPACES_SECRET_KEY) are available.
# It will fail if run directly without Infisical injection.
#
# Backups can be specified as:
#   - Local filename:  weown-billing_backup_20260115_120000
#   - S3 URL:          s3://bucket-name/weown-billing/weown-billing_backup_20260115_120000.tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load site.conf (safe reader — only accepts UPPER_CASE=value lines)
source "$SCRIPT_DIR/lib.sh"
load_site_conf "$PROJECT_DIR/site.conf"

REMOTE="${2:-${1:-}}"
BACKUP_NAME="${1:-}"

if [[ $# -eq 2 ]]; then
  REMOTE="${1:-}"
  BACKUP_NAME="${2:-}"
elif [[ $# -eq 1 ]]; then
  REMOTE=""
  BACKUP_NAME="${1:-}"
else
  echo "Usage (remote): $0 [user@host] <backup-name>"
  echo "Usage (local):  $0 <backup-name>"
  echo ""
  echo "Examples:"
  echo "  $0 root@143.198.xxx.xxx weown-billing_backup_20260115_120000"
  echo "  $0 weown-billing_backup_20260115_120000"
  echo ""
  echo "Note: Run via Infisical on the droplet:"
  exit 1
fi

# Remote mode needs the Infisical project ID to wrap the droplet's restore.sh
# in `infisical run`. Local mode is already running inside `infisical run`
# (operator invokes via `infisical run -- ./restore.sh`) so its parent env
# already has SPACES_* - the script does not need to know the projectId.
if [[ -n "$REMOTE" ]]; then
  : "${INFISICAL_PROJECT_ID:?INFISICAL_PROJECT_ID not set. Fill in site.conf or set as env var.}"
fi
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

PROJECT_NAME="weown_billing"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

run_restore() {
  local host="$1"
  local backup_name="$2"

  read -r -d '' RESTORE_CMDS <<SCRIPT || true
set -euo pipefail

PROJECT_NAME="weown_billing"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"

# --- Verify Infisical secrets are available ---
if [[ -z "\${POSTGRES_PASSWORD:-}" ]]; then
  echo "ERROR: POSTGRES_PASSWORD is not set. Did you run this via 'infisical run'?"
  exit 1
fi

BACKUP_NAME="$backup_name"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
WORK_DIR="$BACKUP_DIR/${BACKUP_NAME}"

# --- Fetch backup from DO Spaces if not present locally ---
if [[ ! -f "\$BACKUP_FILE" && "$REMOTE_STORAGE" == "do-spaces" && -n "\${SPACES_ACCESS_KEY:-}" && -n "\${SPACES_SECRET_KEY:-}" ]]; then
  echo "==> Backup not found locally, fetching from DO Spaces..."
  mkdir -p "\$BACKUP_DIR"
  AWS_ACCESS_KEY_ID="\$SPACES_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="\$SPACES_SECRET_KEY" \
  aws s3 cp "s3://${SPACES_BUCKET}/weown-billing/${BACKUP_NAME}.tar.gz" \
    "\$BACKUP_FILE" \
    --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" \
    --quiet
  echo "==> Downloaded from DO Spaces"
fi

if [[ ! -f "\$BACKUP_FILE" ]]; then
  echo "ERROR: Backup not found: \$BACKUP_FILE"
  echo "Available local backups:"
  ls -1 "\$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "==> Restoring weown-billing from \$BACKUP_NAME"
echo ""

# --- Stop web to prevent writes during restore ---
echo "==> Stopping billing web..."
docker compose -f "\$APP_DIR/compose.yaml" stop web

# --- Extract archive ---
echo "==> Extracting archive..."
cd "\$BACKUP_DIR"
rm -rf "\$WORK_DIR"
tar xzf "\${BACKUP_NAME}.tar.gz"

# --- Restore PostgreSQL database ---
echo "==> Restoring PostgreSQL database..."
docker compose -f "\$APP_DIR/compose.yaml" exec -T db psql -U "\${POSTGRES_USER:-billing}" -d "\${POSTGRES_DB:-billing}" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
docker compose -f "\$APP_DIR/compose.yaml" exec -T db psql -U "\${POSTGRES_USER:-billing}" -d "\${POSTGRES_DB:-billing}" < "\$WORK_DIR/db.sql"
echo "    Database restore complete"


# --- Restore Caddy data volume (optional, if present in backup) ---
if [[ -f "\$WORK_DIR/caddy_data.tar.gz" ]]; then
  echo "==> Restoring Caddy data volume..."
  docker run --rm \
    -v "\${PROJECT_NAME}_caddy_data:/data" \
    -v "\$WORK_DIR:/backup:ro" \
    alpine:3.19 \
    tar xzf /backup/caddy_data.tar.gz -C /data
  echo "    Caddy data restore complete"
fi

# --- Cleanup ---
echo "==> Cleaning up..."
rm -rf "\$WORK_DIR"

# --- Start Keycloak ---
echo "==> Starting billing web..."
docker compose -f "\$APP_DIR/compose.yaml" start web

echo ""
echo "=== RESTORE COMPLETE ==="
echo "    Backup: \$BACKUP_NAME"
echo ""
echo "Verify status:"
echo "    ssh ${REMOTE:-root@<host>} 'cd \$APP_DIR && docker compose ps'"
echo ""
echo "Billing admin: https://billing.weown.dev/admin/"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running restore on remote: ${host}"
    # For remote execution, we SSH and then run infisical run on the host
    # because the backup script must have POSTGRES_PASSWORD available
    # $RESTORE_CMDS contains quotes of both kinds — ship it base64-encoded so
    # no quoting layer (local shell, ssh, remote shell) can mangle it.
    RESTORE_B64=$(printf '%s' "$RESTORE_CMDS" | base64 | tr -d '\n')
    ssh "$host" "source /opt/$PROJECT_NAME/.infisical-auth.env && export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=\"\$INFISICAL_CLIENT_ID\" && export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=\"\$INFISICAL_CLIENT_SECRET\" && export INFISICAL_TOKEN=\"\$(infisical login --method=universal-auth --plain --silent)\" && echo $RESTORE_B64 | base64 -d > /tmp/weown-restore-cmds.sh && infisical run --projectId=$INFISICAL_PROJECT_ID --env=$INFISICAL_ENV -- bash /tmp/weown-restore-cmds.sh; RC=\$?; rm -f /tmp/weown-restore-cmds.sh; exit \$RC"
  else
    echo "==> Running restore locally"
    eval "$RESTORE_CMDS"
  fi
}

echo "==> Restore requested: $BACKUP_NAME"
run_restore "$REMOTE" "$BACKUP_NAME"
