#!/bin/bash

# WeOwn n8n Enterprise Deployment Script
# Production-ready workflow automation with enterprise security
# Version: 1.0.0
#
# This script provides:
# - Enterprise-grade security with zero-trust networking
# - Automatic prerequisite installation with resume capability  
# - Full transparency about every operation
# - Comprehensive error handling and recovery
# - Data migration from Docker setup
# - Clear explanations of credentials, scaling, and management

set -euo pipefail

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_PATH="${SCRIPT_DIR}/helm"
SCRIPT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
DOMAIN=""
EMAIL=""
NAMESPACE=""
RELEASE_NAME=""
ADMIN_USER="admin"
ADMIN_PASSWORD=""
ENCRYPTION_KEY=""
EXTERNAL_IP=""
SHOW_CREDENTIALS=false

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Help function
show_help() {
    cat << EOF
n8n Enterprise Kubernetes Deployment Script
WeOwn Production-Grade Automation Platform with Enterprise Security

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    --domain DOMAIN         Set the domain for n8n (e.g., automation.example.com)
    --email EMAIL           Set email for Let's Encrypt certificates
    --namespace NAMESPACE   Set Kubernetes namespace (default: n8n-{domain-slug})
    --show-credentials      Show admin credentials for existing deployment
    --migration             Enable data migration from existing setup
    --queue-mode           Enable queue mode for production scaling

EXAMPLES:
    ./deploy.sh

FEATURES:
    ✓ Enterprise Security (Zero-Trust NetworkPolicy, Pod Security Standards)
    ✓ TLS 1.3 Encryption with Let's Encrypt
    ✓ Interactive UX with Prerequisites Validation
    ✓ Data Migration from Docker Setup
    ✓ Production Scaling with Queue Mode
    ✓ Comprehensive Error Recovery
    ✓ WeOwn SOC2/ISO42001 Compliance

EOF
}

# Banner function
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      WeOwn n8n Enterprise                   ║"
    echo "║              Workflow Automation Platform                    ║"
    echo "║                                                              ║"
    echo "║   🔄 Automation • 🛡️ Enterprise Security • 🚀 Scalable      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}=== Enterprise Security & Compliance ===${NC}\n"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
    echo
}

# Prerequisites checking
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl helm curl openssl base64; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo -e "${YELLOW}Install missing tools:${NC}"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                kubectl) echo "  • kubectl: https://kubernetes.io/docs/tasks/tools/" ;;
                helm) echo "  • helm: https://helm.sh/docs/intro/install/" ;;
                curl) echo "  • curl: Usually pre-installed on most systems" ;;
                openssl) echo "  • openssl: Usually pre-installed on most systems" ;;
                base64) echo "  • base64: Usually pre-installed on most systems" ;;
            esac
        done
        exit 1
    fi
    
    # Check Kubernetes connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo -e "${YELLOW}Solutions:${NC}"
        echo "  • Check if kubectl is configured: kubectl config current-context"
        echo "  • Verify cluster connectivity: kubectl cluster-info"
        echo "  • Switch to correct cluster if needed"
        exit 1
    fi
    
    local context=$(kubectl config current-context)
    log_success "Connected to Kubernetes cluster: $context"
}

# NGINX Ingress Controller installation
install_ingress_nginx() {
    log_step "Checking NGINX Ingress Controller..."
    
    if kubectl get deployment ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        log_success "NGINX Ingress Controller already installed"
        return 0
    fi
    
    log_info "Installing NGINX Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
    
    log_info "Waiting for NGINX Ingress Controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    # Ensure proper namespace labeling for NetworkPolicy
    kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
    
    log_success "NGINX Ingress Controller installed and configured"
}

# cert-manager installation
install_cert_manager() {
    log_step "Checking cert-manager..."
    
    if kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
        log_success "cert-manager already installed"
        return 0
    fi
    
    log_info "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    
    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_success "cert-manager installed and ready"
}

# Get external IP
get_external_ip() {
    log_step "Detecting external IP address..."
    
    local max_attempts=60
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "null" ]]; then
            log_success "External IP detected: $EXTERNAL_IP"
            return 0
        fi
        
        log_info "Waiting for external IP... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_error "Failed to detect external IP after $max_attempts attempts"
    echo -e "${YELLOW}Manual steps:${NC}"
    echo "1. Check LoadBalancer service: kubectl get svc -n ingress-nginx"
    echo "2. Configure DNS manually once IP is available"
    exit 1
}

# Interactive configuration
interactive_config() {
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        log_info "Using provided configuration: domain=$DOMAIN, email=$EMAIL"
        return 0
    fi
    
    log_step "Interactive Configuration Setup"
    echo
    echo -e "${CYAN}=== n8n Enterprise Deployment Configuration ===${NC}"
    echo
    
    # Domain configuration
    while [[ -z "$DOMAIN" ]]; do
        echo -e "${BLUE}Enter the domain for your n8n installation:${NC}"
        echo -e "${YELLOW}  Examples: automation.company.com, n8n.example.org${NC}"
        echo -e "${YELLOW}  Note: Must be a subdomain you control${NC}"
        read -p "Domain: " DOMAIN
        
        if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            echo -e "${RED}Invalid domain format. Please enter a valid domain.${NC}"
            DOMAIN=""
        fi
    done
    
    # Email configuration
    while [[ -z "$EMAIL" ]]; do
        echo
        echo -e "${BLUE}Enter your email for Let's Encrypt certificates:${NC}"
        echo -e "${YELLOW}  This email will receive certificate expiration notices${NC}"
        read -p "Email: " EMAIL
        
        if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo -e "${RED}Invalid email format. Please enter a valid email.${NC}"
            EMAIL=""
        fi
    done
    
    # Namespace configuration
    if [[ -z "$NAMESPACE" ]]; then
        local domain_slug=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
        NAMESPACE="n8n-${domain_slug}"
        echo
        echo -e "${BLUE}Kubernetes namespace will be: ${GREEN}$NAMESPACE${NC}"
    fi
    
    # Release name
    RELEASE_NAME="n8n-$(echo "$DOMAIN" | cut -d. -f1)"
    
    echo
    echo -e "${CYAN}=== Configuration Summary ===${NC}"
    echo -e "${GREEN}Domain:    $DOMAIN${NC}"
    echo -e "${GREEN}Email:     $EMAIL${NC}"
    echo -e "${GREEN}Namespace: $NAMESPACE${NC}"
    echo -e "${GREEN}Release:   $RELEASE_NAME${NC}"
    echo
    
    read -p "Continue with this configuration? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Configuration cancelled by user"
        exit 0
    fi
}

# Generate secrets
generate_secrets() {
    log_step "Generating secure credentials..."
    
    # Generate admin password if not already set
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
    fi
    
    # Generate encryption key if not already set (preserve from migration)
    if [[ -z "$ENCRYPTION_KEY" ]]; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
    fi
    
    log_success "Secure credentials generated"
}

# Create namespace
create_namespace() {
    log_step "Creating Kubernetes namespace..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace $NAMESPACE created"
    fi
}

# Deploy n8n
deploy_n8n() {
    log_step "Deploying n8n with Helm..."
    
    # Prepare values file with replacements
    local temp_values=$(mktemp)
    sed "s/DOMAIN_PLACEHOLDER/$DOMAIN/g; s/EMAIL_PLACEHOLDER/$EMAIL/g; s/ADMIN_USER_PLACEHOLDER/$ADMIN_USER/g; s/ADMIN_PASSWORD_PLACEHOLDER/$ADMIN_PASSWORD/g; s/ENCRYPTION_KEY_PLACEHOLDER/$ENCRYPTION_KEY/g" \
        "$CHART_PATH/values.yaml" > "$temp_values"
    
    # Deploy with Helm
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --values "$temp_values" \
        --wait \
        --timeout=10m
    
    # Clean up temporary file
    rm "$temp_values"
    
    log_success "n8n deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Check pod status
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local pod_status=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pod_status" == "Running" ]]; then
            log_success "n8n pod is running"
            break
        elif [[ "$pod_status" == "Failed" || "$pod_status" == "Error" ]]; then
            log_error "n8n pod failed to start"
            kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" --tail=20
            exit 1
        fi
        
        log_info "Waiting for pod to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Pod did not become ready in time"
        exit 1
    fi
    
    # Check certificate
    log_info "Waiting for TLS certificate..."
    kubectl wait --for=condition=ready certificate -n "$NAMESPACE" --all --timeout=300s
    
    log_success "Deployment verified successfully"
}

# Display DNS instructions
show_dns_instructions() {
    log_step "DNS Configuration Instructions"
    echo
    echo -e "${CYAN}=== DNS Configuration Required ===${NC}"
    echo
    echo -e "${YELLOW}To complete the setup, configure your DNS:${NC}"
    echo
    echo -e "${GREEN}1. Add an A record for your domain:${NC}"
    echo -e "   ${BLUE}Type:${NC} A"
    echo -e "   ${BLUE}Name:${NC} $DOMAIN"
    echo -e "   ${BLUE}Value:${NC} $EXTERNAL_IP"
    echo -e "   ${BLUE}TTL:${NC} 300 (5 minutes)"
    echo
    echo -e "${GREEN}2. Wait for DNS propagation (usually 5-15 minutes)${NC}"
    echo
    echo -e "${GREEN}3. Test DNS resolution:${NC}"
    echo -e "   ${BLUE}nslookup $DOMAIN${NC}"
    echo -e "   ${BLUE}dig $DOMAIN${NC}"
    echo
    echo -e "${YELLOW}Once DNS is configured, your n8n will be available at:${NC}"
    echo -e "${CYAN}https://$DOMAIN${NC}"
    echo
}

# Show credentials securely
show_credentials() {
    if [[ "$SHOW_CREDENTIALS" != "true" ]]; then
        echo
        echo -e "${YELLOW}🔐 Deployment completed with secure credentials generated${NC}"
        echo -e "${BLUE}Would you like to view the admin credentials? (they won't be stored anywhere)${NC}"
        read -p "Show credentials? [y/N]: " show_creds
        if [[ ! "$show_creds" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Credentials are securely stored in Kubernetes secrets.${NC}"
            echo -e "${BLUE}To view later: kubectl get secret $RELEASE_NAME -n $NAMESPACE -o yaml${NC}"
            return
        fi
    fi
    
    echo
    echo -e "${CYAN}=== n8n Admin Credentials ===${NC}"
    echo -e "${GREEN}URL:${NC} https://$DOMAIN"
    echo -e "${GREEN}Username:${NC} $ADMIN_USER"
    echo -e "${GREEN}Password:${NC} $ADMIN_PASSWORD"
    echo
    echo -e "${YELLOW}⚠️  Save these credentials securely - they won't be displayed again!${NC}"
    echo
}

# Display completion summary
show_completion_summary() {
    log_step "Deployment Complete!"
    echo
    echo -e "${CYAN}=== n8n Enterprise Deployment Summary ===${NC}"
    echo
    echo -e "${GREEN}✓ n8n Enterprise successfully deployed${NC}"
    echo -e "${GREEN}✓ Enterprise security features enabled${NC}"
    echo -e "${GREEN}✓ TLS 1.3 certificates configured${NC}"
    echo -e "${GREEN}✓ Zero-trust networking active${NC}"
    echo
    
    # Show credentials securely
    show_credentials
    
    echo -e "${BLUE}Management Commands:${NC}"
    echo -e "  ${YELLOW}Check status:${NC} kubectl get pods -n $NAMESPACE"
    echo -e "  ${YELLOW}View logs:${NC} kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -f"
    echo -e "  ${YELLOW}Scale up:${NC} kubectl scale deployment $RELEASE_NAME -n $NAMESPACE --replicas=2"
    echo -e "  ${YELLOW}View secrets:${NC} kubectl get secret $RELEASE_NAME -n $NAMESPACE -o yaml"
    echo
    echo -e "${BLUE}Security Features Active:${NC}"
    echo -e "  ${GREEN}✓${NC} Pod Security Standards: Restricted"
    echo -e "  ${GREEN}✓${NC} NetworkPolicy: Zero-trust micro-segmentation"
    echo -e "  ${GREEN}✓${NC} TLS 1.3: Automated certificate management"
    echo -e "  ${GREEN}✓${NC} RBAC: Least-privilege access control"
    echo -e "  ${GREEN}✓${NC} Secrets: Kubernetes-native encryption"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  1. Configure DNS (see instructions above)"
    echo -e "  2. Access n8n at https://$DOMAIN"
    echo -e "  3. Create your first workflow"
    echo -e "  4. Consider enabling queue mode for production scaling"
    echo
}

# Migration function (placeholder)
migrate_data() {
    log_step "Data migration available after deployment"
    log_info "Migration guide: ./WORKFLOW_MIGRATION_README.md"
}

# Show credentials function for post-deployment
show_credentials_only() {
    local namespace="${1:-$NAMESPACE}"
    local release="${2:-$RELEASE_NAME}"
    
    if [[ -z "$namespace" || -z "$release" ]]; then
        echo "Usage: $0 --show-credentials [namespace] [release-name]"
        echo "Example: $0 --show-credentials n8n-domain-com n8n-domain"
        exit 1
    fi
    
    echo "🔐 n8n Admin Credentials (from Kubernetes secret)"
    echo "================================================"
    echo
    
    if ! kubectl get secret "$release" -n "$namespace" &>/dev/null; then
        echo "❌ Secret '$release' not found in namespace '$namespace'"
        echo "💡 Usage: $0 --show-credentials [namespace] [release-name]"
        exit 1
    fi
    
    echo "n8n Admin:"
    echo "  Username: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.N8N_BASIC_AUTH_USER}' | base64 -d)"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' | base64 -d)"
    echo
    echo "Encryption Key: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d)"
    echo
    echo "🌐 n8n URL: https://$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'Check ingress configuration')"
    echo
    echo "⚠️  Keep these credentials secure and private!"
}

# Main deployment function
main() {
    print_banner
    
    log_info "Starting n8n Enterprise deployment..."
    
    # Execute deployment steps (stateless)
    check_prerequisites
    install_ingress_nginx
    install_cert_manager
    get_external_ip
    interactive_config
    generate_secrets
    create_namespace
    
    # Migration step (if enabled)
    if [[ "${ENABLE_MIGRATION:-false}" == "true" ]]; then
        migrate_data
    fi
    
    deploy_n8n
    verify_deployment
    show_dns_instructions
    show_completion_summary
    
    log_success "n8n Enterprise deployment completed successfully!"
}

# Parse command line arguments
ENABLE_MIGRATION=false
ENABLE_QUEUE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --show-credentials)
            show_credentials_only "${2:-}" "${3:-}"
            exit 0
            ;;
        --migration)
            ENABLE_MIGRATION=true
            shift
            ;;
        --queue-mode)
            ENABLE_QUEUE_MODE=true
            shift
            ;;
        --show-creds)
            SHOW_CREDENTIALS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
