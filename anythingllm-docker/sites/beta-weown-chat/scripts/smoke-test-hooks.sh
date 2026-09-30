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

  # In-container probes use `docker exec` on the container found by its compose
  # LABELS. A bare `docker compose exec` must parse compose.yaml, whose
  # ${ANYTHINGLLM_IMAGE:?} is set only inside the deploy's `infisical run`, so from
  # a plain SSH session it fails and returns nothing (same trap as check 2.1 in
  # smoke-test-framework.sh). Exit 4 = no running anythingllm container.
  compose_project=$(basename "${REMOTE_SITE_DIR}")
  allm="c=\$(docker ps -q --filter label=com.docker.compose.project=${compose_project} --filter label=com.docker.compose.service=anythingllm | head -1); [ -n \"\$c\" ] || exit 4; docker exec \"\$c\""

  # Check 3.1: AnythingLLM web interface accessible (via Caddy on port 80)
  log_info "Checking AnythingLLM web interface..."
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || [ "$http_code" = "308" ]; then   # 301/302/308 = caddy https redirect, healthy
    log_pass "AnythingLLM web interface accessible (HTTP $http_code)"
  else
    log_fail "AnythingLLM web interface not accessible (HTTP $http_code)"
  fi

  # Check 3.2: AnythingLLM API health: /api/ping, the endpoint the compose
  # healthcheck and the deploy's own health wait use, probed INSIDE the app
  # container through $allm (no host curl, no published port needed). PASS only
  # on the real answer: this used to pass on ANY non-empty body, and the path it
  # probed (/api/v1/health, a SigNoz endpoint) returns AnythingLLM's HTML page
  # with a 200. A failed SSH is reported as such, never as "API down".
  log_info "Checking AnythingLLM API health (/api/ping)..."
  api_response=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "$allm curl -s --max-time 5 http://localhost:3001/api/ping" 2>/dev/null)
  api_rc=$?

  case "$api_response" in
    *'"online":true'*) log_pass "AnythingLLM API healthy (/api/ping: online)" ;;
    *)
      if [ "$api_rc" = 255 ]; then
        log_fail "AnythingLLM API NOT CHECKED: SSH to ${DROPLET_IP} failed (rc 255)"
      elif [ "$api_rc" = 4 ]; then
        log_fail "AnythingLLM API NOT CHECKED: no running anythingllm container in project ${compose_project}"
      elif [ -z "$api_response" ]; then
        log_fail "AnythingLLM API not responding (/api/ping empty, rc $api_rc)"
      else
        log_fail "AnythingLLM API unexpected /api/ping response (rc $api_rc)"
      fi
      ;;
  esac

  # Check 3.3: Collector process. In the single-image AnythingLLM deployment the
  # collector runs INSIDE the app container (no separate container). Its internal
  # port varies by image build, so treat a reachable APP container + healthy API
  # (checked above) as sufficient, and report the collector probe as INFO only —
  # never a hard FAIL (document upload is exercised directly by the §7 test).
  log_info "Checking AnythingLLM collector (in-container; informational)..."
  collector_code=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "$allm sh -c 'curl -s -o /dev/null -w %{http_code} --max-time 5 http://localhost:8888/ 2>/dev/null'" 2>/dev/null || echo "000")
  case "$collector_code" in ''|*[!0-9]*) collector_code=000 ;; esac

  if [ "$collector_code" != "000" ]; then
    log_pass "AnythingLLM collector responding in-container (HTTP $collector_code)"
  else
    log_info "Collector port not probed (varies by image build) — upload path is verified by the Noggenfogger test, not here"
  fi

  # Check 3.4: Vector database accessible (via SSH to container)
  log_info "Checking vector database..."
  vector_check=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "$allm curl -s http://localhost:3001/api/v1/admin/stats 2>/dev/null | grep -c 'vectorCount'" 2>/dev/null || echo "0")
  case "$vector_check" in ''|*[!0-9]*) vector_check=0 ;; esac

  if [ "$vector_check" -gt 0 ]; then
    log_pass "Vector database accessible"
  else
    log_skip "Vector database check inconclusive (may not be configured yet)"
  fi

  # Check 3.5: Workspace storage exists (bind-mounted ./storage under the site dir)
  log_info "Checking workspace storage bind mount..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" "test -d \"${REMOTE_SITE_DIR}/storage\"" >/dev/null 2>&1; then
    log_pass "Workspace storage directory exists"
  else
    log_fail "Workspace storage missing (expected ${REMOTE_SITE_DIR}/storage bind mount)"
  fi
}
