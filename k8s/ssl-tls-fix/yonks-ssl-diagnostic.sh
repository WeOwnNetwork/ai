#!/bin/bash

# Yonks Cluster SSL/TLS Diagnostic Script
# Diagnoses SSL handshake failures and load balancer conflicts
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
CLUSTER_NAME="pb1-yonksteam-academy-k8s-pool"
APP_LOAD_BALANCER_ID="cbc86166-2cf0-46b5-a21f-d53d9066a87f"
OLD_LOAD_BALANCER_ID="124b7cc4-1249-430c-9303-4b3e399df2b3"
APP_LOAD_BALANCER_IP="134.199.133.94"
OLD_LOAD_BALANCER_IP="134.199.132.124"

# Domains to test
DOMAINS=(
    "yonksteam.xyz"
    "ai.yonksteam.xyz"
    "matomo.yonksteam.xyz"
    "n8n.yonksteam.xyz"
    "vault.yonksteam.xyz"
)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo "=========================================="
echo "Yonks Cluster SSL/TLS Diagnostic"
echo "=========================================="
echo

# Step 1: Verify cluster context
log_step "1. Verifying Kubernetes cluster context..."
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CURRENT_CONTEXT" == *"yonksteam"* ]] || [[ "$CURRENT_CONTEXT" == *"yonks"* ]]; then
    log_success "Cluster context: $CURRENT_CONTEXT"
else
    log_warning "Current context '$CURRENT_CONTEXT' may not be Yonks cluster"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi
echo

# Step 2: Check ingress-nginx pods
log_step "2. Checking ingress-nginx deployment..."
INGRESS_NAMESPACE=$(kubectl get namespace -o name | grep -E "ingress|nginx" | head -1 | cut -d/ -f2 || echo "ingress-nginx")
INGRESS_PODS=$(kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ "$INGRESS_PODS" -gt 0 ]]; then
    log_success "Found $INGRESS_PODS ingress-nginx pod(s)"
    kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx
else
    log_error "No ingress-nginx pods found in namespace '$INGRESS_NAMESPACE'"
    log_info "Checking alternative namespaces..."
    kubectl get pods --all-namespaces -l app.kubernetes.io/name=ingress-nginx
fi
echo

# Step 3: Check NGINX logs for SSL errors
log_step "3. Checking NGINX logs for SSL errors..."
if [[ "$INGRESS_PODS" -gt 0 ]]; then
    INGRESS_POD=$(kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$INGRESS_POD" ]]; then
        log_info "Checking logs for pod: $INGRESS_POD"
        SSL_ERRORS=$(kubectl logs -n "$INGRESS_NAMESPACE" "$INGRESS_POD" --tail=100 2>/dev/null | grep -i "SSL\|TLS\|handshake\|error:0A00010B" || true)
        if [[ -n "$SSL_ERRORS" ]]; then
            log_error "Found SSL errors in logs:"
            echo "$SSL_ERRORS" | head -10
        else
            log_success "No recent SSL errors found in logs"
        fi
    fi
fi
echo

# Step 4: Check ingress resources
log_step "4. Checking ingress resources..."
INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "Found $INGRESS_COUNT ingress resource(s)"
echo

# Check each domain's ingress
for domain in "${DOMAINS[@]}"; do
    log_info "Checking ingress for: $domain"
    if command -v jq &> /dev/null; then
        INGRESS=$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq -r ".items[] | select(.spec.rules[]?.host == \"$domain\") | \"\(.metadata.namespace)/\(.metadata.name)\"" || echo "")
        if [[ -n "$INGRESS" ]]; then
            log_success "  Found: $INGRESS"
            # Check TLS configuration
            TLS_HOSTS=$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq -r ".items[] | select(.spec.rules[]?.host == \"$domain\") | .spec.tls[]?.hosts[]?" || echo "")
            if echo "$TLS_HOSTS" | grep -q "$domain"; then
                log_success "  TLS configured for $domain"
            else
                log_warning "  TLS not configured for $domain"
            fi
        else
            log_warning "  No ingress found for $domain"
        fi
    else
        INGRESS=$(kubectl get ingress --all-namespaces -o yaml 2>/dev/null | grep -A 5 "host: $domain" || echo "")
        if [[ -n "$INGRESS" ]]; then
            log_success "  Found ingress for $domain (using yaml output)"
        else
            log_warning "  No ingress found for $domain"
        fi
    fi
done
echo

# Step 5: Test SSL connectivity
log_step "5. Testing SSL/TLS connectivity..."
for domain in "${DOMAINS[@]}"; do
    log_info "Testing $domain..."
    
    # Test HTTPS
    if command -v openssl &> /dev/null; then
        SSL_TEST=$(timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>&1 | grep -E "Verify return code|SSL handshake|CONNECTED" || echo "FAILED")
        if echo "$SSL_TEST" | grep -q "CONNECTED"; then
            log_success "  HTTPS connection successful"
        else
            log_error "  HTTPS connection failed"
            echo "    $SSL_TEST"
        fi
    else
        log_warning "  openssl not available, skipping SSL test"
    fi
    
    # Test HTTP redirect
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L "http://$domain" 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" == "301" ]] || [[ "$HTTP_STATUS" == "302" ]] || [[ "$HTTP_STATUS" == "308" ]]; then
        log_success "  HTTP redirect working (status: $HTTP_STATUS)"
    elif [[ "$HTTP_STATUS" == "200" ]]; then
        log_warning "  HTTP not redirecting to HTTPS (status: $HTTP_STATUS)"
    else
        log_error "  HTTP connection failed (status: $HTTP_STATUS)"
    fi
done
echo

# Step 6: Check Load Balancer services
log_step "6. Checking Load Balancer services..."
if command -v jq &> /dev/null; then
    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name) - \(.status.loadBalancer.ingress[0].ip // "pending")"' || echo "")
else
    LB_SERVICES=$(kubectl get svc --all-namespaces -o wide 2>/dev/null | grep LoadBalancer || echo "")
fi
if [[ -n "$LB_SERVICES" ]]; then
    log_info "Load Balancer services found:"
    echo "$LB_SERVICES"
    LB_COUNT=$(echo "$LB_SERVICES" | wc -l | tr -d ' ')
    if [[ "$LB_COUNT" -gt 1 ]]; then
        log_warning "Multiple Load Balancers detected - this may cause routing conflicts"
    fi
else
    log_warning "No Load Balancer services found"
fi
echo

# Step 7: Check cert-manager certificates
log_step "7. Checking TLS certificates..."
CERT_COUNT=0
for domain in "${DOMAINS[@]}"; do
    if command -v jq &> /dev/null; then
        CERT=$(kubectl get certificate --all-namespaces -o json 2>/dev/null | jq -r ".items[] | select(.spec.dnsNames[]? == \"$domain\") | \"\(.metadata.namespace)/\(.metadata.name) - \(.status.conditions[]? | select(.type == \"Ready\") | .status)\"" || echo "")
    else
        CERT=$(kubectl get certificate --all-namespaces -o yaml 2>/dev/null | grep -A 10 "dnsNames:" | grep "$domain" || echo "")
        if [[ -n "$CERT" ]]; then
            CERT=$(kubectl get certificate --all-namespaces 2>/dev/null | grep "$domain" || echo "")
        fi
    fi
    if [[ -n "$CERT" ]]; then
        if echo "$CERT" | grep -q "True\|Ready"; then
            log_success "  $domain: Certificate ready"
        else
            log_warning "  $domain: Certificate not ready"
            echo "    $CERT"
        fi
        ((CERT_COUNT++))
    else
        log_warning "  $domain: No certificate found"
    fi
done
echo

# Step 8: Summary and recommendations
log_step "8. Summary and Recommendations"
echo "=========================================="
echo "Diagnostic Summary:"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Current Context: $CURRENT_CONTEXT"
echo "Ingress Pods: $INGRESS_PODS"
echo "Ingress Resources: $INGRESS_COUNT"
echo "Certificates Checked: $CERT_COUNT"
echo

# Check for dual load balancer issue
if [[ -n "$LB_SERVICES" ]]; then
    LB_WITH_APP_IP=$(echo "$LB_SERVICES" | grep "$APP_LOAD_BALANCER_IP" || true)
    LB_WITH_OLD_IP=$(echo "$LB_SERVICES" | grep "$OLD_LOAD_BALANCER_IP" || true)
    
    if [[ -n "$LB_WITH_OLD_IP" ]]; then
        log_error "DETECTED: Old Load Balancer still active ($OLD_LOAD_BALANCER_IP)"
        log_error "This is causing routing conflicts!"
        echo
        log_info "RECOMMENDED ACTION:"
        log_info "1. Remove old Load Balancer: $OLD_LOAD_BALANCER_ID"
        log_info "2. Verify only app Load Balancer remains: $APP_LOAD_BALANCER_ID"
        log_info "3. Restart ingress-nginx pods"
        log_info "4. Re-run this diagnostic to verify fix"
    fi
fi

echo
log_info "Next steps:"
log_info "1. Review the diagnostic output above"
log_info "2. If dual load balancer detected, run: ./yonks-ssl-fix.sh"
log_info "3. After fixes, re-run this diagnostic to verify"
echo

