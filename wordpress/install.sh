#!/bin/bash

# WordPress Enterprise Standalone Installer v3.0.0
# Clones only the WordPress directory and deploys independently
# Enhanced security, user experience, and production readiness

set -euo pipefail

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Script metadata
readonly SCRIPT_NAME="WordPress Enterprise Standalone Installer"
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_AUTHOR="WeOwn Network"

# Repository configuration
readonly REPO_URL="https://github.com/WeOwnNetwork/ai.git"
readonly WORDPRESS_DIR="wordpress"
readonly TARGET_DIR="./weown-wordpress"

# Global variables
CLEANUP_ON_EXIT=true
KEEP_GIT_HISTORY=false

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

# OS Detection
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macOS" ;;
        Linux*) echo "Linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
        *) echo "Unknown" ;;
    esac
}

# Tool installation instructions
get_install_instructions() {
    local tool="$1"
    local os="$2"
    
    case "$tool" in
        "git")
            case "$os" in
                "macOS") echo "brew install git or xcode-select --install" ;;
                "Linux") echo "sudo apt-get install git (Ubuntu)" ;;
                "Windows") echo "Install Git for Windows: https://git-scm.com/download/win" ;;
                *) echo "Visit: https://git-scm.com/downloads" ;;
            esac
            ;;
        "kubectl")
            case "$os" in
                "macOS") echo "brew install kubectl" ;;
                "Linux") echo "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/" ;;
                "Windows") echo "choco install kubernetes-cli or download from https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/" ;;
                *) echo "Visit: https://kubernetes.io/docs/tasks/tools/install-kubectl/" ;;
            esac
            ;;
        "helm")
            case "$os" in
                "macOS") echo "brew install helm" ;;
                "Linux") echo "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" ;;
                "Windows") echo "choco install kubernetes-helm or download from https://helm.sh/docs/intro/install/" ;;
                *) echo "Visit: https://helm.sh/docs/intro/install/" ;;
            esac
            ;;
    esac
}

# Prerequisites checking
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local os=$(detect_os)
    log_substep "Detected OS: $os"
    
    local missing_tools=()
    
    # Check git first (required for cloning)
    if ! command -v git &> /dev/null; then
        log_error "git is not installed (required for cloning repository)"
        echo -e "  ${BLUE}Install instructions:${NC} $(get_install_instructions "git" "$os")"
        exit 1
    fi
    log_substep "✓ git installed"
    
    # Check other required tools
    for tool in kubectl helm; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
            log_warning "$tool is not installed"
            echo -e "  ${BLUE}Install instructions:${NC} $(get_install_instructions "$tool" "$os")"
        else
            log_substep "✓ $tool installed"
        fi
    done
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo -e "\n${YELLOW}To install missing tools on $os:${NC}"
        case "$os" in
            "macOS") 
                echo "  brew install kubectl helm"
                ;;
            "Linux")
                echo "  # Install kubectl:"
                echo "  $(get_install_instructions "kubectl" "$os")"
                echo "  # Install helm:"
                echo "  $(get_install_instructions "helm" "$os")"
                ;;
            "Windows")
                echo "  # Via Chocolatey:"
                echo "  choco install kubernetes-cli kubernetes-helm"
                ;;
        esac
        echo
        log_info "Please install the missing tools and run this script again"
        exit 1
    fi
    
    log_success "All prerequisites are installed!"
}

# Cleanup function
cleanup_on_error() {
    if [[ "$CLEANUP_ON_EXIT" == "true" ]]; then
        if [[ -d "$TARGET_DIR" ]]; then
            log_warning "Cleaning up incomplete installation..."
            rm -rf "$TARGET_DIR"
            log_info "Cleanup completed"
        fi
    fi
}

# Set up error handling
trap cleanup_on_error ERR INT TERM

# Clone WordPress directory only
clone_wordpress_directory() {
    log_step "Cloning WordPress Enterprise Deployment"
    
    # Check if target directory already exists
    if [[ -d "$TARGET_DIR" ]]; then
        log_warning "Directory $TARGET_DIR already exists"
        echo -n -e "${WHITE}Remove existing directory and continue? [y/N]: ${NC}"
        read -r response
        
        if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
            log_substep "Removing existing directory..."
            rm -rf "$TARGET_DIR"
        else
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    log_substep "Cloning WeOwn repository..."
    
    # Use sparse checkout to clone only the wordpress directory
    git clone --filter=blob:none --sparse "$REPO_URL" "$TARGET_DIR"
    
    cd "$TARGET_DIR"
    
    # Configure sparse checkout for wordpress directory only
    git sparse-checkout init --cone
    git sparse-checkout set "$WORDPRESS_DIR"
    
    log_substep "✓ Repository cloned with sparse checkout"
    
    # Move wordpress contents to root level for easier access
    if [[ -d "$WORDPRESS_DIR" ]]; then
        log_substep "Reorganizing directory structure..."
        
        # Create temporary directory
        mkdir -p temp_wordpress
        
        # Move wordpress contents to temp
        mv "$WORDPRESS_DIR"/* temp_wordpress/ 2>/dev/null || true
        mv "$WORDPRESS_DIR"/.* temp_wordpress/ 2>/dev/null || true
        
        # Remove original wordpress directory
        rm -rf "$WORDPRESS_DIR"
        
        # Move contents to root
        mv temp_wordpress/* . 2>/dev/null || true
        mv temp_wordpress/.* . 2>/dev/null || true
        
        # Clean up temp directory
        rm -rf temp_wordpress
        
        log_substep "✓ Directory structure optimized"
    else
        log_error "WordPress directory not found in repository"
        exit 1
    fi
    
    # Remove .git directory if not keeping git history
    if [[ "$KEEP_GIT_HISTORY" == "false" ]]; then
        log_substep "Removing git history for cleaner deployment..."
        rm -rf .git
        log_substep "✓ Git history removed"
    fi
    
    # Make deploy script executable
    if [[ -f "deploy.sh" ]]; then
        chmod +x deploy.sh
        log_substep "✓ Deploy script made executable"
    else
        log_error "deploy.sh not found in WordPress directory"
        exit 1
    fi
    
    log_success "WordPress deployment files ready!"
}

# Display final instructions
display_instructions() {
    log_step "Installation Complete! 🚀"
    
    echo -e "\n${BOLD}📁 WordPress Enterprise Deployment Ready${NC}"
    echo -e "  📍 Location: ${CYAN}$(pwd)${NC}"
    echo -e "  📊 Size: $(du -sh . | cut -f1) (WordPress directory only)"
    echo
    
    echo -e "${BOLD}🚀 Quick Deployment:${NC}"
    echo -e "  ${CYAN}./deploy.sh${NC}"
    echo
    
    echo -e "${BOLD}📋 What You Get:${NC}"
    echo -e "  ✓ Enterprise WordPress Helm chart with security hardening"
    echo -e "  ✓ MySQL 8.0 + Redis cache integration"
    echo -e "  ✓ Zero-trust NetworkPolicy and TLS 1.3 automation"
    echo -e "  ✓ Horizontal pod autoscaling and automated backups"
    echo -e "  ✓ Production-ready deployment with comprehensive documentation"
    echo
    
    echo -e "${BOLD}📖 Documentation:${NC}"
    echo -e "  Configuration: ${CYAN}cat README.md${NC}"
    echo -e "  Version History: ${CYAN}cat CHANGELOG.md${NC}"
    echo -e "  Helm Chart: ${CYAN}ls helm/templates/${NC}"
    echo
    
    echo -e "${BOLD}🔧 Advanced Options:${NC}"
    echo -e "  Non-interactive: ${CYAN}./deploy.sh --domain example.com --email admin@example.com${NC}"
    echo -e "  Skip prerequisites: ${CYAN}./deploy.sh --skip-prerequisites${NC}"
    echo -e "  Help: ${CYAN}./deploy.sh --help${NC}"
    echo
    
    echo -e "${BOLD}🛡️ Security Features:${NC}"
    echo -e "  • Zero-trust networking with NetworkPolicy"
    echo -e "  • TLS 1.3 with automated Let's Encrypt certificates"
    echo -e "  • Non-root containers with capability dropping"
    echo -e "  • Rate limiting and brute force protection"
    echo -e "  • Encrypted secrets and secure credential management"
    echo
    
    echo -e "${BOLD}🎯 Next Steps:${NC}"
    echo -e "  1. Ensure you have a Kubernetes cluster configured"
    echo -e "  2. Have your domain name ready for TLS certificates"
    echo -e "  3. Run ${CYAN}./deploy.sh${NC} and follow the interactive setup"
    echo -e "  4. Create DNS A record when prompted by the deployment script"
    echo
    
    echo -e "${GREEN}✨ Ready to deploy enterprise WordPress to Kubernetes!${NC}"
}

# Main installation flow
main() {
    clear
    echo -e "${BOLD}${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                WordPress Enterprise Standalone Installer        ║"
    echo "║                         v${SCRIPT_VERSION} by ${SCRIPT_AUTHOR}                        ║"
    echo "║                                                                  ║"
    echo "║  🚀 Clones only WordPress • Kubernetes-native • Zero-trust      ║"
    echo "║  🛡️  Enterprise security • Production-ready • Auto-scaling      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-git-history)
                KEEP_GIT_HISTORY=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_ON_EXIT=false
                shift
                ;;
            --target-dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --target-dir DIR         Set target directory (default: ./weown-wordpress)"
                echo "  --keep-git-history       Keep .git directory for version tracking"
                echo "  --no-cleanup             Don't clean up on error"
                echo "  --help                   Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for available options"
                exit 1
                ;;
        esac
    done
    
    log_info "Installing WordPress Enterprise Deployment to: $TARGET_DIR"
    echo
    
    # Installation steps
    check_prerequisites
    clone_wordpress_directory
    display_instructions
    
    # Disable cleanup on successful completion
    CLEANUP_ON_EXIT=false
}

# Run main function
main "$@"
