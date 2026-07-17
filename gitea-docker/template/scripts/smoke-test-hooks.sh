#!/bin/sh
# Gitea-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for Gitea deployments.
#
# Checks:
#   3.1: Gitea health endpoint (/api/healthz)
#   3.2: PostgreSQL database ready
#   3.3: Caddy reverse proxy responding
#   3.4: Gitea sign-in page accessible
#   3.5: Gitea SSH port reachable

run_template_specific_checks() {
  log_info "Running Gitea-specific checks..."

  # Check 3.1: Gitea health endpoint
  log_info "Checking Gitea health endpoint..."
  gitea_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T gitea curl -fsS http://127.0.0.1:3000/api/healthz 2>/dev/null" || echo "")

  if echo "$gitea_health" | grep -qi "pass" 2>/dev/null; then
    log_pass "Gitea health endpoint reporting pass"
  else
    log_fail "Gitea health endpoint not healthy"
  fi

  # Check 3.2: PostgreSQL database ready
  log_info "Checking PostgreSQL database..."
  pg_ready=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
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

  # Check 3.4: Gitea sign-in page accessible via Caddy
  log_info "Checking Gitea sign-in page..."
  login_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/user/login" 2>/dev/null || echo "000")

  if [ "$login_code" = "200" ] || [ "$login_code" = "302" ] || [ "$login_code" = "303" ]; then
    log_pass "Gitea sign-in page accessible (HTTP $login_code)"
  else
    log_fail "Gitea sign-in page not accessible (HTTP $login_code)"
  fi

  # Check 3.5: Gitea SSH port reachable (git clone over SSH)
  log_info "Checking Gitea SSH port ${GITEA_SSH_PORT:-2222}..."
  if nc -z -w 10 "${DROPLET_IP}" "${GITEA_SSH_PORT:-2222}" 2>/dev/null; then
    log_pass "Gitea SSH port reachable"
  else
    log_fail "Gitea SSH port not reachable"
  fi
}
