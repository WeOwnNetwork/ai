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
    local var_name="$1"
    grep "^${var_name}" terraform.tfvars | sed 's/.*= *"\(.*\)"/\1/' | tr -d ' '
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
