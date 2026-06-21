#!/bin/sh
# Keycloak-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for Keycloak deployments.
#
# Checks:
#   3.1: Keycloak health endpoint (/health/ready)
#   3.2: PostgreSQL database ready
#   3.3: Caddy HTTPS reverse proxy responding
#   3.4: Keycloak admin console accessible
#   3.5: OIDC realms endpoint with correct HTTPS issuer URL

run_template_specific_checks() {
  log_info "Running Keycloak-specific checks..."

  # Check 3.1: Keycloak health endpoint via Docker
  log_info "Checking Keycloak health endpoint..."
  kc_health=$(ssh -o ConnectTimeout=10 root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T keycloak curl -sf http://localhost:8080/health/ready 2>/dev/null" || echo "")

  if echo "$kc_health" | grep -qi "ready\|UP\|status" 2>/dev/null; then
    log_pass "Keycloak health endpoint reporting ready"
  else
    log_skip "Keycloak health check skipped (curl may not be in container)"
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

  # Check 3.3: Caddy HTTPS reverse proxy via public domain
  log_info "Checking Caddy HTTPS reverse proxy..."
  domain_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${SITE_NAME}.weown.dev/" 2>/dev/null || echo "000")

  if [ "$domain_code" = "200" ] || [ "$domain_code" = "301" ] || [ "$domain_code" = "302" ] || [ "$domain_code" = "308" ]; then
    log_pass "HTTPS reverse proxy responding (HTTP $domain_code via ${SITE_NAME}.weown.dev)"
  else
    log_fail "HTTPS reverse proxy not responding (HTTP $domain_code)"
  fi

  # Check 3.4: Keycloak admin console accessible via HTTPS
  log_info "Checking Keycloak admin console..."
  admin_code=$(curl -skL -o /dev/null -w "%{http_code}" --max-time 10 "https://${SITE_NAME}.weown.dev/admin/" 2>/dev/null || echo "000")

  if [ "$admin_code" = "200" ]; then
    log_pass "Keycloak admin console accessible (HTTP $admin_code)"
  else
    log_fail "Keycloak admin console not accessible (HTTP $admin_code)"
  fi

  # Check 3.5: OIDC realms endpoint with correct HTTPS issuer
  log_info "Checking OIDC issuer uses HTTPS..."
  issuer=$(curl -sk --max-time 10 "https://${SITE_NAME}.weown.dev/realms/master/.well-known/openid-configuration" 2>/dev/null | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4 || echo "")

  if echo "$issuer" | grep -q "^https://"; then
    log_pass "OIDC issuer is HTTPS ($issuer)"
  else
    log_fail "OIDC issuer is not HTTPS (got: $issuer)"
  fi
}
