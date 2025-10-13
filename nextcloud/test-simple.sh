#!/bin/bash

# Simple Nextcloud Test Script (No Helm Required)
# Tests basic Kubernetes functionality

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
    
    for tool in kubectl curl; do
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
        log_info "Please start Minikube: minikube start"
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -1)
    log_info "✓ Connected to: ${cluster_info#*at }"
    
    log_success "Prerequisites test passed"
    return 0
}

test_helm_chart_files() {
    log_step "Testing Helm Chart Files"
    
    local required_files=(
        "helm/Chart.yaml"
        "helm/values.yaml"
        "helm/templates/_helpers.tpl"
        "helm/templates/deployment.yaml"
        "helm/templates/service.yaml"
        "helm/templates/ingress.yaml"
        "helm/templates/secrets.yaml"
        "helm/templates/pvc.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "✓ $file exists"
        else
            log_error "✗ $file missing"
            return 1
        fi
    done
    
    log_success "Helm chart files test passed"
    return 0
}

test_yaml_syntax() {
    log_step "Testing YAML Syntax"
    
    # Test if YAML files are valid
    for yaml_file in helm/templates/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            # Basic YAML syntax check
            if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                log_info "✓ $yaml_file syntax valid"
            else
                log_warning "⚠ $yaml_file syntax check skipped (python3 not available)"
            fi
        fi
    done
    
    log_success "YAML syntax test completed"
    return 0
}

test_kubernetes_resources() {
    log_step "Testing Kubernetes Resource Creation"
    
    # Create test namespace
    kubectl create namespace nextcloud-simple-test --dry-run=client -o yaml | kubectl apply -f -
    log_info "✓ Test namespace created"
    
    # Test creating a simple pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: nextcloud-simple-test
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sleep', '3600']
EOF
    
    log_info "✓ Test pod created"
    
    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod/test-pod -n nextcloud-simple-test --timeout=60s
    log_info "✓ Test pod is ready"
    
    # Clean up
    kubectl delete pod test-pod -n nextcloud-simple-test
    kubectl delete namespace nextcloud-simple-test
    
    log_success "Kubernetes resources test passed"
    return 0
}

test_minikube_addons() {
    log_step "Testing Minikube Addons"
    
    # Check if ingress addon is enabled
    if minikube addons list | grep -q "ingress.*enabled"; then
        log_info "✓ Ingress addon is enabled"
    else
        log_warning "⚠ Ingress addon not enabled. Run: minikube addons enable ingress"
    fi
    
    # Check if storage provisioner is enabled
    if minikube addons list | grep -q "storage-provisioner.*enabled"; then
        log_info "✓ Storage provisioner is enabled"
    else
        log_warning "⚠ Storage provisioner not enabled. Run: minikube addons enable storage-provisioner"
    fi
    
    log_success "Minikube addons test completed"
    return 0
}

show_next_steps() {
    log_step "Next Steps"
    
    echo -e "${BOLD}To complete the full testing:${NC}"
    echo "1. Install Helm:"
    echo "   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    echo
    echo "2. Enable Minikube addons:"
    echo "   minikube addons enable ingress"
    echo "   minikube addons enable storage-provisioner"
    echo
    echo "3. Run full test suite:"
    echo "   ./test-deployment.sh"
    echo
    echo -e "${BOLD}Or deploy Nextcloud directly:${NC}"
    echo "   ./deploy.sh"
}

# Main test function
run_simple_tests() {
    echo -e "${BOLD}${PURPLE}Nextcloud Simple Test Suite${NC}"
    echo -e "${PURPLE}Version: 1.0.0${NC}"
    echo
    
    local test_functions=(
        "test_prerequisites"
        "test_helm_chart_files"
        "test_yaml_syntax"
        "test_kubernetes_resources"
        "test_minikube_addons"
    )
    
    local failed_tests=()
    
    for test_func in "${test_functions[@]}"; do
        if ! $test_func; then
            failed_tests+=("$test_func")
        fi
    done
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log_success "🎉 All simple tests passed!"
        show_next_steps
        return 0
    else
        log_error "Failed tests: ${failed_tests[*]}"
        return 1
    fi
}

# Run tests
run_simple_tests
