#!/usr/bin/env bash
# create-weown-user.sh — onboard an internal WeOwn team member into the
# Keycloak `weown` realm (the realm Gitea git.weown.tools trusts).
#
#   ./create-weown-user.sh <username> <email> [first] [last]
#   e.g. ./create-weown-user.sh yonks jason@weown.net Jason Younker
#
# EMAIL-NATIVE (2026-07-31, SMTP proven): creates the user and sends them a
# set-your-password email (UPDATE_PASSWORD required action) from
# no-reply@weown.net — no credential ever passes through a human channel.
# Pass --temp-password as the LAST arg to fall back to the old
# print-a-one-time-password flow (e.g. if mail is down).
# Their Gitea account auto-creates, non-admin, on first "Sign in with Keycloak".
# Idempotent: existing users are left untouched.
set -euo pipefail

USERNAME="${1:?usage: $0 <username> <email> [first] [last]}"
EMAIL="${2:?usage: $0 <username> <email> [first] [last]}"
FIRST="${3:-$USERNAME}"
LAST="${4:-}"
MODE="email"
for a in "$@"; do [ "$a" = "--temp-password" ] && MODE="temp"; done

ssh sso-keycloak 'bash -s' -- <<REMOTE
MODE="$MODE"
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

if KC get "users?username=$USERNAME&exact=true" -r weown --fields username 2>/dev/null | grep -q '"$USERNAME"'; then
  echo "==> user '$USERNAME' already exists in realm weown — nothing changed"
  exit 0
fi
KC create users -r weown -s username="$USERNAME" -s email="$EMAIL" \
  -s firstName="$FIRST" -s lastName="$LAST" -s enabled=true -s emailVerified=true >/dev/null
ID=\$(KC get users -r weown -q username="$USERNAME" --fields id | grep -o '"id" : "[^"]*' | head -1 | cut -d'"' -f4)
[ -n "\$ID" ] || { echo "ERROR: user created but id lookup failed"; exit 1; }
if [ "\$MODE" = "email" ]; then
  # -b bare-array body — the -s form 404s on KC 26 (proven 2026-07-31)
  KC update "users/\$ID/execute-actions-email" -r weown -b '["UPDATE_PASSWORD"]'
  echo "==> created realm-weown user '$USERNAME' <$EMAIL>"
  echo "==> set-your-password email SENT to $EMAIL (from no-reply@weown.net; link valid 12h)"
  echo "    After setting it: https://git.weown.tools/user/login -> Sign in with Keycloak"
else
  PW=\$(openssl rand -base64 15)
  KC set-password -r weown --username "$USERNAME" --new-password "\$PW" --temporary
  echo "==> created realm-weown user '$USERNAME' <$EMAIL> (password change forced at first login)"
  echo
  echo "  ONE-TIME PASSWORD for $USERNAME: \$PW"
  echo "  Hand over securely. First login: https://git.weown.tools/user/login -> Sign in with Keycloak"
fi
REMOTE
