#!/usr/bin/env bash
# Verify tofu plan does not contain destructive changes
# Usage: ./verify-plan-safety.sh <plan-file>
#
# Exits with error if plan contains droplet or reserved IP replacement.
# Compliance: NIST PR.IP, CIS 4.1, ISO A.8.32, SOC 2 CC8.1
set -euo pipefail

PLAN_FILE="${1:-}"

if [[ -z "$PLAN_FILE" ]]; then
  echo "Usage: $0 <plan-file>"
  echo ""
  echo "Example:"
  echo "  tofu plan -out=sso.plan"
  echo "  $0 sso.plan"
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Error: Plan file not found: $PLAN_FILE"
  exit 1
fi

echo "==================================================================="
echo "  Terraform Plan Safety Check"
echo "  Plan: $PLAN_FILE"
echo "==================================================================="
echo ""

# Check if jq is available
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required for plan analysis"
  echo "Install: brew install jq  (macOS)  or  apt install jq  (Linux)"
  exit 1
fi

# Convert plan to JSON for analysis
PLAN_JSON=$(mktemp)
trap 'rm -f "$PLAN_JSON"' EXIT

echo "==> Converting plan to JSON..."
tofu show -json "$PLAN_FILE" > "$PLAN_JSON" 2>/dev/null || {
  echo "Error: Failed to convert plan to JSON"
  exit 1
}

ERRORS=0

# Check for droplet replacement (destructive)
echo "==> Checking for droplet replacement..."
DROPPLET_CHANGES=$(jq -r '.resource_changes[]? | select(.type == "digitalocean_droplet") | "\(.address): \(.change.actions | join(", "))"' "$PLAN_JSON" 2>/dev/null || true)

if echo "$DROPPLET_CHANGES" | grep -q "delete"; then
  echo "  ❌ CRITICAL: Plan contains droplet replacement (delete+create)"
  echo "     Affected resources:"
  echo "$DROPPLET_CHANGES" | grep "delete" | sed 's/^/       /'
  echo ""
  echo "     STOP — Do not apply. Investigate lifecycle blocks."
  echo "     The cloud-init user_data change should be ignored via:"
  echo "       lifecycle { ignore_changes = [user_data] }"
  ((ERRORS++))
else
  echo "  ✅ No droplet replacement detected"
fi

# Check for reserved IP replacement
echo "==> Checking for reserved IP replacement..."
IP_CHANGES=$(jq -r '.resource_changes[]? | select(.type == "digitalocean_reserved_ip") | "\(.address): \(.change.actions | join(", "))"' "$PLAN_JSON" 2>/dev/null || true)

if echo "$IP_CHANGES" | grep -q "delete"; then
  echo "  ❌ CRITICAL: Plan contains reserved IP replacement"
  echo "     Affected resources:"
  echo "$IP_CHANGES" | grep "delete" | sed 's/^/       /'
  ((ERRORS++))
else
  echo "  ✅ No reserved IP replacement detected"
fi

# Check for firewall replacement
echo "==> Checking for firewall replacement..."
FW_CHANGES=$(jq -r '.resource_changes[]? | select(.type == "digitalocean_firewall") | "\(.address): \(.change.actions | join(", "))"' "$PLAN_JSON" 2>/dev/null || true)

if echo "$FW_CHANGES" | grep -q "delete"; then
  echo "  ⚠️  WARNING: Plan contains firewall replacement"
  echo "     This is usually safe but will cause brief network interruption"
  echo "     Affected resources:"
  echo "$FW_CHANGES" | grep "delete" | sed 's/^/       /'
else
  echo "  ✅ No firewall replacement detected"
fi

# Summary of all changes
echo ""
echo "==> Summary of all planned changes:"
ALL_CHANGES=$(jq -r '.resource_changes[]? | "\(.address): \(.change.actions | join(", "))"' "$PLAN_JSON" 2>/dev/null || true)

if [[ -z "$ALL_CHANGES" ]]; then
  echo "  No changes planned"
else
  echo "$ALL_CHANGES" | while read -r line; do
    if echo "$line" | grep -q "delete"; then
      echo "  ❌ $line"
    elif echo "$line" | grep -q "create"; then
      echo "  🟢 $line"
    elif echo "$line" | grep -q "update"; then
      echo "  🟡 $line"
    else
      echo "  ⚪ $line"
    fi
  done
fi

echo ""
echo "==================================================================="
echo "  Safety Check Complete"
echo "==================================================================="

if [[ $ERRORS -gt 0 ]]; then
  echo "  Status: ❌ FAILED — Destructive changes detected"
  echo "  Do NOT apply this plan without investigation."
  exit 1
else
  echo "  Status: ✅ PASSED — No destructive changes"
  echo "  Plan is safe for human review."
  exit 0
fi
