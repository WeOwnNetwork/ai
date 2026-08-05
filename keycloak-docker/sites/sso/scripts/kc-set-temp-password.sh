#!/usr/bin/env bash
# kc-set-temp-password.sh — interim invite path while realm SMTP is not
# configured: set a generated ONE-TIME password (UPDATE_PASSWORD forced) on an
# EXISTING Keycloak user, looked up by email. Prints the password ONCE.
#
#   ./kc-set-temp-password.sh <realm> <email>
#   e.g. ./kc-set-temp-password.sh weown-chat chat-demo@weown.net
#
# Does NOT create users (tenant users are created by kc-provision-tenant.sh).
set -euo pipefail

REALM="${1:?usage: $0 <realm> <email>}"
EMAIL="${2:?usage: $0 <realm> <email>}"

ssh sso-keycloak 'bash -s' -- <<REMOTE
set -euo pipefail
cd /opt/sso_keycloak
source ./.infisical-auth.env
INFISICAL_ENV="\${INFISICAL_ENV:-prod}"
INFISICAL_PROJECT_ID="\${INFISICAL_PROJECT_ID:-117b72e5-c084-44f6-9393-f5252b5ae0a8}"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="\$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="\$INFISICAL_CLIENT_SECRET"
export INFISICAL_TOKEN
INFISICAL_TOKEN=\$(infisical login --method=universal-auth --plain --silent </dev/null)
KC_ADMIN=\$(infisical secrets get KEYCLOAK_ADMIN --projectId="\$INFISICAL_PROJECT_ID" --env="\$INFISICAL_ENV" --plain </dev/null)
KC_PASS=\$(infisical secrets get KEYCLOAK_ADMIN_PASSWORD --projectId="\$INFISICAL_PROJECT_ID" --env="\$INFISICAL_ENV" --plain </dev/null)
KC() { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "\$@" </dev/null; }
KC config credentials --server http://localhost:8080 --realm master --user "\$KC_ADMIN" --password "\$KC_PASS" >/dev/null

U=\$(KC get "users?email=$EMAIL" -r "$REALM" --fields username 2>/dev/null | grep -o '"username" : "[^"]*"' | head -1 | sed 's/.*: "\(.*\)"/\1/')
[ -n "\$U" ] || { echo "ERROR: no user with email $EMAIL in realm $REALM"; exit 1; }
PW=\$(openssl rand -base64 15)
KC set-password -r "$REALM" --username "\$U" --new-password "\$PW" --temporary
echo "==> realm $REALM: temp password set for '\$U' <$EMAIL> (change forced at first login)"
echo
echo "  ONE-TIME PASSWORD for \$U: \$PW"
REMOTE
