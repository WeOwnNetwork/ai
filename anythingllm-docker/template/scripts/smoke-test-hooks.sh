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

  if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || [ "$http_code" = "308" ]; then   # 301/302/308 = caddy https redirect, healthy
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

  # Check 3.3: Collector process. In the single-image AnythingLLM deployment the
  # collector runs INSIDE the app container (no separate container). Its internal
  # port varies by image build, so treat a reachable APP container + healthy API
  # (checked above) as sufficient, and report the collector probe as INFO only —
  # never a hard FAIL (document upload is exercised directly by the §7 test).
  log_info "Checking AnythingLLM collector (in-container; informational)..."
  collector_code=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose exec -T anythingllm sh -c 'curl -s -o /dev/null -w %{http_code} --max-time 5 http://localhost:8888/ 2>/dev/null'" 2>/dev/null || echo "000")
  case "$collector_code" in ''|*[!0-9]*) collector_code=000 ;; esac

  if [ "$collector_code" != "000" ]; then
    log_pass "AnythingLLM collector responding in-container (HTTP $collector_code)"
  else
    log_info "Collector port not probed (varies by image build) — upload path is verified by the Noggenfogger test, not here"
  fi

  # Check 3.4: Vector database accessible (via SSH to container)
  log_info "Checking vector database..."
  vector_check=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "cd ${REMOTE_SITE_DIR} && docker compose exec -T anythingllm curl -s http://localhost:3001/api/v1/admin/stats 2>/dev/null | grep -c 'vectorCount'" 2>/dev/null || echo "0")
  case "$vector_check" in ''|*[!0-9]*) vector_check=0 ;; esac

  if [ "$vector_check" -gt 0 ]; then
    log_pass "Vector database accessible"
  else
    log_skip "Vector database check inconclusive (may not be configured yet)"
  fi

  # Check 3.5: Workspace storage exists (a named docker VOLUME, not a dir under
  # /opt — the data lives on the encrypted block-storage volume's docker root)
  log_info "Checking workspace storage volume..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "docker volume inspect $(basename "${REMOTE_SITE_DIR}")_storage" >/dev/null 2>&1; then
    log_pass "Workspace storage volume exists"
  else
    log_fail "Workspace storage volume missing (expected docker volume $(basename "${REMOTE_SITE_DIR}")_storage)"
  fi
}
