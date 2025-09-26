#!/bin/bash

# n8n Enterprise Kubernetes Installation Script
# One-liner installer for easy cohort deployment
# Usage: curl -sSL https://raw.githubusercontent.com/your-org/n8n-k8s/main/install.sh | bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/WeOwnNetwork/ai.git"
TARGET_DIR="n8n-enterprise"
N8N_PATH="n8n"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              n8n Enterprise Kubernetes Installer                ║"
    echo "║          Workflow Automation Platform Deployment                ║"
    echo "║                                                                  ║"
    echo "║   🔄 Automation • 🛡️ Enterprise Security • 🚀 One-Command Setup   ║"
    echo "║              100% Security Compliant (A+ Grade)                 ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for required tools
    local missing_tools=()
    
    if ! command -v git >/dev/null 2>&1; then
        missing_tools+=("git")
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm >/dev/null 2>&1; then
        missing_tools+=("helm")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo
        echo "Please install the missing tools:"
        echo "• Git: https://git-scm.com/downloads"
        echo "• kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "• Helm: https://helm.sh/docs/intro/install/"
        echo
        exit 1
    fi
    
    # Check Kubernetes connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "Please ensure you have a valid kubeconfig and cluster access"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

clone_n8n_only() {
    log_info "Cloning n8n deployment files (sparse checkout)..."
    
    # Remove target directory if it exists
    if [[ -d "$TARGET_DIR" ]]; then
        log_warning "Directory $TARGET_DIR already exists. Removing..."
        rm -rf "$TARGET_DIR"
    fi
    
    # Sparse clone to get only n8n directory
    git clone --filter=blob:none --sparse "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    git sparse-checkout set "$N8N_PATH"
    
    # Move n8n contents to root and cleanup
    if [[ -d "$N8N_PATH" ]]; then
        mv "$N8N_PATH"/* .
        mv "$N8N_PATH"/.* . 2>/dev/null || true  # Move hidden files, ignore errors
        rmdir "$N8N_PATH"
    else
        log_error "n8n directory not found in repository"
        exit 1
    fi
    
    log_success "n8n deployment files downloaded successfully"
}

run_deployment() {
    log_info "Starting n8n Enterprise deployment..."
    echo
    
    # Make deploy script executable
    chmod +x deploy.sh
    
    # Run the deployment script
    ./deploy.sh "$@"
}

show_usage() {
    cat << EOF
n8n Enterprise Kubernetes Installer

USAGE:
    curl -sSL https://raw.githubusercontent.com/your-org/n8n-k8s/main/install.sh | bash
    
    # Or download and run locally:
    curl -O https://raw.githubusercontent.com/your-org/n8n-k8s/main/install.sh
    chmod +x install.sh
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    --domain DOMAIN         Set the domain for n8n
    --email EMAIL           Set email for Let's Encrypt certificates
    --no-deploy             Only download files, don't deploy

EXAMPLES:
    # Basic installation (interactive)
    ./install.sh
    
    # Non-interactive with parameters
    ./install.sh --domain n8n.example.com --email admin@example.com
    
    # Download only (no deployment)
    ./install.sh --no-deploy

FEATURES:
    ✓ Sparse Git Clone (minimal bandwidth usage)
    ✓ Prerequisites Validation
    ✓ Automatic n8n Enterprise Deployment
    ✓ Zero-Trust Security by Default
    ✓ TLS 1.3 with Let's Encrypt
    ✓ Enterprise Compliance Ready
EOF
}

main() {
    print_banner
    
    # Parse arguments
    local no_deploy=false
    local deploy_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --no-deploy)
                no_deploy=true
                shift
                ;;
            --domain|--email|--namespace|--migration|--queue-mode)
                deploy_args+=("$1" "$2")
                shift 2
                ;;
            --show-credentials)
                deploy_args+=("$1")
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute installation steps
    check_prerequisites
    clone_n8n_only
    
    if [[ "$no_deploy" == "false" ]]; then
        run_deployment "${deploy_args[@]}"
    else
        log_success "n8n files downloaded to: $(pwd)"
        echo
        echo "To deploy n8n, run:"
        echo "  cd $(pwd)"
        echo "  ./deploy.sh"
    fi
}

# Handle script being piped from curl
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
