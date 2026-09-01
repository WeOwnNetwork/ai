#!/bin/sh
# entrypoint-bao.sh — OpenBao AppRole container entrypoint (SECRET_BACKEND=openbao).
# The openbao-repo seam (seam/secret-lib.sh) rendered per-site: approle login →
# kv get → export env → exec the image's real entrypoint. Values move
# process-to-process; never printed, never argv, never in `docker inspect`.
#
# POSIX sh, NOT bash: the dashboard runs node:20-alpine, which has no bash —
# a bash shebang put it in a Restarting(127) loop (measured 2026-09-01). Same
# reason entrypoint-infisical.sh is /bin/sh. No jq either: the host's
# /usr/bin/jq is glibc-linked and cannot exec in these musl containers — both
# images ship node, so node does the JSON→export transform.
#
# First boot: /.bao-wrap.token (single-use response-wrapping token, placed by
# the deploy) is unwrapped into the secret-id file, then blanked. Restarts
# reuse the secret-id file (0600 uid-1000, on the encrypted volume-backed host
# dir — same at-rest posture as .infisical-auth.env.container).
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail || true

BAO_ADDR="https://10.128.0.51:8200"
BAO_ROLE_ID="4c6c2ed0-acf3-5dc7-3394-ba79eb38c1d1"
BAO_SECRET_PATH="platform/beta-weown-chat"
export BAO_ADDR
# Platform store speaks TLS with its own CA; cert bind-mounted by compose.
export BAO_CACERT="/.bao-ca.crt"

SECRET_ID_FILE="/.bao-secret-id"
WRAP_FILE="/.bao-wrap.token"

if [ ! -s "$SECRET_ID_FILE" ]; then
  [ -s "$WRAP_FILE" ] || { echo "entrypoint-bao: no secret-id and no wrap token — provision first" >&2; exit 1; }
  # §2.4: unwrap the single-use wrapping token into the durable secret-id.
  bao unwrap -field=secret_id "$(cat "$WRAP_FILE")" > "$SECRET_ID_FILE"
  chmod 600 "$SECRET_ID_FILE"
  : > "$WRAP_FILE"   # single-use: blank it so a leaked copy is worthless
fi

# Fail LOUD on an unreadable file: the app user is uid 1000, and a root-owned
# 0600 secret-id made $(cat) fail inside command substitution — sh does not
# abort there, so login got an EMPTY secret_id and bao answered an opaque 400
# (measured 2026-09-01, an hour of diagnosis the message below would have saved).
[ -r "$SECRET_ID_FILE" ] || { echo "entrypoint-bao: $SECRET_ID_FILE not readable by uid $(id -u) — deploy must chown it to the container user" >&2; exit 1; }
SID="$(cat "$SECRET_ID_FILE")"
[ -n "$SID" ] || { echo "entrypoint-bao: $SECRET_ID_FILE is empty" >&2; exit 1; }

# AUTH RETRIES ARE RATE-LIMITED, AND THAT IS A CORRECTNESS REQUIREMENT, NOT
# POLITENESS (measured 2026-09-01, acceptance test 3).
#
# OpenBao locks out an AppRole after repeated failed logins in a window and
# then answers "403 permission denied" to EVERY attempt — including the
# correct credential — until the window passes with NO further attempts. This
# container runs under `restart: unless-stopped`, so the old fail-fast-exit
# path retried every few seconds forever and RENEWED THE LOCK on each pass. A
# transient store problem (a rotation, a store restart, a network blip) is
# thereby converted into a sustained outage that the instance inflicts on
# ITSELF, and at the store it is indistinguishable from a bad credential — so
# it sends whoever is on call to the wrong lane entirely. Measured: 19 restarts
# locked the role so hard that a root-minted secret-id, presented from the
# store host itself, was refused.
#
# Two mechanisms, because the container restart policy is outside this script's
# control: bounded in-process retries with exponential backoff (a genuinely
# transient failure self-heals without a restart), then a long COOLDOWN SLEEP
# before exiting, so that even under an unbounded restart policy the effective
# login rate stays far below any lockout threshold.
LOGIN_ATTEMPTS="${BAO_LOGIN_ATTEMPTS:-5}"
LOGIN_COOLDOWN="${BAO_LOGIN_COOLDOWN:-300}"
ERR_FILE="$(mktemp 2>/dev/null || echo /tmp/.bao-login-err)"
TOK=""
attempt=1
delay=2
while [ "$attempt" -le "$LOGIN_ATTEMPTS" ]; do
  if TOK="$(bao write -field=token auth/approle/login \
              role_id="$BAO_ROLE_ID" secret_id="$SID" 2>"$ERR_FILE")"; then
    [ "$attempt" -gt 1 ] && echo "entrypoint-bao: approle login succeeded on attempt $attempt" >&2
    break
  fi
  TOK=""
  # bao's login error carries no secret material — it is the request URL, an
  # HTTP code and a reason — so it is safe to surface verbatim, and it is the
  # single most useful line an operator can have here.
  cat "$ERR_FILE" >&2
  if [ "$attempt" -lt "$LOGIN_ATTEMPTS" ]; then
    echo "entrypoint-bao: approle login failed (attempt $attempt/$LOGIN_ATTEMPTS) — retrying in ${delay}s" >&2
    sleep "$delay"
    delay=$((delay * 2))
  fi
  attempt=$((attempt + 1))
done
rm -f "$ERR_FILE"

if [ -z "$TOK" ]; then
  echo "entrypoint-bao: approle login FAILED after $LOGIN_ATTEMPTS attempts." >&2
  echo "entrypoint-bao:   403 permission denied  -> the role may be LOCKED OUT at the store." >&2
  echo "entrypoint-bao:     Stop this container (docker stop), have the store operator clear" >&2
  echo "entrypoint-bao:     the lock (sys/locked-users), THEN start it. Restarting only renews it." >&2
  echo "entrypoint-bao:   400 invalid role or secret ID -> the credential is wrong or revoked;" >&2
  echo "entrypoint-bao:     re-run the deploy with a fresh BAO_WRAP_TOKEN to replace it." >&2
  echo "entrypoint-bao: sleeping ${LOGIN_COOLDOWN}s before exit so a restart policy cannot renew a lockout." >&2
  sleep "$LOGIN_COOLDOWN"
  exit 1
fi
unset SID

# Export every key at the instance's path, then exec the real entrypoint.
# -format=json + node keeps values off argv; the eval never echoes them.
KVJSON="$(BAO_TOKEN="$TOK" bao kv get -mount=weown -format=json "$BAO_SECRET_PATH" \
          | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")).data.data;const q=s=>"\x27"+String(s).split("\x27").join("\x27\\\x27\x27")+"\x27";for(const[k,v]of Object.entries(d))console.log("export "+k+"="+q(v));')" \
  || { echo "entrypoint-bao: kv get failed" >&2; exit 1; }
eval "$KVJSON"
unset TOK KVJSON

exec "$@"
