#!/usr/bin/env bash
# entrypoint-secrets.sh — the container entrypoint that replaces the
# Infisical-only entrypoint-infisical.sh (ADR-006), dispatching on
# $SECRET_BACKEND via secret-lib.sh. Backwards-compatible: with SECRET_BACKEND
# unset or `infisical`, behaviour is identical to today.
#
# Bind-mount this + secret-lib.sh read-only, same as the ADR-006 wrapper:
#   entrypoint: ["/opt/<app>/entrypoint-secrets.sh"]
#   command:    ["<the image's real entrypoint>", "..."]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/secret-lib.sh"

# For the infisical backend, log in first exactly as ADR-006 did (env-var auth,
# never argv). The other backends authenticate inside secret_run.
if [ "${SECRET_BACKEND:-infisical}" = "infisical" ]; then
  if [ -f /.infisical-auth.env ]; then
    # shellcheck source=/dev/null
    . /.infisical-auth.env
    export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="${INFISICAL_CLIENT_ID:?}"
    export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="${INFISICAL_CLIENT_SECRET:?}"
    infisical login --method=universal-auth --plain --silent </dev/null >/dev/null
  fi
fi

exec_target=("$@")
[ "${#exec_target[@]}" -gt 0 ] || { echo "entrypoint-secrets: no command given" >&2; exit 2; }

secret_run "${exec_target[@]}"
