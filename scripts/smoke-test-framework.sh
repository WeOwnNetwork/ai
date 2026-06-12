#!/bin/sh
# Generic smoke test framework for all docker templates
#
# This script provides a standardized post-deployment verification framework
# that works across all template types (anythingllm, keycloak, wordpress, etc.)
#
# Usage:
#   ./scripts/smoke-test-framework.sh <site-dir> [template-specific-hooks]
#
# Arguments:
#   site-dir                  Path to the rendered site directory
#   template-specific-hooks   Optional: path to template-specific hook script
#
# Exit codes:
#   0 = All tests passed
#   1 = One or more tests failed
#
# Design:
#   - ~5 minutes execution time
#   - Idempotent (safe to run multiple times)
#   - No secrets in logs
#   - Clear pass/fail output with actionable error messages
#   - Template-specific hooks for application-specific checks

set -eu

# ============================================================================
# Configuration
# ============================================================================

SITE_DIR="${1:?Usage: $0 <site-dir> [template-specific-hooks]}"
TEMPLATE_HOOKS="${2:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
  printf "${BLUE}[INFO]${NC} %s\n" "$*"
}

log_pass() {
  printf "${GREEN}[PASS]${NC} %s\n" "$*"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

log_fail() {
  printf "${RED}[FAIL]${NC} %s\n" "$*"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

log_skip() {
  printf "${YELLOW}[SKIP]${NC} %s\n" "$*"
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

log_section() {
  printf "\n"
  printf "${BLUE}======================================================================${NC}\n"
  printf "${BLUE}%s${NC}\n" "$*"
  printf "${BLUE}======================================================================${NC}\n"
  printf "\n"
}

# ============================================================================
# Phase 1: Infrastructure Checks
# ============================================================================

check_infrastructure() {
  log_section "Phase 1: Infrastructure Checks"

  # Check 1.1: SSH connectivity
  log_info "Checking SSH connectivity..."
  if ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o BatchMode=yes root@"${DROPLET_IP}" "echo 'SSH OK'" >/dev/null 2>&1; then
    log_pass "SSH connectivity to ${DROPLET_IP}"
  else
    log_fail "SSH connectivity to ${DROPLET_IP}"
  fi

  # Check 1.2: Cloud-init completion
  log_info "Checking cloud-init completion..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -f /var/lib/cloud/instance/boot-finished" >/dev/null 2>&1; then
    log_pass "Cloud-init completed"
  else
    log_fail "Cloud-init not completed (check /var/log/cloud-init.log)"
  fi

  # Check 1.3: Docker service
  log_info "Checking Docker service..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "systemctl is-active --quiet docker" >/dev/null 2>&1; then
    log_pass "Docker service running"
  else
    log_fail "Docker service not running"
  fi

  # Check 1.4: Docker Compose
  log_info "Checking Docker Compose..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "docker compose version" >/dev/null 2>&1; then
    log_pass "Docker Compose available"
  else
    log_fail "Docker Compose not available"
  fi

  # Check 1.5: Infisical CLI
  log_info "Checking Infisical CLI..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "infisical --version" >/dev/null 2>&1; then
    log_pass "Infisical CLI installed"
  else
    log_fail "Infisical CLI not installed"
  fi

  # Check 1.6: Auth file exists (per-site location)
  log_info "Checking auth file..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -f ${REMOTE_SITE_DIR}/.infisical-auth.env" >/dev/null 2>&1; then
    log_pass "Auth file exists"
  else
    log_fail "Auth file missing (${REMOTE_SITE_DIR}/.infisical-auth.env)"
  fi

  # Check 1.7: Auth file permissions
  log_info "Checking auth file permissions..."
  perms=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "stat -c %a ${REMOTE_SITE_DIR}/.infisical-auth.env" 2>/dev/null || echo "000")
  if [ "$perms" = "600" ]; then
    log_pass "Auth file permissions correct (600)"
  else
    log_fail "Auth file permissions incorrect (got $perms, expected 600)"
  fi
}

# ============================================================================
# Phase 2: Container Checks
# ============================================================================

check_containers() {
  log_section "Phase 2: Container Checks"

  # Check 2.1: All containers running
  log_info "Checking container status..."
  running=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -c '\"State\": *\"running\"'" 2>/dev/null || echo "0")
  total=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | wc -l" 2>/dev/null || echo "0")

  if [ "$running" -eq "$total" ] && [ "$total" -gt 0 ]; then
    log_pass "All containers running ($running/$total)"
  else
    log_fail "Not all containers running ($running/$total)"
  fi

  # Check 2.2: No restart loops
  log_info "Checking for restart loops..."
  restarts=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -o '\"RestartCount\": *[0-9]*' | awk -F: '{sum+=$2} END {print sum+0}'" 2>/dev/null || echo "0")

  # Ensure restarts is always numeric (default to 0 if empty)
  restarts="${restarts:-0}"

  if [ "$restarts" -lt 10 ]; then
    log_pass "No restart loops detected (total restarts: $restarts)"
  else
    log_fail "Restart loops detected (total restarts: $restarts)"
  fi

  # Check 2.3: Healthchecks passing
  log_info "Checking healthcheck status..."
  healthy=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -c '\"Health\": *\"healthy\"'" 2>/dev/null || echo "0")

  if [ "$healthy" -gt 0 ]; then
    log_pass "Healthchecks passing ($healthy containers healthy)"
  else
    log_skip "No healthchecks configured or none healthy"
  fi

  # Check 2.4: Logs clean (no critical errors)
  log_info "Checking logs for critical errors..."
  errors=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose logs --tail=100 2>&1 | grep -iE 'FATAL ERROR|PANIC|CRITICAL ERROR' | wc -l" 2>/dev/null || echo "0")

  if [ "$errors" -eq 0 ]; then
    log_pass "No critical errors in recent logs"
  else
    log_fail "Critical errors found in logs ($errors occurrences)"
  fi
}

# ============================================================================
# Phase 3: Application-Specific Checks (Template Hooks)
# ============================================================================

check_application() {
  log_section "Phase 3: Application-Specific Checks"

  if [ -n "$TEMPLATE_HOOKS" ] && [ -f "$TEMPLATE_HOOKS" ]; then
    log_info "Running template-specific checks from $TEMPLATE_HOOKS..."
    # Source hooks into current scope — hooks use log_pass/log_fail which
    # update framework counters. Disable set -e during hook execution to
    # prevent expected failures from terminating the framework.
    # shellcheck source=/dev/null
    . "$TEMPLATE_HOOKS"

    # Call the template-specific checks function if it exists
    if command -v run_template_specific_checks >/dev/null 2>&1; then
      set +e
      run_template_specific_checks
      set -e
    else
      log_skip "No template-specific checks function defined"
    fi
  else
    log_skip "No template-specific hooks provided"
  fi
}

# ============================================================================
# Phase 4: Backup System
# ============================================================================

check_backup() {
  log_section "Phase 4: Backup System"

  # Check 4.1: Backup script exists
  log_info "Checking backup script..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -f ${REMOTE_SITE_DIR}/scripts/backup.sh" >/dev/null 2>&1; then
    log_pass "Backup script exists"
  else
    log_fail "Backup script missing"
  fi

  # Check 4.2: Backup script executable
  log_info "Checking backup script permissions..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -x ${REMOTE_SITE_DIR}/scripts/backup.sh" >/dev/null 2>&1; then
    log_pass "Backup script executable"
  else
    log_fail "Backup script not executable"
  fi

  # Check 4.3: Backup cron job
  log_info "Checking backup cron job..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "crontab -l | grep -q backup.sh" >/dev/null 2>&1; then
    log_pass "Backup cron job configured"
  else
    log_skip "Backup cron job not configured"
  fi

  # Check 4.4: Backup directory
  log_info "Checking backup directory..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -d ${REMOTE_SITE_DIR}/backups" >/dev/null 2>&1; then
    log_pass "Backup directory exists"
  else
    log_skip "Backup directory not created yet"
  fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  printf "\n"
  printf "========================================================================\n"
  printf "Smoke Test Framework - Post-Deployment Verification\n"
  printf "========================================================================\n"
  printf "Site Directory: %s\n" "$SITE_DIR"
  printf "Template Hooks: %s\n" "${TEMPLATE_HOOKS:-none}"
  printf "Started: %s\n" "$(date)"
  printf "========================================================================\n"
  printf "\n"

  # Validate site directory
  if [ ! -d "$SITE_DIR" ]; then
    log_fail "Site directory not found: $SITE_DIR"
    exit 1
  fi

  # Extract site configuration
  if [ ! -f "$SITE_DIR/site.conf" ]; then
    log_fail "site.conf not found in $SITE_DIR"
    exit 1
  fi

  # Resolve DROPLET_IP: environment variable > terraform output > site.conf > error
  # Save env var before sourcing site.conf (site.conf may define DROPLET_IP)
  env_droplet_ip="${DROPLET_IP:-}"

  # shellcheck source=/dev/null
  . "$SITE_DIR/site.conf"

  # Restore env var if it was set (env var takes precedence over site.conf)
  if [ -n "$env_droplet_ip" ]; then
    DROPLET_IP="$env_droplet_ip"
  fi

  # If still empty, try terraform output (lowest precedence)
  if [ -z "${DROPLET_IP:-}" ]; then
    if [ -d "$SITE_DIR/terraform" ] && command -v tofu >/dev/null 2>&1; then
      DROPLET_IP=$(cd "$SITE_DIR/terraform" && tofu output -raw droplet_ip 2>/dev/null || echo "")
    fi
  fi

  if [ -z "${DROPLET_IP:-}" ]; then
    log_fail "DROPLET_IP not set. Provide via: (1) environment variable, (2) terraform output, or (3) site.conf"
    exit 1
  fi

  # Resolve SITE_NAME from directory name if not in site.conf
  SITE_NAME="${SITE_NAME:-$(basename "$SITE_DIR")}"
  REMOTE_SITE_DIR="/opt/${SITE_NAME}"

  log_info "Site Name: ${SITE_NAME:-unknown}"
  log_info "Droplet IP: $DROPLET_IP"
  log_info "Remote Directory: $REMOTE_SITE_DIR"

  # Run all phases
  check_infrastructure
  check_containers
  check_application
  check_backup

  # Summary
  log_section "Smoke Test Summary"
  printf "Tests Run:     %d\n" "$TESTS_RUN"
  printf "Tests Passed:  ${GREEN}%d${NC}\n" "$TESTS_PASSED"
  printf "Tests Failed:  ${RED}%d${NC}\n" "$TESTS_FAILED"
  printf "Tests Skipped: ${YELLOW}%d${NC}\n" "$TESTS_SKIPPED"
  printf "\n"

  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf "${GREEN}========================================================================${NC}\n"
    printf "${GREEN}✓ All smoke tests passed!${NC}\n"
    printf "${GREEN}========================================================================${NC}\n"
    exit 0
  else
    printf "${RED}========================================================================${NC}\n"
    printf "${RED}✗ Some smoke tests failed. Review failures above.${NC}\n"
    printf "${RED}========================================================================${NC}\n"
    exit 1
  fi
}

# Run main function
main
