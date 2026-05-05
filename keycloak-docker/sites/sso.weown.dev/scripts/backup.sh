#!/usr/bin/env bash
# sso - Backup Script
# Backs up PostgreSQL database and Keycloak data volumes
#
# Usage: ./backup.sh [user@host]
set -euo pipefail

REMOTE="${1:-}"
APP_DIR="/opt/sso"
BACKUP_DIR="$APP_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="sso_backup_$TIMESTAMP"

if [[ -z "$REMOTE" ]]; then
  echo "Usage: $0 user@droplet-ip"
  echo ""
  echo "Example: $0 root@143.198.xxx.xxx"
  exit 1
fi

echo "==> Backing up sso from $REMOTE"
echo ""

# Create backup directory
# shellcheck disable=SC2029
ssh "$REMOTE" "mkdir -p $BACKUP_DIR"

# Backup PostgreSQL database
echo "==> Backing up PostgreSQL database..."
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml exec -T db pg_dump -U ${DB_USER:-keycloak} ${DB_NAME:-keycloak} > $BACKUP_DIR/${BACKUP_NAME}_db.sql"

# Backup Keycloak data volume
echo "==> Backing up Keycloak data..."
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml run --rm -T keycloak tar czf /tmp/keycloak_data.tar.gz -C /opt/keycloak/data ."
# shellcheck disable=SC2029
ssh "$REMOTE" "docker compose -f $APP_DIR/compose.yaml cp keycloak:/tmp/keycloak_data.tar.gz $BACKUP_DIR/${BACKUP_NAME}_keycloak_data.tar.gz"

# Create archive
echo "==> Creating archive..."
# shellcheck disable=SC2029
ssh "$REMOTE" "cd $BACKUP_DIR && tar czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}_db.sql ${BACKUP_NAME}_keycloak_data.tar.gz && rm -f ${BACKUP_NAME}_db.sql ${BACKUP_NAME}_keycloak_data.tar.gz"

# Get backup size
# shellcheck disable=SC2029
BACKUP_SIZE=$(ssh "$REMOTE" "ls -lh $BACKUP_DIR/${BACKUP_NAME}.tar.gz | awk '{print \$5}'")

echo ""
echo "==> Backup complete!"
echo "    File: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "    Size: $BACKUP_SIZE"
echo ""
echo "==> To restore:"
echo "    ./restore.sh $REMOTE $BACKUP_NAME"
