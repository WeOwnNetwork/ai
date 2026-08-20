#!/usr/bin/env bash
# Create an isolated Buzz droplet for dev.weown.buzz (parity with felg Buzz).
# Does NOT touch the existing buzzweowntools / felg droplet.
set -euo pipefail

DOMAIN="${BUZZ_SITE_DOMAIN:-dev.weown.buzz}"
NAME="${BUZZ_SITE_DROPLET_NAME:-dev-weown-buzz-2vcpu-4gb-amd-atl1}"
REGION="${BUZZ_SITE_REGION:-atl1}"
SIZE="${BUZZ_SITE_SIZE:-s-2vcpu-4gb-amd}"
IMAGE="${BUZZ_SITE_IMAGE:-ubuntu-24-04-x64}"
# Same VPC as buzzweowntools (felg) — still a separate droplet/volumes.
VPC_UUID="${BUZZ_SITE_VPC_UUID:-e39f0577-5287-4c16-a218-f2e9bd872417}"
# WeOwn.tools project (same as buzzweowntools droplet).
PROJECT_ID="${BUZZ_SITE_PROJECT_ID:-f416f1a9-5e73-4909-bdeb-fb732244aaa9}"
TAGS="${BUZZ_SITE_TAGS:-weown-ai,BuzzChat,AgenticAI,WeOwnAi,droplet,buzz-dev,dev-weown-buzz}"

# Prefer known operator keys; doctl accepts IDs or fingerprints.
SSH_KEYS="${BUZZ_SITE_SSH_KEYS:-55607590,57190333,57522265}"

if ! command -v doctl >/dev/null 2>&1; then
  echo "ERROR: doctl required" >&2
  exit 1
fi

if doctl compute droplet list --format Name --no-header | grep -qx "$NAME"; then
  echo "=== droplet already exists: $NAME ==="
  doctl compute droplet list --format ID,Name,PublicIPv4,Region,Status,Tags | grep -F "$NAME" || true
  exit 0
fi

echo "=== creating droplet $NAME ($SIZE @ $REGION) for $DOMAIN ==="
echo "=== project=$PROJECT_ID vpc=$VPC_UUID ==="
echo "=== WARNING: this bills DigitalOcean; does not modify felg/buzzweowntools ==="

doctl compute droplet create "$NAME" \
  --region "$REGION" \
  --size "$SIZE" \
  --image "$IMAGE" \
  --vpc-uuid "$VPC_UUID" \
  --ssh-keys "$SSH_KEYS" \
  --tag-names "$TAGS" \
  --enable-monitoring \
  --enable-private-networking \
  --wait

DROPLET_ID="$(doctl compute droplet list --format ID,Name --no-header | awk -v n="$NAME" '$2==n {print $1; exit}')"
: "${DROPLET_ID:?failed to resolve droplet id}"

echo "=== assigning to DO project WeOwn.tools ==="
doctl projects resources assign "$PROJECT_ID" --resource "do:droplet:${DROPLET_ID}"

echo "=== droplet ready ==="
doctl compute droplet get "$DROPLET_ID" --format ID,Name,PublicIPv4,Region,Status,Tags
IP="$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)"
echo "DROPLET_ID=${DROPLET_ID}"
echo "DROPLET_PUBLIC_IP=${IP}"
echo "NEXT: ./buzz-docker/sites/dev-weown-buzz/scripts/02-bootstrap-host.sh ${IP}"
