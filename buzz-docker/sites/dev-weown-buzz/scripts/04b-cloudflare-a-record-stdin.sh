#!/usr/bin/env bash
# Non-interactive Cloudflare A-record helper.
# Usage (token NEVER on argv — stdin only):
#   printf '%s\n' "$CF_API_TOKEN" | ./04b-cloudflare-a-record-stdin.sh DROPLET_PUBLIC_IP
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 DROPLET_PUBLIC_IP   # CF token on stdin" >&2
  exit 1
fi
IP="$1"
DOMAIN="${BUZZ_SITE_DOMAIN:-dev.weown.buzz}"
ZONE_NAME="${BUZZ_CF_ZONE:-weown.buzz}"
PROXIED="${BUZZ_CF_PROXIED:-true}"

IFS= read -r CF_API_TOKEN || true
trap 'unset CF_API_TOKEN 2>/dev/null || true' EXIT
: "${CF_API_TOKEN:?CF token required on stdin}"

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

ZONE_JSON="$(api GET "/zones?name=${ZONE_NAME}")"
ZONE_ID="$(printf '%s' "$ZONE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["id"] if r else "")')"
: "${ZONE_ID:?zone not found or token lacks Zone:Read}"

REC_JSON="$(api GET "/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}")"
REC_ID="$(printf '%s' "$REC_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["id"] if r else "")')"
OLD_IP="$(printf '%s' "$REC_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0].get("content","") if r else "")')"

BODY="$(DOMAIN="$DOMAIN" IP="$IP" PROXIED="$PROXIED" python3 - <<'PY'
import json, os
print(json.dumps({
  "type": "A",
  "name": os.environ["DOMAIN"],
  "content": os.environ["IP"],
  "ttl": 1,
  "proxied": os.environ["PROXIED"].lower() == "true",
  "comment": "Buzz relay site dev-weown-buzz (isolated droplet)",
}))
PY
)"

if [[ -n "$REC_ID" ]]; then
  if [[ "$OLD_IP" == "$IP" ]]; then
    echo "A record already correct"
  else
    echo "updating A ${DOMAIN}: ${OLD_IP} -> ${IP}"
    api PUT "/zones/${ZONE_ID}/dns_records/${REC_ID}" "$BODY" >/dev/null
  fi
else
  echo "creating A ${DOMAIN} -> ${IP}"
  api POST "/zones/${ZONE_ID}/dns_records" "$BODY" >/dev/null
fi

echo "OK: DNS upserted for ${DOMAIN} (proxied=${PROXIED})"
echo "Set Cloudflare SSL/TLS to Full (strict). Caddy will obtain LE once DNS resolves."
