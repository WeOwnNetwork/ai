#!/usr/bin/env bash
# sso - Restore Script
# Restores PostgreSQL database and Keycloak data volumes from backup
#
# Usage: ./restore.sh [user@host] [backup-name]
set -euo pipefail

REMOTE="${1:-}"
BACKUP_NAME="${2:-}"
APP_DIR="/opt/sso"
BACKUP_DIR="$APP_DIR/backups"

if [[ -z "$REMOTE" ]] || [[ -z "$BACKUP_NAME" ]]; then
  echo "Usage: $0 user@host backup-name"
  echo ""
  echo "Example: $0 root@143.198.xxx.xxx sso_backup_20260426_120000"
  exit 1
fi

echo "==> Restoring sso from $BACKUP_NAME"
echo ""

# Check if backup exists
# shellcheck disable=SC2029
if ! ssh "$REMOTE" "test -f $BACKUP_DIR/${BACKUP_NAME}.tar.gz"; then
  echo "Error: Backup $BACKUP_NAME not found"
  exit 1
fi

# Stop Keycloak
echo "==> Stopping Keycloak..."
# shellcheck disable=SC2029
ssh "$REMOTE" "cd $APP_DIR && docker compose stop keycloak"

# Extract archive
echo "==> Extracting archive..."
# shellcheck disable=SC2029
ssh "$REMOTE" "cd $BACKUP_DIR && tar xzf ${BACKUP_NAME}.tar.gz"

# Restore PostgreSQL database
echo "==> Restoring PostgreSQL database..."
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml exec -T db psql -U ${DB_USER:-keycloak} ${DB_NAME:-keycloak} < $BACKUP_DIR/${BACKUP_NAME}_db.sql"

# Restore Keycloak data
echo "==> Restoring Keycloak data..."
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml cp $BACKUP_DIR/${BACKUP_NAME}_keycloak_data.tar.gz keycloak:/tmp/keycloak_data.tar.gz"
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml run --rm -T keycloak sh -c 'rm -rf /opt/keycloak/data/* && tar xzf /tmp/keycloak_data.tar.gz -C /opt/keycloak/data'"

# Cleanup
echo "==> Cleaning up..."
# shellcheck disable=SC2029
ssh "$REMOTE" "rm -f $BACKUP_DIR/${BACKUP_NAME}_db.sql $BACKUP_DIR/${BACKUP_NAME}_keycloak_data.tar.gz"

# Start Keycloak
echo "==> Starting Keycloak..."
# shellcheck disable=SC2029
ssh "$REMOTE" "cd $APP_DIR && docker compose start keycloak"

echo ""
echo "==> Restore complete!"
echo ""
echo "==> Verify status with:"
echo "    ssh $REMOTE 'cd $APP_DIR && docker compose ps'"
