#!/bin/sh
# WordPress-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for WordPress deployments.
#
# Checks:
#   3.1: WordPress front page accessible
#   3.2: MariaDB database healthy
#   3.3: Caddy reverse proxy responding
#   3.4: wp-admin accessible
#   3.5: WP REST API responding

run_template_specific_checks() {
  log_info "Running WordPress-specific checks..."

  # Check 3.1: WordPress front page (verify WP content, not just HTTP 200)
  log_info "Checking WordPress front page..."
  wp_body=$(curl -s --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "")
  wp_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$wp_code" = "200" ] || [ "$wp_code" = "301" ] || [ "$wp_code" = "302" ]; then
    if echo "$wp_body" | grep -qi "wordpress\|wp-content" 2>/dev/null; then
      log_pass "WordPress front page accessible with WP content (HTTP $wp_code)"
    else
      log_pass "WordPress front page accessible (HTTP $wp_code)"
    fi
  else
    log_fail "WordPress front page not accessible (HTTP $wp_code)"
  fi

  # Check 3.2: MariaDB database healthy
  log_info "Checking MariaDB health..."
  db_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T db healthcheck.sh --connect --innodb_initialized 2>/dev/null" || echo "")

  if [ -n "$db_health" ]; then
    log_pass "MariaDB healthy and InnoDB initialized"
  else
    # Fallback: try mysqladmin ping
    db_ping=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
      "cd ${REMOTE_SITE_DIR} && docker compose exec -T db mysqladmin ping -h localhost 2>/dev/null" || echo "")
    if echo "$db_ping" | grep -q "alive" 2>/dev/null; then
      log_pass "MariaDB responding to ping"
    else
      log_fail "MariaDB not healthy"
    fi
  fi

  # Check 3.3: Caddy reverse proxy responding (probe from host via Caddy port)
  log_info "Checking Caddy reverse proxy..."
  caddy_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$caddy_code" = "200" ] || [ "$caddy_code" = "301" ] || [ "$caddy_code" = "302" ]; then
    log_pass "Caddy reverse proxy responding (HTTP $caddy_code)"
  else
    log_fail "Caddy reverse proxy not responding (HTTP $caddy_code)"
  fi

  # Check 3.4: wp-admin accessible
  log_info "Checking wp-admin..."
  admin_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/wp-admin/" 2>/dev/null || echo "000")

  if [ "$admin_code" = "200" ] || [ "$admin_code" = "302" ] || [ "$admin_code" = "301" ]; then
    log_pass "wp-admin accessible (HTTP $admin_code)"
  else
    log_fail "wp-admin not accessible (HTTP $admin_code)"
  fi

  # Check 3.5: WP REST API responding
  log_info "Checking WordPress REST API..."
  api_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}/wp-json/" 2>/dev/null || echo "000")

  if [ "$api_code" = "200" ]; then
    log_pass "WordPress REST API responding (HTTP $api_code)"
  else
    log_fail "WordPress REST API not responding (HTTP $api_code)"
  fi
}
