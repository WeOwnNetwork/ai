#!/usr/bin/env bash
# Verify all required Infisical secrets are present for a deployment
# Usage: ./verify-infisical-secrets.sh <infisical-project-id> [environment]
#
# Requires: infisical CLI installed and authenticated
set -euo pipefail

PROJECT_ID="${1:-}"
ENV="${2:-prod}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <infisical-project-id> [environment]"
  echo ""
  echo "Examples:"
  echo "  $0 weown-keycloak"
  echo "  $0 weown-keycloak staging"
  exit 1
fi

# Check if infisical CLI is available
if ! command -v infisical &>/dev/null; then
  echo "Error: infisical CLI not found"
  echo "Install: curl -fsSL https://infisical.com/install-cli.sh | bash"
  exit 1
fi

# Check if authenticated
if ! infisical login --method=universal-auth --silent &>/dev/null 2>&1; then
  echo "Error: Not authenticated to Infisical"
  echo "Run: infisical login"
  exit 1
fi

echo "==================================================================="
echo "  Infisical Secret Verification"
echo "  Project: $PROJECT_ID"
echo "  Environment: $ENV"
echo "==================================================================="
echo ""

REQUIRED_SECRETS=(
  "DB_NAME"
  "DB_USER"
  "DB_PASSWORD"
  "DB_ROOT_PASSWORD"
  "KEYCLOAK_ADMIN_USERNAME"
  "KEYCLOAK_ADMIN_PASSWORD"
)

OPTIONAL_SECRETS=(
  "MINIMUS_TOKEN"
  "SPACES_ACCESS_KEY"
  "SPACES_SECRET_KEY"
)

MISSING=0

echo "--- Required Secrets ---"
for secret in "${REQUIRED_SECRETS[@]}"; do
  if infisical secrets get "$secret" --projectId="$PROJECT_ID" --env="$ENV" &>/dev/null; then
    echo "  ✅ $secret"
  else
    echo "  ❌ $secret — MISSING"
    ((MISSING++))
  fi
done

echo ""
echo "--- Optional Secrets ---"
for secret in "${OPTIONAL_SECRETS[@]}"; do
  if infisical secrets get "$secret" --projectId="$PROJECT_ID" --env="$ENV" &>/dev/null; then
    echo "  ✅ $secret"
  else
    echo "  ⚠️  $secret — not set (optional)"
  fi
done

echo ""
echo "==================================================================="
echo "  Verification Complete"
echo "==================================================================="
echo "  Missing required secrets: $MISSING"

if [[ $MISSING -gt 0 ]]; then
  echo "  Status: ❌ FAILED — Add missing secrets before deployment"
  exit 1
else
  echo "  Status: ✅ PASSED — All required secrets present"
  exit 0
fi
