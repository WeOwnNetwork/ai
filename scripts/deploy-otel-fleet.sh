#!/usr/bin/env bash
# Deploy OTel Collector agent to all droplets matching a tag
# Deploys compose.yaml + config.yaml to /opt/otel-agent/ on each host
#
# Usage:
#   ./deploy-otel-fleet.sh <tag> <signoz-private-ip>
#   ./deploy-otel-fleet.sh weown-ai 10.132.0.5
#
# The SigNoz private IP is the VPC address of your SigNoz droplet.
# Get it from: terraform output droplet_private_ip (in your signoz-docker site)
#
# Requires: doctl authenticated, SSH access to all droplets
# Compliance: NIST DE.CM, CIS 8.5
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}==>${NC} $*"; }
warn()    { echo -e "${YELLOW}WARN:${NC} $*"; }
die()     { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

check_doctl() {
  command -v doctl &>/dev/null || die "doctl not installed. brew install doctl"
  doctl account get &>/dev/null || die "doctl not authenticated. Run: doctl auth init"
}

TAG="${1:-}"
SIGNOZ_IP="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel-agent"

if [[ -z "$TAG" || -z "$SIGNOZ_IP" ]]; then
  echo "Usage: $0 <tag> <signoz-private-ip>"
  echo ""
  echo "Examples:"
  echo "  $0 weown-ai 10.132.0.5"
  echo "  $0 wordpress 10.132.0.5"
  echo "  $0 anythingllm 10.132.0.5"
  echo ""
  echo "Get the SigNoz private IP from:"
  echo "  cd <signoz-site>/terraform && tofu output droplet_private_ip"
  exit 1
fi

[[ -f "$OTEL_DIR/compose.yaml" ]] || die "otel-agent/compose.yaml not found at $OTEL_DIR"
[[ -f "$OTEL_DIR/config.yaml" ]]  || die "otel-agent/config.yaml not found at $OTEL_DIR"

check_doctl

mapfile -t IPS < <(doctl compute droplet list --tag-name "$TAG" --format PublicIPv4 --no-header | grep -v '^$')
[[ ${#IPS[@]} -eq 0 ]] && die "No droplets found with tag: $TAG"

echo -e "\n${BOLD}Deploying OTel agent to ${#IPS[@]} droplet(s) [tag=$TAG]${NC}"
echo -e "    SigNoz endpoint: ${SIGNOZ_IP}:4317\n"

SUCCESS=0
FAILED=0

for ip in "${IPS[@]}"; do
  name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
    | awk -v i="$ip" '$2 == i { print $1 }')
  echo -e "${BOLD}── $name ($ip) ──${NC}"

  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "root@${ip}" \
    "mkdir -p /opt/otel-agent" 2>/dev/null; then

    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      "$OTEL_DIR/compose.yaml" "root@${ip}:/opt/otel-agent/" 2>/dev/null
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      "$OTEL_DIR/config.yaml" "root@${ip}:/opt/otel-agent/" 2>/dev/null

    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "root@${ip}" "
      cd /opt/otel-agent && \
      HOSTNAME=\$(hostname) \
      SIGNOZ_ENDPOINT=${SIGNOZ_IP}:4317 \
      docker compose pull --quiet 2>/dev/null && \
      HOSTNAME=\$(hostname) \
      SIGNOZ_ENDPOINT=${SIGNOZ_IP}:4317 \
      docker compose up -d 2>/dev/null && \
      echo '  OTel agent running'
    " 2>/dev/null && ((SUCCESS++)) || { warn "Deploy failed on $ip"; ((FAILED++)); }
  else
    warn "Could not reach $ip"
    ((FAILED++))
  fi
  echo ""
done

echo -e "${BOLD}Summary:${NC}"
info "OTel agent deployed: $SUCCESS / ${#IPS[@]}"
[[ $FAILED -gt 0 ]] && warn "Failed: $FAILED"
echo ""
info "Verify in SigNoz UI: Infrastructure > Hosts"
info "Logs will appear in: Logs Explorer (filter by host.name)"
