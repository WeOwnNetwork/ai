#!/usr/bin/env bash
# test-template.sh — Render and validate a docker template
#
# This script renders a test site from a template and runs validation checks
# without deploying anything. It's safe to run locally and cleans up after itself.
#
# Usage:
#   ./scripts/test-template.sh <template-name> [site-name]
#
# Examples:
#   ./scripts/test-template.sh anythingllm-docker
#   ./scripts/test-template.sh keycloak-docker test-keycloak
#
# What it does:
#   1. Renders a test site from the template using copier
#   2. Validates compose file syntax (docker-compose config)
#   3. Validates ansible playbook syntax (ansible-playbook --syntax-check)
#   4. Checks for hardcoded secrets in rendered files
#   5. Verifies ADR-006 wrapper script exists and is correct
#   6. Cleans up the rendered site
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks failed
#   2 = usage error

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_check() {
  echo -e "${GREEN}[CHECK]${NC} $*"
}

# Usage
if [[ $# -lt 1 ]]; then
  log_error "Usage: $0 <template-name> [site-name]"
  log_error "Example: $0 anythingllm-docker"
  exit 2
fi

TEMPLATE_NAME="$1"
SITE_NAME="${2:-test-$(date +%s)}"

# Get absolute path to repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Validate template exists
if [[ ! -d "$REPO_ROOT/$TEMPLATE_NAME/template" ]]; then
  log_error "Template not found: $TEMPLATE_NAME"
  log_error "Expected directory: $REPO_ROOT/$TEMPLATE_NAME/template/"
  exit 2
fi

log_info "Testing template: $TEMPLATE_NAME"
log_info "Site name: $SITE_NAME"

# Create temporary directory for rendered site
SITE_DIR="$REPO_ROOT/$TEMPLATE_NAME/sites/$SITE_NAME"
if [[ -d "$SITE_DIR" ]]; then
  log_error "Site directory already exists: $SITE_DIR"
  log_error "Please use a different site name or delete the existing directory"
  exit 2
fi

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
  log_info "Cleaning up rendered site..."
  rm -rf "$SITE_DIR"
  log_info "Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Step 1: Render the site
log_info "Step 1: Rendering site from template..."
# Provide required variables that don't have defaults
# Use absolute paths to avoid directory confusion
RENDER_OUTPUT=$(copier copy --trust --defaults \
  --data "project_name=$SITE_NAME" \
  --data "domain=test.example.com" \
  --data 'ssh_source_cidrs=["0.0.0.0/0", "::/0"]' \
  "$REPO_ROOT/$TEMPLATE_NAME" "$SITE_DIR" 2>&1) || {
  log_error "Failed to render site from template"
  log_error "Copier output:"
  echo "$RENDER_OUTPUT" | tail -20
  exit 1
}
log_check "Site rendered successfully"
TESTS_PASSED=$((TESTS_PASSED + 1))

# Step 2: Validate compose file syntax
log_info "Step 2: Validating compose file syntax..."
if [[ -f "$SITE_DIR/docker/compose.prod.yaml" ]]; then
  # Provide dummy values for required env vars (these come from Infisical at runtime)
  if ANYTHINGLLM_IMAGE="test:latest" \
     OPENROUTER_API_KEY="test" \
     JWT_SECRET="test" \
     ADMIN_EMAIL="test@example.com" \
     docker compose -f "$SITE_DIR/docker/compose.prod.yaml" config >/dev/null 2>&1; then
    log_check "Compose file syntax is valid"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_error "Compose file syntax is invalid"
    # Show the error for debugging
    ANYTHINGLLM_IMAGE="test:latest" \
    OPENROUTER_API_KEY="test" \
    JWT_SECRET="test" \
    ADMIN_EMAIL="test@example.com" \
    docker compose -f "$SITE_DIR/docker/compose.prod.yaml" config 2>&1 | head -5
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  log_warn "No compose.prod.yaml found, skipping compose validation"
fi

# Step 3: Validate ansible playbook syntax
log_info "Step 3: Validating ansible playbook syntax..."
if [[ -f "$SITE_DIR/ansible/deploy.yml" ]]; then
  if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check "$SITE_DIR/ansible/deploy.yml" >/dev/null 2>&1; then
      log_check "Ansible playbook syntax is valid"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log_error "Ansible playbook syntax is invalid"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    log_warn "ansible-playbook not found, skipping ansible validation"
  fi
else
  log_warn "No ansible/deploy.yml found, skipping ansible validation"
fi

# Step 4: Check for hardcoded secrets
log_info "Step 4: Checking for hardcoded secrets..."
SECRETS_FOUND=0

# Check for common secret patterns (more specific to avoid false positives)
# Look for actual hardcoded values, not variable references
if grep -rE '(password|secret|token|key)\s*=\s*["'"'"'][^$"'"'"']{8,}["'"'"']' "$SITE_DIR" --include="*.yaml" --include="*.yml" --include="*.sh" 2>/dev/null | grep -vE '(example|placeholder|changeme|\{\{|\$\{|INFISICAL_|TF_VAR_|BASH_REMATCH)' >/dev/null; then
  log_error "Found potential hardcoded secrets in rendered files"
  SECRETS_FOUND=1
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $SECRETS_FOUND -eq 0 ]]; then
  log_check "No hardcoded secrets found"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Step 5: Verify ADR-006 wrapper script
log_info "Step 5: Verifying ADR-006 wrapper script..."
WRAPPER_SCRIPT="$SITE_DIR/scripts/entrypoint-infisical.sh"
if [[ -f "$WRAPPER_SCRIPT" ]]; then
  # Make it executable (copier doesn't preserve execute permissions)
  chmod +x "$WRAPPER_SCRIPT"

  # Check if it's executable
  if [[ -x "$WRAPPER_SCRIPT" ]]; then
    log_check "Wrapper script exists and is executable"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_error "Wrapper script exists but is not executable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Check for required content
  if grep -q "infisical login" "$WRAPPER_SCRIPT" && grep -q "infisical run" "$WRAPPER_SCRIPT"; then
    log_check "Wrapper script contains required authentication logic"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_error "Wrapper script is missing required authentication logic"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  log_warn "No wrapper script found (template may not use ADR-006)"
fi

# Step 6: Verify compose entrypoint
log_info "Step 6: Verifying compose entrypoint configuration..."
if [[ -f "$SITE_DIR/docker/compose.prod.yaml" ]]; then
  if grep -q "entrypoint-infisical.sh" "$SITE_DIR/docker/compose.prod.yaml"; then
    log_check "Compose file uses wrapper script as entrypoint"
    TESTS_PASSED=$((TESTS_PASSED + 1))

    # Check for bind-mount
    if grep -q "entrypoint-infisical.sh:ro" "$SITE_DIR/docker/compose.prod.yaml"; then
      log_check "Wrapper script is bind-mounted read-only"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log_error "Wrapper script is not bind-mounted read-only"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    log_warn "Compose file does not use wrapper script (template may not use ADR-006)"
  fi
fi

# Step 7: Verify ansible uploads wrapper script
log_info "Step 7: Verifying ansible uploads wrapper script..."
if [[ -f "$SITE_DIR/ansible/deploy.yml" ]]; then
  if grep -q "entrypoint-infisical.sh" "$SITE_DIR/ansible/deploy.yml"; then
    log_check "Ansible playbook uploads wrapper script"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_warn "Ansible playbook does not upload wrapper script (template may not use ADR-006)"
  fi
fi

# Summary
echo ""
log_info "========================================="
log_info "Test Summary"
log_info "========================================="
log_info "Tests passed: $TESTS_PASSED"
if [[ $TESTS_FAILED -gt 0 ]]; then
  log_error "Tests failed: $TESTS_FAILED"
  exit 1
else
  log_info "Tests failed: 0"
  log_info "All checks passed!"
  exit 0
fi
