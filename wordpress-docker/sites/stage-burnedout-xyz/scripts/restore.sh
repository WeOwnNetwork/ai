#!/usr/bin/env bash
# stage-burnedout-xyz - Restore Script
# Restore WordPress from a skinny backup
#
# Usage: ./restore.sh [user@host] backup-file.tar.gz
#
# CAUTION: This will overwrite the current WordPress installation!
set -euo pipefail

REMOTE="${1:-}"
BACKUP_FILE="${2:-}"
PROJECT_NAME="stageburnedoutxyz"
APP_DIR="/opt/$PROJECT_NAME"

usage() {
  echo "Usage: $0 [user@host] backup-file.tar.gz"
  echo ""
  echo "Examples:"
  echo "  Remote restore: $0 root@143.198.xxx.xxx ./backups/backup-20260420.tar.gz"
  echo "  Local restore:  $0 local /opt/stageburnedoutxyz/backups/backup-20260420.tar.gz"
  echo ""
  echo "CAUTION: This will overwrite the current WordPress installation!"
  exit 1
}

if [[ -z "$REMOTE" ]] || [[ -z "$BACKUP_FILE" ]]; then
  usage
fi

if [[ ! -f "$BACKUP_FILE" ]] && [[ "$REMOTE" != "local" ]]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "==> WARNING: This will overwrite the current WordPress installation!"
echo "    Target: $REMOTE"
echo "    Backup: $BACKUP_FILE"
echo ""
read -p "Are you sure you want to continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

run_restore() {
  local host="$1"
  local backup="$2"
  local backup_name
  backup_name=$(basename "$backup" .tar.gz)

  if [[ "$host" == "local" ]]; then
    # Local restore
    RESTORE_DIR="/tmp/${backup_name}"

    echo "==> Extracting backup..."
    mkdir -p "$RESTORE_DIR"
    tar xzf "$backup" -C /tmp/

    echo "==> Stopping WordPress..."
    cd "$APP_DIR"
    docker compose stop wordpress

    echo "==> Restoring database..."
    source "$APP_DIR/.env"
    cat "${RESTORE_DIR}/${backup_name}/wordpress.sql" | \
      docker exec -i ${PROJECT_NAME}-db-1 mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"

    echo "==> Restoring wp-content..."
    docker cp "${RESTORE_DIR}/${backup_name}/wp-content" ${PROJECT_NAME}-wordpress-1:/var/www/html/

    echo "==> Restoring config files..."
    cp "${RESTORE_DIR}/${backup_name}/Caddyfile" "$APP_DIR/Caddyfile"
    cp "${RESTORE_DIR}/${backup_name}/dot-env" "$APP_DIR/.env"

    echo "==> Starting WordPress..."
    docker compose up -d

    echo "==> Cleaning up..."
    rm -rf "$RESTORE_DIR"

  else
    # Remote restore - upload backup first
    echo "==> Uploading backup to $host..."
    scp "$backup" "$host:/tmp/"

    REMOTE_BACKUP="/tmp/$(basename "$backup")"

    ssh "$host" bash -s "$REMOTE_BACKUP" "$backup_name" "$PROJECT_NAME" "$APP_DIR" <<'RESTORE_SCRIPT'
set -euo pipefail

REMOTE_BACKUP="$1"
BACKUP_NAME="$2"
PROJECT_NAME="$3"
APP_DIR="$4"
RESTORE_DIR="/tmp/${BACKUP_NAME}"

echo "==> Extracting backup..."
mkdir -p "$RESTORE_DIR"
tar xzf "$REMOTE_BACKUP" -C /tmp/

echo "==> Stopping WordPress..."
cd "$APP_DIR"
docker compose stop wordpress

echo "==> Restoring database..."
source "$APP_DIR/.env"
cat "${RESTORE_DIR}/${BACKUP_NAME}/wordpress.sql" | \
  docker exec -i ${PROJECT_NAME}-db-1 mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"

echo "==> Restoring wp-content..."
docker cp "${RESTORE_DIR}/${BACKUP_NAME}/wp-content" ${PROJECT_NAME}-wordpress-1:/var/www/html/

echo "==> Restoring config files..."
cp "${RESTORE_DIR}/${BACKUP_NAME}/Caddyfile" "$APP_DIR/Caddyfile"
cp "${RESTORE_DIR}/${BACKUP_NAME}/dot-env" "$APP_DIR/.env"

echo "==> Starting WordPress..."
docker compose up -d

echo "==> Cleaning up..."
rm -rf "$RESTORE_DIR"
rm -f "$REMOTE_BACKUP"
RESTORE_SCRIPT
  fi
}

run_restore "$REMOTE" "$BACKUP_FILE"

echo ""
echo "=== RESTORE COMPLETE ==="
echo "Site: https://stage.burnedout.xyz"
echo ""
echo "Verify the site is working correctly."
echo "If there are issues, check the logs:"
echo "  ssh $REMOTE 'cd $APP_DIR && docker compose logs'"
