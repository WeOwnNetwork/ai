#!/usr/bin/env bash
# sso.weown.dev - Terraform Init Script
# Reads Spaces credentials from terraform.tfvars and passes to backend-config
#
# Usage: ./init.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse credentials from terraform.tfvars
get_tfvar() {
  # Anchor both ends of the key so e.g. `spaces_access_key` doesn't also
  # match `spaces_access_key_v2 = ...` if a future config grows variations.
  # Uses `|| true` to prevent grep exit-1 from crashing under set -euo pipefail.
  local var_name="$1"
  grep -E "^${var_name}[[:space:]]*=" terraform.tfvars 2>/dev/null \
    | sed 's/.*= *"\(.*\)"/\1/' \
    | tr -d ' ' \
    || true
}

echo "==> Reading Spaces credentials from terraform.tfvars..."

SPACES_ACCESS_KEY=$(get_tfvar "spaces_access_key")
SPACES_SECRET_KEY=$(get_tfvar "spaces_secret_key")
SPACES_ENCRYPTION_KEY=$(get_tfvar "spaces_encryption_key")

if [[ -z "$SPACES_ACCESS_KEY" ]] || [[ -z "$SPACES_SECRET_KEY" ]] || [[ -z "$SPACES_ENCRYPTION_KEY" ]]; then
    echo "ERROR: Missing Spaces credentials in terraform.tfvars"
    echo "Required variables: spaces_access_key, spaces_secret_key, spaces_encryption_key"
    exit 1
fi

echo "==> Initializing Terraform with DO Spaces backend..."

tofu init \
    -backend-config="access_key=${SPACES_ACCESS_KEY}" \
    -backend-config="secret_key=${SPACES_SECRET_KEY}" \
    -backend-config="sse_customer_key=${SPACES_ENCRYPTION_KEY}"

echo ""
echo "==> Init complete. Next steps:"
echo "    tofu plan"
echo "    tofu apply"
