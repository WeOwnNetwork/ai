#!/bin/bash

# Yonks Cluster SSL/TLS Fix Script
# Fixes SSL handshake failures by removing old load balancer
# Cluster: pb1-yonksteam-academy-k8s-pool
# WARNING: Makes infrastructure changes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="pb1-yonksteam-academy-k8s-pool"
APP_LOAD_BALANCER_ID="cbc86166-2cf0-46b5-a21f-d53d9066a87f"
OLD_LOAD_BALANCER_ID="124b7cc4-1249-430c-9303-4b3e399df2b3"
APP_LOAD_BALANCER_IP="134.199.133.94"
OLD_LOAD_BALANCER_IP="134.199.132.124"

# Domains to verify
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
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

echo "=========================================="
echo "Yonks Cluster SSL/TLS Fix Script"
echo "=========================================="
echo
log_warning "This script will make infrastructure changes!"
log_warning "Please ensure you have:"
log_warning "1. Backed up all configurations"
log_warning "2. Verified cluster access"
log_warning "3. DigitalOcean API access for LB removal"
echo

read -p "Continue with SSL/TLS fix? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Aborted by user"
    exit 0
fi
echo

# Step 1: Pre-flight checks
log_step "1. Pre-flight checks..."

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi
log_success "kubectl found"

# Check doctl (DigitalOcean CLI)
if ! command -v doctl &> /dev/null; then
    log_warning "doctl not found. Load balancer removal will need to be done manually via DO console."
    log_info "Install doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/"
    MANUAL_LB_REMOVAL=true
else
    log_success "doctl found"
    MANUAL_LB_REMOVAL=false
fi

# Verify cluster context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
log_info "Current cluster context: $CURRENT_CONTEXT"
if [[ ! "$CURRENT_CONTEXT" == *"yonksteam"* ]] && [[ ! "$CURRENT_CONTEXT" == *"yonks"* ]]; then
    log_warning "Context doesn't match Yonks cluster pattern"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi
echo

# Step 2: Identify Load Balancer services
log_step "2. Identifying Load Balancer services..."
if command -v jq &> /dev/null; then
    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name) - \(.status.loadBalancer.ingress[0].ip // "pending")"' || echo "")
else
    LB_SERVICES=$(kubectl get svc --all-namespaces -o wide 2>/dev/null | grep LoadBalancer || echo "")
fi

if [[ -z "$LB_SERVICES" ]]; then
    log_error "No Load Balancer services found in cluster"
    exit 1
fi

log_info "Found Load Balancer services:"
echo "$LB_SERVICES"
echo

# Check if old LB IP is still referenced
OLD_LB_SERVICE=$(echo "$LB_SERVICES" | grep "$OLD_LOAD_BALANCER_IP" || echo "")
if [[ -z "$OLD_LB_SERVICE" ]]; then
    log_success "Old Load Balancer IP ($OLD_LOAD_BALANCER_IP) not found in Kubernetes services"
    log_info "The service may have been cleaned up, but the DO Load Balancer might still exist"
else
    log_warning "Found service with old LB IP: $OLD_LB_SERVICE"
    log_info "This service may need to be updated or removed"
fi
echo

# Step 3: Remove old Load Balancer from DigitalOcean
log_step "3. Removing old Load Balancer from DigitalOcean..."

if [[ "$MANUAL_LB_REMOVAL" == "false" ]]; then
    log_info "Attempting to remove Load Balancer: $OLD_LOAD_BALANCER_ID"
    
    # Check if LB exists
    if doctl compute load-balancer get "$OLD_LOAD_BALANCER_ID" &>/dev/null; then
        log_warning "Old Load Balancer found: $OLD_LOAD_BALANCER_ID"
        log_info "IP: $OLD_LOAD_BALANCER_IP"
        
        # Get LB details
        if command -v jq &> /dev/null; then
            LB_NAME=$(doctl compute load-balancer get "$OLD_LOAD_BALANCER_ID" -o json | jq -r '.[0].name' || echo "unknown")
        else
            LB_NAME=$(doctl compute load-balancer get "$OLD_LOAD_BALANCER_ID" -o text 2>/dev/null | grep -i "name" | awk '{print $2}' || echo "unknown")
        fi
        log_info "Name: $LB_NAME"
        
        read -p "Delete this Load Balancer? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deleting Load Balancer..."
            if doctl compute load-balancer delete "$OLD_LOAD_BALANCER_ID" -f; then
                log_success "Load Balancer deleted successfully"
            else
                log_error "Failed to delete Load Balancer"
                log_info "Please delete manually via DigitalOcean console"
                exit 1
            fi
        else
            log_info "Skipping Load Balancer deletion"
        fi
    else
        log_success "Old Load Balancer not found (may already be deleted)"
    fi
else
    log_warning "MANUAL ACTION REQUIRED:"
    log_info "1. Go to DigitalOcean Console"
    log_info "2. Navigate to Networking > Load Balancers"
    log_info "3. Find Load Balancer ID: $OLD_LOAD_BALANCER_ID"
    log_info "4. Delete the Load Balancer"
    log_info "5. Wait for deletion to complete (2-5 minutes)"
    echo
    read -p "Press Enter after deleting the Load Balancer..."
fi
echo

# Step 4: Verify app Load Balancer is healthy
log_step "4. Verifying app Load Balancer..."
if [[ "$MANUAL_LB_REMOVAL" == "false" ]]; then
    if doctl compute load-balancer get "$APP_LOAD_BALANCER_ID" &>/dev/null; then
        if command -v jq &> /dev/null; then
            APP_LB_STATUS=$(doctl compute load-balancer get "$APP_LOAD_BALANCER_ID" -o json | jq -r '.[0].status' || echo "unknown")
            APP_LB_IP=$(doctl compute load-balancer get "$APP_LOAD_BALANCER_ID" -o json | jq -r '.[0].ip' || echo "unknown")
        else
            APP_LB_INFO=$(doctl compute load-balancer get "$APP_LOAD_BALANCER_ID" -o text 2>/dev/null || echo "")
            APP_LB_STATUS=$(echo "$APP_LB_INFO" | grep -i "status" | awk '{print $2}' || echo "unknown")
            APP_LB_IP=$(echo "$APP_LB_INFO" | grep -i "ip" | awk '{print $2}' || echo "unknown")
        fi
        
        log_success "App Load Balancer found"
        log_info "  ID: $APP_LOAD_BALANCER_ID"
        log_info "  IP: $APP_LB_IP"
        log_info "  Status: $APP_LB_STATUS"
        
        if [[ "$APP_LB_IP" != "$APP_LOAD_BALANCER_IP" ]]; then
            log_warning "IP mismatch! Expected: $APP_LOAD_BALANCER_IP, Got: $APP_LB_IP"
        fi
    else
        log_error "App Load Balancer not found!"
        exit 1
    fi
fi
echo

# Step 5: Restart ingress-nginx pods
log_step "5. Restarting ingress-nginx pods..."
INGRESS_NAMESPACE=$(kubectl get namespace -o name | grep -E "ingress|nginx" | head -1 | cut -d/ -f2 || echo "ingress-nginx")

if kubectl get namespace "$INGRESS_NAMESPACE" &>/dev/null; then
    log_info "Found ingress namespace: $INGRESS_NAMESPACE"
    
    INGRESS_PODS=$(kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$INGRESS_PODS" ]]; then
        log_info "Restarting ingress-nginx pods..."
        for pod in $INGRESS_PODS; do
            log_info "  Deleting pod: $pod"
            kubectl delete pod "$pod" -n "$INGRESS_NAMESPACE" --grace-period=30
        done
        
        log_info "Waiting for pods to restart (30 seconds)..."
        sleep 30
        
        # Wait for pods to be ready
        log_info "Waiting for pods to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n "$INGRESS_NAMESPACE" --timeout=120s || {
            log_warning "Some pods may not be ready yet, but continuing..."
        }
        
        log_success "Ingress-nginx pods restarted"
    else
        log_warning "No ingress-nginx pods found to restart"
    fi
else
    log_warning "Ingress namespace not found: $INGRESS_NAMESPACE"
fi
echo

# Step 6: Wait for propagation
log_step "6. Waiting for changes to propagate..."
log_info "Waiting 60 seconds for DNS and load balancer changes to propagate..."
for i in {60..1}; do
    echo -ne "\r  Waiting: ${i}s remaining..."
    sleep 1
done
echo -e "\r  Waiting complete                            "
echo

# Step 7: Verify fix
log_step "7. Verifying SSL/TLS connectivity..."
VERIFICATION_FAILED=0

for domain in "${DOMAINS[@]}"; do
    log_info "Testing $domain..."
    
    # Test HTTPS
    if command -v openssl &> /dev/null; then
        SSL_TEST=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>&1 | grep -E "CONNECTED" || echo "")
        if [[ -n "$SSL_TEST" ]]; then
            log_success "  ✓ HTTPS connection successful"
        else
            log_error "  ✗ HTTPS connection failed"
            ((VERIFICATION_FAILED++))
        fi
    fi
    
    # Test HTTP redirect
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L -m 10 "http://$domain" 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" == "301" ]] || [[ "$HTTP_STATUS" == "302" ]] || [[ "$HTTP_STATUS" == "308" ]]; then
        log_success "  ✓ HTTP redirect working (status: $HTTP_STATUS)"
    elif [[ "$HTTP_STATUS" == "200" ]]; then
        log_warning "  ⚠ HTTP not redirecting (status: $HTTP_STATUS)"
    else
        log_warning "  ⚠ HTTP test inconclusive (status: $HTTP_STATUS)"
    fi
done
echo

# Step 8: Check NGINX logs for errors
log_step "8. Checking NGINX logs for SSL errors..."
if [[ -n "${INGRESS_PODS:-}" ]]; then
    INGRESS_POD=$(echo "$INGRESS_PODS" | awk '{print $1}')
    if [[ -n "$INGRESS_POD" ]]; then
        RECENT_SSL_ERRORS=$(kubectl logs -n "$INGRESS_NAMESPACE" "$INGRESS_POD" --tail=50 --since=2m 2>/dev/null | grep -i "SSL\|TLS\|handshake\|error:0A00010B" || echo "")
        if [[ -n "$RECENT_SSL_ERRORS" ]]; then
            log_warning "Recent SSL errors found in logs:"
            echo "$RECENT_SSL_ERRORS" | head -5
        else
            log_success "No recent SSL errors in logs"
        fi
    fi
fi
echo

# Final summary
log_step "Fix Summary"
echo "=========================================="
if [[ "$VERIFICATION_FAILED" -eq 0 ]]; then
    log_success "SSL/TLS fix appears successful!"
    log_info "All domains tested successfully"
else
    log_warning "Some verification tests failed"
    log_info "Please check the output above and verify manually"
fi

echo
log_info "Next steps:"
log_info "1. Test applications from mobile devices"
log_info "2. Test applications from desktop browsers"
log_info "3. Monitor NGINX logs for any remaining errors"
log_info "4. Run diagnostic script: ./yonks-ssl-diagnostic.sh"
echo

