#!/usr/bin/env bash
# Configure SMTP (Twilio SendGrid) on Keycloak realms — sso.weown.id
#
# Usage (from the Mac):   ./scripts/kc-configure-smtp.sh root@129.212.240.145 [realm ...]
#   Default realms: weown weown-chat
#
# Secret model: the SendGrid API key must already exist in the KeycloakSSO
# Infisical project (prod) as SENDGRID_API_KEY. This script never sees it —
# the droplet-side snippet runs inside `infisical run`. No secret is on any
# argv: docker compose gets KC_CLI_PASSWORD and SMTP_JSON by NAME (`-e VAR`),
# kcadm reads the admin password from KC_CLI_PASSWORD (Keycloak 26+) and the
# SMTP settings, key included, as JSON on stdin (`update -f - --merge`).
# SMTP username for SendGrid is the literal string "apikey".
#
# After running: trigger a real password-reset email to prove delivery
# (Realm → Users → <user> → Credentials → "Send reset email"), and check
# SPF/DMARC on weown.net (DKIM was verified by Jason 2026-07-26).
set -euo pipefail

HOST="${1:?usage: $0 root@<sso-ip> [realm ...]}"; shift || true
REALMS=("${@:-weown weown-chat}")
[ $# -gt 0 ] || REALMS=(weown weown-chat)
# Every caller value below is pasted into a command that runs as root on the SSO host, so
# accept only what Keycloak names and addresses are made of (#276 review: a quote plus
# shell syntax in an argument would otherwise run there).
valid() {
  if [[ ! "$2" =~ $3 ]]; then echo "ERROR: invalid $1: $2" >&2; exit 2; fi
}
valid "ssh target" "$HOST" '^[A-Za-z0-9][A-Za-z0-9._@:-]*$'
for r in "${REALMS[@]}"; do valid realm "$r" '^[A-Za-z0-9][A-Za-z0-9._-]*$'; done

SMTP_FROM="no-reply@weown.net"          # DKIM-verified domain (WeOwn.Net, 2026-07-26)
SMTP_FROM_DISPLAY="WeOwn ID"
SMTP_HOST="smtp.sendgrid.net"
SMTP_PORT="2525"                         # STARTTLS — DO blocks egress 25/465/587; SendGrid listens on 2525 for exactly this

ssh "$HOST" "REALMS='${REALMS[*]}' SMTP_FROM='$SMTP_FROM' SMTP_FROM_DISPLAY='$SMTP_FROM_DISPLAY' SMTP_HOST='$SMTP_HOST' SMTP_PORT='$SMTP_PORT' bash -s" <<'EOF'
set -euo pipefail
cd /opt/sso_keycloak
source ./.infisical-auth.env
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
export INFISICAL_TOKEN
INFISICAL_TOKEN=$(timeout 30 infisical login --method=universal-auth --plain --silent </dev/null)

# The container-side script is a file fed to `sh -s` (the sibling kc-*.sh
# pattern): no secret is in it, and it needs no quoting three layers deep.
KCSCRIPT=$(mktemp /tmp/kc-configure-smtp.XXXXXX)
trap 'rm -f "$KCSCRIPT"' EXIT
export KCSCRIPT REALMS SMTP_FROM SMTP_FROM_DISPLAY SMTP_HOST SMTP_PORT
cat > "$KCSCRIPT" <<'KCEOF'
set -eu
KCADM=/opt/keycloak/bin/kcadm.sh
# No --password: kcadm reads KC_CLI_PASSWORD from its environment.
"$KCADM" config credentials --server http://localhost:8080 --realm master --user "$KC_USER" >/dev/null
for R in $REALMS; do
  # The settings, SendGrid key included, arrive as JSON on stdin, never as
  # `-s smtpServer.password=<key>` on kcadm's argv. --merge keeps every other
  # realm and smtpServer setting (kcadm deep-merges the object).
  printf '%s' "$SMTP_JSON" | "$KCADM" update "realms/$R" -f - --merge
  echo "OK: realm $R SMTP -> $SMTP_HOST:$SMTP_PORT from $SMTP_FROM (forgot-password enabled)"
done
KCEOF

# Run inside infisical run so SENDGRID_API_KEY + KEYCLOAK_ADMIN* are in env.
# jq builds the JSON from the environment (env.X), so the key is on no argv.
infisical run --projectId="$INFISICAL_PROJECT_ID" --env=prod -- bash -c '
set -euo pipefail
: "${SENDGRID_API_KEY:?SENDGRID_API_KEY missing from Infisical (KeycloakSSO/prod) — store it first}"
SMTP_JSON=$(jq -n "{smtpServer: {host: env.SMTP_HOST, port: env.SMTP_PORT, starttls: \"true\", auth: \"true\", user: \"apikey\", password: env.SENDGRID_API_KEY, from: env.SMTP_FROM, fromDisplayName: env.SMTP_FROM_DISPLAY, ssl: \"false\"}, resetPasswordAllowed: true}")
export SMTP_JSON
KC_CLI_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" docker compose exec -T \
  -e KC_USER="$KEYCLOAK_ADMIN" -e KC_CLI_PASSWORD -e SMTP_JSON \
  -e REALMS -e SMTP_FROM -e SMTP_HOST -e SMTP_PORT \
  keycloak sh -s < "$KCSCRIPT"
'
EOF
echo
echo "SMTP configured on realms: ${REALMS[*]}"
echo "PROVE IT: send a reset email to a real user in each realm and confirm receipt."
