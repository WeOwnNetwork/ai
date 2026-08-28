#!/usr/bin/env bash
# Secure Handoff: paste secrets into /opt/imait-bot/.env on this host.
# Secrets stay in this shell — never pass them on argv. See AGENTS.md S1–S2.
set -euo pipefail

ENV_FILE="${1:-/opt/imait-bot/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy .env.example first." >&2
  exit 1
fi

upsert() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    # Avoid sed -i backup files; rewrite via temp.
    awk -v k="$key" -v v="$value" '
      BEGIN { FS=OFS="=" }
      $1==k { print k"="v; next }
      { print }
    ' "$ENV_FILE" > "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

chmod 600 "$ENV_FILE"

read -rs "BUZZ_PRIVATE_KEY?Paste BUZZ_PRIVATE_KEY (nsec or hex): " 2>/dev/null \
  || read -rsp "Paste BUZZ_PRIVATE_KEY (nsec or hex): " BUZZ_PRIVATE_KEY
echo
trap 'unset BUZZ_PRIVATE_KEY OPENROUTER_API_KEY 2>/dev/null || true' EXIT
upsert BUZZ_PRIVATE_KEY "$BUZZ_PRIVATE_KEY"

read -rs "OPENROUTER_API_KEY?Paste OPENROUTER_API_KEY (empty to skip): " 2>/dev/null \
  || read -rsp "Paste OPENROUTER_API_KEY (empty to skip): " OPENROUTER_API_KEY
echo
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  upsert OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
fi

echo "Wrote secrets into $ENV_FILE (values not printed). Restart: docker compose up -d"
