#!/bin/sh
# Keycloak-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for Keycloak deployments.
#
# Checks:
#   3.1: Keycloak health endpoint (/health/ready)
#   3.2: PostgreSQL database ready
#   3.3: Caddy reverse proxy responding
#   3.4: Keycloak admin console accessible
#   3.5: Realms endpoint accessible

run_template_specific_checks() {
  log_info "Running Keycloak-specific checks..."

  # Check 3.1: Keycloak health endpoint
  log_info "Checking Keycloak health endpoint..."
  kc_health=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T keycloak curl -sf http://localhost:8080/health/ready 2>/dev/null" || echo "")

  if echo "$kc_health" | grep -qi "ready\|UP\|status" 2>/dev/null; then
    log_pass "Keycloak health endpoint reporting ready"
  else
    log_fail "Keycloak health endpoint not ready"
  fi

  # Check 3.2: PostgreSQL database ready
  log_info "Checking PostgreSQL database..."
  pg_ready=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T db pg_isready -h localhost 2>/dev/null" || echo "")

  if echo "$pg_ready" | grep -q "accepting" 2>/dev/null; then
    log_pass "PostgreSQL accepting connections"
  else
    log_fail "PostgreSQL not accepting connections"
  fi

  # Check 3.3: Caddy reverse proxy responding on public port
  log_info "Checking Caddy reverse proxy..."
  caddy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$caddy_code" = "200" ] || [ "$caddy_code" = "301" ] || [ "$caddy_code" = "302" ] || [ "$caddy_code" = "308" ]; then
    log_pass "Caddy reverse proxy responding (HTTP $caddy_code)"
  else
    log_fail "Caddy reverse proxy not responding (HTTP $caddy_code)"
  fi

  # Check 3.4: Keycloak admin console accessible via Caddy
  log_info "Checking Keycloak admin console..."
  admin_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/admin/" 2>/dev/null || echo "000")

  if [ "$admin_code" = "200" ] || [ "$admin_code" = "302" ] || [ "$admin_code" = "303" ]; then
    log_pass "Keycloak admin console accessible (HTTP $admin_code)"
  else
    log_fail "Keycloak admin console not accessible (HTTP $admin_code)"
  fi

  # Check 3.5: Realms endpoint accessible (proves Keycloak is serving OIDC)
  log_info "Checking Keycloak realms endpoint..."
  realms_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/realms/master" 2>/dev/null || echo "000")

  if [ "$realms_code" = "200" ] || [ "$realms_code" = "302" ]; then
    log_pass "Keycloak realms endpoint accessible (HTTP $realms_code)"
  else
    log_fail "Keycloak realms endpoint not accessible (HTTP $realms_code)"
  fi
}
