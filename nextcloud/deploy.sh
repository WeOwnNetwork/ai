#!/bin/bash

# Nextcloud Deployment Script
# Version: 1.0.0

# Function definitions first
show_credentials_only() {
    local namespace="nextcloud"
    local release="nextcloud"
    
    if [[ -n "${2:-}" ]]; then
        namespace="$2"
    fi
    if [[ -n "${3:-}" ]]; then
        release="$3"
    fi
    
    echo "Nextcloud Credentials"
    echo "===================="
    echo
    
    if ! kubectl get secret "$release" -n "$namespace" &>/dev/null; then
        echo "Secret '$release' not found in namespace '$namespace'"
        echo "Usage: $0 --show-credentials [namespace] [release-name]"
        exit 1
    fi
    
    echo "Nextcloud Admin:"
    echo "  Username: admin"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.NEXTCLOUD_ADMIN_PASSWORD}' | base64 -d)"
    echo
    echo "Database (PostgreSQL):"
    echo "  Root Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.POSTGRES_ROOT_PASSWORD}' | base64 -d)"
    echo "  Nextcloud Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
    echo
    echo "Redis Cache:"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d)"
    echo
    echo "🌐 Nextcloud URL: https://$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'Check ingress configuration')"
    echo
    echo "⚠️  Keep these credentials secure and private!"
}

show_help() {
    echo "Nextcloud Enterprise Deployment Script"
    echo "======================================="
    echo
    echo "Usage:"
    echo "  $0                                    # Deploy Nextcloud"
    echo "  $0 --show-credentials [ns] [release]  # Show credentials"
    echo "  $0 --cleanup [ns] [release]           # Clean up failed deployment"
    echo "  $0 --help                            # Show this help"
    echo
    echo "Examples:"
    echo "  $0 --show-credentials                 # Default namespace/release"
    echo "  $0 --show-credentials my-nc my-site   # Custom namespace/release"
    echo "  $0 --cleanup                          # Clean up default nextcloud"
    echo "  $0 --cleanup my-nc my-site            # Clean up custom deployment"
}

# Check for credential display flag
if [[ "$1" == "--show-credentials" ]]; then
    show_credentials_only "$@"
    exit 0
fi

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Check for cleanup flag
if [[ "$1" == "--cleanup" ]]; then
    namespace="${2:-nextcloud}"
    release="${3:-nextcloud}"
    cleanup_failed_deployment "$namespace" "$release"
    exit 0
fi

# Nextcloud Enterprise Deployment Script v1.0.0
# Enhanced security, user experience, and production readiness
# Compatible with enterprise zero-trust security standards

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
readonly SCRIPT_NAME="Nextcloud Enterprise Deployment"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_AUTHOR="WeOwn AI Infrastructure"

# Default values - standard Nextcloud naming
readonly DEFAULT_NAMESPACE="nextcloud"
readonly DEFAULT_RELEASE_NAME="nextcloud"
readonly HELM_CHART_PATH="./helm"

# Global variables
DOMAIN=""
SUBDOMAIN="nc"
NAMESPACE="${NAMESPACE:-}"  # Use environment variable or empty
RELEASE_NAME="${RELEASE_NAME:-}"  # Use environment variable or empty
EMAIL=""
DEPLOY_STATE=""
SKIP_PREREQUISITES=false
ENABLE_MONITORING=true
ENABLE_BACKUP=true
SHOW_CREDENTIALS="false"  # Default to secure behavior

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

# Cleanup function for failed deployments
cleanup_failed_deployment() {
    local namespace="$1"
    local release="$2"
    
    log_step "Cleaning up previous failed deployment"
    
    # Check if Helm release exists
    if helm list -n "$namespace" | grep -q "$release"; then
        log_substep "Uninstalling existing Helm release: $release"
        helm uninstall "$release" -n "$namespace" || true
    fi
    
    # Check for orphaned secrets that block Helm adoption
    local secrets_to_check=$(kubectl get secrets -n "$namespace" 2>/dev/null | grep -E "^(nextcloud|$release)" | awk '{print $1}')
    
    if [[ -n "$secrets_to_check" ]]; then
        log_substep "Checking for orphaned secrets from previous deployment"
        echo "$secrets_to_check" | while read -r secret; do
            # Check if secret has Helm management labels
            if ! kubectl get secret "$secret" -n "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null | grep -q "Helm"; then
                log_substep "Deleting orphaned secret: $secret"
                kubectl delete secret "$secret" -n "$namespace" 2>/dev/null || true
            else
                log_substep "Keeping Helm-managed secret: $secret"
            fi
        done
    fi
    
    # Clean up any leftover resources
    kubectl delete ingress,service,deployment,statefulset,configmap,pvc -n "$namespace" -l app.kubernetes.io/name=nextcloud 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# OS Detection and tool installation functions
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macOS" ;;
        Linux*) echo "Linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
        *) echo "Unknown" ;;
    esac
}

get_install_instructions() {
    local tool="$1"
    local os="$2"
    
    case "$tool" in
        "kubectl")
            case "$os" in
                "macOS") echo "Install via Homebrew: brew install kubectl" ;;
                "Linux") echo "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" ;;
                "Windows") echo "Install via Chocolatey: choco install kubernetes-cli" ;;
                *) echo "Visit: https://kubernetes.io/docs/tasks/tools/install-kubectl/" ;;
            esac
            ;;
        "helm")
            case "$os" in
                "macOS") echo "Install via Homebrew: brew install helm" ;;
                "Linux") echo "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" ;;
                "Windows") echo "Install via Chocolatey: choco install kubernetes-helm" ;;
                *) echo "Visit: https://helm.sh/docs/intro/install/" ;;
            esac
            ;;
        "openssl")
            case "$os" in
                "macOS") echo "openssl is pre-installed on macOS" ;;
                "Linux") echo "sudo apt-get install openssl (Ubuntu)" ;;
                "Windows") echo "Use Git Bash or WSL with openssl" ;;
                *) echo "Visit: https://www.openssl.org/source/" ;;
            esac
            ;;
        "curl")
            case "$os" in
                "macOS") echo "curl is pre-installed on macOS" ;;
                "Linux") echo "sudo apt-get install curl (Ubuntu)" ;;
                "Windows") echo "curl is available in Windows 10+" ;;
                *) echo "Visit: https://curl.se/download.html" ;;
            esac
            ;;
        "git")
            case "$os" in
                "macOS") echo "brew install git or xcode-select --install" ;;
                "Linux") echo "sudo apt-get install git (Ubuntu)" ;;
                "Windows") echo "Install Git for Windows: https://git-scm.com/download/win" ;;
                *) echo "Visit: https://git-scm.com/downloads" ;;
            esac
            ;;
    esac
}

# Validation functions
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

validate_namespace() {
    local namespace="$1"
    if [[ ! "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        log_error "Invalid namespace format: $namespace"
        return 1
    fi
    return 0
}

# Prerequisites checking with enhanced error handling
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local os=$(detect_os)
    log_substep "Detected OS: $os"
    
    local missing_tools=()
    
    # Check required tools with installation guidance
    for tool in kubectl helm openssl curl git; do
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
        echo -e "\n${YELLOW}To install all tools on $os:${NC}"
        case "$os" in
            "macOS") 
                echo "  brew install kubectl helm git"
                echo "  (openssl and curl are pre-installed)"
                ;;
            "Linux")
                echo "  # Ubuntu/Debian:"
                echo "  sudo apt-get update && sudo apt-get install -y kubectl helm openssl curl git"
                ;;
            "Windows")
                echo "  # Via Chocolatey:"
                echo "  choco install kubernetes-cli kubernetes-helm git"
                ;;
        esac
        echo
        log_info "Please install the missing tools and run the script again"
        return 1
    fi
    
    # Check Kubernetes connectivity with detailed guidance
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo
        log_info "Troubleshooting steps:"
        echo "  1. Ensure you have a Kubernetes cluster (DigitalOcean, AWS EKS, GKE, etc.)"
        echo "  2. Configure kubectl with your cluster credentials"
        echo "  3. Test connection: kubectl get nodes"
        echo
        echo "  ${BLUE}For DigitalOcean Kubernetes:${NC}"
        echo "    doctl kubernetes cluster kubeconfig save <cluster-id>"
        echo
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -1)
    log_substep "✓ Connected to: ${cluster_info#*at }"
    
    # Check if Helm chart exists
    if [[ ! -d "$HELM_CHART_PATH" ]]; then
        log_error "Helm chart not found at: $HELM_CHART_PATH"
        log_info "Ensure you're running this script from the nextcloud directory"
        return 1
    fi
    log_substep "✓ Helm chart found"
    
    # Check Helm dependencies
    if [[ -f "$HELM_CHART_PATH/Chart.yaml" ]]; then
        log_substep "✓ Chart.yaml found"
    else
        log_error "Chart.yaml not found in $HELM_CHART_PATH"
        return 1
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# Install NGINX Ingress Controller
install_ingress_nginx() {
    log_step "Installing NGINX Ingress Controller"
    
    if kubectl get namespace ingress-nginx &> /dev/null; then
        log_substep "✓ NGINX Ingress Controller already installed"
        return 0
    fi
    
    log_substep "Installing NGINX Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    log_substep "Waiting for NGINX Ingress Controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_success "NGINX Ingress Controller installed successfully"
}

# Install cert-manager
install_cert_manager() {
    log_step "Installing cert-manager"
    
    if kubectl get namespace cert-manager &> /dev/null; then
        log_substep "✓ cert-manager already installed"
        return 0
    fi
    
    log_substep "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
    
    log_substep "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_success "cert-manager installed successfully"
}

# Generate secure credentials
generate_credentials() {
    log_step "Generating Secure Credentials"
    
    # Generate admin password
    ADMIN_PASSWORD=$(openssl rand -base64 24)
    log_substep "✓ Generated admin password"
    
    # Generate PostgreSQL passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 24)
    POSTGRES_ROOT_PASSWORD=$(openssl rand -base64 24)
    log_substep "✓ Generated PostgreSQL passwords"
    
    # Generate Redis password
    REDIS_PASSWORD=$(openssl rand -base64 24)
    log_substep "✓ Generated Redis password"
    
    # Generate Nextcloud secret
    NEXTCLOUD_SECRET=$(openssl rand -hex 32)
    log_substep "✓ Generated Nextcloud secret"
    
    log_success "All credentials generated securely"
}

# Gather configuration from user
gather_configuration() {
    log_step "Gathering Configuration"
    
    # Domain configuration
    while [[ -z "${DOMAIN:-}" ]]; do
        read -p "Enter your domain (e.g., example.com): " DOMAIN
        if ! validate_domain "$DOMAIN"; then
            DOMAIN=""
        fi
    done
    log_substep "✓ Domain: $DOMAIN"
    
    # Subdomain configuration
    read -p "Enter subdomain for Nextcloud (default: nc) [nc]: " SUBDOMAIN
    SUBDOMAIN="${SUBDOMAIN:-nc}"
    log_substep "✓ Subdomain: $SUBDOMAIN"
    
    # Email configuration
    while [[ -z "${EMAIL:-}" ]]; do
        read -p "Enter email for SSL certificates: " EMAIL
        if ! validate_email "$EMAIL"; then
            EMAIL=""
        fi
    done
    log_substep "✓ Email: $EMAIL"
    
    # Namespace configuration
    read -p "Enter Kubernetes namespace (default: nextcloud) [nextcloud]: " NAMESPACE
    NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
    if ! validate_namespace "$NAMESPACE"; then
        NAMESPACE="$DEFAULT_NAMESPACE"
        log_warning "Using default namespace: $NAMESPACE"
    fi
    log_substep "✓ Namespace: $NAMESPACE"
    
    # Release name configuration
    read -p "Enter Helm release name (default: nextcloud) [nextcloud]: " RELEASE_NAME
    RELEASE_NAME="${RELEASE_NAME:-$DEFAULT_RELEASE_NAME}"
    log_substep "✓ Release name: $RELEASE_NAME"
    
    log_success "Configuration gathered successfully"
}

# Create namespace with labels
create_namespace() {
    log_step "Creating Namespace"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_substep "✓ Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        log_substep "✓ Created namespace: $NAMESPACE"
    fi
    
    # Label namespace for NetworkPolicy compatibility
    kubectl label namespace "$NAMESPACE" name="$NAMESPACE" --overwrite
    log_substep "✓ Labeled namespace for NetworkPolicy"
    
    log_success "Namespace ready"
}

# Create Kubernetes secrets
create_secrets() {
    log_step "Creating Kubernetes Secrets"
    
    # Create main secrets
    kubectl create secret generic "$RELEASE_NAME" \
        --namespace="$NAMESPACE" \
        --from-literal=NEXTCLOUD_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRES_ROOT_PASSWORD="$POSTGRES_ROOT_PASSWORD" \
        --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
        --from-literal=NEXTCLOUD_SECRET="$NEXTCLOUD_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_substep "✓ Created main secrets"
    
    # Create PostgreSQL secrets
    kubectl create secret generic "$RELEASE_NAME-postgresql" \
        --namespace="$NAMESPACE" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRES_ROOT_PASSWORD="$POSTGRES_ROOT_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_substep "✓ Created PostgreSQL secrets"
    
    # Create Redis secrets
    kubectl create secret generic "$RELEASE_NAME-redis" \
        --namespace="$NAMESPACE" \
        --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_substep "✓ Created Redis secrets"
    
    log_success "All secrets created securely"
}

# Deploy Helm chart
deploy_helm_chart() {
    log_step "Deploying Nextcloud with Helm"
    
    # Replace placeholders in values.yaml
    local temp_values="/tmp/nextcloud-values-$(date +%s).yaml"
    sed -e "s|DOMAIN_PLACEHOLDER|$SUBDOMAIN.$DOMAIN|g" \
        -e "s|EMAIL_PLACEHOLDER|$EMAIL|g" \
        -e "s|ADMIN_PASSWORD_PLACEHOLDER|$ADMIN_PASSWORD|g" \
        -e "s|POSTGRES_PASSWORD_PLACEHOLDER|$POSTGRES_PASSWORD|g" \
        -e "s|POSTGRES_ROOT_PASSWORD_PLACEHOLDER|$POSTGRES_ROOT_PASSWORD|g" \
        -e "s|REDIS_PASSWORD_PLACEHOLDER|$REDIS_PASSWORD|g" \
        -e "s|NEXTCLOUD_SECRET_PLACEHOLDER|$NEXTCLOUD_SECRET|g" \
        "$HELM_CHART_PATH/values.yaml" > "$temp_values"
    
    log_substep "✓ Prepared values file"
    
    # Deploy with Helm
    helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
        --namespace="$NAMESPACE" \
        --values="$temp_values" \
        --wait \
        --timeout=10m
    
    log_substep "✓ Helm deployment completed"
    
    # Clean up temp file
    rm -f "$temp_values"
    
    log_success "Nextcloud deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying Deployment"
    
    # Check pods
    log_substep "Checking pod status..."
    kubectl wait --namespace="$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=nextcloud \
        --timeout=300s
    
    log_substep "✓ Nextcloud pods ready"
    
    # Check PostgreSQL
    kubectl wait --namespace="$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=postgresql \
        --timeout=300s
    
    log_substep "✓ PostgreSQL ready"
    
    # Check Redis
    kubectl wait --namespace="$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=redis \
        --timeout=300s
    
    log_substep "✓ Redis ready"
    
    # Check ingress
    log_substep "Checking ingress configuration..."
    if kubectl get ingress "$RELEASE_NAME" --namespace="$NAMESPACE" &> /dev/null; then
        log_substep "✓ Ingress configured"
    else
        log_warning "Ingress not found - check configuration"
    fi
    
    log_success "Deployment verification completed"
}

# Display credentials securely
display_credentials() {
    log_step "Deployment Complete"
    
    echo -e "\n${GREEN}🎉 Nextcloud Enterprise Deployment Successful!${NC}"
    echo
    echo -e "${BOLD}Access Information:${NC}"
    echo "  🌐 URL: https://$SUBDOMAIN.$DOMAIN"
    echo "  👤 Admin Username: admin"
    echo "  🔑 Admin Password: $ADMIN_PASSWORD"
    echo
    echo -e "${BOLD}Database Information:${NC}"
    echo "  🗄️  PostgreSQL Root Password: $POSTGRES_ROOT_PASSWORD"
    echo "  🔐 PostgreSQL User Password: $POSTGRES_PASSWORD"
    echo
    echo -e "${BOLD}Cache Information:${NC}"
    echo "  ⚡ Redis Password: $REDIS_PASSWORD"
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT SECURITY NOTES:${NC}"
    echo "  • Save these credentials securely"
    echo "  • Change the admin password after first login"
    echo "  • Enable 2FA for additional security"
    echo "  • Configure trusted domains in Nextcloud settings"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Wait 2-3 minutes for TLS certificate to be issued"
    echo "  2. Visit https://$SUBDOMAIN.$DOMAIN"
    echo "  3. Login with admin credentials"
    echo "  4. Complete Nextcloud setup wizard"
    echo "  5. Install recommended apps (Calendar, Contacts, etc.)"
    echo
    echo -e "${BLUE}To view credentials again:${NC}"
    echo "  $0 --show-credentials $NAMESPACE $RELEASE_NAME"
    echo
}

# Main deployment function
main() {
    echo -e "${BOLD}${PURPLE}Nextcloud Enterprise Deployment${NC}"
    echo -e "${PURPLE}Version: $SCRIPT_VERSION${NC}"
    echo -e "${PURPLE}Author: $SCRIPT_AUTHOR${NC}"
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Install infrastructure components
    install_ingress_nginx
    install_cert_manager
    
    # Gather configuration
    gather_configuration
    
    # Generate credentials
    generate_credentials
    
    # Create namespace
    create_namespace
    
    # Deploy Helm chart (secrets will be created by Helm templates)
    deploy_helm_chart
    
    # Verify deployment
    verify_deployment
    
    # Display credentials
    display_credentials
}

# Run main function
main "$@"
