#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/styles.sh"

# Helper to find chart path
# Assumes running from ai/cli/
CHART_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"

check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm not installed."
        exit 1
    fi
}

deploy_chart() {
    local release_name=$1
    local namespace=$2
    local chart_path=$3
    local values_file=$4
    
    log_info "Deploying '$release_name' to namespace '$namespace'..."
    
    # Create namespace if needed
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Execute helm upgrade/install with proper argument quoting, avoiding eval
    local cmd=(helm upgrade --install "$release_name" "$chart_path" --namespace "$namespace")
    if [ -f "$values_file" ]; then
        cmd+=(-f "$values_file")
    fi
    
    if "${cmd[@]}"; then
        log_success "Deployed $release_name successfully."
    else
        log_error "Failed to deploy $release_name."
        return 1
    fi
}

list_deployments() {
    helm list -A
}

uninstall_chart() {
    local release_name=$1
    local namespace=$2
    
    log_warn "Uninstalling '$release_name' from '$namespace'..."
    helm uninstall "$release_name" -n "$namespace"
}
