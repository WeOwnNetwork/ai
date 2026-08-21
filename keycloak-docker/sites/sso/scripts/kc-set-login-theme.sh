#!/usr/bin/env bash
# Select the WeOwn login theme on Keycloak realms — sso.weown.id
#
# Usage (from the Mac):   ./scripts/kc-set-login-theme.sh root@129.212.240.145 [realm ...]
#   Default realm: weown        (pass realms explicitly to include e.g. weown-chat)
#
# Why this script exists: ansible/deploy.yml uploads ../theme/weown and
# docker/compose.prod.yaml bind-mounts it read-only at
# /opt/keycloak/themes/weown, but the theme stays INERT until a realm's
# loginTheme points at it. That last step was an undocumented click-path in
# the Admin Console (Realm settings → Themes → Login theme); this makes it
# re-runnable and verifiable.
#
# State measured externally 2026-08-21 (see the probe at the bottom of this
# script — it needs PKCE or Keycloak 302s away before rendering a login page):
#   realm weown-chat -> already serving `weown`   (theme files ARE on the box)
#   realm weown      -> still serving `keycloak.v2` (the stock parent)
# So the theme is deployed; only the `weown` realm's selection is outstanding,
# which is why that realm is this script's default.
#
# Safety:
#   * PREFLIGHT — aborts unless the theme is actually present inside the
#     container. Pointing loginTheme at a missing theme breaks the login page
#     for every user of that realm, and Keycloak does not validate the name.
#   * UNDO — prints the exact revert command with the PREVIOUS value before
#     changing anything.
#   * VERIFY — reads the value back from kcadm, then independently reads the
#     theme name out of the served login page's /resources/<hash>/login/<name>/
#     paths, rather than trusting an exit code.
#
# No secrets pass through this script: admin credentials stay inside
# `infisical run` on the droplet and reach kcadm in-process only.
set -euo pipefail

HOST="${1:?usage: $0 root@<sso-ip> [realm ...]}"; shift || true
REALMS=("$@")
[ ${#REALMS[@]} -gt 0 ] || REALMS=(weown)

THEME="weown"
PUBLIC_URL="https://sso.weown.id"

ssh "$HOST" "REALMS='${REALMS[*]}' THEME='$THEME' bash -s" <<'EOF'
set -euo pipefail
cd /opt/sso_keycloak
source ./.infisical-auth.env
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
export INFISICAL_TOKEN
INFISICAL_TOKEN=$(timeout 30 infisical login --method=universal-auth --plain --silent </dev/null)

infisical run --projectId="$INFISICAL_PROJECT_ID" --env=prod -- bash -c '
set -euo pipefail
docker compose exec -T \
  -e KC_USER="$KEYCLOAK_ADMIN" -e KC_PASS="$KEYCLOAK_ADMIN_PASSWORD" \
  -e REALMS="$REALMS" -e THEME="$THEME" \
  keycloak sh -c "
set -eu

# --- PREFLIGHT: the theme must exist in the container, or login breaks ---
if [ ! -f \"/opt/keycloak/themes/\$THEME/login/theme.properties\" ]; then
  echo \"ABORT: /opt/keycloak/themes/\$THEME/login/theme.properties not found in the container.\" >&2
  echo \"       The bind mount or the ansible upload has not landed — run scripts/deploy.sh first.\" >&2
  exit 1
fi
echo \"preflight OK: theme '\$THEME' is present in the container\"

/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
  --user \"\$KC_USER\" --password \"\$KC_PASS\" >/dev/null

for R in \$REALMS; do
  PREV=\$(/opt/keycloak/bin/kcadm.sh get realms/\$R --fields loginTheme 2>/dev/null | tr -d ' \"{}\n' | sed 's/^loginTheme://')
  if [ -n \"\$PREV\" ]; then
    echo \"realm \$R: loginTheme was '\$PREV'\"
  else
    echo \"realm \$R: loginTheme was unset (Keycloak default)\"
    PREV=''
  fi
  # Runnable as-is inside the container; an empty value clears the override.
  echo \"  UNDO: /opt/keycloak/bin/kcadm.sh update realms/\$R -s 'loginTheme=\$PREV'\"

  /opt/keycloak/bin/kcadm.sh update realms/\$R -s \"loginTheme=\$THEME\"

  NOW=\$(/opt/keycloak/bin/kcadm.sh get realms/\$R --fields loginTheme | tr -d ' \"{}\n' | sed 's/^loginTheme://')
  if [ \"\$NOW\" = \"\$THEME\" ]; then
    echo \"  OK: realm \$R loginTheme -> \$NOW\"
  else
    echo \"  FAILED: realm \$R loginTheme reads back as '\$NOW', expected '\$THEME'\" >&2
    exit 1
  fi
done
" </dev/null
'
EOF

echo
echo "=== external verification (the artifact, not the exit code) ==="
# Keycloak's account-console client enforces PKCE: without code_challenge* the
# auth endpoint 302s to an error page and never renders a login form, which
# reads as a false negative. The active login theme is visible in the served
# resource paths as /resources/<hash>/login/<themeName>/.
CV=$(openssl rand -hex 32)
CC=$(printf '%s' "$CV" | openssl dgst -binary -sha256 | openssl base64 | tr '+/' '-_' | tr -d '=')
RC=0
for R in "${REALMS[@]}"; do
  U="$PUBLIC_URL/realms/$R/protocol/openid-connect/auth?client_id=account-console&response_type=code&scope=openid&code_challenge_method=S256&code_challenge=$CC&redirect_uri=$PUBLIC_URL/realms/$R/account/"
  TMP=$(mktemp)
  CODE=$(curl -s -o "$TMP" -w '%{http_code}' --max-time 20 "$U" || echo 000)
  ACTIVE=$(grep -oE '/resources/[^/]+/login/[a-zA-Z0-9._-]+' "$TMP" | sed 's|.*/login/||' | sort -u | tr '\n' ' ' | sed 's/ $//')
  rm -f "$TMP"
  printf 'realm %-12s login page HTTP %s  active login theme: %s' "$R" "$CODE" "${ACTIVE:-<none detected>}"
  if [ "$CODE" = "200" ] && [ "$ACTIVE" = "$THEME" ]; then
    echo "  ✔"
  else
    echo "  ⚠ expected '$THEME' on a 200 — investigate before leaving this"
    RC=1
  fi
done
exit $RC
