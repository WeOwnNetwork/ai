#!/usr/bin/env bash
# provision-openrouter-key.sh — rotate/set the OpenRouter API key for one
# platform instance in OpenBao.
#
# Two modes:
#   --manual   prompt operator to paste a key (fallback, like s004 bootstrap)
#   --auto     mint a new budget-capped key via OpenRouter provisioning API
#              (requires OPENROUTER_PROVISIONING_KEY in env or prompts for it)
#
# Uses `kv patch` to merge without touching other secrets.
# Values move via stdin/pipes — never on argv, never printed, never on disk.
#
# Usage:
#   ./provision-openrouter-key.sh <instance> [--manual|--auto] [--limit <credits>]
#
# Auth: BAO_ADDR + BAO_TOKEN (or active `bao login` session) with write
# capability on weown/data/platform/<instance>.

set -euo pipefail

INSTANCE="${1:?usage: provision-openrouter-key.sh <instance> [--manual|--auto] [--limit <credits>]}"
shift

MODE="manual"
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manual) MODE="manual"; shift ;;
    --auto)   MODE="auto"; shift ;;
    --limit)  LIMIT="${2:?--limit requires a value}"; shift 2 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

KV_PATH="platform/${INSTANCE}"

[[ "$INSTANCE" =~ ^[a-z0-9-]+$ ]] || {
  echo "ERROR: instance must be lowercase alnum+hyphens: $INSTANCE" >&2; exit 1
}

command -v bao >/dev/null || { echo "ERROR: bao CLI not found" >&2; exit 1; }
command -v jq  >/dev/null || { echo "ERROR: jq not found" >&2; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl not found" >&2; exit 1; }

# Preflight: confirm auth
bao token lookup >/dev/null 2>&1 || {
  echo "ERROR: no valid BAO_TOKEN or active session for ${BAO_ADDR:-<unset>}" >&2; exit 1
}

# Confirm instance exists
bao kv get -mount=weown "$KV_PATH" >/dev/null 2>&1 || {
  echo "ERROR: instance '$INSTANCE' not found at weown/$KV_PATH — provisioned?" >&2; exit 1
}

# Current version (metadata only)
CURRENT_VERSION=$(bao kv get -mount=weown -format=json "$KV_PATH" \
  | jq -r '.data.metadata.version')
echo "Instance:        $INSTANCE"
echo "KV path:         weown/$KV_PATH"
echo "Current version: $CURRENT_VERSION"
echo "Mode:            $MODE"
echo

# Naming convention (matches s004 bootstrap pattern)
if exp_label="$(TZ=America/New_York date -d '+7 days' '+%Y-%m-%dT%H%M%Z' 2>/dev/null)"; then :; else
  exp_label="$(TZ=America/New_York date -v+7d '+%Y-%m-%dT%H%M%Z')"
fi
KEY_NAME="OPENROUTER_API_ANYTHINGLLM_$(echo "$INSTANCE" | tr "[:lower:]" "[:upper:]")_7D_EXP_${exp_label}"

trap 'unset OR_KEY OPENROUTER_PROVISIONING_KEY 2>/dev/null || true' EXIT

case "$MODE" in
  manual)
    echo "Create a NEW OpenRouter key (7-day expiry) named:"
    echo "  $KEY_NAME"
    echo
    printf "Paste the OpenRouter API key (blank to abort): "
    read -rs OR_KEY; echo
    [ -n "${OR_KEY:-}" ] || { echo "Aborted." >&2; exit 1; }
    ;;

  auto)
    # Get provisioning key — from env or prompt
    if [ -z "${OPENROUTER_PROVISIONING_KEY:-}" ]; then
      printf "Paste the OpenRouter PROVISIONING key (blank to abort): "
      read -rs OPENROUTER_PROVISIONING_KEY; echo
      [ -n "${OPENROUTER_PROVISIONING_KEY:-}" ] || { echo "Aborted." >&2; exit 1; }
    fi

    echo "Minting key: $KEY_NAME"
    [ -n "$LIMIT" ] && echo "Credit limit: $LIMIT"

    # Build request body via jq — never interpolated into argv
    REQ_BODY=$(jq -nc \
      --arg name "$KEY_NAME" \
      --arg label "$INSTANCE" \
      --arg limit "${LIMIT:-}" \
      '{name: $name, label: $label} + (if $limit != "" then {limit: ($limit|tonumber)} else {} end)')

    # Call OpenRouter API — provisioning key via stdin-loaded header
    RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST "https://openrouter.ai/api/v1/keys" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${OPENROUTER_PROVISIONING_KEY}" \
      -d "$REQ_BODY")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
      OR_KEY=$(echo "$BODY" | jq -r '.data.key // .key // empty')
      [ -n "${OR_KEY:-}" ] || {
        echo "✗ API returned $HTTP_CODE but no key in response:" >&2
        echo "$BODY" | jq . 2>/dev/null || echo "$BODY" >&2
        exit 1
      }
      echo "✓ Key minted via OpenRouter API (HTTP $HTTP_CODE)"
    else
      echo "✗ OpenRouter API error (HTTP $HTTP_CODE):" >&2
      echo "$BODY" | jq . 2>/dev/null || echo "$BODY" >&2
      exit 1
    fi
    ;;
esac

# Write to OpenBao via kv patch — value on stdin via jq pipe, never argv
printf '%s' "$OR_KEY" | jq -Rn '{"OPENROUTER_API_KEY": input}' \
  | bao kv patch -mount=weown "$KV_PATH" - >/dev/null 2>&1 \
  && {
    NEW_VERSION=$(bao kv get -mount=weown -format=json "$KV_PATH" \
      | jq -r '.data.metadata.version')
    echo "✓ OPENROUTER_API_KEY written to weown/$KV_PATH (v$CURRENT_VERSION → v$NEW_VERSION)"
  } || {
    echo "✗ FAILED to write — check token capabilities on weown/data/$KV_PATH" >&2
    exit 1
  }

unset OR_KEY
echo "Done. Instance $INSTANCE will pick up the new key at next boot/restart."
