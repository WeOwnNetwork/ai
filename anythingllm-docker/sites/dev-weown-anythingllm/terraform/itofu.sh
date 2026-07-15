#!/usr/bin/env bash
# itofu.sh - run OpenTofu with infra secrets injected from Infisical (no
# terraform.tfvars on disk, no manual paste).
#
# Secrets: all TF_VAR_* provisioning values live in a SEPARATE operator-only
# Infisical project (e.g. `weown-tofu`) - NOT the app project the droplet's
# Machine Identity can read. This wrapper runs tofu under `infisical run`, so
# tofu reads them as TF_VAR_* env vars; `init` forwards the DO Spaces creds to
# the S3 backend (the backend block can't read TF_VAR_*).
#
# plan/apply use a SAVED plan so apply runs exactly what you reviewed:
#   - `plan`  -> `tofu plan -out=plan.tfplan`   (no flag needed)
#   - `apply` -> `tofu apply plan.tfplan`, then DELETES it
# The plan file holds sensitive values (rendered cloud-init, etc.) in plaintext,
# so it is gitignored and removed after apply.
#
# Required Infisical secrets (weown-tofu, prod env):
#   TF_VAR_do_token, TF_VAR_ssh_key_fingerprint,
#   TF_VAR_spaces_access_key, TF_VAR_spaces_secret_key, TF_VAR_spaces_encryption_key,
#   TF_VAR_infisical_client_id, TF_VAR_infisical_client_secret, TF_VAR_infisical_project_id,
#   TF_VAR_alert_email  (a DO-VERIFIED email; enable_monitoring defaults true, so a
#                        missing/placeholder value fails DO alert creation with "email
#                        is not verified" - or set TF_VAR_enable_monitoring=false to
#                        skip the DO monitor alerts entirely)
#
# Usage (run from this terraform/ dir, after `infisical login`):
#   export WEOWN_TOFU_PROJECT_ID=<weown-tofu Infisical project id>
#   ./itofu.sh init && ./itofu.sh plan && ./itofu.sh apply
#   ./itofu.sh output -raw droplet_ip      # any other subcommand passes through
#
# Note: this script does NOT read site.conf because WEOWN_TOFU_PROJECT_ID is
# operator-global (same across all sites), not site-specific. Set it once in
# your shell profile or pass it as an env var.
set -euo pipefail

: "${WEOWN_TOFU_PROJECT_ID:?Set WEOWN_TOFU_PROJECT_ID to the weown-tofu Infisical project id (operator-only infra secrets).}"
ENV_SLUG="${WEOWN_TOFU_ENV:-prod}"
PLAN_FILE="${WEOWN_TOFU_PLAN:-plan.tfplan}"   # gitignored; holds secrets -> consumed + deleted by apply

command -v infisical >/dev/null 2>&1 || { echo "ERROR: infisical CLI not found." >&2; exit 1; }
command -v tofu      >/dev/null 2>&1 || { echo "ERROR: tofu not found." >&2; exit 1; }
infisical whoami >/dev/null 2>&1 || infisical user >/dev/null 2>&1 || {
  echo "ERROR: no Infisical session - run 'infisical login' first." >&2; exit 1; }
[ "$#" -ge 1 ] || { echo "usage: ./itofu.sh <init|plan|apply|output|destroy|...> [args]" >&2; exit 1; }

# Run a command with the weown-tofu secrets injected as env vars.
irun() { infisical run --projectId="$WEOWN_TOFU_PROJECT_ID" --env="$ENV_SLUG" -- "$@"; }

case "$1" in
  init)
    shift
    # The S3 backend block can't reference TF_VAR_*, so forward the Spaces creds
    # from the Infisical-injected env to -backend-config. Single quotes are
    # intentional - these expand inside `infisical run`, not here.
    # shellcheck disable=SC2016
    irun bash -c 'export AWS_ACCESS_KEY_ID="$TF_VAR_spaces_access_key"; export AWS_SECRET_ACCESS_KEY="$TF_VAR_spaces_secret_key"; exec tofu init -reconfigure \
      -backend-config="sse_customer_key=$TF_VAR_spaces_encryption_key" "$@"' itofu "$@"
    ;;
  plan)
    shift
    echo "-> tofu plan -out=$PLAN_FILE  (saved plan is SENSITIVE + gitignored; 'apply' consumes & deletes it)"
    irun tofu plan -out="$PLAN_FILE" "$@"
    ;;
  apply)
    shift
    if [ "$#" -eq 0 ] && [ -f "$PLAN_FILE" ]; then
      echo "-> applying saved plan ($PLAN_FILE) - exactly what you reviewed - then deleting it"
      set +e; irun tofu apply "$PLAN_FILE"; rc=$?; set -e
      rm -f "$PLAN_FILE"   # plan files contain sensitive values (rendered cloud-init, etc.) in plaintext
      exit "$rc"
    fi
    irun tofu apply "$@"
    ;;
  *)
    irun tofu "$@"
    ;;
esac
