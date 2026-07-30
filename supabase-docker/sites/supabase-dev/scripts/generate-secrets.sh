#!/usr/bin/env bash
# supabase-dev — Generate Supabase application secrets
#
# Mints every application secret Supabase needs. ANON_KEY and SERVICE_ROLE_KEY
# are real HS256 JWTs signed with the generated JWT_SECRET — they MUST
# cryptographically verify against JWT_SECRET or GoTrue + PostgREST auth
# fails at container start.
#
# Usage:
#   ./scripts/generate-secrets.sh
#     Prints KEY=VALUE pairs to stdout. Copy-paste into Infisical Dashboard →
#     your project's secrets tab.
#
#   ./scripts/generate-secrets.sh --infisical-cmds --project-id <id>
#     Prints `infisical secrets set` commands ready to run.
#
#   ./scripts/generate-secrets.sh --help
#     Show help.
#
# CRITICAL:
#   - NEVER commit the output. No .env file is written to disk by default.
#   - Store values in Infisical. The droplet fetches them via `infisical run`.
#   - Re-running generates NEW values. Only re-run to ROTATE all app secrets
#     (invalidates existing JWTs; requires re-writing Infisical + a
#     `docker compose restart` on the droplet).
#
# Dependencies:
#   - openssl (random + HMAC-SHA256)
#   - date, printf, tr (POSIX)
#   No Python, no jose, no jwt CLI. Runs on any macOS or Linux with openssl.

set -euo pipefail

# ─── Argument parsing ────────────────────────────────────────────────────────
MODE="pairs"           # pairs | infisical-cmds
PROJECT_ID=""
INFISICAL_ENV="prod"

show_help() {
  cat <<EOF
Usage:
  $0                                    Print KEY=VALUE pairs to stdout
  $0 --infisical-cmds --project-id ID   Print 'infisical secrets set' cmds
  $0 --env <slug>                       Infisical env slug (default: prod)
  $0 --help                             This help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --infisical-cmds) MODE="infisical-cmds"; shift ;;
    --project-id)     PROJECT_ID="$2"; shift 2 ;;
    --env)            INFISICAL_ENV="$2"; shift 2 ;;
    -h|--help)        show_help; exit 0 ;;
    *)                echo "unknown flag: $1" >&2; show_help >&2; exit 1 ;;
  esac
done

if [[ "$MODE" == "infisical-cmds" && -z "$PROJECT_ID" ]]; then
  echo "ERROR: --infisical-cmds requires --project-id <id>" >&2
  exit 1
fi

# ─── base64url + HS256 JWT helpers ───────────────────────────────────────────
# base64url = base64 with `=` padding stripped, `/` → `_`, `+` → `-`.
# `openssl base64 -A` outputs on one line (no wrapping) on both macOS BSD and
# GNU. Final `tr -d '\n'` catches any trailing newline from stdin edge cases.
b64url() {
  openssl base64 -A | tr -d '=\n' | tr '/+' '_-'
}

# HS256-sign a JWT with the given secret. Payload has `role` (Supabase RLS
# reads this), `iss=supabase` (GoTrue requires an iss), plus iat/exp claims.
# exp = 10 years — Supabase self-host convention (these are long-lived keys,
# rotation = re-run this script + re-paste to Infisical).
mint_jwt() {
  local role="$1"
  local secret="$2"
  local iat exp header payload h p sig
  iat=$(date +%s)
  exp=$((iat + 10 * 365 * 24 * 3600))
  header='{"alg":"HS256","typ":"JWT"}'
  payload=$(printf '{"role":"%s","iss":"supabase","iat":%d,"exp":%d}' "$role" "$iat" "$exp")
  h=$(printf '%s' "$header"  | b64url)
  p=$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$secret" -binary | b64url)
  printf '%s.%s.%s\n' "$h" "$p" "$sig"
}

# ─── Generate ────────────────────────────────────────────────────────────────

# Postgres superuser password. Hex-only avoids URL-parsing traps in the DB
# connection string (which GoTrue + PostgREST + Realtime embed inline).
POSTGRES_PASSWORD=$(openssl rand -hex 32)

# JWT_SECRET — 80 hex chars (40 bytes). Also stored in Infisical under
# PGRST_JWT_SECRET and GOTRUE_JWT_SECRET (same value, three var names —
# Supabase self-host convention because each service reads a different env).
JWT_SECRET=$(openssl rand -hex 40)

# Role JWTs signed against JWT_SECRET.
ANON_KEY=$(mint_jwt "anon" "$JWT_SECRET")
SERVICE_ROLE_KEY=$(mint_jwt "service_role" "$JWT_SECRET")

# Studio basic-auth. Username is human-typed at login — default to `admin`,
# operator can override before pasting to Infisical. Password is random.
DASHBOARD_USERNAME="admin"
DASHBOARD_PASSWORD=$(openssl rand -hex 24)
# Caddy's basic_auth consumes a BCRYPT hash (DASHBOARD_PASSWORD_BCRYPT), not the
# plaintext. Mint it via the caddy image reading the password on stdin (never
# argv). The plaintext DASHBOARD_PASSWORD is what the operator types at login.
DASHBOARD_PASSWORD_BCRYPT=$(printf '%s' "$DASHBOARD_PASSWORD" | docker run --rm -i caddy:2 caddy hash-password 2>/dev/null)   || { echo "ERROR: could not mint DASHBOARD_PASSWORD_BCRYPT (docker + caddy:2 image required)" >&2; exit 1; }

# Realtime service. Per Supabase self-host docs:
#   SECRET_KEY_BASE — cookie/session signing key, must be ≥64 chars
#   DB_ENC_KEY      — column encryption key, must be EXACTLY 16 chars
REALTIME_SECRET_KEY_BASE=$(openssl rand -hex 32)   # 64 hex chars
REALTIME_DB_ENC_KEY=$(openssl rand -hex 8)         # 16 hex chars

# ─── Output ──────────────────────────────────────────────────────────────────
emit() {
  # $1 = KEY, $2 = VALUE
  local key="$1" val="$2"
  if [[ "$MODE" == "infisical-cmds" ]]; then
    # Single-quote the value; escape any embedded single quotes (unlikely
    # given openssl rand -hex output, but defensive).
    local escaped_val="${val//\'/\'\\\'\'}"
    printf "infisical secrets set --projectId='%s' --env='%s' %s='%s'\n" \
      "$PROJECT_ID" "$INFISICAL_ENV" "$key" "$escaped_val"
  else
    printf '%s=%s\n' "$key" "$val"
  fi
}

if [[ "$MODE" == "pairs" ]]; then
  cat <<HEADER
# supabase-dev — generated $(date -Iseconds)
# ⚠️  DO NOT commit this output. Paste into Infisical Dashboard → Secrets.
# NOTE: JWT_SECRET must ALSO be stored as PGRST_JWT_SECRET and
# GOTRUE_JWT_SECRET in Infisical — same value, three var names.

HEADER
fi

emit POSTGRES_PASSWORD        "$POSTGRES_PASSWORD"
emit JWT_SECRET               "$JWT_SECRET"
emit PGRST_JWT_SECRET         "$JWT_SECRET"
emit GOTRUE_JWT_SECRET        "$JWT_SECRET"
emit ANON_KEY                 "$ANON_KEY"
emit SERVICE_ROLE_KEY         "$SERVICE_ROLE_KEY"
emit DASHBOARD_USERNAME       "$DASHBOARD_USERNAME"
emit DASHBOARD_PASSWORD       "$DASHBOARD_PASSWORD"
emit DASHBOARD_PASSWORD_BCRYPT "$DASHBOARD_PASSWORD_BCRYPT"
emit REALTIME_SECRET_KEY_BASE "$REALTIME_SECRET_KEY_BASE"
emit REALTIME_DB_ENC_KEY      "$REALTIME_DB_ENC_KEY"

if [[ "$MODE" == "pairs" ]]; then
  cat <<FOOTER

# Verify ANON_KEY signs correctly (optional smoke test):
#   JWT_SECRET='<paste JWT_SECRET>'
#   payload='eyJyb2xlIjoiYW5vbi...'   # ANON_KEY's middle segment (between the dots)
#   sig='.....'                       # ANON_KEY's third segment
#   expected=\$(printf '%s.%s' "\$header" "\$payload" | openssl dgst -sha256 -hmac "\$JWT_SECRET" -binary | openssl base64 -A | tr -d '=\n' | tr '/+' '_-')
#   [ "\$expected" = "\$sig" ] && echo OK
FOOTER
fi
