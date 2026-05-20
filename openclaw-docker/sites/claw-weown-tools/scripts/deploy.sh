#!/usr/bin/env bash
# claw-weown-tools - Deploy Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE="${1:-}"
APP_DIR="/opt/claw-weown-tools"

if [[ -z "$REMOTE" ]]; then
  echo "Usage: $0 user@droplet-ip"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/docker/.env" ]]; then
  echo "Error: docker/.env not found"
  exit 1
fi

echo "==> Deploying claw-weown-tools to $REMOTE"

echo "==> Uploading compose and config files..."
scp "$PROJECT_DIR/docker/compose.prod.yaml" "$REMOTE:$APP_DIR/compose.yaml"
scp "$PROJECT_DIR/docker/Caddyfile" "$REMOTE:$APP_DIR/Caddyfile"

echo "==> Uploading .env..."
scp "$PROJECT_DIR/docker/.env" "$REMOTE:$APP_DIR/.env"

echo "==> Pulling latest images and restarting..."
ssh "$REMOTE" "cd $APP_DIR && docker compose pull && docker compose up -d"

DOMAIN=$(ssh "$REMOTE" "grep DOMAIN $APP_DIR/.env | cut -d= -f2")

echo ""
echo "==> Deployment complete!"
echo "    Site: https://$DOMAIN"
