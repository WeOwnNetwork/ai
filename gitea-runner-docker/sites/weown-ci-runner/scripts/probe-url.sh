#!/bin/sh
# weown-ci-runner — classify ONE request made from inside a container
#
# ansible/deploy.yml runs this in a throwaway container on the host's Docker (the same
# DOCKER-USER path dind and every job in it take) to prove the metadata block, and
# tests/live-check.sh runs it against stand-ins. It prints exactly one of:
#   REACHED          the request got an answer (wget exit 0)
#   BLOCKED          connection refused: what the DOCKER-USER REJECT rule produces
#   NO_WGET          the probe cannot run, so it proves nothing
#   OTHER(<rc>) ...  anything else (timeout, DNS, TLS): proves nothing either
# The caller decides which answer passes; only an exact match should.
#
# usage: probe-url.sh <url> <timeout-seconds>
command -v wget > /dev/null 2>&1 || { echo NO_WGET; exit 0; }
out=$(wget -q -T "$2" -O /dev/null "$1" 2>&1)
rc=$?
case "$rc:$out" in
  0:*) echo REACHED ;;
  *"Connection refused"*) echo BLOCKED ;;
  *) echo "OTHER($rc) $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)" ;;
esac
