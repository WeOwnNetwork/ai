#!/bin/sh
# OpenClaw-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for OpenClaw deployments.
#
# Checks:
#   3.1: OpenClaw container responding (TCP health probe)
#   3.2: Caddy reverse proxy responding
#   3.3: OpenClaw gateway accessible via Caddy

run_template_specific_checks() {
  log_info "Running OpenClaw-specific checks..."

  # Check 3.1: OpenClaw container responding on internal port
  log_info "Checking OpenClaw internal health..."
  oc_health=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -c '\"Health\":\"healthy\"'" 2>/dev/null || echo "0")

  if [ "$oc_health" -gt 0 ]; then
    log_pass "OpenClaw container healthcheck passing"
  else
    # Fallback: check if container is at least running
    oc_running=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
      "cd ${REMOTE_SITE_DIR} && docker compose ps --format json | grep -i openclaw | grep -c '\"State\":\"running\"'" 2>/dev/null || echo "0")
    if [ "$oc_running" -gt 0 ]; then
      log_skip "OpenClaw container running but healthcheck not yet passing (may still be starting)"
    else
      log_fail "OpenClaw container not running"
    fi
  fi

  # Check 3.2: Caddy reverse proxy responding
  log_info "Checking Caddy reverse proxy..."
  caddy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$caddy_code" = "200" ] || [ "$caddy_code" = "301" ] || [ "$caddy_code" = "302" ] || [ "$caddy_code" = "426" ]; then
    log_pass "Caddy reverse proxy responding (HTTP $caddy_code)"
  else
    log_fail "Caddy reverse proxy not responding (HTTP $caddy_code)"
  fi

  # Check 3.3: OpenClaw gateway accessible via Caddy
  log_info "Checking OpenClaw gateway endpoint..."
  gw_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/api/" 2>/dev/null || echo "000")

  # 401/403 is acceptable — means gateway is up but requires auth
  if [ "$gw_code" = "200" ] || [ "$gw_code" = "401" ] || [ "$gw_code" = "403" ] || [ "$gw_code" = "404" ]; then
    log_pass "OpenClaw gateway responding (HTTP $gw_code)"
  else
    log_fail "OpenClaw gateway not responding (HTTP $gw_code)"
  fi
}
