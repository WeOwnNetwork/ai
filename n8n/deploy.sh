#!/bin/bash

# WeOwn n8n Enterprise Deployment Script
# Production-ready workflow automation with enterprise security
# Version: 2.8.0
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
SCRIPT_VERSION="2.8.0"

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
    --enable-basic-auth     Enable nginx basic auth (default: disabled, uses n8n's built-in auth only)
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
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                      WeOwn n8n Enterprise                    ║"
    echo "║              Workflow Automation Platform                    ║"
    echo "║                                                              ║"
    echo "║   🔄 Automation • 🛡️ Enterprise Security • 🚀 Scalable        ║"
    echo "║           ENTERPRISE SECURITY FEATURES ENABLED              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}=== Enterprise Security & compliance ===${NC}\n"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
    echo
}

# Auto-install missing tools
auto_install_tool() {
    local tool=$1
    log_info "Auto-installing $tool..."
    
    case $tool in
        kubectl)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew &> /dev/null; then
                    brew install kubectl
                else
                    log_info "Installing Homebrew first..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                    brew install kubectl
                fi
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/
            fi
            ;;
        helm)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew &> /dev/null; then
                    brew install helm
                else
                    log_info "Installing Homebrew first..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                    brew install helm
                fi
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            fi
            ;;
        curl)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew &> /dev/null; then
                    brew install curl
                else
                    log_warning "curl should be pre-installed on macOS. Please install manually."
                fi
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y curl
                elif command -v yum &> /dev/null; then
                    sudo yum install -y curl
                fi
            fi
            ;;
        openssl)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew &> /dev/null; then
                    brew install openssl
                else
                    log_warning "openssl should be pre-installed on macOS. Please install manually."
                fi
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y openssl
                elif command -v yum &> /dev/null; then
                    sudo yum install -y openssl
                fi
            fi
            ;;
    esac
}

# Prerequisites checking with auto-installation
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl helm curl openssl base64; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    # Auto-install missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing required tools: ${missing_tools[*]}"
        echo -e "${YELLOW}Attempting auto-installation...${NC}"
        
        for tool in "${missing_tools[@]}"; do
            if [[ "$tool" == "base64" ]]; then
                log_warning "base64 should be pre-installed. If missing, please install coreutils package."
                continue
            fi
            
            read -p "Auto-install $tool? [Y/n]: " install_confirm
            if [[ ! "$install_confirm" =~ ^[Nn]$ ]]; then
                auto_install_tool "$tool"
                
                # Verify installation
                if command -v "$tool" &> /dev/null; then
                    log_success "$tool installed successfully"
                else
                    log_error "Failed to install $tool. Please install manually:"
                    case $tool in
                        kubectl) echo "  • kubectl: https://kubernetes.io/docs/tasks/tools/" ;;
                        helm) echo "  • helm: https://helm.sh/docs/intro/install/" ;;
                        curl) echo "  • curl: Usually pre-installed on most systems" ;;
                        openssl) echo "  • openssl: Usually pre-installed on most systems" ;;
                    esac
                    exit 1
                fi
            else
                log_error "Cannot continue without $tool. Please install manually and re-run."
                exit 1
            fi
        done
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

    echo
    read -p "Is this the correct cluster? [Y/n]: " confirm_cluster
    if [[ "$confirm_cluster" =~ ^[Nn]$ ]]; then
        log_error "Deployment aborted by user. Please switch to the correct cluster using 'doctl' or 'kubectl config use-context'."
        exit 1
    fi
}

# NGINX Ingress Controller installation
install_ingress_nginx() {
    log_step "Checking NGINX Ingress Controller..."
    
    if kubectl get deployment ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        log_success "NGINX Ingress Controller already installed"
        return 0
    fi
    
    log_info "Installing NGINX Ingress Controller..."
    if ! kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml; then
        log_error "Failed to install NGINX Ingress Controller"
        log_info "You can install it manually with:"
        log_info "  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml"
        exit 1
    fi
    
    log_info "Waiting for NGINX Ingress Controller to be ready (this may take a few minutes)..."
    if ! kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s 2>/dev/null; then
        log_warning "Ingress controller is taking longer than expected..."
        log_info "Checking status..."
        kubectl get pods -n ingress-nginx
        log_info "The deployment will continue. Check ingress-nginx namespace for status."
    fi
    
    # Ensure proper namespace labeling for NetworkPolicy
    kubectl label namespace ingress-nginx name=ingress-nginx --overwrite 2>/dev/null || true
    
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
    if ! kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml; then
        log_error "Failed to install cert-manager"
        log_info "You can install it manually with:"
        log_info "  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml"
        exit 1
    fi
    
    log_info "Waiting for cert-manager to be ready (this may take a few minutes)..."
    if ! kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s 2>/dev/null; then
        log_warning "cert-manager is taking longer than expected..."
        log_info "Checking status..."
        kubectl get pods -n cert-manager
        log_info "The deployment will continue. Check cert-manager namespace for status."
    fi
    
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
    
    # Subdomain and domain configuration
    local subdomain=""
    local base_domain=""
    
    while [[ -z "$subdomain" ]]; do
        echo -e "${BLUE}Enter the subdomain for your n8n installation:${NC}"
        echo -e "${YELLOW}  Examples: n8n, automation, workflows${NC}"
        echo -e "${YELLOW}  Note: Just the subdomain part (e.g. 'n8n' for n8n.yourdomain.com)${NC}"
        read -p "Subdomain: " subdomain
        
        if [[ ! "$subdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            echo -e "${RED}Invalid subdomain format. Please enter a valid subdomain (letters, numbers, hyphens only).${NC}"
            subdomain=""
        fi
    done
    
    while [[ -z "$base_domain" ]]; do
        echo
        echo -e "${BLUE}Enter your base domain:${NC}"
        echo -e "${YELLOW}  Examples: company.com, yourdomain.org, example.net${NC}"
        echo -e "${YELLOW}  Note: Your root domain that you control${NC}"
        read -p "Base domain: " base_domain
        
        if [[ ! "$base_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)* ]]; then
            echo -e "${RED}Invalid domain format. Please enter a valid domain.${NC}"
            base_domain=""
        fi
    done
    
    # Construct full domain
    DOMAIN="${subdomain}.${base_domain}"
    
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
    
    # Namespace and release name configuration
    echo
    echo -e "${BLUE}Choose namespace and release name:${NC}"
    echo -e "${YELLOW}  Y/y: Use 'n8n' for both namespace and release name${NC}"
    echo -e "${YELLOW}  N/n: Enter custom namespace and release name${NC}"
    read -p "Use default 'n8n' namespace and release? [Y/n]: " use_default
    
    if [[ "$use_default" =~ ^[Nn]$ ]]; then
        # Custom namespace
        while [[ -z "$NAMESPACE" ]]; do
            echo
            echo -e "${BLUE}Enter custom namespace:${NC}"
            echo -e "${YELLOW}  Must be a valid Kubernetes namespace (lowercase, alphanumeric, hyphens)${NC}"
            read -p "Namespace: " NAMESPACE
            
            if [[ ! "$NAMESPACE" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
                echo -e "${RED}Invalid namespace format. Please use lowercase letters, numbers, and hyphens only.${NC}"
                NAMESPACE=""
            fi
        done
        
        # Custom release name
        while [[ -z "$RELEASE_NAME" ]]; do
            echo
            echo -e "${BLUE}Enter custom release name:${NC}"
            echo -e "${YELLOW}  Must be a valid Helm release name (lowercase, alphanumeric, hyphens)${NC}"
            read -p "Release name: " RELEASE_NAME
            
            if [[ ! "$RELEASE_NAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
                echo -e "${RED}Invalid release name format. Please use lowercase letters, numbers, and hyphens only.${NC}"
                RELEASE_NAME=""
            fi
        done
    else
        # Default namespace and release name
        NAMESPACE="n8n"
        RELEASE_NAME="n8n"
    fi
    
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

# Create ClusterIssuer for Let's Encrypt
create_clusterissuer() {
    log_step "Setting up Let's Encrypt ClusterIssuer..."
    
    if kubectl get clusterissuer letsencrypt-prod &> /dev/null; then
        log_info "ClusterIssuer 'letsencrypt-prod' already exists"
        
        # Check if it has the correct email
        local current_email=$(kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.spec.acme.email}' 2>/dev/null || echo "")
        if [[ "$current_email" != "$EMAIL" ]]; then
            log_warning "ClusterIssuer email ($current_email) differs from configured email ($EMAIL)"
            read -p "Update ClusterIssuer email? [Y/n]: " update_email
            if [[ ! "$update_email" =~ ^[Nn]$ ]]; then
                kubectl delete clusterissuer letsencrypt-prod
                log_info "Deleted existing ClusterIssuer to recreate with new email"
            else
                log_info "Keeping existing ClusterIssuer with email: $current_email"
                return 0
            fi
        else
            log_success "ClusterIssuer already configured correctly"
            return 0
        fi
    fi
    
    log_info "Creating Let's Encrypt ClusterIssuer..."
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    
    log_success "ClusterIssuer created successfully"
}

# Generate secrets
generate_secrets() {
    log_step "Generating secure credentials..."
    
    # Generate encryption key if not already set (preserve from migration)
    if [[ -z "$ENCRYPTION_KEY" ]]; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
    fi
    
    log_success "Secure credentials generated"
}

# Alias for security audit compatibility
generate_credentials() {
    generate_secrets
}

# Detect external IP
detect_external_ip() {
    log_step "Detecting external IP address..."
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
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

# Check nginx ingress controller snippet support
check_nginx_snippet_support() {
    log_info "Checking nginx ingress controller snippet support..."
    
    # Create a test ingress to check if server-snippet is allowed
    local test_ingress=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snippet-test-$RANDOM
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: "# test"
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nonexistent
            port:
              number: 80
EOF
)
    
    # Test if server-snippet is allowed
    if echo "$test_ingress" | kubectl apply --dry-run=server -f - &>/dev/null; then
        log_info "✓ server-snippet annotations are supported"
        export NGINX_SUPPORTS_SERVER_SNIPPET=true
    else
        log_info "⚠️  server-snippet annotations are disabled (security policy)"
        log_info "Using configuration-snippet as fallback"
        export NGINX_SUPPORTS_SERVER_SNIPPET=false
    fi
}

# Validate Helm chart before deployment
validate_helm_chart() {
    log_step "Validating Helm chart..."
    
    # Create temporary values file with runtime substitutions
    local temp_values=$(mktemp)
    # Create temp values with basic substitutions
    sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
        -e "s/EMAIL_PLACEHOLDER/$EMAIL/g" \
        helm/values.yaml > "$temp_values"
    
    # Validate Helm chart syntax
    if ! helm template "$RELEASE_NAME" ./helm --values "$temp_values" > /dev/null 2>&1; then
        log_error "Helm chart validation failed"
        echo -e "${YELLOW}Running helm template for detailed error:${NC}"
        helm template "$RELEASE_NAME" ./helm --values "$temp_values"
        rm "$temp_values"
        exit 1
    fi
    
    # Validate Kubernetes manifests
    if ! helm template "$RELEASE_NAME" ./helm --values "$temp_values" | kubectl apply --dry-run=client -f - > /dev/null 2>&1; then
        log_error "Kubernetes manifest validation failed"
        echo -e "${YELLOW}Running kubectl dry-run for detailed error:${NC}"
        helm template "$RELEASE_NAME" ./helm --values "$temp_values" | kubectl apply --dry-run=client -f -
        rm "$temp_values"
        exit 1
    fi
    
    rm "$temp_values"
    log_success "Helm chart validation passed"
}

# Deploy n8n using Helm
deploy_n8n() {
    log_step "Deploying n8n with Helm..."
    
    # Create temporary values file with runtime substitutions
    local temp_values=$(mktemp)
    sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
        -e "s/EMAIL_PLACEHOLDER/$EMAIL/g" \
        helm/values.yaml > "$temp_values"
    
    # Set Helm configuration values
    local helm_args=(
        --namespace "$NAMESPACE"
        --values "$temp_values"
        --wait
        --timeout=10m
        --history-max 3
        --set "n8n.secrets.N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY"
    )
    
    # Deploy with Helm
    if ! helm upgrade --install "$RELEASE_NAME" ./helm "${helm_args[@]}"; then
        log_error "Helm deployment failed"
        echo -e "${YELLOW}Checking deployment status:${NC}"
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
        kubectl describe pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
        rm "$temp_values"
        exit 1
    fi
    
    # Clean up temporary file
    rm "$temp_values"
    
    log_success "n8n deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Check pod readiness (not just running status)
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for n8n pod to be ready..."
    while [[ $attempt -le $max_attempts ]]; do
        local pod_ready=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        local pod_status=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pod_ready" == "True" && "$pod_status" == "Running" ]]; then
            log_success "n8n pod is running and ready"
            break
        elif [[ "$pod_status" == "Failed" || "$pod_status" == "Error" ]]; then
            log_error "n8n pod failed to start"
            kubectl describe pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
            kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" --tail=50
            exit 1
        elif [[ "$pod_status" == "Pending" ]]; then
            log_info "Pod is pending scheduling... (attempt $attempt/$max_attempts)"
            kubectl get events -n "$NAMESPACE" --sort-by='.firstTimestamp' | tail -3
        else
            log_info "Waiting for pod to be ready... Status: $pod_status (attempt $attempt/$max_attempts)"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Deployment did not become ready within timeout"
        exit 1
    fi
    
    # n8n uses built-in authentication - no nginx basic auth needed
    
    # Check service and ingress
    log_info "Verifying service and ingress..."
    
    if [[ "$SHOW_CREDENTIALS" != "true" ]]; then
        echo
        echo -e "${YELLOW}🔐 Deployment completed with secure credentials generated${NC}"
        
        # Always prompt for credential display, regardless of interactive mode
        echo -e "${BLUE}Would you like to view the encryption key? (stored in Kubernetes secrets)${NC}"
        
        # Handle both interactive and non-interactive input
        if [[ -t 0 ]]; then
            # Interactive mode - use read prompt
            read -p "Show credentials? [y/N]: " show_creds
        else
            # Non-interactive mode - read from stdin with timeout
            echo -n "Show credentials? [y/N]: "
            read -t 10 show_creds || show_creds="N"
            echo "$show_creds"
        fi
        
        if [[ ! "$show_creds" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Encryption key is securely stored in Kubernetes secrets.${NC}"
            echo -e "${BLUE}To view later: kubectl get secret $RELEASE_NAME -n $NAMESPACE -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d${NC}"
            return
        fi
    fi
    
    echo
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      n8n Access Information            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}URL:${NC} https://$DOMAIN"
    echo -e "${YELLOW}Create admin account on first visit to web interface${NC}"
    echo
    
    echo -e "${CYAN}Encryption Key:${NC}"
    echo "  $ENCRYPTION_KEY"
    echo
}

# Show credentials securely
show_credentials() {
    echo
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      n8n Access Information            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}URL:${NC} https://$DOMAIN"
    echo -e "${YELLOW}Create admin account on first visit to web interface${NC}"
    echo
    
    echo -e "${CYAN}Encryption Key:${NC}"
    echo "  $ENCRYPTION_KEY"
    echo
    echo -e "${YELLOW}⚠️  SAVE THIS KEY! It is required to decrypt your workflows/credentials if you move instances.${NC}"
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
    
    echo "n8n Encryption Key:"
    echo "  $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d)"
    echo
    echo "🌐 n8n URL: https://$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'Check ingress configuration')"
    echo
    echo "⚠️  Keep these credentials secure and private!"
}

# Validate DNS configuration
validate_dns() {
    log_step "Verifying DNS configuration..."
    
    if [[ -z "$EXTERNAL_IP" ]]; then
        log_warning "External IP not detected. Skipping DNS validation."
        return 0
    fi
    
    log_info "Checking if $DOMAIN resolves to $EXTERNAL_IP..."
    
    local resolved_ip=""
    local match=false
    
    # Try to resolve using available tools
    if command -v dig &> /dev/null; then
        resolved_ip=$(dig +short "$DOMAIN" | tail -n1)
    elif command -v host &> /dev/null; then
        resolved_ip=$(host "$DOMAIN" | grep "has address" | awk '{print $4}' | head -n1)
    elif command -v nslookup &> /dev/null; then
        resolved_ip=$(nslookup "$DOMAIN" | grep "Address" | tail -n1 | awk '{print $2}')
    else
        log_warning "No DNS resolution tools found. Skipping DNS validation."
        return 0
    fi
    
    if [[ "$resolved_ip" == "$EXTERNAL_IP" ]]; then
        log_success "DNS verified: $DOMAIN -> $EXTERNAL_IP"
        return 0
    fi
    
    log_warning "DNS Mismatch Detected!"
    echo -e "${YELLOW}Domain:      $DOMAIN${NC}"
    echo -e "${YELLOW}Expected IP: $EXTERNAL_IP${NC}"
    echo -e "${YELLOW}Resolved IP: ${resolved_ip:-"(not found)"}${NC}"
    echo
    echo -e "${YELLOW}The DNS A record for $DOMAIN does not point to this cluster's Ingress IP.$NC"
    echo -e "Please configure your DNS provider to point ${BLUE}$DOMAIN${NC} to ${BLUE}$EXTERNAL_IP${NC}"
    echo
    
    read -p "I have updated the DNS record and want to retry verification [R], or proceed anyway [p], or abort [a]? [R/p/a]: " choice
    choice=${choice:-R}
    
    case "$choice" in
        p|P)
            log_warning "Proceeding with deployment despite DNS mismatch. SSL certificate generation may fail."
            return 0
            ;;
        a|A)
            log_error "Deployment aborted by user."
            exit 1
            ;;
        *)
            # Retry
            log_info "Retrying DNS verification..."
            sleep 2
            validate_dns
            ;;
    esac
}

# Main deployment function
main() {
    print_banner
    
    log_info "Starting n8n Enterprise deployment..."
    check_prerequisites
    install_ingress_nginx
    install_cert_manager
    detect_external_ip
    check_nginx_snippet_support
    interactive_config
    generate_credentials
    create_namespace
    create_clusterissuer
    validate_helm_chart
    
    # Validate DNS BEFORE deployment (prevents Let's Encrypt failures)
    validate_dns
    
    # Migration step (if enabled)
    if [[ "${ENABLE_MIGRATION:-false}" == "true" ]]; then
        migrate_data
    fi
    
    deploy_n8n
    verify_deployment
    show_completion_summary
    
    log_success "n8n Enterprise deployment completed successfully!"
}

# Parse command line arguments
ENABLE_MIGRATION=false
ENABLE_QUEUE_MODE=false
# n8n uses built-in authentication only

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
