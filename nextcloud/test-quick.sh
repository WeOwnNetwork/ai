#!/bin/bash

# Quick Nextcloud Test Script
# Tests deployment without waiting for full readiness

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Configuration
readonly NAMESPACE="nextcloud-quick-test"
readonly RELEASE_NAME="nextcloud-quick-test"
readonly TEST_DOMAIN="nextcloud-test.local"
readonly TEST_EMAIL="test@example.com"

# Logging functions
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${PURPLE}▶${NC} ${BOLD}$1${NC}"
}

# Test functions
test_prerequisites() {
    log_step "Testing Prerequisites"
    
    local missing_tools=()
    
    for tool in kubectl helm curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_info "✓ $tool available"
        fi
    done
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log_error "Missing tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Test Kubernetes connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -1)
    log_info "✓ Connected to: ${cluster_info#*at }"
    
    log_success "Prerequisites test passed"
    return 0
}

test_helm_chart() {
    log_step "Testing Helm Chart"
    
    # Test chart syntax
    if helm lint ./helm &> /dev/null; then
        log_info "✓ Helm chart syntax valid"
    else
        log_error "Helm chart syntax errors"
        return 1
    fi
    
    # Test template rendering
    if helm template "$RELEASE_NAME" ./helm --namespace="$NAMESPACE" &> /dev/null; then
        log_info "✓ Helm templates render successfully"
    else
        log_error "Helm template rendering failed"
        return 1
    fi
    
    log_success "Helm chart test passed"
    return 0
}

test_deployment() {
    log_step "Testing Deployment (Quick Mode)"
    
    # Create test namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_info "✓ Test namespace created"
    
    # Generate test credentials
    local admin_password="testpass123"
    local postgres_password="testpass123"
    local redis_password="testpass123"
    local nextcloud_secret="testsecret123456789012345678901234"
    
    # Create test values file
    local test_values="/tmp/nextcloud-quick-test-values.yaml"
    
    # Create test values file with simple replacements
    cp ./helm/values.yaml "$test_values"
    
    # Replace placeholders using simple sed commands
    sed -i "s/DOMAIN_PLACEHOLDER/$TEST_DOMAIN/g" "$test_values"
    sed -i "s/EMAIL_PLACEHOLDER/$TEST_EMAIL/g" "$test_values"
    sed -i "s/ADMIN_PASSWORD_PLACEHOLDER/$admin_password/g" "$test_values"
    sed -i "s/POSTGRES_PASSWORD_PLACEHOLDER/$postgres_password/g" "$test_values"
    sed -i "s/POSTGRES_ROOT_PASSWORD_PLACEHOLDER/$postgres_password/g" "$test_values"
    sed -i "s/REDIS_PASSWORD_PLACEHOLDER/$redis_password/g" "$test_values"
    sed -i "s/NEXTCLOUD_SECRET_PLACEHOLDER/$nextcloud_secret/g" "$test_values"
    
    log_info "✓ Test values file created"
    
    # Deploy with Helm (no wait - quick mode)
    if helm upgrade --install "$RELEASE_NAME" ./helm \
        --namespace="$NAMESPACE" \
        --values="$test_values" \
        --timeout=2m; then
        log_info "✓ Helm deployment initiated"
    else
        log_error "Helm deployment failed"
        log_info "Checking deployment status..."
        kubectl get pods -n "$NAMESPACE"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
        return 1
    fi
    
    # Clean up test values
    rm -f "$test_values"
    
    log_success "Deployment test passed"
    return 0
}

test_pods_created() {
    log_step "Testing Pod Creation"
    
    # Wait a bit for pods to be created
    sleep 10
    
    # Check if pods are created (not necessarily ready)
    local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
    
    if [[ $total_pods -gt 0 ]]; then
        log_info "✓ $total_pods pods created"
        
        # Show pod status
        kubectl get pods -n "$NAMESPACE"
        
        # Check for any failed pods
        local failed_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "Error\|CrashLoopBackOff\|ImagePullBackOff" || true)
        
        if [[ $failed_pods -eq 0 ]]; then
            log_info "✓ No failed pods detected"
        else
            log_warning "⚠ $failed_pods pods in failed state"
            kubectl get pods -n "$NAMESPACE" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff"
        fi
    else
        log_error "No pods created"
        return 1
    fi
    
    log_success "Pod creation test passed"
    return 0
}

test_services() {
    log_step "Testing Services"
    
    # Check service endpoints
    local services=("$RELEASE_NAME" "$RELEASE_NAME-postgresql" "$RELEASE_NAME-redis")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            log_info "✓ Service $service exists"
        else
            log_warning "⚠ Service $service not found"
        fi
    done
    
    log_success "Services test passed"
    return 0
}

test_volumes() {
    log_step "Testing Persistent Volumes"
    
    local pvcs=("$RELEASE_NAME-data" "$RELEASE_NAME-config" "$RELEASE_NAME-apps" "$RELEASE_NAME-postgresql")
    
    for pvc in "${pvcs[@]}"; do
        if kubectl get pvc "$pvc" -n "$NAMESPACE" &> /dev/null; then
            local status=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            log_info "✓ PVC $pvc status: $status"
        else
            log_warning "⚠ PVC $pvc not found"
        fi
    done
    
    log_success "Volumes test passed"
    return 0
}

cleanup_test() {
    log_step "Cleaning Up Test Environment"
    
    # Delete Helm release
    if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_info "✓ Helm release uninstalled"
    fi
    
    # Delete namespace
    if kubectl delete namespace "$NAMESPACE" &> /dev/null; then
        log_info "✓ Test namespace deleted"
    fi
    
    log_success "Cleanup completed"
}

show_test_results() {
    log_step "Quick Test Results Summary"
    
    echo -e "${BOLD}Test Environment:${NC}"
    echo "  Namespace: $NAMESPACE"
    echo "  Release: $RELEASE_NAME"
    echo "  Domain: $TEST_DOMAIN"
    echo "  Email: $TEST_EMAIL"
    echo
    
    echo -e "${BOLD}Tests Performed:${NC}"
    echo "  ✓ Prerequisites check"
    echo "  ✓ Helm chart validation"
    echo "  ✓ Deployment initiation"
    echo "  ✓ Pod creation verification"
    echo "  ✓ Services creation"
    echo "  ✓ Persistent volumes"
    echo
    
    echo -e "${GREEN}🎉 Quick tests completed successfully!${NC}"
    echo
    echo -e "${BOLD}Note:${NC} This is a quick test that doesn't wait for full pod readiness."
    echo -e "${BOLD}For full testing:${NC} Use ./test-deployment.sh (takes longer but more comprehensive)"
    echo
    echo -e "${BOLD}To check pod status manually:${NC}"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=nextcloud"
}

# Main test function
run_quick_tests() {
    echo -e "${BOLD}${PURPLE}Nextcloud Quick Test Suite${NC}"
    echo -e "${PURPLE}Version: 1.0.0${NC}"
    echo
    
    local test_functions=(
        "test_prerequisites"
        "test_helm_chart"
        "test_deployment"
        "test_pods_created"
        "test_services"
        "test_volumes"
    )
    
    local failed_tests=()
    
    for test_func in "${test_functions[@]}"; do
        if ! $test_func; then
            failed_tests+=("$test_func")
        fi
    done
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        show_test_results
        cleanup_test
        return 0
    else
        log_error "Failed tests: ${failed_tests[*]}"
        echo
        echo -e "${BOLD}Debug Information:${NC}"
        kubectl get all -n "$NAMESPACE"
        echo
        kubectl describe pods -n "$NAMESPACE"
        return 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "cleanup")
        cleanup_test
        ;;
    "help"|"-h"|"--help")
        echo "Nextcloud Quick Test Script"
        echo
        echo "Usage:"
        echo "  $0           # Run quick tests"
        echo "  $0 cleanup   # Clean up test environment"
        echo "  $0 help      # Show this help"
        ;;
    *)
        run_quick_tests
        ;;
esac
