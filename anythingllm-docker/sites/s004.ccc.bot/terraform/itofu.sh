#!/usr/bin/env bash
# itofu.sh — run OpenTofu with infra secrets injected from Infisical (no
# terraform.tfvars on disk, no manual paste).
#
# All TF_VAR_* provisioning secrets live in a SEPARATE operator-only Infisical
# project (e.g. `weown-tofu`) — NOT the app project the droplet's Machine
# Identity can read. This wrapper runs tofu under `infisical run`, so tofu reads
# them as TF_VAR_* env vars. `init` also forwards the DO Spaces creds to the S3
# backend (the backend block can't read TF_VAR_*).
#
# Required Infisical secrets in the weown-tofu project (prod env):
#   TF_VAR_do_token, TF_VAR_ssh_key_fingerprint,
#   TF_VAR_spaces_access_key, TF_VAR_spaces_secret_key, TF_VAR_spaces_encryption_key,
#   TF_VAR_infisical_client_id, TF_VAR_infisical_client_secret, TF_VAR_infisical_project_id
#
# Usage (run from this terraform/ dir, after `infisical login`):
#   export WEOWN_TOFU_PROJECT_ID=<weown-tofu Infisical project id>
#   ./itofu.sh init        # then:  ./itofu.sh plan   /   ./itofu.sh apply   /   ./itofu.sh output ...
set -euo pipefail

: "${WEOWN_TOFU_PROJECT_ID:?Set WEOWN_TOFU_PROJECT_ID to the weown-tofu Infisical project id (operator-only infra secrets).}"
ENV_SLUG="${WEOWN_TOFU_ENV:-prod}"

command -v infisical >/dev/null 2>&1 || { echo "ERROR: infisical CLI not found." >&2; exit 1; }
command -v tofu      >/dev/null 2>&1 || { echo "ERROR: tofu not found." >&2; exit 1; }
infisical whoami >/dev/null 2>&1 || infisical user >/dev/null 2>&1 || {
  echo "ERROR: no Infisical session — run 'infisical login' first." >&2; exit 1; }
[ "$#" -ge 1 ] || { echo "usage: ./itofu.sh <init|plan|apply|output|destroy|...> [args]" >&2; exit 1; }

if [ "$1" = "init" ]; then
  shift
  # The S3 backend block can't reference TF_VAR_*, so forward the Spaces creds
  # from the Infisical-injected env to -backend-config. The single quotes are
  # intentional — these expand inside `infisical run`, not here.
  # shellcheck disable=SC2016
  exec infisical run --projectId="$WEOWN_TOFU_PROJECT_ID" --env="$ENV_SLUG" -- \
    bash -c 'exec tofu init -reconfigure \
      -backend-config="access_key=$TF_VAR_spaces_access_key" \
      -backend-config="secret_key=$TF_VAR_spaces_secret_key" \
      -backend-config="sse_customer_key=$TF_VAR_spaces_encryption_key" "$@"' itofu "$@"
fi

exec infisical run --projectId="$WEOWN_TOFU_PROJECT_ID" --env="$ENV_SLUG" -- tofu "$@"
