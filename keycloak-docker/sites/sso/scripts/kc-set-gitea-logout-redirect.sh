#!/usr/bin/env bash
# Allow Gitea's post-logout redirect on the `gitea` client — sso.weown.id
#
# Usage (from the Mac):   ./scripts/kc-set-gitea-logout-redirect.sh sso-keycloak
#
# Symptom without this: signing out of git.weown.tools lands on Keycloak's
# "Invalid redirect uri" error page (HTTP 400). Keycloak validates
# post_logout_redirect_uri against the client's `post.logout.redirect.uris`
# attribute, which is separate from `redirectUris` and empty by default.
#
# Idempotent: re-running sets the same value and re-verifies.
#
# ⚠️ kcadm read-back gotcha (cost a wrong "it didn't apply" conclusion once):
#    `kcadm.sh get clients/<id> --fields attributes` renders nested attribute
#    maps as `{}` even when they are populated. A verify built on --fields
#    reports failure on a successful write. Read the FULL representation and
#    grep, as below — and confirm with the live logout endpoint.
#
# ⚠️ Never set this with `-s 'attributes={...}'`: that REPLACES the whole
#    attribute map, silently destroying `realm_client` and
#    `client.secret.creation.time`. Set the single dotted key only.
set -euo pipefail

HOST="${1:?usage: $0 <ssh-host-alias>}"
REALM="weown"
CLIENT="gitea"
ALLOWED="https://git.weown.tools/*"
PUBLIC_URL="https://sso.weown.id"

ssh "$HOST" "REALM='$REALM' CLIENT='$CLIENT' ALLOWED='$ALLOWED' bash -s" <<'REMOTE'
set -euo pipefail
cd /opt/sso_keycloak
source ./.infisical-auth.env
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
export INFISICAL_TOKEN
INFISICAL_TOKEN=$(timeout 30 infisical login --method=universal-auth --plain --silent </dev/null)

# Body goes to a file and is fed to `sh` on stdin: inlining it as `sh -c "..."`
# inside `bash -c '...'` puts it a quoting layer too deep and any single quote
# truncates it (see kc-set-login-theme.sh's history).
KCSCRIPT=$(mktemp /tmp/kc-gitea-logout.XXXXXX)
trap 'rm -f "$KCSCRIPT"' EXIT
export KCSCRIPT REALM CLIENT ALLOWED

cat > "$KCSCRIPT" <<'KCEOF'
set -eu
KCADM=/opt/keycloak/bin/kcadm.sh
"$KCADM" config credentials --server http://localhost:8080 --realm master \
  --user "$KC_USER" --password "$KC_PASS" >/dev/null

ID=$("$KCADM" get clients -r "$REALM" -q "clientId=$CLIENT" --fields id --format csv --noquotes)
[ -n "$ID" ] || { echo "ABORT: client '$CLIENT' not found in realm '$REALM'" >&2; exit 1; }

echo "UNDO: $KCADM update clients/$ID -r $REALM -s 'attributes.\"post.logout.redirect.uris\"='"
"$KCADM" update "clients/$ID" -r "$REALM" \
  -s "attributes.\"post.logout.redirect.uris\"=$ALLOWED"

# Full representation, not --fields: --fields renders attributes as {}.
if "$KCADM" get "clients/$ID" -r "$REALM" | grep -q "post.logout.redirect.uris"; then
  "$KCADM" get "clients/$ID" -r "$REALM" | grep "post.logout.redirect.uris" | sed 's/^/  stored: /'
else
  echo "FAILED: attribute not present after update" >&2
  exit 1
fi
"$KCADM" get "clients/$ID" -r "$REALM" --fields redirectUris | sed 's/^/  /'
KCEOF

infisical run --projectId="$INFISICAL_PROJECT_ID" --env=prod -- bash -c '
set -euo pipefail
docker compose exec -T \
  -e KC_USER="$KEYCLOAK_ADMIN" -e KC_PASS="$KEYCLOAK_ADMIN_PASSWORD" \
  -e REALM="$REALM" -e CLIENT="$CLIENT" -e ALLOWED="$ALLOWED" \
  keycloak sh -s < "$KCSCRIPT"
'
REMOTE

echo
echo "=== external verification: allowed target accepted, others still rejected ==="
probe() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    "$PUBLIC_URL/realms/$REALM/protocol/openid-connect/logout?client_id=$CLIENT&post_logout_redirect_uri=$1"
}
RC=0
OK=$(probe 'https%3A%2F%2Fgit.weown.tools%2F')
BAD=$(probe 'https%3A%2F%2Fexample.invalid%2F')
EVIL=$(probe 'https%3A%2F%2Fgit.weown.tools.evil.com%2F')
printf 'git.weown.tools           -> %s (want 302)\n' "$OK"
printf 'example.invalid           -> %s (want 400)\n' "$BAD"
printf 'git.weown.tools.evil.com  -> %s (want 400)\n' "$EVIL"
[ "$OK" = "302" ] || { echo "FAIL: allowed target not accepted" >&2; RC=1; }
[ "$BAD" = "400" ] && [ "$EVIL" = "400" ] || { echo "FAIL: allowlist is too permissive" >&2; RC=1; }
[ "$RC" = 0 ] && echo "✔ logout redirect scoped correctly"
exit $RC
