#!/usr/bin/env bash
# burnedout-xyz - Restore Script
# Restore WordPress from a skinny backup
#
# Usage: ./restore.sh [user@host] backup-file.tar.gz
#        ./restore.sh local backup-file.tar.gz   (restore to local compose.local.yaml stack)
#
# CAUTION: This will overwrite the current WordPress installation!
set -euo pipefail

REMOTE="${1:-}"
BACKUP_FILE="${2:-}"
# PROJECT_NAME is used inside heredocs passed to SSH — export so it's available
export PROJECT_NAME="burnedout"
export APP_DIR="/opt/burnedout"

usage() {
  echo "Usage: $0 [user@host|local] backup-file.tar.gz"
  echo ""
  echo "Examples:"
  echo "  Remote restore: $0 root@burnedout.xyz ./backups/backup-20260501.tar.gz"
  echo "  Local restore:  $0 local ./backups/backup-20260501.tar.gz"
  echo ""
  echo "CAUTION: This will overwrite the current WordPress installation!"
  exit 1
}

if [[ -z "$REMOTE" ]] || [[ -z "$BACKUP_FILE" ]]; then
  usage
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
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

local_restore() {
  local backup="$1"
  local backup_name
  backup_name=$(basename "$backup" .tar.gz)
  local restore_dir="/tmp/${backup_name}"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DOCKER_DIR="${SCRIPT_DIR}/../docker"
  export COMPOSE_PROJECT_NAME=burnedout-local

  echo "==> Extracting backup..."
  mkdir -p "$restore_dir"
  tar xzf "$backup" -C /tmp/

  echo "==> Stopping WordPress container..."
  cd "$DOCKER_DIR"
  docker compose -f compose.local.yaml stop wordpress

  # Restore database (if SQL dump is non-empty)
  if [[ -s "${restore_dir}/wordpress.sql" ]]; then
    echo "==> Importing database..."
    # Source .env for credentials
    # shellcheck disable=SC1091
    set -a; source .env; set +a
    docker compose -f compose.local.yaml exec -T db \
      mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" \
      < "${restore_dir}/wordpress.sql"
    echo "    ✓ Database imported"

    echo "==> Fixing URLs for local development..."
    docker compose -f compose.local.yaml exec -T db \
      mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" \
      -e "UPDATE wp_options SET option_value='http://localhost:8080' WHERE option_name IN ('siteurl','home');"
    echo "    ✓ siteurl + home → http://localhost:8080"
  else
    echo "    ⚠️  wordpress.sql is empty or missing — skipping DB import"
  fi

  # Restore wordfence-waf.php if captured (avoids 500s until Wordfence regenerates it)
  if [[ -f "${restore_dir}/wordfence-waf.php" ]]; then
    echo "==> Restoring wordfence-waf.php..."
    WP_CONTAINER_TMP="$(docker compose -f compose.local.yaml ps -q wordpress 2>/dev/null || true)"
    if [[ -n "$WP_CONTAINER_TMP" ]]; then
      docker cp "${restore_dir}/wordfence-waf.php" "${WP_CONTAINER_TMP}:/var/www/html/wordfence-waf.php"
      echo "    ✓ wordfence-waf.php restored"
    fi
  fi

  echo "==> Restoring wp-content..."
  # Get the wordpress container name
  WP_CONTAINER="$(docker compose -f compose.local.yaml ps -q wordpress 2>/dev/null || true)"
  if [[ -n "$WP_CONTAINER" ]]; then
    docker cp "${restore_dir}/wp-content" "${WP_CONTAINER}:/var/www/html/"
  else
    # Container stopped — start db only, then copy
    docker compose -f compose.local.yaml up -d db
    sleep 5
    docker compose -f compose.local.yaml up -d wordpress
    sleep 5
    WP_CONTAINER="$(docker compose -f compose.local.yaml ps -q wordpress)"
    docker cp "${restore_dir}/wp-content" "${WP_CONTAINER}:/var/www/html/"
  fi
  # Fix ownership and permissions — docker cp copies as root; PHP-FPM runs as uid 1000
  docker exec -u root "$WP_CONTAINER" sh -c \
    "chown -R 1000:1000 /var/www/html/wp-content && find /var/www/html/wp-content -type d -exec chmod 755 {} + && find /var/www/html/wp-content -type f -exec chmod 644 {} +"
  echo "    ✓ wp-content restored"

  echo "==> Starting full stack..."
  docker compose -f compose.local.yaml up -d

  echo "==> Cleaning up..."
  rm -rf "$restore_dir"

  echo ""
  echo "=== LOCAL RESTORE COMPLETE ==="
  echo "Site: http://localhost:8080"
  echo ""
  echo "If DB was imported from production, run URL replacement:"
  echo "  docker exec -it <wp-container> wp search-replace 'https://burnedout.xyz' 'http://localhost:8080' --all-tables --allow-root"
}

remote_restore() {
  local host="$1"
  local backup="$2"

  echo "==> Uploading backup to ${host}..."
  scp "$backup" "${host}:/tmp/"

  local backup_name
  backup_name=$(basename "$backup" .tar.gz)
  local remote_backup
  remote_backup="/tmp/$(basename "$backup")"

  # Pass variables as positional args to the remote script so shellcheck
  # can verify local usage and the heredoc stays quoted (server-side expansion)
  # shellcheck disable=SC2087
  ssh "$host" bash -s "$remote_backup" "$backup_name" "$APP_DIR" << 'RESTORE_SCRIPT'
set -euo pipefail

REMOTE_BACKUP="$1"
BACKUP_NAME="$2"
APP_DIR="$3"
PROJECT_NAME="burnedout"
RESTORE_DIR="/tmp/${BACKUP_NAME}"

echo "==> Extracting backup..."
mkdir -p "$RESTORE_DIR"
tar xzf "$REMOTE_BACKUP" -C /tmp/

echo "==> Stopping WordPress..."
cd "$APP_DIR"

# Source infisical auth if available
if [[ -f "${APP_DIR}/infisical-auth.sh" ]]; then
  source "${APP_DIR}/infisical-auth.sh"
  COMPOSE_CMD="infisical run -- docker compose"
else
  COMPOSE_CMD="docker compose"
fi

$COMPOSE_CMD stop wordpress

# Restore database (if SQL dump is non-empty)
if [[ -s "${RESTORE_DIR}/wordpress.sql" ]]; then
  echo "==> Importing database..."
  source "${APP_DIR}/.env" 2>/dev/null || true
  docker exec -i "${PROJECT_NAME}-db-1" \
    mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" \
    < "${RESTORE_DIR}/wordpress.sql"
  echo "    ✓ Database imported"
else
  echo "    ⚠️  wordpress.sql is empty or missing — skipping DB import"
fi

# Restore wordfence-waf.php if captured (avoids 500s until Wordfence regenerates it)
if [[ -f "${RESTORE_DIR}/wordfence-waf.php" ]]; then
  echo "==> Restoring wordfence-waf.php..."
  docker cp "${RESTORE_DIR}/wordfence-waf.php" "${PROJECT_NAME}-wordpress-1:/var/www/html/wordfence-waf.php"
  echo "    ✓ wordfence-waf.php restored"
fi

echo "==> Restoring wp-content..."
docker cp "${RESTORE_DIR}/wp-content" "${PROJECT_NAME}-wordpress-1:/var/www/html/"
# Fix ownership and permissions — docker cp copies as root; PHP-FPM runs as uid 1000
docker exec -u root "${PROJECT_NAME}-wordpress-1" sh -c \
  "chown -R 1000:1000 /var/www/html/wp-content && find /var/www/html/wp-content -type d -exec chmod 755 {} + && find /var/www/html/wp-content -type f -exec chmod 644 {} +"
echo "    ✓ wp-content restored"

echo "==> Starting stack..."
$COMPOSE_CMD up -d

echo "==> Cleaning up..."
rm -rf "$RESTORE_DIR"
rm -f "$REMOTE_BACKUP"
RESTORE_SCRIPT

  echo ""
  echo "=== REMOTE RESTORE COMPLETE ==="
  echo "Site: https://burnedout.xyz"
}

if [[ "$REMOTE" == "local" ]]; then
  local_restore "$BACKUP_FILE"
else
  remote_restore "$REMOTE" "$BACKUP_FILE"
fi
