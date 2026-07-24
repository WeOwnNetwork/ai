#!/bin/sh
# dev-weown-anythingllm-anythingllm — Infisical authentication wrapper (ADR-006)
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
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
INFISICAL_TOKEN="$(infisical login --method=universal-auth --plain --silent)"

if [ -z "$INFISICAL_TOKEN" ]; then
  echo "ERROR: Failed to authenticate with Infisical" >&2
  exit 1
fi

# Step 3: Clear client credentials from environment to reduce exposure
# The app process inherits env vars, so unset client ID/secret after login.
# INFISICAL_TOKEN is still needed by `infisical run` to fetch secrets.
unset INFISICAL_CLIENT_ID
unset INFISICAL_CLIENT_SECRET

# Step 4: Preserve compose-pinned non-secret config before Infisical injection.
# Infisical may carry stale EMBEDDING_ENGINE=native (or other drift) that overrides
# the compose environment block and breaks the Embedder UI + RAG vector dims.
EMBEDDING_ENGINE_PIN="${EMBEDDING_ENGINE:-}"
EMBEDDING_MODEL_PREF_PIN="${EMBEDDING_MODEL_PREF:-}"
EMBEDDING_BASE_PATH_PIN="${EMBEDDING_BASE_PATH:-}"
LLM_PROVIDER_PIN="${LLM_PROVIDER:-}"
OPENROUTER_MODEL_PREF_PIN="${OPENROUTER_MODEL_PREF:-}"
OPENROUTER_TIMEOUT_MS_PIN="${OPENROUTER_TIMEOUT_MS:-}"
LLM_STREAM_TIMEOUT_PIN="${LLM_STREAM_TIMEOUT:-}"

REPIN_ENV=""
if [ -n "$EMBEDDING_ENGINE_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} EMBEDDING_ENGINE=${EMBEDDING_ENGINE_PIN}"
fi
if [ -n "$EMBEDDING_MODEL_PREF_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} EMBEDDING_MODEL_PREF=${EMBEDDING_MODEL_PREF_PIN}"
fi
if [ -n "$EMBEDDING_BASE_PATH_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} EMBEDDING_BASE_PATH=${EMBEDDING_BASE_PATH_PIN}"
fi
if [ -n "$LLM_PROVIDER_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} LLM_PROVIDER=${LLM_PROVIDER_PIN}"
fi
if [ -n "$OPENROUTER_MODEL_PREF_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} OPENROUTER_MODEL_PREF=${OPENROUTER_MODEL_PREF_PIN}"
fi
if [ -n "$OPENROUTER_TIMEOUT_MS_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} OPENROUTER_TIMEOUT_MS=${OPENROUTER_TIMEOUT_MS_PIN}"
fi
if [ -n "$LLM_STREAM_TIMEOUT_PIN" ]; then
  REPIN_ENV="${REPIN_ENV} LLM_STREAM_TIMEOUT=${LLM_STREAM_TIMEOUT_PIN}"
fi

# Step 5: Exec infisical run, then re-apply IaC pins via env(1) so compose wins over Infisical drift.
# The "$@" passes through any arguments from the compose command field.
# Optional --path scoping for the shared-project + folder-per-instance model.
# Set INFISICAL_PATH in /.infisical-auth.env to enable; leave unset for
# dedicated-project-at-root sites (backward-compat).
PATH_ARG=""
if [ -n "${INFISICAL_PATH:-}" ]; then
  PATH_ARG="--path=${INFISICAL_PATH}"
fi
# shellcheck disable=SC2086
exec infisical run \
  --projectId="$INFISICAL_PROJECT_ID" \
  --env="prod" \
  ${PATH_ARG} \
  -- env ${REPIN_ENV} "$@"
