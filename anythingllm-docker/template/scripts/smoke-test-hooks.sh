#!/bin/sh
# AnythingLLM-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for AnythingLLM deployments.
#
# Usage:
#   ./scripts/smoke-test-framework.sh <site-dir> <template>/scripts/smoke-test-hooks.sh

# ============================================================================
# Template-Specific Checks for AnythingLLM
# ============================================================================

run_template_specific_checks() {
  log_info "Running AnythingLLM-specific checks..."

  # Check 3.1: AnythingLLM web interface accessible (via Caddy on port 80)
  log_info "Checking AnythingLLM web interface..."
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
    log_pass "AnythingLLM web interface accessible (HTTP $http_code)"
  else
    log_fail "AnythingLLM web interface not accessible (HTTP $http_code)"
  fi

  # Check 3.2: AnythingLLM API health endpoint (via SSH to loopback)
  log_info "Checking AnythingLLM API health..."
  api_response=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "curl -s http://localhost:3001/api/v1/health 2>/dev/null" || echo "")

  if [ -n "$api_response" ]; then
    log_pass "AnythingLLM API health endpoint responding"
  else
    log_fail "AnythingLLM API health endpoint not responding"
  fi

  # Check 3.3: Collector container running (AnythingLLM-specific)
  log_info "Checking AnythingLLM collector container..."
  collector_running=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -i collector | grep -c '\"State\": *\"running\"'" 2>/dev/null || echo "0")

  if [ "$collector_running" -gt 0 ]; then
    log_pass "AnythingLLM collector container running"
  else
    log_fail "AnythingLLM collector container not running (required for document processing)"
  fi

  # Check 3.4: Vector database accessible (via SSH to container)
  log_info "Checking vector database..."
  vector_check=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose exec -T anythingllm curl -s http://localhost:3001/api/v1/admin/stats 2>/dev/null | grep -c 'vectorCount'" 2>/dev/null || echo "0")

  if [ "$vector_check" -gt 0 ]; then
    log_pass "Vector database accessible"
  else
    log_skip "Vector database check inconclusive (may not be configured yet)"
  fi

  # Check 3.5: Workspace directory exists
  log_info "Checking workspace directory..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -d ${REMOTE_SITE_DIR}/storage" >/dev/null 2>&1; then
    log_pass "Workspace storage directory exists"
  else
    log_fail "Workspace storage directory missing"
  fi
}
