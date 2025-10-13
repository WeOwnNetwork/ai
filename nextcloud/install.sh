#!/bin/bash

# Nextcloud One-Command Installer
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
readonly REPO_URL="https://github.com/WeOwnAI/ai.git"
readonly TARGET_DIR="nextcloud-enterprise"
readonly SCRIPT_VERSION="1.0.0"

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

# Check if git is installed
check_git() {
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install git first."
        echo
        echo "Installation instructions:"
        echo "  macOS: brew install git"
        echo "  Ubuntu/Debian: sudo apt-get install git"
        echo "  Windows: Download from https://git-scm.com/download/win"
        exit 1
    fi
    log_info "Git is available"
}

# Check if target directory already exists
check_target_directory() {
    if [[ -d "$TARGET_DIR" ]]; then
        log_warning "Directory '$TARGET_DIR' already exists"
        read -p "Do you want to remove it and continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing directory..."
            rm -rf "$TARGET_DIR"
        else
            log_info "Installation cancelled"
            exit 0
        fi
    fi
}

# Clone repository using sparse checkout
clone_repository() {
    log_step "Cloning Nextcloud Repository"
    
    log_info "Creating sparse clone of WeOwn AI repository..."
    git clone --filter=blob:none --sparse "$REPO_URL" "$TARGET_DIR"
    
    cd "$TARGET_DIR"
    
    log_info "Configuring sparse checkout for Nextcloud..."
    git sparse-checkout init --cone
    git sparse-checkout set nextcloud
    
    log_success "Repository cloned successfully"
}

# Verify installation
verify_installation() {
    log_step "Verifying Installation"
    
    local required_files=(
        "nextcloud/deploy.sh"
        "nextcloud/helm/Chart.yaml"
        "nextcloud/helm/values.yaml"
        "nextcloud/README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "✓ $file"
        else
            log_error "✗ $file (missing)"
            return 1
        fi
    done
    
    # Check if deploy.sh is executable
    if [[ -x "nextcloud/deploy.sh" ]]; then
        log_info "✓ deploy.sh is executable"
    else
        log_warning "Making deploy.sh executable..."
        chmod +x nextcloud/deploy.sh
    fi
    
    log_success "Installation verified successfully"
}

# Display next steps
show_next_steps() {
    log_step "Installation Complete"
    
    echo -e "${GREEN}Nextcloud installed successfully!${NC}"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Navigate to the installation directory:"
    echo "     ${BLUE}cd $TARGET_DIR/nextcloud${NC}"
    echo
    echo "  2. Run the deployment script:"
    echo "     ${BLUE}./deploy.sh${NC}"
    echo
    echo -e "${BOLD}What the deployment script will do:${NC}"
    echo "  • Check prerequisites (kubectl, helm, etc.)"
    echo "  • Install NGINX Ingress Controller and cert-manager"
    echo "  • Gather your domain and email configuration"
    echo "  • Generate secure credentials automatically"
    echo "  • Deploy Nextcloud with PostgreSQL and Redis"
    echo "  • Configure TLS certificates with Let's Encrypt"
    echo "  • Set up enterprise security (zero-trust, RBAC)"
    echo
    echo -e "${BOLD}Prerequisites:${NC}"
    echo "  • Kubernetes cluster (DigitalOcean, AWS EKS, GKE, etc.)"
    echo "  • kubectl configured to access your cluster"
    echo "  • Domain name with DNS control"
    echo "  • Email address for SSL certificates"
    echo
    echo -e "${BOLD}For help:${NC}"
    echo "  • View deployment options: ${BLUE}./deploy.sh --help${NC}"
    echo "  • Read documentation: ${BLUE}cat README.md${NC}"
    echo
    echo -e "${YELLOW}⚠️  Note: This installer only downloads the deployment files.${NC}"
    echo -e "${YELLOW}    The actual Nextcloud deployment happens when you run ./deploy.sh${NC}"
}

# Main installation function
main() {
    echo -e "${BOLD}${PURPLE}Nextcloud Installer${NC}"
    echo -e "${PURPLE}Version: $SCRIPT_VERSION${NC}"
    echo
    
    # Check prerequisites
    check_git
    check_target_directory
    
    # Clone repository
    clone_repository
    
    # Verify installation
    if ! verify_installation; then
        log_error "Installation verification failed"
        exit 1
    fi
    
    # Show next steps
    show_next_steps
}

# Handle script interruption
trap 'log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
