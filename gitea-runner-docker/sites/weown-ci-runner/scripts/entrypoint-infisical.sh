#!/bin/sh
# weown-ci-runner — Infisical authentication wrapper (ADR-006), the runner's entrypoint
#
# Already registered (/data/.runner): act_runner authenticates from that file and needs
# no secret, so the runner is exec'd directly and Infisical is never contacted.
#
# Not registered yet: log in with the Machine Identity from the mounted auth file, then
# exec the runner under `infisical run`, which injects GITEA_RUNNER_REGISTRATION_TOKEN for
# run.sh's one-time registration. The project and environment come from the same auth
# file (cloud-init wrote them from terraform), never from render time.
#
# Security:
#   - /.infisical-auth.env is the host's own root 0600 file, bind-mounted read-only.
#   - The Machine Identity credentials reach `infisical login` only, as per-command
#     environment, and every spelling of them is unset before exec: the runner process
#     inherits only the short-lived INFISICAL_TOKEN.
#
# POSIX sh: it runs in the act_runner image.

set -eu

# Never taken from the container's environment: login gets them per command below.
unset INFISICAL_UNIVERSAL_AUTH_CLIENT_ID INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET

if [ -s /data/.runner ]; then
  exec "$@"
fi

if [ ! -f /.infisical-auth.env ]; then
  echo "ERROR: /.infisical-auth.env not found (it is bind-mounted from the host)" >&2
  exit 1
fi

# shellcheck disable=SC1091
. /.infisical-auth.env

if [ -z "${INFISICAL_CLIENT_ID:-}" ] || [ -z "${INFISICAL_CLIENT_SECRET:-}" ] || [ -z "${INFISICAL_PROJECT_ID:-}" ]; then
  echo "ERROR: the auth file lacks INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET or INFISICAL_PROJECT_ID" >&2
  exit 1
fi

INFISICAL_TOKEN="$(INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID" \
  INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET" \
  infisical login --method=universal-auth --plain --silent)"
if [ -z "$INFISICAL_TOKEN" ]; then
  echo "ERROR: Failed to authenticate with Infisical" >&2
  exit 1
fi
export INFISICAL_TOKEN

PROJECT_ID="$INFISICAL_PROJECT_ID"
ENV_SLUG="${INFISICAL_ENV_SLUG:-prod}"
unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET \
  INFISICAL_UNIVERSAL_AUTH_CLIENT_ID INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET

exec infisical run --projectId="$PROJECT_ID" --env="$ENV_SLUG" -- "$@"
