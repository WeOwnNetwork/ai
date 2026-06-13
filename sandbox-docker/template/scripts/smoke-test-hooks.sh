#!/bin/sh
# Sandbox-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for Sandbox deployments.
#
# Checks:
#   3.1: Sandbox API docs endpoint (/v1/docs)
#   3.2: Caddy reverse proxy responding
#   3.3: Sandbox API accessible via Caddy

run_template_specific_checks() {
  log_info "Running Sandbox-specific checks..."

  # Check 3.1: Sandbox API docs endpoint (internal, loopback only)
  log_info "Checking Sandbox API docs endpoint..."
  sb_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T sandbox curl -sf http://127.0.0.1:8080/v1/docs 2>/dev/null | head -c 100" || echo "")

  if [ -n "$sb_health" ]; then
    log_pass "Sandbox API docs endpoint responding"
  else
    log_fail "Sandbox API docs endpoint not responding"
  fi

  # Check 3.2: Caddy reverse proxy responding
  log_info "Checking Caddy reverse proxy..."
  caddy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$caddy_code" = "200" ] || [ "$caddy_code" = "301" ] || [ "$caddy_code" = "302" ]; then
    log_pass "Caddy reverse proxy responding (HTTP $caddy_code)"
  else
    log_fail "Caddy reverse proxy not responding (HTTP $caddy_code)"
  fi

  # Check 3.3: Sandbox API accessible via Caddy
  log_info "Checking Sandbox API via Caddy..."
  api_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/v1/docs" 2>/dev/null || echo "000")

  # 401/403 is acceptable — means API is up but requires auth
  if [ "$api_code" = "200" ] || [ "$api_code" = "401" ] || [ "$api_code" = "403" ]; then
    log_pass "Sandbox API accessible via Caddy (HTTP $api_code)"
  else
    log_fail "Sandbox API not accessible via Caddy (HTTP $api_code)"
  fi
}
