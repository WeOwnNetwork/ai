#!/usr/bin/env bash
# Compare site files against templates
# Usage: ./check-template-alignment.sh [site-name]
#
# Checks if site files match the updated template patterns.
# Non-zero exit if misalignment detected.
set -euo pipefail

SITE_NAME="${1:-sso.weown.dev}"
TEMPLATE_DIR="keycloak-docker/template"
SITE_DIR="keycloak-docker/sites/${SITE_NAME}"

if [[ ! -d "$SITE_DIR" ]]; then
  echo "Error: Site directory not found: $SITE_DIR"
  echo "Available sites:"
  ls -1 keycloak-docker/sites/ 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "==================================================================="
echo "  Template Alignment Check: ${SITE_NAME}"
echo "  Template:  ${TEMPLATE_DIR}"
echo "==================================================================="
echo ""

ERRORS=0

# Check variables.tf
echo "--- variables.tf ---"
if [[ -f "$SITE_DIR/terraform/variables.tf" ]]; then
  # Check for legacy secret variables that should NOT exist
  if grep -q 'db_password\|db_root_password\|keycloak_admin_password' "$SITE_DIR/terraform/variables.tf"; then
    echo "  ❌ FAIL: Legacy secret variables still present (db_password, db_root_password, keycloak_admin_password)"
    ((ERRORS++))
  else
    echo "  ✅ PASS: No legacy secret variables"
  fi

  # Check for Infisical Machine Identity vars
  if grep -q 'infisical_client_id' "$SITE_DIR/terraform/variables.tf"; then
    echo "  ✅ PASS: infisical_client_id variable present"
  else
    echo "  ❌ FAIL: infisical_client_id variable missing"
    ((ERRORS++))
  fi

  if grep -q 'infisical_client_secret' "$SITE_DIR/terraform/variables.tf"; then
    echo "  ✅ PASS: infisical_client_secret variable present"
  else
    echo "  ❌ FAIL: infisical_client_secret variable missing"
    ((ERRORS++))
  fi
else
  echo "  ❌ FAIL: variables.tf not found"
  ((ERRORS++))
fi

echo ""

# Check main.tf
echo "--- main.tf ---"
if [[ -f "$SITE_DIR/terraform/main.tf" ]]; then
  # Check for conditional Infisical logic (should be removed)
  if grep -q 'enable_infisical' "$SITE_DIR/terraform/main.tf"; then
    echo "  ❌ FAIL: Conditional enable_infisical logic still present"
    ((ERRORS++))
  else
    echo "  ✅ PASS: No conditional Infisical logic"
  fi

  # Check for hardcoded project name
  if grep -q 'project_name.*=.*"sso"' "$SITE_DIR/terraform/main.tf"; then
    echo "  ❌ FAIL: Hardcoded project name 'sso' — should use var.project_name"
    ((ERRORS++))
  else
    echo "  ✅ PASS: No hardcoded project name"
  fi
else
  echo "  ❌ FAIL: main.tf not found"
  ((ERRORS++))
fi

echo ""

# Check terraform.tfvars
echo "--- terraform.tfvars ---"
if [[ -f "$SITE_DIR/terraform/terraform.tfvars" ]]; then
  # Check for app secrets that should NOT be in tfvars
  if grep -q 'db_password\|db_root_password\|keycloak_admin_password' "$SITE_DIR/terraform/terraform.tfvars"; then
    echo "  ❌ FAIL: Application secrets in terraform.tfvars"
    ((ERRORS++))
  else
    echo "  ✅ PASS: No application secrets in terraform.tfvars"
  fi

  # Check for Spaces credentials that should NOT be in tfvars
  if grep -q 'spaces_access_key\|spaces_secret_key' "$SITE_DIR/terraform/terraform.tfvars"; then
    echo "  ❌ FAIL: DO Spaces credentials in terraform.tfvars"
    ((ERRORS++))
  else
    echo "  ✅ PASS: No DO Spaces credentials in terraform.tfvars"
  fi

  # Check for Machine Identity
  if grep -q 'infisical_client_id' "$SITE_DIR/terraform/terraform.tfvars"; then
    echo "  ✅ PASS: infisical_client_id in terraform.tfvars"
  else
    echo "  ⚠️  WARN: infisical_client_id not in terraform.tfvars (may be empty)"
  fi
else
  echo "  ❌ FAIL: terraform.tfvars not found"
  ((ERRORS++))
fi

echo ""

# Check compose.prod.yaml
echo "--- docker/compose.prod.yaml ---"
if [[ -f "$SITE_DIR/docker/compose.prod.yaml" ]]; then
  if [[ -s "$SITE_DIR/docker/compose.prod.yaml" ]]; then
    echo "  ✅ PASS: compose.prod.yaml exists and is not empty"
  else
    echo "  ❌ FAIL: compose.prod.yaml is empty"
    ((ERRORS++))
  fi
else
  echo "  ❌ FAIL: compose.prod.yaml not found"
  ((ERRORS++))
fi

echo ""

# Check deploy.sh
echo "--- scripts/deploy.sh ---"
if [[ -f "$SITE_DIR/scripts/deploy.sh" ]]; then
  if grep -q '\-\-projectId' "$SITE_DIR/scripts/deploy.sh"; then
    echo "  ✅ PASS: deploy.sh uses --projectId flag"
  else
    echo "  ❌ FAIL: deploy.sh missing --projectId flag"
    ((ERRORS++))
  fi
else
  echo "  ❌ FAIL: deploy.sh not found"
  ((ERRORS++))
fi

echo ""
echo "==================================================================="
echo "  Alignment Check Complete"
echo "==================================================================="
echo "  Errors: $ERRORS"

if [[ $ERRORS -gt 0 ]]; then
  echo "  Status: ❌ FAILED — Site files need updating"
  exit 1
else
  echo "  Status: ✅ PASSED — Site files aligned with templates"
  exit 0
fi
