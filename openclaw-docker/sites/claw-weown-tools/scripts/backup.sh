#!/usr/bin/env bash
# claw-weown-tools - Backup Script
set -euo pipefail

REMOTE="${1:-}"
PROJECT_NAME="claw-weown-tools"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
RETENTION_DAYS=30

run_backup() {
  local host="$1"

  read -r -d '' BACKUP_CMDS <<'SCRIPT' || true
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECT_NAME="claw-weown-tools"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
BACKUP_NAME="${PROJECT_NAME}-backup-${TIMESTAMP}"
WORK_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

echo "==> Creating backup directory: ${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "==> Copying OpenClaw config..."
docker cp ${PROJECT_NAME}-openclaw-1:/home/node/.openclaw "${WORK_DIR}/openclaw-config"

echo "==> Copying OpenClaw workspace..."
docker cp ${PROJECT_NAME}-openclaw-1:/home/node/openclaw/workspace "${WORK_DIR}/openclaw-workspace"

echo "==> Copying configs..."
cp "${APP_DIR}/Caddyfile" "${WORK_DIR}/Caddyfile"
cp "${APP_DIR}/.env" "${WORK_DIR}/dot-env"
cp "${APP_DIR}/compose.yaml" "${WORK_DIR}/compose.yaml"

echo "==> Recording container state..."
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > "${WORK_DIR}/containers.txt"

echo "==> Compressing..."
cd "${BACKUP_DIR}"
tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
rm -rf "${WORK_DIR}"

FINAL_SIZE=$(ls -lh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | awk '{print $5}')
echo ""
echo "=== BACKUP COMPLETE ==="
echo "File: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo "Size: ${FINAL_SIZE}"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running backup on remote: ${host}"
    ssh "$host" "$BACKUP_CMDS"
  else
    eval "$BACKUP_CMDS"
  fi
}

run_backup "$REMOTE"

if [[ -n "$REMOTE" ]]; then
  ssh "$REMOTE" "find ${BACKUP_DIR} -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete"
fi
