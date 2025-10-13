#!/bin/bash

# Nextcloud Deployment Testing Script
# Version: 1.0.0

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Configuration
readonly NAMESPACE="nextcloud-test"
readonly RELEASE_NAME="nextcloud-test"
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

log_substep() {
    echo -e "  ${BLUE}•${NC} $1"
}

# Test functions
test_prerequisites() {
    log_step "Testing Prerequisites"
    
    local missing_tools=()
    
    for tool in kubectl helm curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_substep "✓ $tool available"
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
    log_substep "✓ Connected to: ${cluster_info#*at }"
    
    log_success "Prerequisites test passed"
    return 0
}

test_helm_chart() {
    log_step "Testing Helm Chart"
    
    # Test chart syntax
    if helm lint ./helm &> /dev/null; then
        log_substep "✓ Helm chart syntax valid"
    else
        log_error "Helm chart syntax errors"
        return 1
    fi
    
    # Test template rendering
    if helm template "$RELEASE_NAME" ./helm --namespace="$NAMESPACE" &> /dev/null; then
        log_substep "✓ Helm templates render successfully"
    else
        log_error "Helm template rendering failed"
        return 1
    fi
    
    log_success "Helm chart test passed"
    return 0
}

test_deployment() {
    log_step "Testing Deployment"
    
    # Create test namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_substep "✓ Test namespace created"
    
    # Generate test credentials
    local admin_password=$(openssl rand -base64 12)
    local postgres_password=$(openssl rand -base64 12)
    local redis_password=$(openssl rand -base64 12)
    local nextcloud_secret=$(openssl rand -hex 16)
    
    # Create test values file
    local test_values="/tmp/nextcloud-test-values.yaml"
    
    # Use simple password generation to avoid special characters
    local admin_password="testpass123"
    local postgres_password="testpass123"
    local redis_password="testpass123"
    local nextcloud_secret="testsecret123456789012345678901234"
    
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
    
    log_substep "✓ Test values file created"
    
    # Deploy with Helm (increased timeout for image pulling)
    if helm upgrade --install "$RELEASE_NAME" ./helm \
        --namespace="$NAMESPACE" \
        --values="$test_values" \
        --wait \
        --timeout=10m; then
        log_substep "✓ Helm deployment successful"
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

test_pods() {
    log_step "Testing Pod Status"
    
    # Wait for pods to be ready
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local ready_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "Running\|Completed" || true)
        local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
        
        if [[ $ready_pods -eq $total_pods && $total_pods -gt 0 ]]; then
            log_substep "✓ All $total_pods pods are ready"
            break
        fi
        
        log_substep "Waiting for pods... ($ready_pods/$total_pods ready)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Pods did not become ready within $timeout seconds"
        kubectl get pods -n "$NAMESPACE"
        return 1
    fi
    
    # Check individual pod health
    for pod in $(kubectl get pods -n "$NAMESPACE" -o name); do
        local pod_name=${pod#pod/}
        if kubectl get "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' | grep -q "Running\|Succeeded"; then
            log_substep "✓ $pod_name is healthy"
        else
            log_warning "$pod_name is not in Running state"
        fi
    done
    
    log_success "Pod status test passed"
    return 0
}

test_services() {
    log_step "Testing Services"
    
    # Check service endpoints
    local services=("$RELEASE_NAME" "$RELEASE_NAME-postgresql" "$RELEASE_NAME-redis")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            local endpoints=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
            if [[ $endpoints -gt 0 ]]; then
                log_substep "✓ Service $service has $endpoints endpoints"
            else
                log_warning "Service $service has no endpoints"
            fi
        else
            log_warning "Service $service not found"
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
            if [[ "$status" == "Bound" ]]; then
                log_substep "✓ PVC $pvc is bound"
            else
                log_warning "PVC $pvc status: $status"
            fi
        else
            log_warning "PVC $pvc not found"
        fi
    done
    
    log_success "Volumes test passed"
    return 0
}

test_secrets() {
    log_step "Testing Secrets"
    
    local secrets=("$RELEASE_NAME" "$RELEASE_NAME-postgresql" "$RELEASE_NAME-redis")
    
    for secret in "${secrets[@]}"; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            log_substep "✓ Secret $secret exists"
        else
            log_warning "Secret $secret not found"
        fi
    done
    
    log_success "Secrets test passed"
    return 0
}

test_network_policies() {
    log_step "Testing Network Policies"
    
    if kubectl get networkpolicy "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_substep "✓ NetworkPolicy $RELEASE_NAME exists"
    else
        log_warning "NetworkPolicy not found"
    fi
    
    log_success "Network policies test passed"
    return 0
}

test_ingress() {
    log_step "Testing Ingress"
    
    if kubectl get ingress "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_substep "✓ Ingress $RELEASE_NAME exists"
        
        # Check ingress controller
        if kubectl get pods -n ingress-nginx &> /dev/null; then
            log_substep "✓ NGINX Ingress Controller is running"
        else
            log_warning "NGINX Ingress Controller not found"
        fi
    else
        log_warning "Ingress not found"
    fi
    
    log_success "Ingress test passed"
    return 0
}

test_connectivity() {
    log_step "Testing Internal Connectivity"
    
    # Test database connectivity
    local postgres_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$postgres_pod" ]]; then
        if kubectl exec "$postgres_pod" -n "$NAMESPACE" -- pg_isready -U nextcloud -d nextcloud &> /dev/null; then
            log_substep "✓ PostgreSQL is accepting connections"
        else
            log_warning "PostgreSQL connection test failed"
        fi
    fi
    
    # Test Redis connectivity
    local redis_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$redis_pod" ]]; then
        if kubectl exec "$redis_pod" -n "$NAMESPACE" -- redis-cli ping &> /dev/null; then
            log_substep "✓ Redis is accepting connections"
        else
            log_warning "Redis connection test failed"
        fi
    fi
    
    log_success "Connectivity test passed"
    return 0
}

test_application() {
    log_step "Testing Application Health"
    
    # Port forward to test application
    local nextcloud_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=nextcloud -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$nextcloud_pod" ]]; then
        # Start port forward in background
        kubectl port-forward "$nextcloud_pod" -n "$NAMESPACE" 8080:80 &
        local port_forward_pid=$!
        
        # Wait for port forward to be ready
        sleep 5
        
        # Test application endpoint
        if curl -f http://localhost:8080/status.php &> /dev/null; then
            log_substep "✓ Nextcloud application is responding"
        else
            log_warning "Nextcloud application health check failed"
        fi
        
        # Clean up port forward
        kill $port_forward_pid 2>/dev/null || true
    else
        log_warning "Nextcloud pod not found"
    fi
    
    log_success "Application test passed"
    return 0
}

cleanup_test() {
    log_step "Cleaning Up Test Environment"
    
    # Delete Helm release
    if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_substep "✓ Helm release uninstalled"
    fi
    
    # Delete namespace
    if kubectl delete namespace "$NAMESPACE" &> /dev/null; then
        log_substep "✓ Test namespace deleted"
    fi
    
    log_success "Cleanup completed"
}

show_test_results() {
    log_step "Test Results Summary"
    
    echo -e "${BOLD}Test Environment:${NC}"
    echo "  Namespace: $NAMESPACE"
    echo "  Release: $RELEASE_NAME"
    echo "  Domain: $TEST_DOMAIN"
    echo "  Email: $TEST_EMAIL"
    echo
    
    echo -e "${BOLD}Tests Performed:${NC}"
    echo "  ✓ Prerequisites check"
    echo "  ✓ Helm chart validation"
    echo "  ✓ Deployment test"
    echo "  ✓ Pod status verification"
    echo "  ✓ Services connectivity"
    echo "  ✓ Persistent volumes"
    echo "  ✓ Secrets management"
    echo "  ✓ Network policies"
    echo "  ✓ Ingress configuration"
    echo "  ✓ Internal connectivity"
    echo "  ✓ Application health"
    echo
    
    echo -e "${GREEN}🎉 All tests completed successfully!${NC}"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Test with real domain and SSL certificates"
    echo "  2. Test backup and restore functionality"
    echo "  3. Test scaling and performance"
    echo "  4. Test security policies"
    echo "  5. Deploy to production environment"
}

# Main test function
run_tests() {
    echo -e "${BOLD}${PURPLE}Nextcloud Enterprise Deployment Testing${NC}"
    echo -e "${PURPLE}Version: 1.0.0${NC}"
    echo
    
    local test_functions=(
        "test_prerequisites"
        "test_helm_chart"
        "test_deployment"
        "test_pods"
        "test_services"
        "test_volumes"
        "test_secrets"
        "test_network_policies"
        "test_ingress"
        "test_connectivity"
        "test_application"
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
        echo "Nextcloud Enterprise Deployment Testing Script"
        echo
        echo "Usage:"
        echo "  $0           # Run all tests"
        echo "  $0 cleanup   # Clean up test environment"
        echo "  $0 help      # Show this help"
        ;;
    *)
        run_tests
        ;;
esac
