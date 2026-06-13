#!/bin/sh
# SigNoz-specific smoke test hooks
#
# This file is sourced by smoke-test-framework.sh and provides
# application-specific checks for SigNoz deployments.
#
# Checks:
#   3.1: SigNoz health endpoint (/api/v1/health)
#   3.2: ClickHouse database responding
#   3.3: OTel Collector Gateway healthy
#   3.4: Zookeeper healthy
#   3.5: Caddy reverse proxy + SigNoz UI accessible

run_template_specific_checks() {
  log_info "Running SigNoz-specific checks..."

  # Check 3.1: SigNoz health endpoint
  log_info "Checking SigNoz health endpoint..."
  signoz_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T signoz wget -q --spider http://localhost:8080/api/v1/health 2>&1 && echo OK" || echo "")

  if echo "$signoz_health" | grep -q "OK" 2>/dev/null; then
    log_pass "SigNoz health endpoint OK"
  else
    log_fail "SigNoz health endpoint not responding"
  fi

  # Check 3.2: ClickHouse database responding
  log_info "Checking ClickHouse database..."
  ch_ping=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T clickhouse wget -q -O- http://localhost:8123/ping 2>/dev/null" || echo "")

  if echo "$ch_ping" | grep -q "Ok" 2>/dev/null; then
    log_pass "ClickHouse responding to ping"
  else
    log_fail "ClickHouse not responding"
  fi

  # Check 3.3: OTel Collector Gateway healthy
  log_info "Checking OTel Collector Gateway..."
  otel_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T otel-collector-gateway wget -q --spider http://localhost:13133/health 2>&1 && echo OK" || echo "")

  if echo "$otel_health" | grep -q "OK" 2>/dev/null; then
    log_pass "OTel Collector Gateway healthy"
  else
    log_fail "OTel Collector Gateway not healthy"
  fi

  # Check 3.4: Zookeeper healthy (matches compose healthcheck: echo ruok | nc localhost 2181 | grep -q imok)
  log_info "Checking Zookeeper..."
  zk_status=$(ssh -o ConnectTimeout=10 -o BatchMode=yes root@"${DROPLET_IP}" \
    "cd ${REMOTE_SITE_DIR} && docker compose exec -T zookeeper sh -c 'echo ruok | nc localhost 2181' 2>/dev/null" || echo "")

  if echo "$zk_status" | grep -q "imok" 2>/dev/null; then
    log_pass "Zookeeper healthy"
  else
    log_fail "Zookeeper not responding"
  fi

  # Check 3.5: SigNoz UI accessible via Caddy
  log_info "Checking SigNoz UI via Caddy..."
  ui_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DROPLET_IP}" 2>/dev/null || echo "000")

  if [ "$ui_code" = "200" ] || [ "$ui_code" = "301" ] || [ "$ui_code" = "302" ]; then
    log_pass "SigNoz UI accessible via Caddy (HTTP $ui_code)"
  else
    log_fail "SigNoz UI not accessible via Caddy (HTTP $ui_code)"
  fi
}
