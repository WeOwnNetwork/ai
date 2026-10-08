#!/usr/bin/env bash
# gitea-git — finish the bootstrap-secret rotation BY HAND
# (README "Manual bootstrap-secret rotation")
#
# The v1 client secret is in terraform state and in this droplet's metadata.
# Cloud-init rotates it on first boot, but minting v2 needs the identity to manage
# its own client secrets, a permission the org may not grant. When
# /var/log/gitea_git-rotation.log says ROTATION FAILED:
#
#   1. In Infisical: this site's Machine Identity -> Universal Auth ->
#      create a client secret (v2). Copy it.
#   2. ./scripts/rotate-mi-manual.sh root@<droplet-ip>   (paste v2 at the hidden prompt)
#      v2 goes over ssh STDIN, never argv. On the box it is written to a temp auth
#      file and must log in to Infisical before it is swapped in. If the login
#      fails, nothing changes. This does NOT mark the rotation complete.
#   3. In Infisical: REVOKE v1, and every other client secret of this identity
#      except v2 (the identity is this droplet's alone).
#   4. ./scripts/rotate-mi-manual.sh --verify root@<droplet-ip>
#      The box re-runs its own rotation check (rotate-bootstrap-secret.sh): a login
#      with the v1 client id and secret, read from its own metadata, must answer
#      401 "Invalid credentials". Only then does .rotation-complete read
#      "v1-401 <time>", and only then does ansible/deploy.yml deploy.
#
# --verify alone also finishes an automatic rotation that was interrupted after
# v2 was swapped in: the box revokes what it can and proves v1 dead the same way.
#
# A box built before weown-fleet#163 has an older rotate-bootstrap-secret.sh (no
# "proof-contract" line). It wrote an empty .rotation-complete even when v1
# survived (the deploy refuses an empty one), and running it again could revoke the
# wrong client secret. --verify never runs it there: it proves v1 dead itself with
# ONE login (Infisical locks the client id after 3 failed logins), using the v1
# client id and secret from user_data, and trusts no marker already on the box:
#   401 "Invalid credentials"  -> .rotation-complete reads "v1-401 <time>", exit 0
#   200 (v1 still logs in)     -> .rotation-complete removed, exit 1
#   anything else              -> nothing changes, exit 1
#
# ssh goes to the droplet's own sshd, port 2222 (admin_ssh_port). scripts/deploy.sh
# passes no port: it reaches that sshd only through your ssh config (Host ... Port).
set -euo pipefail

SSH=(ssh -p 2222)

usage() { echo "usage: $0 [--verify] root@<droplet-ip>" >&2; exit 2; }

if [[ "${1:-}" == --verify ]]; then
  REMOTE="${2:-}"
  [[ -n "$REMOTE" ]] || usage
  # The remote half travels as base64 on argv; it holds no secret (the box reads v1
  # from its own metadata).
  VERIFY=$(base64 <<'VERIFY_EOF' | tr -d '\n'
set -uo pipefail
APP=/opt/gitea_git
MARKER="$APP/.rotation-complete"
if grep -qF 'proof-contract: v1-401' "$APP/rotate-bootstrap-secret.sh" 2>/dev/null; then
  # This box's own check writes the marker only on proof.
  bash "$APP/rotate-bootstrap-secret.sh" && grep -qs '^v1-401 ' "$MARKER"
  exit
fi
echo "This box's rotate-bootstrap-secret.sh predates the proof (weown-fleet#163): proving v1 dead here; no marker trusted."
INFISICAL_HOST="https://app.infisical.com"
ANSWER=$(mktemp)
trap 'rm -f "$ANSWER"' EXIT
# The v1 pair exactly as terraform state holds it. Never the auth file's client id:
# Infisical answers an unknown client id with the same 401 "Invalid credentials".
USER_DATA=$(curl -sf --max-time 10 http://169.254.169.254/metadata/v1/user-data)
V1=$(printf '%s\n' "$USER_DATA" | sed -n 's/^ *INFISICAL_CLIENT_SECRET=//p')
V1_CLIENT_ID=$(printf '%s\n' "$USER_DATA" | sed -n 's/^ *INFISICAL_CLIENT_ID=//p')
unset USER_DATA
if [ -z "$V1" ] || [ "$(printf '%s\n' "$V1" | wc -l)" -ne 1 ] \
   || [ -z "$V1_CLIENT_ID" ] || [ "$(printf '%s\n' "$V1_CLIENT_ID" | wc -l)" -ne 1 ]; then
  echo "could not read exactly one v1 client id and secret from this droplet's user_data; nothing changed" >&2
  exit 1
fi
# v1 goes to curl on stdin, never argv.
CODE=$(CS="$V1" jq -nc --arg id "$V1_CLIENT_ID" '{clientId: $id, clientSecret: env.CS}' \
  | curl -sS --max-time 20 -o "$ANSWER" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' --data @- \
      "$INFISICAL_HOST/api/v1/auth/universal-auth/login") || CODE=000
unset V1
# Infisical's error message only: never the answer body, which holds a token on a 200.
MSG=$(jq -r '.message // empty' "$ANSWER" 2>/dev/null | head -c 300)
if [ "$CODE" = 401 ] && [ "$MSG" = "Invalid credentials" ]; then
  # date -u +FORMAT: the same on every date(1).
  printf 'v1-401 %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
  chmod 0600 "$MARKER"
  echo "v1 refused: 401 Invalid credentials"
  exit 0
fi
if [ "$CODE" = 200 ]; then
  rm -f "$MARKER"
  echo "v1 STILL LOGS IN: .rotation-complete removed; the deploy refuses until v1 is revoked" >&2
  exit 1
fi
echo "the v1 login answered $CODE ($MSG), not 401 Invalid credentials: not proven; nothing changed" >&2
exit 1
VERIFY_EOF
)
  # shellcheck disable=SC2029  # $VERIFY (base64, no secret) is meant to expand here
  if "${SSH[@]}" "$REMOTE" "bash -c \"\$(echo $VERIFY | base64 -d)\""; then
    echo "v1 is proven dead and .rotation-complete records it. Next: scripts/deploy.sh $REMOTE"
    echo "(deploy.sh's ssh must reach port 2222 on that host, e.g. Port 2222 in its ~/.ssh/config Host entry)"
  else
    echo "v1 is NOT proven dead (the lines above say why); .rotation-complete is not written." >&2
    exit 1
  fi
  exit 0
fi

REMOTE="${1:-}"
[[ -n "$REMOTE" ]] || usage

read -rsp "v2 client secret for gitea-git's Machine Identity (hidden): " V2; echo
[[ -n "$V2" ]] || { echo "nothing entered; nothing changed" >&2; exit 1; }

# The remote half travels as base64 on argv (it holds no secret); v2 is on stdin.
BODY=$(base64 <<'BODY_EOF' | tr -d '\n'
set -euo pipefail
APP=/opt/gitea_git
AUTH="$APP/.infisical-auth.env"
read -r V2
# shellcheck disable=SC1090
. "$AUTH"
TMP=$(mktemp "$AUTH.XXXXXX")
# v2 is in this file until the mv: an interrupted run must not leave it behind.
trap 'rm -f "$TMP" "${CTMP:-}"' EXIT
chmod 0600 "$TMP"
{
  echo "# Rotated by hand $(date -Iseconds) (scripts/rotate-mi-manual.sh)"
  echo "INFISICAL_PROJECT_ID=$INFISICAL_PROJECT_ID"
  echo "INFISICAL_CLIENT_ID=$INFISICAL_CLIENT_ID"
  echo "INFISICAL_CLIENT_SECRET=$V2"
  echo "INFISICAL_ENV_SLUG=${INFISICAL_ENV_SLUG:-prod}"
} > "$TMP"
if INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID" INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$V2" \
     infisical login --method=universal-auth --plain --silent </dev/null >/dev/null 2>&1; then
  # The containers read their own copy, written by the deploy. It must follow the
  # swap, or revoking v1 (the next step) leaves every container that restarts before
  # the next deploy unable to log in to Infisical. Prepare EVERY replacement before
  # changing anything: a failure while preparing (set -e) leaves the box as it was.
  if [ -f "$AUTH.container" ]; then
    CTMP=$(mktemp "$AUTH.container.XXXXXX")
    cp -p "$AUTH.container" "$CTMP"   # mode and owner as they are (GNU and BSD alike)
    cat "$TMP" > "$CTMP"
  fi
  # Commit: two renames in the same directory.
  mv "$TMP" "$AUTH"
  if [ -n "${CTMP:-}" ]; then
    mv "$CTMP" "$AUTH.container"
    echo "the containers' copy of the auth file now holds v2 too (running containers change on restart)"
  fi
  # A v2 recorded by an earlier automatic run no longer describes the live secret.
  rm -f "$APP/.rotation-live-id"
  echo "v2 proven by an Infisical login and swapped in (rotation NOT yet marked complete)"
else
  rm -f "$TMP"
  echo "v2 did NOT log in to Infisical; the auth file is unchanged" >&2
  exit 1
fi
BODY_EOF
)

# No file on the box: the decoded body is bash's -c argument, so there is no /tmp
# path another process could pre-create or race. v2 still arrives on stdin.
# shellcheck disable=SC2029  # $BODY (base64, no secret) is meant to expand here
if printf '%s\n' "$V2" | "${SSH[@]}" "$REMOTE" "bash -c \"\$(echo $BODY | base64 -d)\""; then
  unset V2
  echo "Now REVOKE v1 in Infisical (every client secret of this identity except v2), then run:"
  echo "  $0 --verify $REMOTE"
else
  unset V2
  echo "Rotation did not complete. The box is unchanged unless the output above says v2 was swapped in;" >&2
  echo "either way it is safe to run this again with the same v2." >&2
  exit 1
fi
