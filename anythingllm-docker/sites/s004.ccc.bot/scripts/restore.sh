#!/usr/bin/env bash
# int-s004-anythingllm - Restore Script
# Restores AnythingLLM storage volumes and configuration from backup.
#
# Usage:
#   Remote mode (from your laptop):
#     ./restore.sh root@droplet-ip <backup-name>
#   Local mode (on the droplet, already inside `infisical run`):
#     ./restore.sh <backup-name>
#
# This script MUST be run WITHIN `infisical run` so that secrets
# (SPACES_ACCESS_KEY, SPACES_SECRET_KEY) are available.
# It will fail if run directly without Infisical injection.
#
# Backups can be specified as:
#   - Local filename:  int-s004-anythingllm_backup_20260115_120000
#   - S3 path:         s3://bucket-name/int-s004-anythingllm/int-s004-anythingllm_backup_20260115_120000.tar.gz
set -euo pipefail

REMOTE=""
BACKUP_NAME=""

if [[ $# -eq 2 ]]; then
  REMOTE="$1"
  BACKUP_NAME="$2"
elif [[ $# -eq 1 ]]; then
  BACKUP_NAME="$1"
else
  echo "Usage (remote): INFISICAL_PROJECT_ID=<id> $0 [user@host] <backup-name>"
  echo "Usage (local):  $0 <backup-name>   # run on the droplet, already inside infisical run"
  echo ""
  echo "Examples:"
  echo "  INFISICAL_PROJECT_ID=abc123 $0 root@198.51.100.42 int-s004-anythingllm_backup_20260115_120000"
  echo "  $0 int-s004-anythingllm_backup_20260115_120000"
  exit 1
fi

# Remote mode needs the Infisical project ID to wrap the droplet's restore.sh
# in `infisical run`. Local mode is already running inside `infisical run`
# (operator invokes via `infisical run -- ./restore.sh`) so its parent env
# already has SPACES_* — the script does not need to know the projectId.
if [[ -n "$REMOTE" ]]; then
  : "${INFISICAL_PROJECT_ID:?Set INFISICAL_PROJECT_ID env var before running remote restore (same value as terraform.tfvars infisical_project_id)}"
fi
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

# Validate BACKUP_NAME — prevents shell-injection when interpolated into the
# remote ssh `bash -c '...'` command below. Names follow the backup.sh format
# `<project>_backup_YYYYMMDD_HHMMSS` so a strict allowlist is safe.
if [[ ! "$BACKUP_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid BACKUP_NAME (allowed: [A-Za-z0-9._-]): $BACKUP_NAME" >&2
  exit 1
fi

PROJECT_NAME="int_s004_anythingllm"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-backups"
SPACES_REGION="atl1"

run_restore() {
  local host="$1"
  local backup_name="$2"

  read -r -d '' RESTORE_CMDS <<SCRIPT || true
set -euo pipefail

PROJECT_NAME="int_s004_anythingllm"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"

BACKUP_NAME="$backup_name"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
WORK_DIR="$BACKUP_DIR/${BACKUP_NAME}"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-backups"
SPACES_REGION="atl1"

# --- Fetch backup from DO Spaces if not present locally ---
if [[ ! -f "\$BACKUP_FILE" && "$REMOTE_STORAGE" == "do-spaces" && -n "\${SPACES_ACCESS_KEY:-}" && -n "\${SPACES_SECRET_KEY:-}" ]]; then
  echo "==> Backup not found locally, fetching from DO Spaces..."
  mkdir -p "\$BACKUP_DIR"
  AWS_ACCESS_KEY_ID="\$SPACES_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="\$SPACES_SECRET_KEY" \
  aws s3 cp "s3://${SPACES_BUCKET}/int-s004-anythingllm/${BACKUP_NAME}.tar.gz" \
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

echo "==> Restoring int-s004-anythingllm from \$BACKUP_NAME"
echo ""

# --- Stop anythingllm to prevent writes during restore ---
echo "==> Stopping AnythingLLM..."
docker compose -f "\$APP_DIR/compose.yaml" stop anythingllm

# --- Extract archive ---
echo "==> Extracting archive..."
cd "\$BACKUP_DIR"
rm -rf "\$WORK_DIR"
tar xzf "\${BACKUP_NAME}.tar.gz"

# --- Restore AnythingLLM storage volume ---
echo "==> Restoring AnythingLLM storage volume..."
docker compose -f "\$APP_DIR/compose.yaml" run --rm -T --entrypoint sh anythingllm -c "rm -rf /app/server/storage/*" 2>/dev/null || true
docker run --rm \
  -v "int_s004_anythingllm_storage:/data" \
  -v "\$WORK_DIR:/backup:ro" \
  alpine:3.19 \
  tar xzf /backup/anythingllm_storage.tar.gz -C /data
echo "    AnythingLLM storage restore complete"

# --- Restore Caddy data volume (optional, if present in backup) ---
if [[ -f "\$WORK_DIR/caddy_data.tar.gz" ]]; then
  echo "==> Restoring Caddy data volume..."
  docker run --rm \
    -v "int_s004_anythingllm_caddy_data:/data" \
    -v "\$WORK_DIR:/backup:ro" \
    alpine:3.19 \
    tar xzf /backup/caddy_data.tar.gz -C /data
  echo "    Caddy data restore complete"
fi

# --- Restore configuration files ---
echo "==> Restoring configuration..."
cp "\$WORK_DIR/Caddyfile" "\$APP_DIR/Caddyfile" 2>/dev/null || true
cp "\$WORK_DIR/compose.yaml" "\$APP_DIR/compose.yaml" 2>/dev/null || true

# --- Cleanup ---
echo "==> Cleaning up..."
rm -rf "\$WORK_DIR"

# --- Start AnythingLLM ---
echo "==> Starting AnythingLLM..."
docker compose -f "\$APP_DIR/compose.yaml" start anythingllm

echo ""
echo "=== RESTORE COMPLETE ==="
echo "    Backup: \$BACKUP_NAME"
echo ""
echo "Verify status:"
echo "    ssh ${REMOTE:-root@<host>} 'cd \$APP_DIR && docker compose ps'"
echo ""
echo "AnythingLLM URL: https://s004.ccc.bot"
echo ""
echo "If the restored data includes workspace configurations, you may need to"
echo "restart the full stack for all settings to take effect:"
echo "    ssh ${REMOTE:-root@<host>} 'cd \$APP_DIR && docker compose restart'"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running restore on remote: ${host}"
    # Reuse the auth helper that cloud-init wrote on the droplet (contains the
    # Machine Identity Client ID + Secret, 0700 root). That `infisical login`
    # call seeds the local CLI session; then `infisical run` does the actual
    # secret injection. Both `--projectId` and `--env` come from the caller's
    # Invoke the DROPLET's restore.sh (uploaded by ansible) inside
    # `infisical run`. Passing the script body via `bash -c '$RESTORE_CMDS'`
    # is unsafe because RESTORE_CMDS contains literal single quotes.
    # The droplet has /opt/<project>/.infisical-auth.env (not .sh) written
    # by cloud-init; we source it + run `infisical login` here, then exec
    # the droplet's restore.sh with the backup name as positional arg.
    ssh "$host" \
      "INFISICAL_PROJECT_ID='$INFISICAL_PROJECT_ID' INFISICAL_ENV='$INFISICAL_ENV' PROJECT_NAME='int_s004_anythingllm' BACKUP_NAME='$BACKUP_NAME' bash -s" <<'EOF'
set -euo pipefail
source "/opt/$PROJECT_NAME/.infisical-auth.env"
infisical login --method=universal-auth \
  --clientId="$INFISICAL_CLIENT_ID" \
  --clientSecret="$INFISICAL_CLIENT_SECRET" \
  --silent
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" \
  -- "/opt/$PROJECT_NAME/restore.sh" "$BACKUP_NAME"
EOF
  else
    echo "==> Running restore locally"
    eval "$RESTORE_CMDS"
  fi
}

echo "==> Restore requested: $BACKUP_NAME"
run_restore "$REMOTE" "$BACKUP_NAME"
