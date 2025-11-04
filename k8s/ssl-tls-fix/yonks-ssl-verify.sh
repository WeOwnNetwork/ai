#!/bin/bash

# Yonks Cluster SSL/TLS Verification Script
# Purpose: Comprehensive verification of SSL/TLS functionality after fixes
# Cluster: pb1-yonksteam-academy-k8s-pool

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DOMAINS=(
    "yonksteam.xyz"
    "ai.yonksteam.xyz"
    "matomo.yonksteam.xyz"
    "n8n.yonksteam.xyz"
    "vault.yonksteam.xyz"
)

APP_LOAD_BALANCER_IP="134.199.133.94"
OLD_LOAD_BALANCER_IP="134.199.132.124"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Test results tracking
PASSED=0
FAILED=0
WARNINGS=0

test_pass() {
    log_success "$1"
    ((PASSED++))
}

test_fail() {
    log_error "$1"
    ((FAILED++))
}

test_warn() {
    log_warning "$1"
    ((WARNINGS++))
}

echo "=========================================="
echo "Yonks Cluster SSL/TLS Verification"
echo "=========================================="
echo

# Test 1: Load Balancer check
log_step "Test 1: Load Balancer Configuration"
if command -v jq &> /dev/null; then
    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[0].ip' || echo "")
else
    LB_SERVICES=$(kubectl get svc --all-namespaces -o wide 2>/dev/null | grep LoadBalancer | awk '{print $5}' || echo "")
fi

OLD_LB_FOUND=$(echo "$LB_SERVICES" | grep -c "$OLD_LOAD_BALANCER_IP" || echo "0")
APP_LB_FOUND=$(echo "$LB_SERVICES" | grep -c "$APP_LOAD_BALANCER_IP" || echo "0")

if [[ "$OLD_LB_FOUND" -eq 0 ]]; then
    test_pass "Old Load Balancer ($OLD_LOAD_BALANCER_IP) not found"
else
    test_fail "Old Load Balancer still active: $OLD_LB_FOUND service(s) using it"
fi

if [[ "$APP_LB_FOUND" -gt 0 ]]; then
    test_pass "App Load Balancer ($APP_LOAD_BALANCER_IP) active: $APP_LB_FOUND service(s)"
else
    test_fail "App Load Balancer not found!"
fi
echo

# Test 2: Certificate validity
log_step "Test 2: TLS Certificate Validity"
for domain in "${DOMAINS[@]}"; do
    if command -v openssl &> /dev/null; then
        CERT_INFO=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>&1 | grep -A 5 "Certificate chain" || echo "")
        
        if echo "$CERT_INFO" | grep -q "CONNECTED"; then
            # Check certificate expiration
            CERT_EXPIRY=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>&1 | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
            
            if [[ -n "$CERT_EXPIRY" ]]; then
                EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || echo "0")
                NOW_EPOCH=$(date +%s)
                DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
                
                if [[ "$DAYS_UNTIL_EXPIRY" -gt 30 ]]; then
                    test_pass "$domain: Certificate valid (expires in $DAYS_UNTIL_EXPIRY days)"
                elif [[ "$DAYS_UNTIL_EXPIRY" -gt 0 ]]; then
                    test_warn "$domain: Certificate expires in $DAYS_UNTIL_EXPIRY days"
                else
                    test_fail "$domain: Certificate expired!"
                fi
            else
                test_warn "$domain: Could not verify certificate expiry"
            fi
        else
            test_fail "$domain: SSL connection failed"
        fi
    else
        test_warn "openssl not available, skipping certificate check"
    fi
done
echo

# Test 3: HTTP to HTTPS redirect
log_step "Test 3: HTTP to HTTPS Redirect"
for domain in "${DOMAINS[@]}"; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L -m 10 "http://$domain" 2>/dev/null || echo "000")
    HTTP_LOCATION=$(curl -s -o /dev/null -w "%{redirect_url}" -L -m 10 "http://$domain" 2>/dev/null || echo "")
    
    if [[ "$HTTP_STATUS" == "301" ]] || [[ "$HTTP_STATUS" == "302" ]] || [[ "$HTTP_STATUS" == "308" ]]; then
        if echo "$HTTP_LOCATION" | grep -q "https"; then
            test_pass "$domain: HTTP redirects to HTTPS (status: $HTTP_STATUS)"
        else
            test_warn "$domain: HTTP redirects but not to HTTPS"
        fi
    elif [[ "$HTTP_STATUS" == "200" ]]; then
        test_fail "$domain: HTTP not redirecting to HTTPS (status: $HTTP_STATUS)"
    else
        test_warn "$domain: HTTP test inconclusive (status: $HTTP_STATUS)"
    fi
done
echo

# Test 4: SSL/TLS protocol support
log_step "Test 4: SSL/TLS Protocol Support"
for domain in "${DOMAINS[@]}"; do
    if command -v openssl &> /dev/null; then
        TLS_VERSION=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" -tls1_3 </dev/null 2>&1 | grep "Protocol" | awk '{print $3}' || echo "")
        
        if echo "$TLS_VERSION" | grep -q "TLSv1.3"; then
            test_pass "$domain: TLS 1.3 supported"
        else
            TLS_VERSION_12=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" -tls1_2 </dev/null 2>&1 | grep "Protocol" | awk '{print $3}' || echo "")
            if echo "$TLS_VERSION_12" | grep -q "TLSv1.2"; then
                test_warn "$domain: Only TLS 1.2 supported (TLS 1.3 preferred)"
            else
                test_fail "$domain: TLS 1.2/1.3 not supported"
            fi
        fi
    fi
done
echo

# Test 5: NGINX logs - SSL errors
log_step "Test 5: NGINX SSL Error Check"
INGRESS_NAMESPACE=$(kubectl get namespace -o name | grep -E "ingress|nginx" | head -1 | cut -d/ -f2 || echo "ingress-nginx")
INGRESS_POD=$(kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$INGRESS_POD" ]]; then
    SSL_ERROR_COUNT=$(kubectl logs -n "$INGRESS_NAMESPACE" "$INGRESS_POD" --tail=200 --since=10m 2>/dev/null | grep -ic "SSL\|TLS\|handshake\|error:0A00010B" || echo "0")
    
    if [[ "$SSL_ERROR_COUNT" -eq 0 ]]; then
        test_pass "No SSL errors in NGINX logs (last 10 minutes)"
    else
        test_fail "$SSL_ERROR_COUNT SSL error(s) found in NGINX logs"
        log_info "Recent errors:"
        kubectl logs -n "$INGRESS_NAMESPACE" "$INGRESS_POD" --tail=200 --since=10m 2>/dev/null | grep -i "SSL\|TLS\|handshake\|error:0A00010B" | tail -5
    fi
else
    test_warn "Could not find ingress-nginx pod to check logs"
fi
echo

# Test 6: Application accessibility
log_step "Test 6: Application Accessibility"
for domain in "${DOMAINS[@]}"; do
    HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k -m 10 "https://$domain" 2>/dev/null || echo "000")
    
    if [[ "$HTTPS_STATUS" == "200" ]] || [[ "$HTTPS_STATUS" == "301" ]] || [[ "$HTTPS_STATUS" == "302" ]]; then
        test_pass "$domain: Application accessible via HTTPS (status: $HTTPS_STATUS)"
    elif [[ "$HTTPS_STATUS" == "401" ]] || [[ "$HTTPS_STATUS" == "403" ]]; then
        test_warn "$domain: Application accessible but requires authentication (status: $HTTPS_STATUS)"
    elif [[ "$HTTPS_STATUS" == "000" ]]; then
        test_fail "$domain: Connection failed"
    else
        test_warn "$domain: Unexpected status: $HTTPS_STATUS"
    fi
done
echo

# Final summary
log_step "Verification Summary"
echo "=========================================="
echo "Tests Passed:  $PASSED"
echo "Tests Failed:  $FAILED"
echo "Warnings:      $WARNINGS"
echo "=========================================="
echo

if [[ "$FAILED" -eq 0 ]]; then
    log_success "All critical tests passed!"
    log_info "SSL/TLS is functioning correctly"
    if [[ "$WARNINGS" -gt 0 ]]; then
        log_info "Review warnings above for optimization opportunities"
    fi
    exit 0
elif [[ "$FAILED" -le 2 ]]; then
    log_warning "Most tests passed, but some issues remain"
    log_info "Review failed tests above"
    exit 1
else
    log_error "Multiple test failures detected"
    log_info "SSL/TLS fix may not be complete"
    log_info "Please review all failures and re-run fix script if needed"
    exit 2
fi

