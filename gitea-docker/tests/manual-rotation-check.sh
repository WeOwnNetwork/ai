#!/usr/bin/env bash
# manual-rotation-check.sh — a site's scripts/rotate-mi-manual.sh, both phases, with
# stand-ins: ssh runs the remote command locally (argv logged); infisical "login"
# succeeds or fails; the box's rotate-bootstrap-secret.sh is a stand-in.
#   - A box built from this template: its stand-in carries the "proof-contract" line
#     and writes the marker only when V1_DEAD=1 (the real logic is rotation-check.sh's
#     job). --verify must run it.
#   - A box built before weown-fleet#163: its stand-in has no such line and, like the
#     old script, would write the marker unconditionally. --verify must NOT run it; it
#     proves v1 dead itself against gitea-runner-docker/tests/stub_infisical.py (the
#     Infisical login and the metadata service), trusting no marker already there.
# Synthetic values only; nothing leaves this machine.
#
#   gitea-docker/tests/manual-rotation-check.sh <site-dir>
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
T=$(cd "$(dirname "$0")" && pwd)
STUB_PY=$(cd "$T/../../gitea-runner-docker/tests" && pwd)/stub_infisical.py
[ -f "$STUB_PY" ] || { echo "NOT RUN: no $STUB_PY"; exit 2; }
command -v jq > /dev/null || { echo "NOT RUN: jq is not installed"; exit 2; }
S=$(mktemp -d)
PORT=18766
STUB=""
trap '[ -n "$STUB" ] && kill "$STUB" 2>/dev/null; find "$S" -delete 2>/dev/null' EXIT
mkdir -p "$S/bin" "$S/bin-mvfail"; : > "$S/argv.log"
printf '#!/bin/sh\nexit 1\n' > "$S/bin-mvfail/mv"; chmod +x "$S/bin-mvfail/mv"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s/argv.log\nexec /usr/bin/curl "$@"\n' "$S" > "$S/bin/curl"
chmod +x "$S/bin/curl"
AUTHNAME=".infisical-auth.env"
BOX=$(sed -n 's/^APP=\(\/opt\/[a-z0-9_]*\)$/\1/p' "$SITE/scripts/rotate-mi-manual.sh" | head -n 1)
[ -n "$BOX" ] || { echo "NOT RUN: no APP= line in rotate-mi-manual.sh"; exit 2; }
# The port the droplet's sshd listens on: cloud-init's 10-ports.conf, else 22.
SSHD_PORT=$(awk '/sshd_config.d\/10-ports.conf/ { f = 1 } f && $1 == "Port" { print $2; exit }' "$SITE/terraform/templates/cloud-init.yaml")
SSHD_PORT=${SSHD_PORT:-22}
V1=v1-secret-old
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }

# stub STATE-MODES: Infisical + metadata, v1 (cs-v1) active unless told otherwise
stub_state() {
  python3 - "$S/state.json" "$V1" "${1:-{\}}" <<'PY'
import json, sys
path, v1, modes = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
st = {"identity": "ident-1", "client_id": "c1", "tokens": [],
      "secrets": [{"id": "cs-v1", "value": v1, "revoked": False, "createdAt": "2026-10-07T00:00:00Z"},
                  {"id": "cs-2", "value": "v2-live-0007", "revoked": False, "createdAt": "2026-10-07T00:00:01Z"}],
      "userdata": "#cloud-config\nwrite_files:\n  - path: /opt/x/.infisical-auth.env\n    content: |\n"
                  "      INFISICAL_CLIENT_ID=c1\n      INFISICAL_CLIENT_SECRET=" + v1 + "\n"}
v1_revoked = modes.pop("v1_revoked", False)
st["secrets"][0]["revoked"] = v1_revoked
st.update(modes)
json.dump(st, open(path, "w"))
PY
}
stub_state
python3 "$STUB_PY" "$PORT" "$S/state.json" 2> "$S/stub.log" &
STUB=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/metadata/v1/user-data" && break; sleep 0.1; done

setup() { # name login-rc [legacy]
  APP="$S/app-$1"; mkdir -p "$APP"
  printf 'INFISICAL_PROJECT_ID=p1\nINFISICAL_CLIENT_ID=c1\nINFISICAL_CLIENT_SECRET=%s\nINFISICAL_ENV_SLUG=prod\n' "$V1" > "$APP/$AUTHNAME"
  chmod 600 "$APP/$AUTHNAME"
  echo cs-9 > "$APP/.rotation-live-id"
  if [ "${3:-}" = legacy ]; then
    # The pre-#163 script marked complete whatever happened: --verify must not run it.
    printf '#!/usr/bin/env bash\ntouch %s/legacy-ran %s/.rotation-complete\nexit 0\n' "$APP" "$APP" > "$APP/rotate-bootstrap-secret.sh"
  else
    # shellcheck disable=SC2016  # the stand-in's own $V1_DEAD expands when it runs
    printf '#!/usr/bin/env bash\n# proof-contract: v1-401 (stand-in)\necho "[stand-in] rotation check"\n[ "${V1_DEAD:-0}" = 1 ] && touch %s/.rotation-complete\nexit 0\n' "$APP" > "$APP/rotate-bootstrap-secret.sh"
  fi
  sed -e "s#$BOX#$APP#g" \
      -e "s#http://169.254.169.254/metadata/v1/user-data#http://127.0.0.1:$PORT/metadata/v1/user-data#" \
      -e "s#^INFISICAL_HOST=\"https://app.infisical.com\"#INFISICAL_HOST=\"http://127.0.0.1:$PORT\"#" \
      "$SITE/scripts/rotate-mi-manual.sh" > "$S/rot.sh"
  [ "$(grep -c "APP=$APP" "$S/rot.sh")" = 2 ] || { echo "NOT RUN: could not point the script at $APP"; exit 2; }
  [ "$(grep -c -e '169.254.169.254' -e 'app.infisical.com' "$S/rot.sh")" = 0 ] || { echo "NOT RUN: could not point the script at the stub"; exit 2; }
  # ssh -p PORT REMOTE CMD: log the argv, run CMD here
  # shellcheck disable=SC2016  # the stand-in's own $1 and $* expand when it runs
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/argv.log\n[ "$1" = -p ] && shift 2\nshift\nexec bash -c "$*"\n' "$S" > "$S/bin/ssh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/argv.log\nexit %s\n' "$S" "$2" > "$S/bin/infisical"
  chmod +x "$S/bin/ssh" "$S/bin/infisical"
}
marker() { [ -f "$APP/.rotation-complete" ] && echo yes || echo no; }
live() { grep '^INFISICAL_CLIENT_SECRET=' "$APP/$AUTHNAME" | grep -q NEW && echo v2 || echo v1; }
temps() { find "$APP" -name "$AUTHNAME.*" | wc -l | tr -d ' '; }
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
legacy_ran() { [ -f "$APP/legacy-ran" ] && echo yes || echo no; }

echo "== the script reaches the droplet's own sshd (port $SSHD_PORT, from cloud-init)"
setup port 0
PATH="$S/bin:$PATH" V1_DEAD=1 bash "$S/rot.sh" --verify root@203.0.113.9 > /dev/null 2>&1
res "$(tail -n 1 "$S/argv.log" | cut -d' ' -f1-3)" "-p $SSHD_PORT root@203.0.113.9" "ssh -p $SSHD_PORT, the port sshd is moved to"

echo "== phase 1, v2 logs in: swapped in, NOT marked complete, recorded id dropped"
setup ok 0
OUT=$(printf 'v2-secret-NEW-7f3a\n' | PATH="$S/bin:$PATH" bash "$S/rot.sh" root@203.0.113.9 2>&1); RC=$?
res "$RC" 0 "phase 1 exits 0"
res "$(marker)" no "phase 1 writes no .rotation-complete"
res "$(live)" v2 "phase 1 swaps v2 in"
res "$(mode "$APP/$AUTHNAME")" 600 "the auth file stays 0600"
res "$([ -f "$APP/.rotation-live-id" ] && echo present || echo gone)" gone "a recorded automatic id is dropped"
res "$(grep -c -- '--verify root@203.0.113.9' <<<"$OUT")" 1 "it tells the operator to revoke v1, then --verify"
res "$(grep -c 'v2-secret-NEW' <<<"$OUT")" 0 "v2 never printed"
res "$(temps)" 0 "no temp auth file left"

echo "== phase 1, v2 does not log in: nothing changes"
setup fail 1
printf 'v2-secret-NEW-7f3a\n' | PATH="$S/bin:$PATH" bash "$S/rot.sh" root@203.0.113.9 > /dev/null 2>&1; RC=$?
res "$RC" 1 "a failed login exits 1"
res "$(live)" v1 "the auth file is unchanged"
res "$(marker)" no "no .rotation-complete"
res "$(temps)" 0 "no temp auth file (holding v2) left"

echo "== phase 1, the swap itself fails: the v2 temp file is not left behind"
setup mvfail 0
printf 'v2-secret-NEW-7f3a\n' | PATH="$S/bin-mvfail:$S/bin:$PATH" bash "$S/rot.sh" root@203.0.113.9 > /dev/null 2>&1; RC=$?
res "$RC" 1 "a failed swap exits 1"
res "$(live)" v1 "the auth file is unchanged"
res "$(temps)" 0 "no temp auth file (holding v2) left"

echo "== --verify, v1 still alive: no marker, exit 1"
setup verify 0
OUT=$(PATH="$S/bin:$PATH" V1_DEAD=0 bash "$S/rot.sh" --verify root@203.0.113.9 2>&1); RC=$?
res "$RC" 1 "--verify exits 1 while v1 is not proven dead"
res "$(marker)" no "no .rotation-complete"
res "$(grep -c 'NOT proven dead' <<<"$OUT")" 1 "it says v1 is not proven dead"

echo "== --verify, v1 proven dead: marker, exit 0"
OUT=$(PATH="$S/bin:$PATH" V1_DEAD=1 bash "$S/rot.sh" --verify root@203.0.113.9 2>&1); RC=$?
res "$RC" 0 "--verify exits 0 once v1 is proven dead"
res "$(marker)" yes ".rotation-complete written (by the box's check)"
res "$(grep -c 'deploy.sh root@203.0.113.9' <<<"$OUT")" 1 "it points to the deploy"

echo "== --verify on a pre-#163 box whose old marker hides a LIVE v1: marker removed, exit 1"
setup legacy-live 0 legacy; touch "$APP/.rotation-complete"; stub_state
OUT=$(PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify root@203.0.113.9 2>&1); RC=$?
res "$RC" 1 "legacy --verify exits 1 while v1 logs in"
res "$(marker)" no "the unproven marker is removed (the deploy now refuses)"
res "$(legacy_ran)" no "the old rotation script is never run"
res "$(grep -c 'v1 STILL LOGS IN' <<<"$OUT")" 1 "it says v1 still logs in"

echo "== --verify on a pre-#163 box, v1 revoked: proven, marker kept, exit 0"
setup legacy-dead 0 legacy; touch "$APP/.rotation-complete"; stub_state '{"v1_revoked": true}'
OUT=$(PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify root@203.0.113.9 2>&1); RC=$?
res "$RC" 0 "legacy --verify exits 0 once v1 answers 401 Invalid credentials"
res "$(marker)" yes ".rotation-complete present"
res "$(legacy_ran)" no "the old rotation script is never run"
res "$(grep -c 'v1 refused: 401 Invalid credentials' <<<"$OUT")" 1 "it shows the 401 proof"

echo "== --verify on a pre-#163 box without a marker, v1 revoked: marker written"
setup legacy-new 0 legacy; stub_state '{"v1_revoked": true}'
PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify root@203.0.113.9 > /dev/null 2>&1; RC=$?
res "$RC|$(marker)|$(mode "$APP/.rotation-complete")" "0|yes|600" "legacy --verify writes a 0600 marker on proof"

echo "== --verify on a pre-#163 box, the client id is locked: a lockout 401 proves nothing"
setup legacy-locked 0 legacy; touch "$APP/.rotation-complete"; stub_state '{"v1_revoked": true, "locked": true}'
OUT=$(PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify root@203.0.113.9 2>&1); RC=$?
res "$RC" 1 "legacy --verify exits 1 on a lockout"
res "$(marker)" yes "nothing changed (the marker is neither proven nor disproven)"
res "$(grep -c 'not proven; nothing changed' <<<"$OUT")" 1 "it says the proof failed"

echo "== --verify on a pre-#163 box, metadata down: nothing changes, exit 1"
setup legacy-nometa 0 legacy; stub_state '{"v1_revoked": true, "metadata_up": false}'
PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify root@203.0.113.9 > /dev/null 2>&1; RC=$?
res "$RC|$(marker)|$(legacy_ran)" "1|no|no" "legacy --verify without user_data: exit 1, no marker, old script not run"

echo "== no argument: usage, exit 2"
PATH="$S/bin:$PATH" bash "$S/rot.sh" > /dev/null 2>&1; res "$?" 2 "no remote: exit 2"
PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify > /dev/null 2>&1; res "$?" 2 "--verify with no remote: exit 2"

res "$(grep -c -e 'v2-secret-NEW' -e "$V1" "$S/argv.log")" 0 "v1 and v2 on no argv (ssh, infisical or curl)"
exit "$BAD"
