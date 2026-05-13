#!/usr/bin/env bash
# ptoken-agency - Deploy Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE="${1:-}"
APP_DIR="/opt/ptoken"

if [[ -z "$REMOTE" ]]; then
  echo "Usage: $0 user@droplet-ip"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/docker/.env.prod" ]]; then
  echo "Error: docker/.env.prod not found"
  exit 1
fi

echo "==> Deploying ptoken-agency to $REMOTE"

echo "==> Uploading compose and config files..."
scp "$PROJECT_DIR/docker/compose.prod.yaml" "$REMOTE:$APP_DIR/compose.yaml"
scp "$PROJECT_DIR/docker/Caddyfile" "$REMOTE:$APP_DIR/Caddyfile"

echo "==> Uploading Wordfence WAF config..."
# shellcheck disable=SC2029
ssh "$REMOTE" "mkdir -p $APP_DIR/wordfence-waf"
scp "$PROJECT_DIR/docker/wordfence-waf/.user.ini" "$REMOTE:$APP_DIR/wordfence-waf/.user.ini"

echo "==> Uploading .env..."
scp "$PROJECT_DIR/docker/.env.prod" "$REMOTE:$APP_DIR/.env"

echo "==> Pulling latest images and restarting..."
# shellcheck disable=SC2029
ssh "$REMOTE" "cd $APP_DIR && docker compose pull && docker compose up -d"

# shellcheck disable=SC2029
DOMAIN=$(ssh "$REMOTE" "grep DOMAIN $APP_DIR/.env | cut -d= -f2")

echo ""
echo "==> Deployment complete!"
echo "    Site: https://www.$DOMAIN"
