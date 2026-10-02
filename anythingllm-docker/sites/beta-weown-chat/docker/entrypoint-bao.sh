#!/bin/sh
# entrypoint-bao.sh — OpenBao AppRole container entrypoint (SECRET_BACKEND=openbao).
# The openbao-repo seam (seam/secret-lib.sh) rendered per-site: approle login →
# kv get → export env → exec the image's real entrypoint. Values move
# process-to-process; never printed, never argv, never in `docker inspect`.
#
# POSIX sh, NOT bash: the dashboard runs node:24-alpine, which has no bash —
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

# The store URL is a private (VPC) address, so it is not in this file as
# committed: ansible/deploy.yml writes it into the copy it uploads to the box.
# A copy that did not come through the deploy refuses to start.
BAO_ADDR="__BAO_ADDR_FILLED_AT_DEPLOY__"
case "$BAO_ADDR" in
  https://*) ;;
  *) echo "entrypoint-bao: the store URL was not filled in; upload this script with ansible/deploy.yml" >&2; exit 1 ;;
esac
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
  # The wrap token rides in BAO_TOKEN (the environment), never on argv: with no
  # TOKEN argument, `bao unwrap` unwraps the calling token. argv is readable by
  # any process through ps and /proc/*/cmdline.
  BAO_TOKEN="$(cat "$WRAP_FILE")" bao unwrap -field=secret_id > "$SECRET_ID_FILE"
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
# 3, not 5: OpenBao's DEFAULT user-lockout threshold is 5 failed logins, and
# measured on 2026-09-01 a compliant 5-attempt cycle locked the role on its
# fifth try every time. The consumer must stay under the threshold ON ITS OWN,
# because the next store someone points this at will be on the defaults; the
# platform store's approle mount is tuned to 10 as belt-and-braces (justified:
# the secret is a 128-bit UUID, so lockout adds ~no brute-force protection on
# THIS mount, while its measured cost is self-DoS by legitimate consumers —
# human-auth mounts keep the defaults). The seam contract states a
# relationship, not a number: sum of concurrent consumers' attempts per
# cooldown < mount threshold, with headroom. The app and the dashboard SHARE
# this credential, so under a simultaneous restart their attempts SUM:
# 2 x 3 = 6 fits the tuned store (10) but NOT a default one (5). 2 per consumer
# (2 x 2 = 4) would fit a default store; 3 is kept for headroom against a
# transient failure, and is safe only because the platform mount is tuned.
# Pointing this at a default-threshold store? Put BAO_LOGIN_ATTEMPTS=2 in the
# container's environment (compose), since it is read before the store is.
LOGIN_ATTEMPTS="${BAO_LOGIN_ATTEMPTS:-3}"
LOGIN_COOLDOWN="${BAO_LOGIN_COOLDOWN:-300}"
ERR_FILE="$(mktemp 2>/dev/null || echo /tmp/.bao-login-err)"
TOK=""
attempt=1
delay=2
# role_id and secret_id travel as a JSON body on STDIN, composed by node from
# the environment. As `secret_id=...` arguments they sat on argv for the whole
# call, visible to any process in the container through ps and /proc.
LOGIN_JS='process.stdout.write(JSON.stringify({role_id:process.env.BAO_ROLE_ID,secret_id:process.env.SID}))'
while [ "$attempt" -le "$LOGIN_ATTEMPTS" ]; do
  if TOK="$(BAO_ROLE_ID="$BAO_ROLE_ID" SID="$SID" node -e "$LOGIN_JS" \
              | bao write -field=token auth/approle/login - 2>"$ERR_FILE")"; then
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
  # role_id is deliberately in the message: it is not a secret (it is baked
  # into a committed render), and a lockout, a CIDR denial and a wrong
  # secret-id are all byte-identical "403 permission denied" at the store —
  # the operator needs the identifier to go straight to sys/locked-users.
  echo "entrypoint-bao: approle login FAILED after $LOGIN_ATTEMPTS attempts (role_id $BAO_ROLE_ID)." >&2
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
#
# A key NAME is data from the store, and it becomes shell text below, so it is
# checked before it goes anywhere near eval. Before this check only the VALUE was
# quoted: a key named like `X=1;<command>;Y` ran <command> in this container,
# before exec, with every secret already in the environment. Anyone who can
# write a key at the instance path could do it (the same bug as openbao#90).
#
# POSIX sh has no `read -d ''` and no process substitution, so the exports cannot
# be read back as data the way the bash seam does it. What makes this eval safe
# is what node guarantees about the text it emits:
#   - every name is a plain identifier, ^[A-Za-z_][A-Za-z0-9_]*$, and is not a
#     variable that makes the loader, a shell or node run code (LD_*, DYLD_*,
#     BASH_ENV, ENV, BASH_FUNC_*, SHELLOPTS, BASHOPTS, PS4, PROMPT_COMMAND, IFS,
#     PATH, and NODE_OPTIONS: the app is node, and --require runs code);
#   - every value is single-quoted with embedded quotes escaped, and may not
#     contain a NUL (sh cannot hold one; it would be silently truncated);
#   - ONE bad name refuses the whole start. It is never skipped, so a hostile
#     key fails loudly, and the app never boots half-configured.
# A refused name is described by position and length, never printed: a
# malformed "name" is sometimes a secret pasted into the wrong field.
KV_EXPORTS_JS="$(cat <<'JS'
const d = JSON.parse(require("fs").readFileSync(0, "utf8")).data.data;
if (!d || typeof d !== "object" || Array.isArray(d)) {
  console.error("entrypoint-bao: the kv document is not a flat object of values");
  process.exit(3);
}
const ok = /^[A-Za-z_][A-Za-z0-9_]*$/;
const deny = /^(LD_.*|DYLD_.*|BASH_ENV|ENV|BASH_FUNC_.*|SHELLOPTS|BASHOPTS|PS4|PROMPT_COMMAND|IFS|PATH|NODE_OPTIONS)$/;
const q = (s) => "'" + s.split("'").join("'\\''") + "'";
const out = [];
let i = 0;
for (const [k, v] of Object.entries(d)) {
  i++;
  if (!ok.test(k)) {
    console.error("entrypoint-bao: refusing key #" + i + " (length " + k.length + "): not a plain identifier");
    process.exit(3);
  }
  if (deny.test(k)) {
    console.error("entrypoint-bao: refusing key " + k + ": it would make the loader, a shell or node run code");
    process.exit(3);
  }
  const s = String(v);
  if (s.includes("\u0000")) {
    console.error("entrypoint-bao: refusing the value of " + k + ": it contains a NUL byte");
    process.exit(3);
  }
  out.push("export " + k + "=" + q(s));
}
process.stdout.write(out.join("\n") + "\n");
JS
)"
KVJSON="$(BAO_TOKEN="$TOK" bao kv get -mount=weown -format=json "$BAO_SECRET_PATH" \
          | node -e "$KV_EXPORTS_JS")" \
  || { echo "entrypoint-bao: kv get failed, or the store document was refused (see above)" >&2
       BAO_TOKEN="$TOK" bao token revoke -self >/dev/null 2>&1 || true
       exit 1; }
# The token was for this one read and the app never sees it: revoke it rather
# than leave it live until its TTL. Best effort; a failed revoke only warns.
BAO_TOKEN="$TOK" bao token revoke -self >/dev/null 2>&1 \
  || echo "entrypoint-bao: warning: could not revoke the login token (it expires on its TTL)" >&2
unset TOK KV_EXPORTS_JS LOGIN_JS
# Nothing is unset AFTER the exports: an accepted key that happens to share a
# helper's name (KVJSON, LOGIN_JS, ...) must reach the app, not be removed on
# the way. So the text rides in $1 for the eval, and the helper is gone first.
set -- "$KVJSON" "$@"
unset KVJSON
eval "$1"
shift

exec "$@"
