#!/usr/bin/env bash
# Enable DigitalOcean extended metrics agent on all droplets
# The do-agent is free and provides memory, disk, and load metrics in the DO dashboard
#
# Usage:
#   ./enable-do-agent.sh                  # all droplets tagged 'weown-ai'
#   ./enable-do-agent.sh anythingllm      # only droplets tagged 'anythingllm'
#
# Requires: doctl authenticated (doctl auth init), or DIGITALOCEAN_ACCESS_TOKEN set
# Compliance: NIST DE.CM, CIS 8.2
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}==>${NC} $*"; }
warn()    { echo -e "${YELLOW}WARN:${NC} $*"; }
die()     { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

check_doctl() {
  command -v doctl &>/dev/null || die "doctl not installed. brew install doctl"
  doctl account get &>/dev/null || die "doctl not authenticated. Run: doctl auth init"
}

TAG="${1:-weown-ai}"

check_doctl

mapfile -t IPS < <(doctl compute droplet list --tag-name "$TAG" --format PublicIPv4 --no-header | grep -v '^$')
[[ ${#IPS[@]} -eq 0 ]] && die "No droplets found with tag: $TAG"

echo -e "\n${BOLD}Enabling DO extended metrics on ${#IPS[@]} droplet(s) [tag=$TAG]${NC}\n"

INSTALLED=0
FAILED=0

for ip in "${IPS[@]}"; do
  name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
    | awk -v i="$ip" '$2 == i { print $1 }')
  echo -e "${BOLD}── $name ($ip) ──${NC}"

  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "root@${ip}" '
    if command -v do-agent &>/dev/null; then
      echo "ALREADY_INSTALLED"
      systemctl is-active --quiet do-agent && echo "STATUS: running" || echo "STATUS: not running"
    else
      echo "INSTALLING..."
      curl -sSL https://repos.insights.digitalocean.com/install.sh | bash
      systemctl enable do-agent 2>/dev/null || true
      systemctl start do-agent 2>/dev/null || true
      echo "INSTALLED"
    fi
  ' 2>/dev/null; then
    # Parse output to count
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "root@${ip}" \
      'command -v do-agent &>/dev/null && systemctl is-active --quiet do-agent && echo OK' 2>/dev/null | grep -q OK; then
      ((INSTALLED++)) || true
    fi
  else
    warn "Could not reach $ip"
    ((FAILED++)) || true
  fi
  echo ""
done

echo -e "${BOLD}Summary:${NC}"
info "Droplets with do-agent active: $INSTALLED / ${#IPS[@]}"
[[ $FAILED -gt 0 ]] && warn "Unreachable: $FAILED"
echo ""
info "Extended metrics (memory, disk, load) will appear in DO dashboard within ~5 minutes"
info "Cost: \$0 — completely free"
