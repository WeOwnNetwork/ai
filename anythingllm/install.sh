#!/bin/bash

# WeOwn AnythingLLM One-Line Installer
# Downloads only the AnythingLLM deployment files and runs the deployment script
# Usage: curl -sSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/anythingllm/install.sh | bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/WeOwnNetwork/ai.git"
BRANCH="main"
ANYTHINGLLM_DIR="anythingllm"
TEMP_DIR="/tmp/weown-anythingllm-$(date +%s)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                WeOwn AnythingLLM Installer                   ║"
    echo "║              One-Line Enterprise Deployment                  ║"
    echo "║                                                              ║"
    echo "║    🤖 Self-hosted • 🛡️  Enterprise Security • 🚀 Automated    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    echo -e "${PURPLE}🔐 Privacy-First AI Platform${NC}"
    echo "• Complete privacy - your data never leaves your infrastructure"
    echo "• Enterprise security with Kubernetes-native deployment"
    echo "• OpenRouter integration with free models available"
    echo "• Document processing and RAG capabilities"
    echo "• Multi-user support with role-based access"
    echo
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

main() {
    print_banner
    
    log_step "Setting up AnythingLLM deployment"
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command -v git &> /dev/null; then
        log_error "git is required but not installed"
        echo "Please install git and try again:"
        echo "  # macOS: brew install git"
        echo "  # Ubuntu/Debian: sudo apt install git"
        echo "  # CentOS/RHEL: sudo yum install git"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not found - you'll need it for Kubernetes deployment"
        echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    fi
    
    if ! command -v helm &> /dev/null; then
        log_warning "helm not found - you'll need it for deployment"
        echo "Install helm: https://helm.sh/docs/intro/install/"
    fi
    
    log_success "Prerequisites check completed"
    echo
    
    # Create temporary directory
    log_step "Creating temporary workspace"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    log_info "Working directory: $TEMP_DIR"
    echo
    
    # Clone only the AnythingLLM directory using sparse checkout
    log_step "Downloading AnythingLLM deployment files"
    log_info "Cloning from: $REPO_URL"
    
    git clone --no-checkout --depth 1 --branch "$BRANCH" "$REPO_URL" weown-ai
    cd weown-ai
    
    # Set up sparse checkout to only get the anythingllm directory
    git sparse-checkout init --cone
    git sparse-checkout set "$ANYTHINGLLM_DIR"
    git checkout
    
    log_success "Downloaded AnythingLLM deployment files"
    echo
    
    # Navigate to the AnythingLLM directory
    ANYTHINGLLM_PATH="$ANYTHINGLLM_DIR"
    if [[ ! -d "$ANYTHINGLLM_PATH" ]]; then
        log_error "AnythingLLM directory not found at $ANYTHINGLLM_PATH"
        exit 1
    fi
    
    cd "$ANYTHINGLLM_PATH"
    log_info "Changed to deployment directory: $(pwd)"
    echo
    
    # Make deploy script executable
    if [[ -f "deploy.sh" ]]; then
        chmod +x deploy.sh
        log_success "Deployment script is ready"
        echo
        
        # Run the deployment script interactively
        log_step "Starting AnythingLLM interactive deployment"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}              Running Interactive Deployment                    ${NC}"
        echo -e "${CYAN}  The deployment script will guide you through all setup steps ${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo
        
        # Run without arguments to trigger interactive mode
        exec ./deploy.sh
    else
        log_error "deploy.sh not found in $HELM_DIR"
        exit 1
    fi
}

# Run main function
main "$@"
