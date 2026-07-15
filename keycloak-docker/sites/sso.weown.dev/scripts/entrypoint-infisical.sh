#!/bin/sh
# sso — Infisical authentication wrapper (ADR-006)
#
# This script authenticates to Infisical and then execs the original entrypoint.
# It is bind-mounted read-only into the container and used as the container entrypoint.
#
# Flow:
#   1. Source /.infisical-auth.env to get INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET
#   2. Login to Infisical using universal-auth method
#   3. Exec infisical run to fetch secrets and start the original entrypoint
#
# Security:
#   - Auth file is 0644 (container-readable copy of 0600 host file)
#   - Bind-mounted read-only (container cannot modify)
#   - Credentials only in process memory, not on disk inside container
#
# This follows the established pattern from the backup cron job.
# Written as POSIX sh for compatibility with Alpine, BusyBox, and minimal images.

set -eu

# Step 1: Source the auth file
if [ ! -f /.infisical-auth.env ]; then
  echo "ERROR: /.infisical-auth.env not found" >&2
  echo "       This file should be bind-mounted from the host." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /.infisical-auth.env

if [ -z "${INFISICAL_CLIENT_ID:-}" ] || [ -z "${INFISICAL_CLIENT_SECRET:-}" ]; then
  echo "ERROR: INFISICAL_CLIENT_ID or INFISICAL_CLIENT_SECRET not set in auth file" >&2
  exit 1
fi

# Step 2: Login to Infisical
export INFISICAL_TOKEN
INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --plain --silent)"

if [ -z "$INFISICAL_TOKEN" ]; then
  echo "ERROR: Failed to authenticate with Infisical" >&2
  exit 1
fi

# Step 3: Clear client credentials from environment to reduce exposure
# The app process inherits env vars, so unset client ID/secret after login.
# INFISICAL_TOKEN is still needed by `infisical run` to fetch secrets.
unset INFISICAL_CLIENT_ID
unset INFISICAL_CLIENT_SECRET

# Step 4: Exec infisical run with the original entrypoint
# The "$@" passes through any arguments from the compose command field
exec infisical run \
  --projectId="$INFISICAL_PROJECT_ID" \
  --env="prod" \
  -- "$@"
