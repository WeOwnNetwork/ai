#!/usr/bin/env bash
# provision-openrouter-key.sh — mint a per-customer, budget-capped OpenRouter API
# key and push it into that customer's Infisical app project as OPENROUTER_API_KEY.
#
# WHY. Each paying customer's private AnythingLLM instance gets its OWN OpenRouter
# key, for two reasons:
#   1. Blast-radius isolation — one customer's leaked/compromised instance can be
#      revoked without touching any other customer.
#   2. Clean per-customer cost attribution + a HARD monthly spend cap, so a runaway
#      or abused instance can never burn the shared account. The cap is enforced by
#      OpenRouter itself (`limit` + `limit_reset: monthly`), not by us.
# This AUTOMATES the previously-manual "create a key in the OpenRouter dashboard
# and paste it" step that the per-site bootstrap-*-infisical.sh scripts prompt for.
#
# HOW. Uses the OpenRouter Management/Provisioning API:
#   POST https://openrouter.ai/api/v1/keys   {name, limit, limit_reset:"monthly"}
# Auth is an OpenRouter PROVISIONING key (distinct from a runtime inference key),
# sourced IN-PROCESS from the operator Infisical project as OPENROUTER_PROVISIONING_KEY
# — never on argv, never printed, never written to disk (read -rs fallback if absent).
# The minted customer key is written straight into the site Infisical project and is
# NEVER printed to the terminal or written to disk.
#
# There is deliberately no OpenTofu here: OpenRouter has no Terraform provider, so
# key provisioning is a script/API step in the deploy flow, not an IaC resource.
#
# Usage:
#   bash scripts/provision-openrouter-key.sh \
#     --customer <slug> \
#     --project-id <site Infisical project id> \
#     [--limit-usd 50] [--env prod] [--operator-project operator-tools] [--force]
#
# Prereqs: infisical CLI (logged in), curl, jq.
#
# SECURITY NOTE. Like the per-site bootstrap-*-infisical.sh scripts, the final
# `infisical secrets set OPENROUTER_API_KEY=<value>` passes the value as a process
# argument, so it is briefly visible in `ps`/proc on THIS operator machine only —
# never on disk, in shell history, or on the network. That is acceptable on a
# single-operator laptop. On a shared host, run with --dry-run to mint nothing and
# set the value in the Infisical UI instead, or wrap this in the Infisical API.
set -uo pipefail

OPENROUTER_KEYS_API="https://openrouter.ai/api/v1/keys"

# ── defaults ─────────────────────────────────────────────────────────────────
CUSTOMER=""
PROJECT_ID=""
LIMIT_USD="50"
ENV_SLUG="prod"
OPERATOR_PROJECT="operator-tools"
FORCE=0
DRY_RUN=0

usage() {
  sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --customer)          CUSTOMER="${2:-}"; shift 2 ;;
    --project-id)        PROJECT_ID="${2:-}"; shift 2 ;;
    --limit-usd)         LIMIT_USD="${2:-}"; shift 2 ;;
    --env)               ENV_SLUG="${2:-}"; shift 2 ;;
    --operator-project)  OPERATOR_PROJECT="${2:-}"; shift 2 ;;
    --force)             FORCE=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           usage 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage 1 ;;
  esac
done

# ── validate inputs ──────────────────────────────────────────────────────────
[[ -n "$CUSTOMER"   ]] || { echo "ERROR: --customer is required (short slug, e.g. acme-cpa)." >&2; exit 1; }
[[ -n "$PROJECT_ID" ]] || { echo "ERROR: --project-id is required (the customer's site Infisical project id)." >&2; exit 1; }
[[ "$CUSTOMER" =~ ^[a-z0-9-]+$ ]] || { echo "ERROR: --customer must be lowercase alphanumeric with hyphens: $CUSTOMER" >&2; exit 1; }
[[ "$LIMIT_USD" =~ ^[0-9]+$ ]]    || { echo "ERROR: --limit-usd must be a whole number of US dollars: $LIMIT_USD" >&2; exit 1; }

# ── preflight ────────────────────────────────────────────────────────────────
for bin in infisical curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' not found on PATH. Install it first." >&2; exit 1; }
done

# Ensure an Infisical session up front (the whoami/user probes return non-zero when
# not logged in; they do not hang). This mirrors the per-site bootstrap scripts.
if infisical whoami >/dev/null 2>&1 || infisical user >/dev/null 2>&1; then
  echo "Infisical session active."
else
  echo "No active Infisical session — launching 'infisical login'..."
  infisical login || { echo "ERROR: 'infisical login' did not complete. Log in and re-run." >&2; exit 1; }
fi

# Clear every secret var no matter how we exit.
trap 'unset PROV_KEY CUSTOMER_KEY 2>/dev/null || true' EXIT

# ── refuse to clobber an existing key unless --force (avoid orphaning) ────────
if infisical secrets get OPENROUTER_API_KEY \
     --projectId="$PROJECT_ID" --env="$ENV_SLUG" --path=/ >/dev/null 2>&1; then
  if [[ "$FORCE" -ne 1 ]]; then
    echo "ERROR: OPENROUTER_API_KEY already set in project $PROJECT_ID (env $ENV_SLUG)." >&2
    echo "       Minting a new one would ORPHAN the old key on OpenRouter. Revoke the old" >&2
    echo "       key in the OpenRouter dashboard first, then re-run with --force to replace." >&2
    exit 1
  fi
  echo "⚠️  OPENROUTER_API_KEY already present — --force given, will overwrite (revoke the OLD key manually)."
fi

# ── source the OpenRouter PROVISIONING key in-process (never printed) ─────────
# Preferred: from the operator Infisical project. Fallback: hidden prompt.
PROV_KEY="$(infisical secrets get OPENROUTER_PROVISIONING_KEY \
  --projectId="$OPERATOR_PROJECT" --env="$ENV_SLUG" --path=/ --plain 2>/dev/null || true)"
if [[ -z "${PROV_KEY:-}" ]]; then
  echo "OPENROUTER_PROVISIONING_KEY not found in Infisical project '$OPERATOR_PROJECT' (env $ENV_SLUG)."
  echo "Paste an OpenRouter PROVISIONING key (Settings → Provisioning API Keys). Input is hidden:"
  read -rs PROV_KEY; echo
fi
[[ -n "${PROV_KEY:-}" ]] || { echo "ERROR: no provisioning key available; cannot mint." >&2; exit 1; }

# ── build the key name + request ─────────────────────────────────────────────
CUSTOMER_UPPER="$(printf '%s' "$CUSTOMER" | tr 'a-z-' 'A-Z_')"
KEY_NAME="OPENROUTER_${CUSTOMER_UPPER}_ANYTHINGLLM_MONTHLY_${LIMIT_USD}USD"
REQ_BODY="$(jq -nc --arg name "$KEY_NAME" --argjson limit "$LIMIT_USD" \
  '{name: $name, limit: $limit, limit_reset: "monthly"}')"

echo
echo "── Minting per-customer OpenRouter key ──"
echo "  customer:     $CUSTOMER"
echo "  key name:     $KEY_NAME"
echo "  monthly cap:  \$$LIMIT_USD (resets 1st of month, UTC)"
echo "  site project: $PROJECT_ID (env $ENV_SLUG)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "[DRY RUN] Would POST $OPENROUTER_KEYS_API with: $REQ_BODY"
  echo "[DRY RUN] Would set OPENROUTER_API_KEY in project $PROJECT_ID. Nothing minted."
  exit 0
fi

# ── mint via the OpenRouter Management API ───────────────────────────────────
HTTP_RESP="$(curl -sS -o - -w $'\n%{http_code}' -X POST "$OPENROUTER_KEYS_API" \
  -H "Authorization: Bearer ${PROV_KEY}" \
  -H "Content-Type: application/json" \
  -d "$REQ_BODY" 2>/dev/null || true)"
HTTP_CODE="${HTTP_RESP##*$'\n'}"
HTTP_BODY="${HTTP_RESP%$'\n'*}"

if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  # On a non-2xx there is no minted key in the body — safe to surface for debugging.
  echo "ERROR: OpenRouter key creation failed (HTTP ${HTTP_CODE:-none})." >&2
  echo "$HTTP_BODY" | jq . 2>/dev/null >&2 || echo "$HTTP_BODY" >&2
  exit 1
fi

# The secret key string is returned once, at the top level (`.key`); some API
# versions nest it under `.data.key`. Parse defensively; never echo the value.
CUSTOMER_KEY="$(printf '%s' "$HTTP_BODY" | jq -r '.key // .data.key // empty')"
if [[ -z "${CUSTOMER_KEY:-}" ]]; then
  echo "ERROR: key created but the secret string wasn't found in the response." >&2
  echo "       Response top-level fields were: $(printf '%s' "$HTTP_BODY" | jq -rc 'keys? // "unparseable"' 2>/dev/null)" >&2
  echo "       Check the OpenRouter dashboard for a dangling key named: $KEY_NAME" >&2
  exit 1
fi

# ── push into the site Infisical project (see SECURITY NOTE in header) ───────
if infisical secrets set "OPENROUTER_API_KEY=${CUSTOMER_KEY}" \
     --projectId="$PROJECT_ID" --env="$ENV_SLUG" --path=/ >/dev/null 2>&1; then
  echo "  ✓ set OPENROUTER_API_KEY in project $PROJECT_ID"
else
  echo "ERROR: minted the key but FAILED to set OPENROUTER_API_KEY in Infisical." >&2
  echo "       The key exists on OpenRouter as '$KEY_NAME' — set it in the UI or re-run, then" >&2
  echo "       delete any duplicate on OpenRouter to avoid orphans." >&2
  exit 1
fi

echo
echo "Done — '$KEY_NAME' minted (\$$LIMIT_USD/mo cap) and stored as OPENROUTER_API_KEY."
echo "No key value touched disk, history, or this terminal."
echo
echo "ZDR posture: keys inherit the OpenRouter ACCOUNT-level Zero-Data-Retention"
echo "guardrail (Settings → Privacy: restrict routing to ZDR-only endpoints). For"
echo "customer instances handling financial/personal records that guardrail MUST be"
echo "on — verify it once per account; every per-customer key is then covered."
echo
echo "Next: deploy/redeploy the instance so the container picks up the key (see"
echo "anythingllm-docker/DEPLOYMENT_GUIDE.md §6.5). Verify a real chat completes."
