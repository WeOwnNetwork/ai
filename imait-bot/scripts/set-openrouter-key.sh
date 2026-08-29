#!/usr/bin/env bash
# Secure Handoff: write OPENROUTER_API_KEY into host .env and recreate imait-bot.
# The key stays in this TTY — never argv, never printed. See AGENTS.md S1–S2.
# Does not pin a model or community; those stay in host .env / config.yaml.
set -euo pipefail

ENV_FILE="${1:-/opt/imait-bot/.env}"
COMPOSE_DIR="$(cd "$(dirname "$ENV_FILE")" && pwd)"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

read -rs "OPENROUTER_API_KEY?Paste OPENROUTER_API_KEY: " 2>/dev/null \
  || read -rsp "Paste OPENROUTER_API_KEY: " OPENROUTER_API_KEY
echo
trap 'unset OPENROUTER_API_KEY 2>/dev/null || true' EXIT
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "Empty key — aborted. No files changed." >&2
  exit 1
fi
if [[ "$OPENROUTER_API_KEY" != sk-or-* ]]; then
  echo "That does not look like an OpenRouter key (expected sk-or-...)." >&2
  exit 1
fi

awk -v v="$OPENROUTER_API_KEY" '
  BEGIN { done=0 }
  /^OPENROUTER_API_KEY=/ { print "OPENROUTER_API_KEY=" v; done=1; next }
  { print }
  END { if (!done) print "OPENROUTER_API_KEY=" v }
' "$ENV_FILE" > "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"
# Hermes uid must read the bind-mount; 0600 root-only caused EACCES earlier.
chmod 644 "$ENV_FILE"

cd "$COMPOSE_DIR"
docker compose up -d --force-recreate --no-deps imait-bot
echo "Key stored (not printed). Waiting for health..."
for i in $(seq 1 30); do
  if docker inspect --format '{{.State.Health.Status}}' imait-bot 2>/dev/null | grep -qx healthy; then
    echo "imait-bot is healthy. Mention the bot as a channel member to test inference."
    exit 0
  fi
  sleep 3
done
echo "Container started but health check not green yet — check: docker compose logs --since 2m imait-bot" >&2
exit 1
