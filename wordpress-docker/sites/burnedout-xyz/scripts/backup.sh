#!/usr/bin/env bash
# burnedout-xyz - Skinny Backup Script
set -euo pipefail

REMOTE="${1:-}"
PROJECT_NAME="burnedout"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
RETENTION_DAYS=30

run_backup() {
  local host="$1"

  read -r -d '' BACKUP_CMDS <<'SCRIPT' || true
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECT_NAME="burnedout"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
BACKUP_NAME="${PROJECT_NAME}-backup-${TIMESTAMP}"
WORK_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

echo "==> Creating backup directory: ${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# Read credentials from the RUNNING container — not .env (they may differ)
DB_ROOT_PASS=$(docker inspect ${PROJECT_NAME}-db-1 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -E '^MARIADB_ROOT_PASSWORD=|^MYSQL_ROOT_PASSWORD=' | head -1 | cut -d= -f2-)

DB_NAME=$(docker inspect ${PROJECT_NAME}-db-1 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -E '^MYSQL_DATABASE=|^MARIADB_DATABASE=' | head -1 | cut -d= -f2- || true)
DB_NAME="${DB_NAME:-wordpress}"

if [[ -z "$DB_ROOT_PASS" ]]; then
  echo "ERROR: Could not read DB password from container ${PROJECT_NAME}-db-1"
  echo "       Is the container running? Try: docker ps | grep ${PROJECT_NAME}-db"
  exit 1
fi

echo "==> Dumping MariaDB database..."
docker exec ${PROJECT_NAME}-db-1 mariadb-dump \
  -u root \
  -p"${DB_ROOT_PASS}" \
  --single-transaction \
  --routines \
  --triggers \
  "${DB_NAME}" > "${WORK_DIR}/wordpress.sql"

DB_SIZE=$(wc -c < "${WORK_DIR}/wordpress.sql")
echo "    Database dump: ${DB_SIZE} bytes"

echo "==> Copying wp-content..."
docker cp ${PROJECT_NAME}-wordpress-1:/var/www/html/wp-content "${WORK_DIR}/wp-content"

echo "==> Copying wp-config.php..."
docker cp ${PROJECT_NAME}-wordpress-1:/var/www/html/wp-config.php "${WORK_DIR}/wp-config.php" 2>/dev/null || true

echo "==> Copying wordfence-waf.php (if present)..."
docker cp ${PROJECT_NAME}-wordpress-1:/var/www/html/wordfence-waf.php "${WORK_DIR}/wordfence-waf.php" 2>/dev/null || true

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

# Cleanup old backups
if [[ -n "$REMOTE" ]]; then
  # shellcheck disable=SC2029
  ssh "$REMOTE" "find ${BACKUP_DIR} -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete"
fi
