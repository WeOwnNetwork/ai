#!/usr/bin/env bash
# Deploy Formbricks to a droplet. Secrets are generated ON the remote host only â€”
# never printed, never passed through agent/SSH argv as values.
#
# Usage:
#   ./scripts/deploy.sh root@<INGRESS_LB_IP>
#
# #WeOwnVer: v4.2.1.1

set -euo pipefail

REMOTE_HOST="${1:?Usage: $0 root@<host>}"
REMOTE_DIR="/opt/formbricks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Ensuring Docker Engine + Compose plugin on ${REMOTE_HOST}"
ssh -o BatchMode=yes "${REMOTE_HOST}" 'bash -s' <<'REMOTE_DOCKER'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
  systemctl enable --now docker
fi
docker --version
docker compose version

# 2 GB droplets need swap for Formbricks v5 (web+hub+cube+pg)
if [[ ! -f /swapfile ]]; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
swapon --show || true
REMOTE_DOCKER

echo "==> Creating ${REMOTE_DIR} and syncing compose files (no secrets)"
ssh -o BatchMode=yes "${REMOTE_HOST}" "mkdir -p '${REMOTE_DIR}/cube/schema' '${REMOTE_DIR}/saml-connection' '${REMOTE_DIR}/scripts'"

scp -o BatchMode=yes \
  "${ROOT_DIR}/docker-compose.yml" \
  "${ROOT_DIR}/Caddyfile" \
  "${ROOT_DIR}/.env.example" \
  "${REMOTE_HOST}:${REMOTE_DIR}/"

scp -o BatchMode=yes \
  "${ROOT_DIR}/cube/cube.js" \
  "${REMOTE_HOST}:${REMOTE_DIR}/cube/"

scp -o BatchMode=yes \
  "${ROOT_DIR}/cube/schema/FeedbackRecords.js" \
  "${REMOTE_HOST}:${REMOTE_DIR}/cube/schema/"

echo "==> Generating .env on remote (if missing) and starting stack"
ssh -o BatchMode=yes "${REMOTE_HOST}" "REMOTE_DIR='${REMOTE_DIR}' bash -s" <<'REMOTE_UP'
set -euo pipefail
cd "${REMOTE_DIR}"

if [[ ! -f .env ]]; then
  umask 077
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  {
    echo "WEBAPP_URL=https://forms.weown.tools"
    echo "NEXTAUTH_URL=https://forms.weown.tools"
    echo "POSTGRES_USER=formbricks"
    echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
    echo "POSTGRES_DB=formbricks"
    echo "DATABASE_URL=postgresql://formbricks:${POSTGRES_PASSWORD}@postgres:5432/formbricks?sslmode=disable"
    echo "REDIS_URL=redis://redis:6379"
    echo "NEXTAUTH_SECRET=$(openssl rand -hex 32)"
    echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
    echo "CRON_SECRET=$(openssl rand -hex 32)"
    echo "HUB_API_KEY=$(openssl rand -hex 32)"
    echo "CUBEJS_API_SECRET=$(openssl rand -hex 32)"
    echo "CUBEJS_JWT_ISSUER=formbricks-web"
    echo "CUBEJS_JWT_AUDIENCE=formbricks-cube"
    echo "CUBEJS_API_URL=http://cube:4000"
    echo "HUB_API_URL=http://hub:8080"
    echo "EMAIL_VERIFICATION_DISABLED=1"
    echo "PASSWORD_RESET_DISABLED=1"
  } > .env
  chmod 600 .env
  echo "Created ${REMOTE_DIR}/.env (secrets not displayed)"
else
  echo "Reusing existing ${REMOTE_DIR}/.env"
fi

docker compose pull
docker compose up -d
docker compose ps -a

echo "==> Waiting for Formbricks HTTP on :3000"
ok=0
for i in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ || true)"
  if [[ "${code}" == "200" || "${code}" == "302" || "${code}" == "307" ]]; then
    echo "localhost:3000 -> HTTP ${code}"
    ok=1
    break
  fi
  sleep 5
done
if [[ "${ok}" != "1" ]]; then
  echo "Formbricks did not become ready in time; recent logs:"
  docker compose logs --tail=80 formbricks-migrate hub-migrate formbricks hub cube postgres redis caddy || true
  exit 1
fi

curl -fsS -o /dev/null -w "health: %{http_code}\n" http://127.0.0.1:3000/health || true
REMOTE_UP

echo "==> Deploy finished. Check https://forms.weown.tools (Cloudflare SSL: Full)."
