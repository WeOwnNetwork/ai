#!/usr/bin/env bash
# s004-anythingllm - Deploy Script
# Deploy or update the AnythingLLM stack on the droplet
#
# Usage: ./deploy.sh [user@host]
#
# Requires:
#   - SSH access to the droplet
#   - Infisical Machine Identity configured on the droplet
#   - docker/compose.prod.yaml and docker/Caddyfile exist locally
#
# SECURITY: No .env file is uploaded. All application secrets (OPENROUTER_API_KEY,
# JWT_SECRET, ADMIN_EMAIL, etc.) are injected at runtime by Infisical via
# `infisical run`. Only the Infisical Machine Identity (Client ID + Secret)
# is stored on the droplet — never application secrets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE="${1:-}"
APP_DIR="/opt/s004anythingllm"

# Required environment variable: INFISICAL_PROJECT_ID (the s004-anythingllm
# Infisical project ID). The Machine Identity credentials are already on the
# droplet from cloud-init, so this script only needs the project ID to invoke
# `infisical run` against the right project.
: "${INFISICAL_PROJECT_ID:?Set INFISICAL_PROJECT_ID env var (find it in the Infisical project URL or settings — same value as terraform.tfvars infisical_project_id)}"
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

if [[ -z "$REMOTE" ]]; then
  echo "Usage: INFISICAL_PROJECT_ID=<id> $0 user@droplet-ip"
  echo ""
  echo "Example: INFISICAL_PROJECT_ID=abc123 $0 root@198.51.100.42"
  exit 1
fi

# Verify required local files exist
if [[ ! -f "$PROJECT_DIR/docker/compose.prod.yaml" ]]; then
  echo "Error: docker/compose.prod.yaml not found"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/docker/Caddyfile" ]]; then
  echo "Error: docker/Caddyfile not found"
  exit 1
fi

echo "==> Deploying s004-anythingllm to $REMOTE"
echo ""

echo "==> Uploading compose and config files..."
scp "$PROJECT_DIR/docker/compose.prod.yaml" "$REMOTE:$APP_DIR/compose.yaml"
scp "$PROJECT_DIR/docker/Caddyfile" "$REMOTE:$APP_DIR/Caddyfile"

echo "==> Pulling latest images and restarting with Infisical runtime injection..."
ssh "$REMOTE" "cd $APP_DIR && \
  docker compose pull && \
  infisical run \
    --projectId=$INFISICAL_PROJECT_ID \
    --env=$INFISICAL_ENV \
    -- docker compose up -d"

echo ""
echo "==> Deployment complete!"
echo "    AnythingLLM URL: https://s004.ccc.bot"
echo ""
echo "==> Verify status with:"
echo "    ssh $REMOTE 'cd $APP_DIR && docker compose ps'"
echo ""
echo "==> View logs with:"
echo "    ssh $REMOTE 'cd $APP_DIR && docker compose logs -f anythingllm'"
