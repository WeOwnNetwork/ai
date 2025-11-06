#!/bin/bash

# Check DNS propagation for all Yonks domains
# Tests from multiple DNS servers to identify propagation issues

set -euo pipefail

DOMAINS=(
    "yonksteam.xyz"
    "ai.yonksteam.xyz"
    "matomo.yonksteam.xyz"
    "n8n.yonksteam.xyz"
    "vault.yonksteam.xyz"
)

EXPECTED_IP="134.199.133.94"

# DNS servers to test from
DNS_SERVERS=(
    "8.8.8.8"      # Google DNS
    "1.1.1.1"      # Cloudflare DNS
    "208.67.222.222"  # OpenDNS
    "9.9.9.9"      # Quad9
)

log_info() {
    echo -e "\033[0;36m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[OK]\033[0m $1"
}

log_warning() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

echo "=========================================="
echo "DNS Propagation Check - Yonks Domains"
echo "=========================================="
echo
echo "Expected IP: $EXPECTED_IP"
echo "Testing from multiple DNS servers..."
echo

for domain in "${DOMAINS[@]}"; do
    echo "----------------------------------------"
    log_info "Checking: $domain"
    echo "----------------------------------------"
    
    all_correct=true
    
    for dns_server in "${DNS_SERVERS[@]}"; do
        if command -v nslookup &> /dev/null; then
            result=$(nslookup "$domain" "$dns_server" 2>/dev/null | grep -A 1 "Name:" | tail -1 | awk '{print $2}' || echo "")
        elif command -v dig &> /dev/null; then
            result=$(dig +short "@$dns_server" "$domain" A 2>/dev/null | head -1 || echo "")
        else
            log_error "Neither nslookup nor dig found. Install one to use this script."
            exit 1
        fi
        
        if [[ -z "$result" ]]; then
            log_warning "$dns_server: No response"
            all_correct=false
        elif [[ "$result" == "$EXPECTED_IP" ]]; then
            log_success "$dns_server: $result ✓"
        else
            log_error "$dns_server: $result ✗ (Expected: $EXPECTED_IP)"
            all_correct=false
        fi
    done
    
    if [[ "$all_correct" == true ]]; then
        log_success "$domain: All DNS servers return correct IP"
    else
        log_error "$domain: Some DNS servers return incorrect IP"
    fi
    
    echo
done

echo "=========================================="
echo "Summary"
echo "=========================================="
echo
echo "If any domain shows incorrect IP from some DNS servers:"
echo "  → This indicates DNS propagation issue"
echo "  → Solution: Use Google DNS (8.8.8.8) or Cloudflare DNS (1.1.1.1)"
echo "  → Or wait 24-48 hours for full propagation"
echo
echo "If all domains show correct IP from all DNS servers:"
echo "  → DNS is properly propagated"
echo "  → Issue might be browser cache or ISP-level blocking"
echo

