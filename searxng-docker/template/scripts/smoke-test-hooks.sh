#!/bin/sh
# SearXNG-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for SearXNG deployments.
#
# Checks:
#   3.1: SearXNG health endpoint (/healthz)
#   3.2: Valkey (Redis) cache responding
#   3.3: Caddy reverse proxy responding
#   3.4: Search functionality works

run_template_specific_checks() {
  log_info "Running SearXNG-specific checks..."

  # Check 3.1: SearXNG health endpoint
  log_info "Checking SearXNG health endpoint..."
  sx_health=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T searxng wget -q --spider http://localhost:8080/healthz 2>&1 && echo OK" || echo "")

  if echo "$sx_health" | grep -q "OK" 2>/dev/null; then
    log_pass "SearXNG health endpoint OK"
  else
    log_fail "SearXNG health endpoint not responding"
  fi

  # Check 3.2: Valkey (Redis) cache responding
  log_info "Checking Valkey cache..."
  valkey_pong=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T valkey valkey-cli ping 2>/dev/null" || echo "")

  if echo "$valkey_pong" | grep -q "PONG" 2>/dev/null; then
    log_pass "Valkey cache responding (PONG)"
  else
    log_fail "Valkey cache not responding"
  fi

  # Check 3.3: Caddy reverse proxy responding
  log_info "Checking Caddy reverse proxy..."
  caddy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$caddy_code" = "200" ] || [ "$caddy_code" = "301" ] || [ "$caddy_code" = "302" ]; then
    log_pass "Caddy reverse proxy responding (HTTP $caddy_code)"
  else
    log_fail "Caddy reverse proxy not responding (HTTP $caddy_code)"
  fi

  # Check 3.4: Search functionality works
  log_info "Checking search functionality..."
  search_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/search?q=test" 2>/dev/null || echo "000")

  if [ "$search_code" = "200" ]; then
    log_pass "Search endpoint responding (HTTP $search_code)"
  else
    log_fail "Search endpoint not responding (HTTP $search_code)"
  fi
}
