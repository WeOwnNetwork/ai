#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu droplet with Docker + pinned Buzz for this site.
# Never SSHs to felg / buzzweowntools. Never prints .env secrets.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 DROPLET_PUBLIC_IP" >&2
  exit 1
fi
IP="$1"
DOMAIN="${BUZZ_SITE_DOMAIN:-dev.weown.buzz}"
APP_ROOT="${BUZZ_SITE_APP_ROOT:-/opt/dev-weown-buzz}"
COMPOSE_DIR="${APP_ROOT}/buzz/deploy/compose"
BUZZ_GIT_SHA="${BUZZ_GIT_SHA:-6df7eba24d49b6a2c7f0188b19e24f3df999678c}"
BUZZ_IMAGE="${BUZZ_IMAGE:-ghcr.io/block/buzz@sha256:815e8e57bd09efb6a6857e9e635bbcdbb4411f5a8f6b3595ef4eb636c4620163}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_SRC="${SCRIPT_DIR}/bootstrap-host-env.sh"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

echo "=== waiting for SSH root@${IP} ==="
for i in $(seq 1 60); do
  if "${SSH[@]}" "root@${IP}" 'echo ssh_ok' >/dev/null 2>&1; then
    break
  fi
  if [[ "$i" -eq 60 ]]; then
    echo "ERROR: SSH not ready" >&2
    exit 1
  fi
  sleep 5
done

echo "=== host prep (Docker, swap, UFW) — target only ${IP} ==="
"${SSH[@]}" "root@${IP}" bash -s -- "$APP_ROOT" <<'REMOTE'
set -euo pipefail
APP_ROOT="$1"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git ufw python3 python3-venv

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker.service

if [[ ! -f /swapfile ]]; then
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

mkdir -p "${APP_ROOT}"
REMOTE

echo "=== clone pinned Buzz upstream ==="
"${SSH[@]}" "root@${IP}" bash -s -- "$APP_ROOT" "$BUZZ_GIT_SHA" <<'REMOTE'
set -euo pipefail
APP_ROOT="$1"
BUZZ_GIT_SHA="$2"
if [[ ! -d "${APP_ROOT}/buzz/.git" ]]; then
  git clone https://github.com/block/buzz.git "${APP_ROOT}/buzz"
fi
git -C "${APP_ROOT}/buzz" fetch --all --tags
git -C "${APP_ROOT}/buzz" checkout "$BUZZ_GIT_SHA"
git -C "${APP_ROOT}/buzz" rev-parse HEAD
REMOTE

echo "=== upload bootstrap (secrets generated on host only) ==="
"${SCP[@]}" "$BOOTSTRAP_SRC" "root@${IP}:/tmp/bootstrap-host-env.sh"
"${SSH[@]}" "root@${IP}" bash -s -- "$DOMAIN" "$BUZZ_IMAGE" "$APP_ROOT" "$COMPOSE_DIR" <<'REMOTE'
set -euo pipefail
DOMAIN="$1"
BUZZ_IMAGE="$2"
APP_ROOT="$3"
COMPOSE_DIR="$4"
chmod +x /tmp/bootstrap-host-env.sh
BUZZ_DOMAIN="$DOMAIN" BUZZ_IMAGE="$BUZZ_IMAGE" APP_ROOT="$APP_ROOT" \
  /tmp/bootstrap-host-env.sh "$COMPOSE_DIR"
REMOTE

echo "=== pull image + start TLS stack ==="
"${SSH[@]}" "root@${IP}" bash -s -- "$COMPOSE_DIR" <<'REMOTE'
set -euo pipefail
COMPOSE_DIR="$1"
cd "$COMPOSE_DIR"
docker pull "$(grep -E '^BUZZ_IMAGE=' .env | cut -d= -f2-)"
BUZZ_COMPOSE_TLS=true ./run.sh start
BUZZ_COMPOSE_TLS=true ./run.sh status || true
docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20
REMOTE

echo "=== bootstrap complete for ${DOMAIN} on ${IP} ==="
echo "NEXT: ./buzz-docker/sites/dev-weown-buzz/scripts/03-enable-pairing.sh ${IP}"
echo "OWNER KEY (human only): ssh root@${IP} 'cat /root/buzz-owner-keypair.txt'"
