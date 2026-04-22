#!/usr/bin/env bash
# stage-burnedout-xyz - Deploy Script
# Deploy or update the WordPress stack on the droplet
#
# Usage: ./deploy.sh [user@host]
#
# Requires:
#   - SSH access to the droplet
#   - docker/.env.prod file with production credentials
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE="${1:-}"
APP_DIR="/opt/stageburnedoutxyz"

if [[ -z "$REMOTE" ]]; then
  echo "Usage: $0 user@droplet-ip"
  echo ""
  echo "Example: $0 root@143.198.xxx.xxx"
  exit 1
fi

# Verify required files exist
if [[ ! -f "$PROJECT_DIR/docker/.env.prod" ]]; then
  echo "Error: docker/.env.prod not found"
  echo "Copy docker/.env.prod.example to docker/.env.prod and fill in values"
  exit 1
fi

echo "==> Deploying stage-burnedout-xyz to $REMOTE"
echo ""

echo "==> Uploading compose and config files..."
scp "$PROJECT_DIR/docker/compose.prod.yaml" "$REMOTE:$APP_DIR/compose.yaml"
scp "$PROJECT_DIR/docker/Caddyfile" "$REMOTE:$APP_DIR/Caddyfile"

echo "==> Uploading Wordfence WAF config..."
ssh "$REMOTE" "mkdir -p $APP_DIR/wordfence-waf"
scp "$PROJECT_DIR/docker/wordfence-waf/.user.ini" "$REMOTE:$APP_DIR/wordfence-waf/.user.ini"

echo "==> Uploading .env..."
scp "$PROJECT_DIR/docker/.env.prod" "$REMOTE:$APP_DIR/.env"

echo "==> Pulling latest images and restarting..."
ssh "$REMOTE" "cd $APP_DIR && docker compose pull && docker compose up -d"

# Get the domain from the deployed .env
DOMAIN=$(ssh "$REMOTE" "grep DOMAIN $APP_DIR/.env | cut -d= -f2")

echo ""
echo "==> Deployment complete!"
echo "    Site: https://$DOMAIN"
echo ""
echo "==> Verify status with:"
echo "    ssh $REMOTE 'cd $APP_DIR && docker compose ps'"
