#!/usr/bin/env bash
# Enable NIP-AB pairing on the NEW droplet only.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 DROPLET_PUBLIC_IP" >&2
  exit 1
fi
IP="$1"
APP_ROOT="${BUZZ_SITE_APP_ROOT:-/opt/dev-weown-buzz}"
COMPOSE_DIR="${APP_ROOT}/buzz/deploy/compose"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAIR_SRC="${SCRIPT_DIR}/enable-pairing-relay.sh"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

"${SCP[@]}" "$PAIR_SRC" "root@${IP}:/tmp/enable-pairing-relay.sh"
"${SSH[@]}" "root@${IP}" bash -s -- "$COMPOSE_DIR" <<'REMOTE'
set -euo pipefail
COMPOSE_DIR="$1"
chmod +x /tmp/enable-pairing-relay.sh
# Site-local pairing script already points at /opt/dev-weown-buzz
/tmp/enable-pairing-relay.sh
REMOTE

echo "NEXT: ./buzz-docker/sites/dev-weown-buzz/scripts/04-cloudflare-a-record.sh ${IP}"
