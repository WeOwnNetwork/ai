#!/usr/bin/env bash
# manual-rotation-check.sh — a site's scripts/rotate-mi-manual.sh, both phases, with
# stand-ins: ssh runs the remote command locally (argv logged); infisical "login"
# succeeds or fails; the box's rotate-bootstrap-secret.sh is a stand-in that writes the
# marker only when V1_DEAD=1 (its real logic is tests/rotation-check.sh's job).
# Synthetic values only; nothing leaves this machine.
#
#   gitea-runner-docker/tests/manual-rotation-check.sh <site-dir>
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
S=$(mktemp -d)
trap 'find "$S" -delete 2>/dev/null' EXIT
mkdir -p "$S/bin" "$S/bin-mvfail"; : > "$S/argv.log"
printf '#!/bin/sh\nexit 1\n' > "$S/bin-mvfail/mv"; chmod +x "$S/bin-mvfail/mv"
AUTHNAME=".infisical-auth.env"
BOX=$(sed -n 's/^APP=\(\/opt\/[a-z0-9_]*\)$/\1/p' "$SITE/scripts/rotate-mi-manual.sh" | head -n 1)
[ -n "$BOX" ] || { echo "NOT RUN: no APP= line in rotate-mi-manual.sh"; exit 2; }
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }
setup() { # name login-rc
  APP="$S/app-$1"; mkdir -p "$APP"
  printf 'INFISICAL_PROJECT_ID=p1\nINFISICAL_CLIENT_ID=c1\nINFISICAL_CLIENT_SECRET=v1-secret-old\nINFISICAL_ENV_SLUG=prod\n' > "$APP/$AUTHNAME"
  chmod 600 "$APP/$AUTHNAME"
  echo cs-9 > "$APP/.rotation-live-id"
  # shellcheck disable=SC2016  # the stand-in's own $V1_DEAD expands when it runs
  printf '#!/usr/bin/env bash\necho "[stand-in] rotation check"\n[ "${V1_DEAD:-0}" = 1 ] && touch %s/.rotation-complete\nexit 0\n' "$APP" > "$APP/rotate-bootstrap-secret.sh"
  sed "s#$BOX#$APP#g" "$SITE/scripts/rotate-mi-manual.sh" > "$S/rot.sh"
  [ "$(grep -c "APP=$APP" "$S/rot.sh")" = 2 ] || { echo "NOT RUN: could not point the script at $APP"; exit 2; }
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/argv.log\nshift\nexec bash -c "$*"\n' "$S" > "$S/bin/ssh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/argv.log\nexit %s\n' "$S" "$2" > "$S/bin/infisical"
  chmod +x "$S/bin/ssh" "$S/bin/infisical"
}
marker() { [ -f "$APP/.rotation-complete" ] && echo yes || echo no; }
live() { grep '^INFISICAL_CLIENT_SECRET=' "$APP/$AUTHNAME" | grep -q NEW && echo v2 || echo v1; }
temps() { find "$APP" -name "$AUTHNAME.*" | wc -l | tr -d ' '; }
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

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

echo "== no argument: usage, exit 2"
PATH="$S/bin:$PATH" bash "$S/rot.sh" > /dev/null 2>&1; res "$?" 2 "no remote: exit 2"
PATH="$S/bin:$PATH" bash "$S/rot.sh" --verify > /dev/null 2>&1; res "$?" 2 "--verify with no remote: exit 2"

res "$(grep -c 'v2-secret-NEW' "$S/argv.log")" 0 "v2 on no argv (ssh or infisical)"
exit "$BAD"
