#!/usr/bin/env bash
# ptoken-agency - Skinny Backup Script
set -euo pipefail

REMOTE="${1:-}"
PROJECT_NAME="ptoken"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
RETENTION_DAYS=30

run_backup() {
  local host="$1"

  read -r -d '' BACKUP_CMDS <<'SCRIPT' || true
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECT_NAME="ptoken"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
BACKUP_NAME="${PROJECT_NAME}-backup-${TIMESTAMP}"
WORK_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

echo "==> Creating backup: ${BACKUP_NAME}"
mkdir -p "${WORK_DIR}"

set -a
source "${APP_DIR}/.env"
set +a

echo "==> Dumping MariaDB database..."
docker exec ${PROJECT_NAME}-db-1 mariadb-dump \
  -u root \
  -p"${MYSQL_ROOT_PASSWORD}" \
  --single-transaction \
  --routines \
  --triggers \
  "${MYSQL_DATABASE}" > "${WORK_DIR}/wordpress.sql"

DB_SIZE=$(wc -c < "${WORK_DIR}/wordpress.sql")
echo "    Database dump: ${DB_SIZE} bytes"

echo "==> Copying wp-content..."
docker cp ${PROJECT_NAME}-wordpress-1:/var/www/html/wp-content "${WORK_DIR}/wp-content"

echo "==> Copying wp-config.php..."
docker cp ${PROJECT_NAME}-wordpress-1:/var/www/html/wp-config.php "${WORK_DIR}/wp-config.php" 2>/dev/null || true

echo "==> Copying configs..."
cp "${APP_DIR}/Caddyfile" "${WORK_DIR}/Caddyfile"
cp "${APP_DIR}/.env" "${WORK_DIR}/dot-env"
cp "${APP_DIR}/compose.yaml" "${WORK_DIR}/compose.yaml"

if [[ -d "${APP_DIR}/wordfence-waf" ]]; then
  cp -r "${APP_DIR}/wordfence-waf" "${WORK_DIR}/"
fi

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
    # shellcheck disable=SC2029
    ssh "$host" "$BACKUP_CMDS"
  else
    eval "$BACKUP_CMDS"
  fi
}

run_backup "$REMOTE"

if [[ -n "$REMOTE" ]]; then
  # shellcheck disable=SC2029
  ssh "$REMOTE" "find ${BACKUP_DIR} -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete"
fi
