#!/usr/bin/env bash
# Create/update Cloudflare proxied A record for this Buzz site.
# Secure Handoff: token is prompted into this shell only — never argv, never logged.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 DROPLET_PUBLIC_IP" >&2
  exit 1
fi
IP="$1"
DOMAIN="${BUZZ_SITE_DOMAIN:-dev.weown.buzz}"
ZONE_NAME="${BUZZ_CF_ZONE:-weown.buzz}"
# Proxied (orange cloud) matches felg / PRJ-432.2.
PROXIED="${BUZZ_CF_PROXIED:-true}"

read -rs "CF_API_TOKEN?Paste Cloudflare API token (DNS edit for ${ZONE_NAME}): " 2>/dev/null \
  || read -rsp "Paste Cloudflare API token (DNS edit for ${ZONE_NAME}): " CF_API_TOKEN
echo
trap 'unset CF_API_TOKEN 2>/dev/null || true' EXIT
: "${CF_API_TOKEN:?token required}"

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json"
  fi
}

echo "=== resolve zone ${ZONE_NAME} ==="
ZONE_JSON="$(api GET "/zones?name=${ZONE_NAME}")"
ZONE_ID="$(printf '%s' "$ZONE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["id"] if r else "")')"
: "${ZONE_ID:?zone not found or token lacks Zone:Read}"

echo "=== existing A records for ${DOMAIN} ==="
REC_JSON="$(api GET "/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}")"
REC_ID="$(printf '%s' "$REC_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["id"] if r else "")')"
OLD_IP="$(printf '%s' "$REC_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0].get("content","") if r else "")')"

BODY="$(python3 - <<PY
import json
print(json.dumps({
  "type": "A",
  "name": "${DOMAIN}",
  "content": "${IP}",
  "ttl": 1,
  "proxied": ${PROXIED},
  "comment": "Buzz relay site dev-weown-buzz (isolated droplet)",
}))
PY
)"

if [[ -n "$REC_ID" ]]; then
  if [[ "$OLD_IP" == "$IP" ]]; then
    echo "=== A record already points at this IP (proxied=${PROXIED}) — no change ==="
  else
    echo "=== updating A ${DOMAIN}: ${OLD_IP} -> ${IP} ==="
    api PUT "/zones/${ZONE_ID}/dns_records/${REC_ID}" "$BODY" >/dev/null
  fi
else
  echo "=== creating A ${DOMAIN} -> ${IP} (proxied=${PROXIED}) ==="
  api POST "/zones/${ZONE_ID}/dns_records" "$BODY" >/dev/null
fi

echo "=== verify public HTTPS (may take a minute for CF/ACME) ==="
for i in $(seq 1 36); do
  CODE="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOMAIN}/" || true)"
  LIVE="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOMAIN}/_liveness" || true)"
  echo "try=$i nip11=${CODE} liveness=${LIVE}"
  if [[ "$CODE" == "200" && "$LIVE" == "200" ]]; then
    curl -fsS --max-time 20 "https://${DOMAIN}/" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("version=",d.get("version")); print("pairing=",d.get("pairing_relay_url"))'
    echo "OK: https://${DOMAIN}/ is live"
    exit 0
  fi
  sleep 10
done

echo "WARN: HTTPS not green yet — check Cloudflare SSL=Full (strict) and Caddy logs on the droplet" >&2
exit 2
