#!/usr/bin/env bash
set -euo pipefail
cd /opt/formbricks

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
  echo "Created /opt/formbricks/.env (secrets not displayed)"
else
  echo "Reusing existing /opt/formbricks/.env"
fi

docker compose pull
docker compose up -d
docker compose ps -a

echo "==> Waiting for Formbricks HTTP on :3000"
ok=0
for i in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ || true)"
  if [[ "${code}" == "200" || "${code}" == "302" || "${code}" == "307" || "${code}" == "308" ]]; then
    echo "localhost:3000 -> HTTP ${code}"
    ok=1
    break
  fi
  echo "attempt ${i}: HTTP ${code}"
  sleep 5
done
if [[ "${ok}" != "1" ]]; then
  echo "Formbricks did not become ready; recent logs:"
  docker compose logs --tail=100 formbricks-migrate hub-migrate formbricks hub cube postgres redis caddy || true
  exit 1
fi

curl -s -o /dev/null -w "health: %{http_code}\n" http://127.0.0.1:3000/health || true
echo "stack-up-ok"
