#!/usr/bin/env bash
# Create or update the public A record for registry.weown.tools.
# The token is read from the environment or an interactive prompt. It is never
# passed on argv.
#
# Public authority is Cloudflare (erin/jack.ns.cloudflare.com), set at the
# Porkbun registrar. A matching A record in the We Own Labs DigitalOcean zone
# is not queried by public resolvers. This script writes the Cloudflare record.
# Do not change the domain nameservers to DigitalOcean: other hostnames in
# weown.tools are served from Cloudflare.
#
# Usage:
#   RECORD_IP=<droplet-ipv4> ./scripts/dns-a-record.sh
# Optional:
#   CLOUDFLARE_API_TOKEN   API token with Zone.DNS edit on weown.tools
#   CF_PROXIED=false       grey-cloud (required for Caddy HTTP-01). Default false.
#   DNS_NAME=registry.weown.tools
#   DNS_ZONE=weown.tools
set -euo pipefail

DNS_ZONE="${DNS_ZONE:-weown.tools}"
DNS_NAME="${DNS_NAME:-registry.weown.tools}"
CF_PROXIED="${CF_PROXIED:-false}"
: "${RECORD_IP:?Set RECORD_IP to the droplet public IPv4 (RFC 5737 example: 203.0.113.10)}"

if [[ ! "$RECORD_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "RECORD_IP must be an IPv4 address" >&2
  exit 1
fi
case "$CF_PROXIED" in
  true|false) ;;
  *) echo "CF_PROXIED must be true or false" >&2; exit 1 ;;
esac

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  if [[ -t 0 ]]; then
    read -rs "CLOUDFLARE_API_TOKEN?Paste CLOUDFLARE_API_TOKEN: " 2>/dev/null \
      || read -rsp "Paste CLOUDFLARE_API_TOKEN: " CLOUDFLARE_API_TOKEN
    echo
    trap 'unset CLOUDFLARE_API_TOKEN 2>/dev/null || true' EXIT
  else
    cat >&2 <<EOF
CLOUDFLARE_API_TOKEN is not set, and this shell is not interactive.

The DigitalOcean zone is not the public DNS for ${DNS_ZONE}. Create the
record in the Cloudflare dashboard:
  Type A
  Name ${DNS_NAME}
  Content ${RECORD_IP}
  Proxy status DNS only (grey cloud)
  TTL Auto

Grey cloud is required so Let's Encrypt HTTP-01 reaches Caddy on port 80.
After the certificate is issued you may orange-cloud the record if the zone
SSL mode is Full (strict). Then re-run Caddy so it renews through the proxy.
EOF
    exit 2
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse the Cloudflare JSON response" >&2
  exit 1
fi

cf_api() {
  local method="$1" url="$2" body="${3:-}"
  local cfg http
  cfg=$(mktemp)
  chmod 600 "$cfg"
  # Token stays in a mode-600 curl config, not in argv.
  printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' \
    "$CLOUDFLARE_API_TOKEN" >"$cfg"
  if [[ -n "$body" ]]; then
    http=$(curl --silent --show-error --config "$cfg" -X "$method" --data "$body" \
      -w $'\n%{http_code}' "$url") || { rm -f "$cfg"; return 1; }
  else
    http=$(curl --silent --show-error --config "$cfg" -X "$method" \
      -w $'\n%{http_code}' "$url") || { rm -f "$cfg"; return 1; }
  fi
  rm -f "$cfg"
  printf '%s' "$http"
}

python_ok() {
  # stdin: body\nhttp_code. Prints a field or exits non-zero. Never prints the token.
  python3 -c '
import json, sys
raw = sys.stdin.read()
body, _, code = raw.rpartition("\n")
code = code.strip()
try:
    data = json.loads(body) if body else {}
except json.JSONDecodeError:
    print("cloudflare response was not JSON (http %s)" % code, file=sys.stderr)
    sys.exit(1)
if code not in ("200", "201") or not data.get("success", False):
    errs = data.get("errors") or data.get("messages") or body[:300]
    print("cloudflare API failed (http %s): %s" % (code, errs), file=sys.stderr)
    sys.exit(1)
field = sys.argv[1]
result = data.get("result")
if field == "zone_id":
    rows = result or []
    if not rows:
        print("zone not found", file=sys.stderr)
        sys.exit(1)
    print(rows[0]["id"])
elif field == "record_id":
    rows = result or []
    print(rows[0]["id"] if rows else "")
elif field == "content":
    print(result.get("content", ""))
else:
    print("ok")
' "$1"
}

zone_url="https://api.cloudflare.com/client/v4/zones?name=${DNS_ZONE}"
zone_id=$(cf_api GET "$zone_url" | python_ok zone_id)

list_url="https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A&name=${DNS_NAME}"
record_id=$(cf_api GET "$list_url" | python_ok record_id)

payload=$(printf '{"type":"A","name":"%s","content":"%s","ttl":1,"proxied":%s}' \
  "$DNS_NAME" "$RECORD_IP" "$CF_PROXIED")

if [[ -n "$record_id" ]]; then
  put_url="https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}"
  content=$(cf_api PUT "$put_url" "$payload" | python_ok content)
  echo "updated A ${DNS_NAME} -> ${content} (proxied=${CF_PROXIED})"
else
  post_url="https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records"
  content=$(cf_api POST "$post_url" "$payload" | python_ok content)
  echo "created A ${DNS_NAME} -> ${content} (proxied=${CF_PROXIED})"
fi
