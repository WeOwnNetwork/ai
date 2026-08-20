#!/usr/bin/env bash
# Enable Buzz mobile pairing sidecar with minimal disruption.
# - Does not print .env secrets
# - Does not recreate Postgres/Redis/MinIO
# - Uses the already-pulled BUZZ image (has buzz-pair-relay binary)
set -euo pipefail

COMPOSE=/opt/dev-weown-buzz/buzz/deploy/compose
cd "$COMPOSE"

DOMAIN="$(grep -E '^BUZZ_DOMAIN=' .env | cut -d= -f2-)"
: "${DOMAIN:?BUZZ_DOMAIN missing from .env}"

PAIR_URL="wss://${DOMAIN}/pair"

echo "=== domain=${DOMAIN} pairing_url=${PAIR_URL} ==="

# 1) Persist pairing URL in .env (public; not a secret)
if grep -qE '^BUZZ_PAIRING_RELAY_URL=' .env; then
  sed -i "s|^BUZZ_PAIRING_RELAY_URL=.*|BUZZ_PAIRING_RELAY_URL=${PAIR_URL}|" .env
else
  printf '\n# Mobile pairing (NIP-AB) — advertised in NIP-11 as pairing_relay_url\nBUZZ_PAIRING_RELAY_URL=%s\n' "$PAIR_URL" >> .env
fi
grep -E '^BUZZ_PAIRING_RELAY_URL=' .env

# 2) Pairing sidecar overlay (same image as main relay)
cat > compose.pairing.yml <<'YAML'
# Mobile pairing sidecar (NIP-AB). Same image; different entrypoint.
# Wired so Desktop Settings → Mobile gets pairing_relay_url and /pair works.
services:
  pairing-relay:
    image: ${BUZZ_IMAGE:?set BUZZ_IMAGE}
    entrypoint: ["/usr/local/bin/buzz-pair-relay"]
    environment:
      BUZZ_PAIR_RELAY_BIND_ADDR: "0.0.0.0:5000"
    # No host ports — only reachable via Caddy on buzz-net.
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "bash -ec 'exec 3<>/dev/tcp/127.0.0.1/5000'",
        ]
      interval: 10s
      timeout: 3s
      retries: 6
      start_period: 5s
    restart: unless-stopped
    networks:
      - buzz-net
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 128M

  relay:
    environment:
      BUZZ_PAIRING_RELAY_URL: ${BUZZ_PAIRING_RELAY_URL:?set BUZZ_PAIRING_RELAY_URL}
YAML

# 3) Caddy: /pair → pairing-relay, everything else → main relay
cp -a Caddyfile "Caddyfile.bak.$(date -u +%Y%m%d%H%M%S)"
cat > Caddyfile <<'CADDY'
{$BUZZ_DOMAIN} {
	encode zstd gzip

	# NIP-AB pairing WebSocket (stateless buzz-pair-relay sidecar).
	# handle_path strips /pair so the sidecar sees /.
	handle_path /pair* {
		reverse_proxy pairing-relay:5000
	}

	handle {
		reverse_proxy relay:3000
	}
}
CADDY

# 4) Teach run.sh to always include the pairing overlay
if ! grep -q 'compose.pairing.yml' run.sh; then
  cp -a run.sh "run.sh.bak.$(date -u +%Y%m%d%H%M%S)"
  # Insert after COMPOSE_FILES=(-f compose.yml)
  python3 - <<'PY'
from pathlib import Path
p = Path("run.sh")
text = p.read_text()
needle = 'COMPOSE_FILES=(-f compose.yml)\n'
insert = needle + 'if [[ -f compose.pairing.yml ]]; then\n  COMPOSE_FILES+=(-f compose.pairing.yml)\nfi\n'
if needle not in text:
    raise SystemExit("run.sh pattern not found")
if "compose.pairing.yml" in text:
    print("run.sh already includes pairing overlay")
else:
    p.write_text(text.replace(needle, insert, 1))
    print("run.sh updated for compose.pairing.yml")
PY
fi

# Resolve BUZZ_IMAGE for compose (digest preferred if present in .env)
if ! grep -qE '^BUZZ_IMAGE=' .env; then
  # Fall back to the image currently running on the relay container (no :main drift).
  DIGEST="$(docker inspect buzz-prod-relay-1 --format '{{index .Image}}')"
  # Prefer RepoDigest if available
  REPO="$(docker inspect buzz-prod-relay-1 --format '{{index .Config.Image}}')"
  echo "BUZZ_IMAGE=${REPO}" >> .env
  echo "NOTE: wrote BUZZ_IMAGE=${REPO} into .env"
fi

# Ensure compose can interpolate — if still :main, pin to running digest
IMG_LINE="$(grep -E '^BUZZ_IMAGE=' .env | cut -d= -f2-)"
case "$IMG_LINE" in
  *:main|*:latest)
    DIGEST="$(docker image inspect "$IMG_LINE" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
    if [[ -n "${DIGEST}" ]]; then
      sed -i "s|^BUZZ_IMAGE=.*|BUZZ_IMAGE=${DIGEST}|" .env
      echo "Pinned floating tag to ${DIGEST}"
    fi
    ;;
esac
grep -E '^BUZZ_IMAGE=' .env

echo "=== bringing up pairing-relay (new) ==="
BUZZ_COMPOSE_TLS=true ./run.sh config >/tmp/buzz-compose-config.yml
grep -E 'pairing-relay|BUZZ_PAIRING_RELAY_URL|/pair' /tmp/buzz-compose-config.yml | head -40

# Start/recreate only what we need
docker compose --env-file .env -f compose.yml -f compose.pairing.yml -f compose.caddy.yml up -d --no-deps pairing-relay
docker compose --env-file .env -f compose.yml -f compose.pairing.yml -f compose.caddy.yml up -d --no-deps --force-recreate caddy
docker compose --env-file .env -f compose.yml -f compose.pairing.yml -f compose.caddy.yml up -d --no-deps --force-recreate relay

echo "=== wait for healthy ==="
for i in $(seq 1 36); do
  RELAY_H="$(docker inspect -f '{{.State.Health.Status}}' buzz-prod-relay-1 2>/dev/null || echo missing)"
  PAIR_H="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' buzz-prod-pairing-relay-1 2>/dev/null || echo missing)"
  echo "try=$i relay=$RELAY_H pairing=$PAIR_H"
  if [[ "$RELAY_H" == "healthy" && "$PAIR_H" == "healthy" ]]; then
    break
  fi
  if [[ "$i" -eq 36 ]]; then
    echo "ERROR: timed out waiting for healthy relay/pairing" >&2
    docker logs buzz-prod-pairing-relay-1 --tail 40 2>&1 || true
    docker logs buzz-prod-relay-1 --tail 40 2>&1 | grep -Eiv 'password|secret|private|token|DATABASE_URL|REDIS_URL' || true
    exit 1
  fi
  sleep 5
done

echo "=== status ==="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -E 'buzz-prod|NAMES' || true

echo "=== verify NIP-11 pairing_relay_url ==="
INFO="$(curl -fsS --max-time 20 "https://${DOMAIN}/" || true)"
if [[ -z "$INFO" ]]; then
  INFO="$(curl -fsSk --max-time 10 -H "Host: ${DOMAIN}" https://127.0.0.1/ || true)"
fi
printf '%s' "$INFO" | python3 -c '
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print("ERROR: empty NIP-11 body")
    raise SystemExit(2)
doc = json.loads(raw)
url = doc.get("pairing_relay_url")
nips = doc.get("supported_nips") or []
print("version=" + str(doc.get("version")))
print("pairing_relay_url=" + str(url))
print("has_nip43=" + str(43 in nips))
if not url:
    print("ERROR: pairing_relay_url missing from NIP-11")
    raise SystemExit(3)
'

echo "=== verify /pair WebSocket upgrade ==="
CODE="$(curl -sS -o /tmp/pair-ws.out -w '%{http_code}' --http1.1 --max-time 15 \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  "https://${DOMAIN}/pair" || true)"
echo "pair_http_code=${CODE}"
if [[ "$CODE" == "101" ]]; then
  echo "OK: /pair WebSocket upgrade succeeded"
else
  echo "INFO: public WS probe returned ${CODE}; checking internal path"
  docker run --rm --network buzz-prod_buzz-net curlimages/curl:8.5.0 -sS -o /dev/null -w 'internal_pair=%{http_code}\n' \
    --http1.1 --max-time 10 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    http://pairing-relay:5000/ || true
fi

echo "=== done ==="
