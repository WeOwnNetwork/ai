#!/usr/bin/env bash
# create-signoz-oom-alert.sh — fleet-wide SigNoz alert for container memcg OOM kills
#
# Why: DO droplet monitor alerts (CPU/memory/disk, see each site's
# monitoring.tf) watch HOST-level metrics and cannot see a cgroup-level OOM
# kill — when INT-S004's AnythingLLM container was memcg-OOM-killed on
# 2026-06-10 (container hit its compose memory limit), host RAM was fine and
# nothing paged. The kernel logs one unambiguous line per kill to syslog,
# which the fleet otel-agent already ships to SigNoz:
#
#   kernel: Memory cgroup out of memory: Killed process <pid> (<comm>) ...
#
# This script creates ONE fleet-wide log-based alert on that line (no host
# filter — any weown-ai droplet that OOM-kills a container fires it).
#
# Usage:
#   export SIGNOZ_BASE_URL="https://<your-workspace>.<region>.signoz.cloud"   # no trailing slash
#   read -rs "SIGNOZ_API_KEY?Paste SigNoz API key: " && export SIGNOZ_API_KEY  # zsh
#   # bash equivalent: read -rsp "Paste SigNoz API key: " SIGNOZ_API_KEY && export SIGNOZ_API_KEY
#   ./scripts/create-signoz-oom-alert.sh
#
# The API key comes from SigNoz → Settings → API Keys (Admin role to manage
# rules). Keep it off argv and out of files; the env-only pattern above is the
# repo standard.
#
# Idempotent: if a rule with the same alert name already exists, the script
# exits 0 without creating a duplicate.
#
# Schema note: the payload targets the SigNoz builder-query alert schema
# ("version": "v4", logs datasource). If your SigNoz version rejects it
# (HTTP 400), create the rule in the UI instead — it is small:
#   Alerts → New Alert → Log-based Alert
#   Query A: count of log lines WHERE body CONTAINS
#            "Memory cgroup out of memory: Killed process"
#   Condition: A > 0 in the last 5 minutes, evaluate every 1 minute
#   Severity: critical; route to your ops notification channel.
set -euo pipefail

: "${SIGNOZ_BASE_URL:?Set SIGNOZ_BASE_URL (e.g. https://<workspace>.<region>.signoz.cloud — SigNoz UI base URL, no trailing slash)}"
: "${SIGNOZ_API_KEY:?Set SIGNOZ_API_KEY (SigNoz → Settings → API Keys; export via read -rs, never on argv)}"

ALERT_NAME="Fleet: container memcg OOM kill"
RULES_URL="${SIGNOZ_BASE_URL}/api/v1/rules"

# Keep the API key OFF argv (a plain -H "...key..." shows in `ps`/audit logs):
# pass it through a curl config file created with mktemp (mode 600), and hold
# the API response body in a second temp file. Both trap-cleaned on exit —
# matches the repo's mktemp+trap convention, no secret on argv or in /tmp.
SIGNOZ_CURL_CFG="$(mktemp)"
SIGNOZ_RESP="$(mktemp)"
trap 'rm -f "$SIGNOZ_CURL_CFG" "$SIGNOZ_RESP"' EXIT
printf 'header = "SIGNOZ-API-KEY: %s"\n' "$SIGNOZ_API_KEY" > "$SIGNOZ_CURL_CFG"

# --- Idempotency check ------------------------------------------------------
existing="$(curl -fsS -K "$SIGNOZ_CURL_CFG" "$RULES_URL" || true)"
if printf '%s' "$existing" | grep -Fq "$ALERT_NAME"; then
  echo "==> Alert rule already exists: '${ALERT_NAME}' — nothing to do."
  exit 0
fi

# --- Create the rule ---------------------------------------------------------
# Matches the exact kernel memcg-kill line. One hit in any 5m window fires.
# preferredChannels [] = route to all configured notification channels; pin a
# channel name in the array to scope it.
payload="$(cat <<'JSON'
{
  "alert": "Fleet: container memcg OOM kill",
  "alertType": "LOGS_BASED_ALERT",
  "ruleType": "threshold_rule",
  "evalWindow": "5m0s",
  "frequency": "1m0s",
  "condition": {
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "graph",
      "builderQueries": {
        "A": {
          "queryName": "A",
          "dataSource": "logs",
          "aggregateOperator": "count",
          "aggregateAttribute": {},
          "expression": "A",
          "disabled": false,
          "stepInterval": 60,
          "filters": {
            "op": "AND",
            "items": [
              {
                "key": { "key": "body", "dataType": "string", "isColumn": true, "type": "" },
                "op": "contains",
                "value": "Memory cgroup out of memory: Killed process"
              }
            ]
          }
        }
      }
    },
    "op": ">",
    "target": 0,
    "matchType": "1"
  },
  "labels": { "severity": "critical", "team": "weown-ai" },
  "annotations": {
    "summary": "A container on {{$labels.host_name}} was OOM-killed by the kernel (memcg limit hit).",
    "description": "The kernel logged 'Memory cgroup out of memory: Killed process' on a fleet droplet. The container hit its docker compose memory limit and was killed (exit 137); docker auto-restarts it, but in-flight requests died and app config/state should be verified. Runbook: anythingllm-docker/sites/<site>/RESIZE_RUNBOOK.md (phase 5 bounce-verification applies). Incident reference: INT-S004 2026-06-10 01:00 MT."
  },
  "preferredChannels": [],
  "version": "v4",
  "source": "weown-ai-repo/scripts/create-signoz-oom-alert.sh"
}
JSON
)"

echo "==> Creating alert rule '${ALERT_NAME}' at ${RULES_URL} ..."
http_code="$(curl -sS -o "$SIGNOZ_RESP" -w '%{http_code}' \
  -X POST "$RULES_URL" \
  -K "$SIGNOZ_CURL_CFG" \
  -H "Content-Type: application/json" \
  --data "$payload")"

if [[ "$http_code" =~ ^2 ]]; then
  echo "==> Created (HTTP ${http_code}). Verify in the UI: Alerts → '${ALERT_NAME}',"
  echo "    then confirm it routes to a real notification channel (Settings → Channels)."
else
  echo "ERROR: SigNoz API returned HTTP ${http_code}:" >&2
  cat "$SIGNOZ_RESP" >&2 || true
  echo "" >&2
  echo "Your SigNoz version may use a different rule schema — create the rule" >&2
  echo "via the UI recipe in this script's header comment instead." >&2
  exit 1
fi
