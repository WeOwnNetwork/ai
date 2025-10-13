#!/bin/bash

# Nextcloud Status Checker
# Quick script to check deployment status

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
NAMESPACE="${1:-nextcloud-test}"

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

check_namespace() {
    log_step "Checking Namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace exists"
    else
        log_error "Namespace $NAMESPACE not found"
        return 1
    fi
}

check_pods() {
    log_step "Checking Pod Status"
    
    local pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$pods" ]]; then
        log_warning "No pods found in namespace"
        return 0
    fi
    
    echo -e "${BOLD}Pod Status:${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo
    echo -e "${BOLD}Pod Summary:${NC}"
    
    local total_pods=$(echo "$pods" | wc -l)
    local running_pods=$(echo "$pods" | grep -c "Running" || true)
    local ready_pods=$(echo "$pods" | grep -c "Ready" || true)
    local pending_pods=$(echo "$pods" | grep -c "Pending" || true)
    local failed_pods=$(echo "$pods" | grep -cE "Error|CrashLoopBackOff|ImagePullBackOff" || true)
    
    log_info "Total pods: $total_pods"
    log_info "Running: $running_pods"
    log_info "Ready: $ready_pods"
    log_info "Pending: $pending_pods"
    log_info "Failed: $failed_pods"
    
    if [[ $failed_pods -gt 0 ]]; then
        log_warning "Failed pods detected:"
        echo "$pods" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff"
    fi
}

check_services() {
    log_step "Checking Services"
    
    local services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        log_warning "No services found"
        return 0
    fi
    
    echo -e "${BOLD}Services:${NC}"
    kubectl get services -n "$NAMESPACE"
}

check_volumes() {
    log_step "Checking Persistent Volumes"
    
    local pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$pvcs" ]]; then
        log_warning "No PVCs found"
        return 0
    fi
    
    echo -e "${BOLD}PVCs:${NC}"
    kubectl get pvc -n "$NAMESPACE"
    
    echo
    echo -e "${BOLD}PVC Status Summary:${NC}"
    local bound_pvcs=$(echo "$pvcs" | grep -c "Bound" || true)
    local pending_pvcs=$(echo "$pvcs" | grep -c "Pending" || true)
    local total_pvcs=$(echo "$pvcs" | wc -l)
    
    log_info "Total PVCs: $total_pvcs"
    log_info "Bound: $bound_pvcs"
    log_info "Pending: $pending_pvcs"
}

check_events() {
    log_step "Recent Events"
    
    local events=$(kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -10 || echo "")
    
    if [[ -z "$events" ]]; then
        log_warning "No events found"
        return 0
    fi
    
    echo -e "${BOLD}Last 10 Events:${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
}

check_ingress() {
    log_step "Checking Ingress"
    
    local ingress=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$ingress" ]]; then
        log_warning "No ingress found"
        return 0
    fi
    
    echo -e "${BOLD}Ingress:${NC}"
    kubectl get ingress -n "$NAMESPACE"
}

show_help() {
    echo "Nextcloud Status Checker"
    echo
    echo "Usage:"
    echo "  $0 [namespace]"
    echo
    echo "Examples:"
    echo "  $0                    # Check nextcloud-test namespace"
    echo "  $0 nextcloud          # Check nextcloud namespace"
    echo "  $0 nextcloud-quick-test # Check quick test namespace"
    echo
    echo "This script will show:"
    echo "  • Pod status and health"
    echo "  • Service status"
    echo "  • Persistent volume status"
    echo "  • Recent events"
    echo "  • Ingress configuration"
}

# Main function
main() {
    if [[ "${1:-}" == "help" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    echo -e "${BOLD}${PURPLE}Nextcloud Status Checker${NC}"
    echo -e "${PURPLE}Namespace: $NAMESPACE${NC}"
    echo
    
    check_namespace || exit 1
    check_pods
    check_services
    check_volumes
    check_events
    check_ingress
    
    echo
    log_success "Status check completed!"
    
    echo
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  Watch pods:     kubectl get pods -n $NAMESPACE -w"
    echo "  View logs:      kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=nextcloud"
    echo "  Describe pod:   kubectl describe pod <pod-name> -n $NAMESPACE"
    echo "  Check events:   kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
}

# Run main function
main "$@"
