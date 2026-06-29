#!/usr/bin/env bash
# claw-weown-dev - Restore Script
# Restores OpenClaw storage volumes and configuration from backup.
#
# Usage:
#   Remote mode (from your laptop):
#     ./restore.sh root@droplet-ip <backup-name>
#   Local mode (on the droplet, already inside `infisical run`):
#     ./restore.sh <backup-name>
#
# The script reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf
# (rendered by copier). Env vars override site.conf values if set.
#
# This script MUST be run WITHIN `infisical run` so that secrets
# (SPACES_ACCESS_KEY, SPACES_SECRET_KEY) are available.
# It will fail if run directly without Infisical injection.
#
# Pass the backup NAME only (no path, no .tar.gz extension), e.g.
#   claw-weown-dev_backup_20260115_120000
# It must match the backup.sh format `<project>_backup_YYYYMMDD_HHMMSS` and the
# allowlist ^[A-Za-z0-9._-]+$. If the tarball is not already under
# /opt/<project>/backups/, the script auto-fetches it from DO Spaces at
# s3://weown-dev-backup/claw-weown-dev/<name>.tar.gz. Do NOT pass an
# s3:// URL or a path; the name validation will reject it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load site.conf (safe reader — only accepts UPPER_CASE=value lines)
source "$SCRIPT_DIR/lib.sh"
load_site_conf "$PROJECT_DIR/site.conf"

REMOTE=""
BACKUP_NAME=""

if [[ $# -eq 2 ]]; then
  REMOTE="$1"
  BACKUP_NAME="$2"
elif [[ $# -eq 1 ]]; then
  BACKUP_NAME="$1"
else
  echo "Usage (remote): $0 [user@host] <backup-name>"
  echo "Usage (local):  $0 <backup-name>   # run on the droplet, already inside infisical run"
  echo ""
  echo "Examples:"
  echo "  $0 root@198.51.100.42 claw-weown-dev_backup_20260115_120000"
  echo "  $0 claw-weown-dev_backup_20260115_120000"
  echo ""
  echo "Config: reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf"
  echo "        (env vars override site.conf values)"
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

# Validate BACKUP_NAME — prevents shell-injection when interpolated into the
# remote ssh `bash -c '...'` command below. Names follow the backup.sh format
# `<project>_backup_YYYYMMDD_HHMMSS` so a strict allowlist is safe.
if [[ ! "$BACKUP_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid BACKUP_NAME (allowed: [A-Za-z0-9._-]): $BACKUP_NAME" >&2
  exit 1
fi

PROJECT_NAME="claw_weown_dev"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-dev-backup"
SPACES_REGION="atl1"

run_restore() {
  local host="$1"
  local backup_name="$2"

  read -r -d '' RESTORE_CMDS <<SCRIPT || true
set -euo pipefail

PROJECT_NAME="claw_weown_dev"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"

BACKUP_NAME="$backup_name"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
WORK_DIR="$BACKUP_DIR/${BACKUP_NAME}"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-dev-backup"
SPACES_REGION="atl1"

# --- Fetch backup from DO Spaces if not present locally ---
if [[ ! -f "\$BACKUP_FILE" && "$REMOTE_STORAGE" == "do-spaces" && -n "\${SPACES_ACCESS_KEY:-}" && -n "\${SPACES_SECRET_KEY:-}" ]]; then
  echo "==> Backup not found locally, fetching from DO Spaces..."
  mkdir -p "\$BACKUP_DIR"
  AWS_ACCESS_KEY_ID="\$SPACES_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="\$SPACES_SECRET_KEY" \
  aws s3 cp "s3://${SPACES_BUCKET}/claw-weown-dev/${BACKUP_NAME}.tar.gz" \
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

echo "==> Restoring claw-weown-dev from \$BACKUP_NAME"
echo ""

# --- Stop openclaw to prevent writes during restore ---
echo "==> Stopping OpenClaw..."
docker compose -f "\$APP_DIR/compose.yaml" stop openclaw

# --- Extract archive ---
echo "==> Extracting archive..."
cd "\$BACKUP_DIR"
rm -rf "\$WORK_DIR"
tar xzf "\${BACKUP_NAME}.tar.gz"

# --- Restore OpenClaw config volume (/home/node/.openclaw) ---
echo "==> Restoring OpenClaw config volume..."
docker compose -f "\$APP_DIR/compose.yaml" run --rm -T --entrypoint sh openclaw -c "rm -rf /home/node/.openclaw/*" 2>/dev/null || true
docker run --rm \
  -v "claw_weown_dev_data:/data" \
  -v "\$WORK_DIR:/backup:ro" \
  alpine:3.19 \
  tar xzf /backup/openclaw_data.tar.gz -C /data
echo "    OpenClaw config restore complete"

# --- Restore OpenClaw workspace volume (/home/node/openclaw/workspace) ---
echo "==> Restoring OpenClaw workspace volume..."
docker compose -f "\$APP_DIR/compose.yaml" run --rm -T --entrypoint sh openclaw -c "rm -rf /home/node/openclaw/workspace/*" 2>/dev/null || true
docker run --rm \
  -v "claw_weown_dev_workspace:/data" \
  -v "\$WORK_DIR:/backup:ro" \
  alpine:3.19 \
  tar xzf /backup/openclaw_workspace.tar.gz -C /data
echo "    OpenClaw workspace restore complete"

# --- Restore Caddy data volume (optional, if present in backup) ---
if [[ -f "\$WORK_DIR/caddy_data.tar.gz" ]]; then
  echo "==> Restoring Caddy data volume..."
  docker run --rm \
    -v "claw_weown_dev_caddy_data:/data" \
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

# --- Start OpenClaw ---
echo "==> Starting OpenClaw..."
docker compose -f "\$APP_DIR/compose.yaml" start openclaw

echo ""
echo "=== RESTORE COMPLETE ==="
echo "    Backup: \$BACKUP_NAME"
echo ""
echo "Verify status:"
echo "    ssh ${REMOTE:-root@<host>} 'cd \$APP_DIR && docker compose ps'"
echo ""
echo "OpenClaw URL: https://claw.weown.dev"
echo ""
echo "If the restored data includes workspace configurations, you may need to"
echo "restart the full stack for all settings to take effect:"
echo "    ssh ${REMOTE:-root@<host>} 'cd \$APP_DIR && docker compose restart'"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running restore on remote: ${host}"
    # Operator-side decryption IF this instance has encrypted backups (H1/A331):
    # the GPG PRIVATE key is off-box, here on the operator's trusted host. Try to
    # fetch <name>.tar.gz.gpg; if present, decrypt locally and push the PLAINTEXT
    # to the droplet for the volume restore. If absent (legacy instance with
    # plaintext backups), fall through — the on-droplet logic fetches the plain
    # .tar.gz as before. The droplet never holds the private key.
    LOCAL_TMP="$(mktemp -d)"; ENC="$LOCAL_TMP/${backup_name}.tar.gz.gpg"
    if AWS_ACCESS_KEY_ID="${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY not set — run inside 'infisical run'}" \
       AWS_SECRET_ACCESS_KEY="${SPACES_SECRET_KEY:?SPACES_SECRET_KEY not set}" \
       aws s3 cp "s3://${SPACES_BUCKET}/claw-weown-dev/${backup_name}.tar.gz.gpg" "$ENC" \
         --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" --quiet 2>/dev/null; then
      echo "==> Encrypted backup found — decrypting with your GPG private key (off-box)..."
      gpg --batch --quiet --decrypt --output "$LOCAL_TMP/${backup_name}.tar.gz" "$ENC" \
        || { echo "ERROR: GPG decryption failed — is the recipient PRIVATE key in your keyring / hardware token?" >&2; rm -rf "$LOCAL_TMP"; exit 1; }
      echo "==> Pushing the decrypted archive to the droplet for restore..."
      ssh "$host" "mkdir -p '$BACKUP_DIR'"
      scp -q "$LOCAL_TMP/${backup_name}.tar.gz" "$host:$BACKUP_DIR/${backup_name}.tar.gz"
      shred -u "$LOCAL_TMP/${backup_name}.tar.gz" "$ENC" 2>/dev/null || rm -f "$LOCAL_TMP/${backup_name}.tar.gz" "$ENC"
    else
      echo "==> No encrypted backup in Spaces; using the legacy plaintext path."
    fi
    rm -rf "$LOCAL_TMP"
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
      "INFISICAL_PROJECT_ID='$INFISICAL_PROJECT_ID' INFISICAL_ENV='$INFISICAL_ENV' PROJECT_NAME='claw_weown_dev' BACKUP_NAME='$BACKUP_NAME' bash -s" <<'EOF'
set -euo pipefail
source "/opt/$PROJECT_NAME/.infisical-auth.env"
export INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --plain --silent)"
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" \
  -- "/opt/$PROJECT_NAME/restore.sh" "$BACKUP_NAME"
EOF
  else
    # Local mode runs ON the droplet, which has no private key (A331). It can
    # only restore a PLAINTEXT archive that an operator already decrypted and
    # placed here. If only the encrypted copy is present, refuse and point to
    # remote mode (which decrypts on the operator's trusted host).
    if [[ ! -f "$BACKUP_DIR/${backup_name}.tar.gz" && -f "$BACKUP_DIR/${backup_name}.tar.gz.gpg" ]]; then
      echo "ERROR: only the ENCRYPTED backup is on this droplet and the GPG private" >&2
      echo "       key is off-box. Run restore from your trusted host in REMOTE mode:" >&2
      echo "         infisical run -- ./scripts/restore.sh root@<this-droplet> ${backup_name}" >&2
      exit 1
    fi
    echo "==> Running restore locally"
    eval "$RESTORE_CMDS"
  fi
}

echo "==> Restore requested: $BACKUP_NAME"
run_restore "$REMOTE" "$BACKUP_NAME"
