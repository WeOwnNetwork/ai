#!/bin/bash

# WeOwn AnythingLLM Enterprise Deployment Script
# Version: 2.0.0 - Enhanced with robust error handling and transparency
# 
# This script provides:
# - Automatic prerequisite installation with resume capability
# - Full transparency about every operation
# - Comprehensive error handling and recovery
# - Clear explanations of admin credentials, updates, backups, and scaling

set -euo pipefail

# Source the deployment functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deploy-functions.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="anything-llm"
RELEASE_NAME="anythingllm"
CHART_PATH="."

# State file for resume capability
STATE_FILE="/tmp/anythingllm-deploy-state-$(whoami)"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Enhanced logging with timestamps
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$STATE_FILE.log"
}

# State management functions
save_state() {
    local step="$1"
    echo "CURRENT_STEP=$step" > "$STATE_FILE"
    echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_FILE"
    log_with_timestamp "State saved: $step"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        log_info "Resuming from step: $CURRENT_STEP"
        return 0
    fi
    return 1
}

clear_state() {
    rm -f "$STATE_FILE" "$STATE_FILE.log"
}

# Enhanced tool installation with logging
install_tool_with_logging() {
    local tool="$1"
    local os="$2"
    
    log_info "Installing $tool for $os..."
    log_info "This installation will be logged for transparency."
    
    case "$tool" in
        "kubectl")
            case "$os" in
                "macOS")
                    if command -v brew >/dev/null 2>&1; then
                        log_info "Using Homebrew to install kubectl..."
                        brew install kubectl 2>&1 | tee -a "$STATE_FILE.log"
                    else
                        log_info "Downloading kubectl directly..."
                        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
                        chmod +x kubectl
                        sudo mv kubectl /usr/local/bin/
                    fi
                    ;;
                "Linux")
                    log_info "Downloading kubectl for Linux..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x kubectl
                    sudo mv kubectl /usr/local/bin/
                    ;;
            esac
            ;;
        "helm")
            case "$os" in
                "macOS")
                    if command -v brew >/dev/null 2>&1; then
                        log_info "Using Homebrew to install Helm..."
                        brew install helm 2>&1 | tee -a "$STATE_FILE.log"
                    else
                        log_info "Using Helm install script..."
                        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>&1 | tee -a "$STATE_FILE.log"
                    fi
                    ;;
                "Linux")
                    log_info "Using Helm install script for Linux..."
                    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>&1 | tee -a "$STATE_FILE.log"
                    ;;
            esac
            ;;
    esac
    
    # Verify installation
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool installed successfully!"
        return 0
    else
        log_error "$tool installation failed!"
        return 1
    fi
}

# Enhanced prerequisite checking with auto-install
check_prerequisites_enhanced() {
    log_step "Checking prerequisites and system requirements"
    echo
    
    local os=$(detect_os)
    log_info "Detected operating system: $os"
    echo
    
    local tools=("kubectl" "helm" "curl" "git" "openssl")
    local missing_tools=()
    
    # Check all tools first
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        else
            log_success "$tool is installed ✓"
        fi
    done
    
    # Handle missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo
        log_warning "Missing tools detected: ${missing_tools[*]}"
        echo
        
        if ask_yes_no "Would you like me to automatically install the missing tools?"; then
            for tool in "${missing_tools[@]}"; do
                log_info "Installing $tool..."
                if install_tool_with_logging "$tool" "$os"; then
                    log_success "$tool installed successfully!"
                else
                    log_error "Failed to install $tool automatically."
                    log_info "Please install $tool manually and re-run this script."
                    log_info "Installation instructions:"
                    get_install_instructions "$tool" "$os"
                    exit 1
                fi
            done
            
            log_success "All missing tools have been installed!"
            save_state "PREREQUISITES_COMPLETE"
        else
            log_error "Cannot continue without required tools."
            log_info "Please install the missing tools and re-run this script."
            log_info "The script will automatically resume from where it left off."
            exit 1
        fi
    else
        log_success "All prerequisites are installed!"
        save_state "PREREQUISITES_COMPLETE"
    fi
}

# Enhanced cluster prerequisite installation
install_cluster_prerequisites_enhanced() {
    log_step "Installing cluster prerequisites"
    echo
    
    log_info "AnythingLLM requires NGINX Ingress Controller and cert-manager for HTTPS."
    log_info "I'll install these components with full logging and progress tracking."
    echo
    
    # Install NGINX Ingress Controller
    if ! kubectl get namespace ingress-nginx &>/dev/null; then
        log_info "Installing NGINX Ingress Controller..."
        log_info "⏱️  This typically takes 2-3 minutes. Please be patient."
        log_info "📋 Full installation logs are being captured."
        
        # Create progress indicator
        (
            while ps aux | grep -q "[h]elm.*ingress-nginx" 2>/dev/null; do
                echo -n "."
                sleep 5
            done
        ) &
        local progress_pid=$!
        
        # Install with logging
        helm upgrade --install ingress-nginx ingress-nginx \
            --repo https://kubernetes.github.io/ingress-nginx \
            --namespace ingress-nginx --create-namespace \
            --set controller.service.type=LoadBalancer \
            --wait --timeout=10m 2>&1 | tee -a "$STATE_FILE.log"
        
        kill $progress_pid 2>/dev/null || true
        echo
        log_success "NGINX Ingress Controller installed successfully!"
        save_state "INGRESS_INSTALLED"
    else
        log_success "NGINX Ingress Controller is already installed ✓"
    fi
    
    # Install cert-manager
    if ! kubectl get namespace cert-manager &>/dev/null; then
        log_info "Installing cert-manager..."
        log_info "⏱️  This typically takes 1-2 minutes. Please be patient."
        log_info "📋 Full installation logs are being captured."
        
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml 2>&1 | tee -a "$STATE_FILE.log"
        
        log_info "Waiting for cert-manager to be ready..."
        kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
        kubectl wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s
        kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s
        
        log_success "cert-manager installed successfully!"
        save_state "CERT_MANAGER_INSTALLED"
    else
        log_success "cert-manager is already installed ✓"
    fi
}

# Enhanced admin credential explanation
explain_admin_credentials() {
    echo
    log_info "🔐 UNDERSTANDING ADMIN CREDENTIALS"
    echo
    echo "The credentials generated during deployment serve multiple purposes:"
    echo
    echo "1. 🔧 SYSTEM AUTHENTICATION:"
    echo "   • Used for API access and system integrations"
    echo "   • Required for emergency admin access"
    echo "   • Stored securely in Kubernetes secrets"
    echo
    echo "2. 🌐 WEB INTERFACE ADMIN ACCOUNT:"
    echo "   • You'll create this AFTER deployment in the web UI"
    echo "   • Must enable 'Multi-User Mode' first (CRITICAL for security)"
    echo "   • Can use the same credentials or create new ones"
    echo
    echo "3. 🔒 SECURITY FLOW:"
    echo "   • Deploy → Access web interface → Enable Multi-User Mode → Create admin account"
    echo "   • Until you complete this flow, your instance is PUBLIC!"
    echo
    log_warning "The generated credentials are NOT automatically used for web login!"
    log_warning "You must manually create your web admin account after deployment!"
    echo
}

# Enhanced deployment with comprehensive explanations
deploy_with_explanations() {
    log_step "Deploying AnythingLLM with comprehensive explanations"
    echo
    
    explain_admin_credentials
    
    log_info "🚀 DEPLOYMENT PROCESS:"
    echo "1. Creating Kubernetes namespace and secrets"
    echo "2. Deploying AnythingLLM application with Helm"
    echo "3. Configuring ingress and TLS certificates"
    echo "4. Verifying deployment health"
    echo "5. Providing post-deployment security instructions"
    echo
    
    # Create namespace
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create secrets
    log_info "Creating Kubernetes secrets with generated credentials..."
    kubectl create secret generic anythingllm-secrets \
        --from-literal=ADMIN_EMAIL="$EMAIL" \
        --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --from-literal=JWT_SECRET="$JWT_SECRET" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secrets created successfully"
    
    # Deploy with Helm
    log_info "Deploying AnythingLLM with Helm..."
    log_info "⏱️  This typically takes 2-5 minutes depending on cluster resources."
    
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace="$NAMESPACE" \
        --set global.namespace="$NAMESPACE" \
        --set "ingress.hosts[0].host=$FULL_DOMAIN" \
        --set "ingress.hosts[0].paths[0].path=/" \
        --set "ingress.hosts[0].paths[0].pathType=Prefix" \
        --set "ingress.tls[0].hosts[0]=$FULL_DOMAIN" \
        --set "ingress.tls[0].secretName=anythingllm-tls" \
        --set anythingllm.secrets.secretName="anythingllm-secrets" \
        --set anythingllm.persistence.enabled=true \
        --set anythingllm.persistence.size=20Gi \
        --set anythingllm.persistence.storageClass="do-block-storage" \
        --wait --timeout=10m
    
    if [[ $? -eq 0 ]]; then
        log_success "AnythingLLM deployed successfully!"
        save_state "DEPLOYMENT_COMPLETE"
    else
        log_error "Deployment failed. Check the logs above for details."
        exit 1
    fi
}

# Post-deployment information
show_post_deployment_info() {
    echo
    log_success "🎉 DEPLOYMENT COMPLETE!"
    echo
    
    log_info "📊 DEPLOYMENT STATUS:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    
    log_info "🌐 INGRESS STATUS:"
    kubectl get ingress -n "$NAMESPACE"
    echo
    
    log_info "🔐 TLS CERTIFICATE STATUS:"
    local cert_status=$(kubectl get certificate -n "$NAMESPACE" -o jsonpath='{.items[0].status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    if [[ "$cert_status" == "True" ]]; then
        log_success "✅ TLS Certificate: Ready and Valid"
        echo "  Certificate: $(kubectl get certificate -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
        echo "  Issuer: Let's Encrypt Production"
    else
        log_warning "⏳ TLS Certificate: Still being issued..."
        echo "  This may take 2-5 minutes. Check status with:"
        echo "  kubectl get certificate -n $NAMESPACE"
    fi
    echo
    
    # Critical security warnings
    log_warning "🚨 CRITICAL SECURITY NOTICE 🚨"
    echo "${RED}Your AnythingLLM instance is currently PUBLIC and accessible to anyone!${NC}"
    echo
    echo "${YELLOW}IMMEDIATE ACTION REQUIRED:${NC}"
    echo "  1. Visit: https://$FULL_DOMAIN"
    echo "  2. Click Settings (⚙️) → Security"
    echo "  3. Enable 'Multi-User Mode' IMMEDIATELY"
    echo "  4. Create admin account (can use generated credentials or create new ones)"
    echo "  5. Configure your preferred LLM provider in Settings"
    echo
    
    # Updates, Backups, and Scaling Information
    show_maintenance_info
}

# Comprehensive maintenance information
show_maintenance_info() {
    log_info "🔧 UPDATES, BACKUPS & SCALING"
    echo
    
    echo "📈 SCALING YOUR DEPLOYMENT:"
    echo "  • Scale pods: kubectl scale deployment anythingllm -n $NAMESPACE --replicas=2"
    echo "  • Scale cluster nodes: Use DigitalOcean control panel or doctl"
    echo "  • For better AI models: Increase memory limits in values.yaml"
    echo "  • Monitor resources: kubectl top pods -n $NAMESPACE"
    echo
    
    echo "🔄 UPDATES:"
    echo "  • Manual updates: Re-run this deployment script"
    echo "  • Check for updates: helm list -n $NAMESPACE"
    echo "  • Update strategy: Rolling updates (zero downtime)"
    echo "  • Automatic updates: Not enabled by default (recommended for stability)"
    echo
    
    echo "💾 BACKUPS:"
    echo "  • Data location: Persistent volume (/app/server/storage)"
    echo "  • Backup method: DigitalOcean volume snapshots"
    echo "  • Manual backup: kubectl cp commands for critical data"
    echo "  • Recommended: Daily automated snapshots via DigitalOcean"
    echo
    
    echo "🌐 DNS & PRODUCTION SETTINGS:"
    echo "  • Current TTL: 300 seconds (5 minutes) - good for testing"
    echo "  • Production TTL: Consider 3600 seconds (1 hour) for stability"
    echo "  • Team usage: Keep 300s TTL for flexibility during setup"
    echo "  • Change TTL in your DNS provider when ready for production"
    echo
}

# Main deployment function
main() {
    # Clear previous state if starting fresh
    if [[ "${1:-}" == "--fresh" ]]; then
        clear_state
    fi
    
    # Show banner
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    WeOwn AnythingLLM                         ║"
    echo "║              Enterprise AI Assistant Platform                ║"
    echo "║                                                              ║"
    echo "║    🤖 Self-hosted • 🛡️  Enterprise Security • 🚀 Automated    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    echo "Version: 2.0.0 - Enhanced with robust error handling"
    echo
    
    # Load previous state if exists
    if load_state; then
        log_info "Resuming previous deployment..."
        echo
    fi
    
    # Step 1: Prerequisites
    if [[ "${CURRENT_STEP:-}" != "PREREQUISITES_COMPLETE" ]]; then
        check_prerequisites_enhanced
    fi
    
    # Step 2: Cluster connection
    if [[ "${CURRENT_STEP:-}" != *"CLUSTER"* ]]; then
        check_cluster_connection
        save_state "CLUSTER_CONNECTED"
    fi
    
    # Step 3: User configuration
    if [[ "${CURRENT_STEP:-}" != *"CONFIG"* ]]; then
        get_user_configuration
        save_state "CONFIG_COMPLETE"
    fi
    
    # Step 4: DNS setup
    if [[ "${CURRENT_STEP:-}" != *"DNS"* ]]; then
        setup_dns_instructions
        save_state "DNS_COMPLETE"
    fi
    
    # Step 5: Cluster prerequisites
    if [[ "${CURRENT_STEP:-}" != *"PREREQUISITES"* ]]; then
        install_cluster_prerequisites_enhanced
        save_state "CLUSTER_PREREQUISITES_COMPLETE"
    fi
    
    # Step 6: Deployment
    if [[ "${CURRENT_STEP:-}" != "DEPLOYMENT_COMPLETE" ]]; then
        deploy_with_explanations
    fi
    
    # Step 7: Post-deployment
    show_post_deployment_info
    
    # Clean up state file on successful completion
    clear_state
    
    log_success "🎉 AnythingLLM deployment completed successfully!"
    log_info "Remember to secure your instance immediately by enabling Multi-User Mode!"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh)
            FRESH_INSTALL=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# If no arguments provided, run interactive deployment
if [[ $# -eq 0 ]] || [[ "${FRESH_INSTALL:-}" == "true" ]]; then
    main "${@}"
else
    log_error "Invalid arguments. Use --help for usage information."
    exit 1
fi
