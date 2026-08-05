#!/usr/bin/env bash
# Configure SMTP (Twilio SendGrid) on Keycloak realms — sso.weown.id
#
# Usage (from the Mac):   ./scripts/kc-configure-smtp.sh root@129.212.240.145 [realm ...]
#   Default realms: weown weown-chat
#
# Secret model: the SendGrid API key must already exist in the KeycloakSSO
# Infisical project (prod) as SENDGRID_API_KEY. This script never sees it —
# the droplet-side snippet runs inside `infisical run`, and kcadm receives the
# value in-process. SMTP username for SendGrid is the literal string "apikey".
#
# After running: trigger a real password-reset email to prove delivery
# (Realm → Users → <user> → Credentials → "Send reset email"), and check
# SPF/DMARC on weown.net (DKIM was verified by Jason 2026-07-26).
set -euo pipefail

HOST="${1:?usage: $0 root@<sso-ip> [realm ...]}"; shift || true
REALMS=("${@:-weown weown-chat}")
[ $# -gt 0 ] || REALMS=(weown weown-chat)

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

# Run everything inside infisical run so SENDGRID_API_KEY + KEYCLOAK_ADMIN*
# are in env; kcadm gets the secret in-process (never argv outside the
# container, never on disk).
infisical run --projectId="$INFISICAL_PROJECT_ID" --env=prod -- bash -c '
set -euo pipefail
: "${SENDGRID_API_KEY:?SENDGRID_API_KEY missing from Infisical (KeycloakSSO/prod) — store it first}"
docker compose exec -T \
  -e KC_USER="$KEYCLOAK_ADMIN" -e KC_PASS="$KEYCLOAK_ADMIN_PASSWORD" -e SG_KEY="$SENDGRID_API_KEY" \
  -e REALMS="$REALMS" -e SMTP_FROM -e SMTP_FROM_DISPLAY -e SMTP_HOST -e SMTP_PORT \
  keycloak sh -c "
set -eu
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
  --user \"\$KC_USER\" --password \"\$KC_PASS\" >/dev/null
for R in \$REALMS; do
  /opt/keycloak/bin/kcadm.sh update realms/\$R \
    -s \"smtpServer.host=\$SMTP_HOST\" \
    -s \"smtpServer.port=\$SMTP_PORT\" \
    -s \"smtpServer.starttls=true\" \
    -s \"smtpServer.auth=true\" \
    -s \"smtpServer.user=apikey\" \
    -s \"smtpServer.password=\$SG_KEY\" \
    -s \"smtpServer.from=\$SMTP_FROM\" \
    -s \"smtpServer.fromDisplayName=\$SMTP_FROM_DISPLAY\" \
    -s \"smtpServer.ssl=false\" \
    -s \"resetPasswordAllowed=true\"
  echo \"OK: realm \$R SMTP -> \$SMTP_HOST:\$SMTP_PORT from \$SMTP_FROM (forgot-password enabled)\"
done
" </dev/null
'
EOF
echo
echo "SMTP configured on realms: ${REALMS[*]}"
echo "PROVE IT: send a reset email to a real user in each realm and confirm receipt."
