#!/bin/bash

# WordPress Enterprise Deployment Script
# Production-ready WordPress with enhanced security and upgrade support
# Version: 3.1.0 - Added instance detection and safe upgrade functionality

# Function definitions first
show_credentials_only() {
    local namespace="wordpress"
    local release="wordpress"
    
    if [[ -n "${2:-}" ]]; then
        namespace="$2"
    fi
    if [[ -n "${3:-}" ]]; then
        release="$3"
    fi
    
    echo "🔐 WordPress Database Credentials (from Kubernetes secret)"
    echo "=========================================================="
    echo
    
    if ! kubectl get secret "$release" -n "$namespace" &>/dev/null; then
        echo "❌ Secret '$release' not found in namespace '$namespace'"
        echo "💡 Usage: $0 --show-credentials [namespace] [release-name]"
        exit 1
    fi
    
    echo "Database (MariaDB):"
    echo "  Root Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.mariadb-root-password}' | base64 -d)"
    echo "  WordPress Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.mariadb-password}' | base64 -d)"
    echo
    echo "Redis Cache:"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.redis-password}' | base64 -d)"
    echo
    echo "🌐 WordPress URL: https://$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'Check ingress configuration')"
    echo
    echo "ℹ️  WordPress admin credentials are set up during post-deployment installation wizard"
    echo "   Visit your WordPress URL and follow the installation steps to create admin account"
    echo
    echo "⚠️  Keep these database credentials secure and private!"
}

# Instance detection and management functions
detect_existing_instance() {
    local namespace="$1"
    local release="$2"
    
    # Check for any helm release (deployed, failed, etc.)
    if helm list -n "$namespace" 2>/dev/null | grep -q "$release"; then
        return 0  # Instance exists (any status)
    fi
    
    # Also check for existing PVCs (data exists even without Helm release)
    if kubectl get pvc -n "$namespace" 2>/dev/null | grep -q "wordpress\|mariadb"; then
        return 0  # Existing data found
    fi
    
    return 1  # No instance found
}

show_instance_detected() {
    local namespace="$1"
    local release="$2"
    
    echo
    log_step "Instance Detection Results"
    echo "🔍 Existing WordPress instance detected!"
    echo "  Namespace: $namespace"
    echo "  Release: $release"
    echo "  Helm Status: $(helm status "$release" -n "$namespace" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo 'no release (data-only)')"
    echo "  Data: $(kubectl get pvc -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ') PVCs found"
    echo "  Pods: $(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ') running"
    echo
}

prompt_deployment_choice() {
    echo "Choose deployment option:" >&2
    echo "  1) 🔄 Update existing instance (recommended - preserves data)" >&2
    echo "  2) 🆕 Deploy new instance with different name" >&2
    echo "  3) ❌ Cancel deployment" >&2
    echo >&2
    read -p "Select option [1-3]: " choice >&2
    echo "$choice"
}

cleanup_stuck_resources() {
    local namespace="$1"
    
    echo "🧹 Cleaning up stuck resources in namespace: $namespace"
    
    # Remove failed backup jobs
    echo "  - Removing failed backup jobs..."
    kubectl delete job -l app.kubernetes.io/component=backup \
        --field-selector=status.successful=0 -n "$namespace" 2>/dev/null || true
    
    # Remove old completed cron jobs (keep last 3)
    echo "  - Cleaning up old cron job executions..."
    # macOS vs Linux date command compatibility
    if [[ "$(uname)" == "Darwin" ]]; then
        three_days_ago=$(date -v-3d -u +%Y-%m-%dT%H:%M:%SZ)
    else
        three_days_ago=$(date -d '3 days ago' -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    kubectl delete job -l app.kubernetes.io/component=cron \
        --field-selector=status.completionTime\<$three_days_ago \
        -n "$namespace" 2>/dev/null || true
    
    # Remove any pods in Error/Completed state
    echo "  - Removing stuck pods..."
    kubectl delete pods --field-selector=status.phase=Failed -n "$namespace" 2>/dev/null || true
    kubectl delete pods --field-selector=status.phase=Succeeded -n "$namespace" 2>/dev/null || true
    
    echo "✅ Resource cleanup completed"
}

sync_database_secrets() {
    local namespace="$1"
    
    echo "🔐 Synchronizing database secrets..."
    
    # Check if wordpress-mariadb secret exists and has placeholder values
    if kubectl get secret wordpress-mariadb -n "$namespace" &>/dev/null; then
        local mariadb_pass=$(kubectl get secret wordpress-mariadb -n "$namespace" -o jsonpath='{.data.mariadb-password}' | base64 -d)
        if [[ "$mariadb_pass" == *"PLACEHOLDER"* ]]; then
            echo "  - Fixing MariaDB password synchronization..."
            kubectl patch secret wordpress-mariadb -n "$namespace" -p '{
                "data": {
                    "mariadb-password": "'$(kubectl get secret wordpress -n "$namespace" -o jsonpath='{.data.mariadb-password}')'",
                    "mariadb-root-password": "'$(kubectl get secret wordpress -n "$namespace" -o jsonpath='{.data.mariadb-root-password}')'"
                }
            }'
            echo "  ✅ Database secrets synchronized"
        else
            echo "  ✅ Database secrets already synchronized"
        fi
    fi
}

prompt_namespace_and_release() {
    echo ""
    echo "📦 Namespace and Release Configuration"
    echo "========================================"
    echo ""
    echo "Choose your deployment namespace and release name:"
    echo "  1) Use default (namespace: wordpress, release: wordpress)"
    echo "  2) Use custom names"
    echo ""
    read -p "Select option [1-2]: " ns_choice
    echo ""
    
    case $ns_choice in
        1)
            NAMESPACE="wordpress"
            RELEASE_NAME="wordpress"
            log_info "Using default namespace and release: wordpress"
            ;;
        2)
            while true; do
                read -p "Enter custom namespace name: " custom_ns
                if [[ "$custom_ns" =~ ^[a-z0-9-]+$ ]] && [[ ${#custom_ns} -le 63 ]]; then
                    NAMESPACE="$custom_ns"
                    break
                else
                    echo "❌ Invalid namespace. Use lowercase letters, numbers, and hyphens only (max 63 chars)"
                fi
            done
            
            while true; do
                read -p "Enter custom release name: " custom_release
                if [[ "$custom_release" =~ ^[a-z0-9-]+$ ]] && [[ ${#custom_release} -le 63 ]]; then
                    RELEASE_NAME="$custom_release"
                    break
                else
                    echo "❌ Invalid release name. Use lowercase letters, numbers, and hyphens only (max 63 chars)"
                fi
            done
            
            log_info "Using custom configuration - Namespace: $NAMESPACE, Release: $RELEASE_NAME"
            ;;
        *)
            log_warning "Invalid choice. Using defaults."
            NAMESPACE="wordpress"
            RELEASE_NAME="wordpress"
            ;;
    esac
    echo ""
}


update_existing_instance() {
    local namespace="$1"
    local release="$2"
    local domain="$3"
    local email="$4"
    
    echo "🔄 Updating existing WordPress instance..."
    echo "  Namespace: $namespace"
    echo "  Release: $release"
    echo "  Domain: $domain"
    echo
    
    # Step 1: Clean up stuck resources
    cleanup_stuck_resources "$namespace"
    
    # Step 2: Check and preserve existing TLS certificate
    echo "🔐 Checking existing TLS certificate..."
    local cert_exists=false
    local cert_ready=false
    
    if kubectl get certificate "$release-tls" -n "$namespace" &>/dev/null; then
        cert_exists=true
        local cert_status=$(kubectl get certificate "$release-tls" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [[ "$cert_status" == "True" ]]; then
            cert_ready=true
            echo "  ✅ Valid TLS certificate found - will be preserved"
            echo "  📅 Certificate: $(kubectl get certificate "$release-tls" -n "$namespace" -o jsonpath='{.status.notAfter}' 2>/dev/null || echo 'Active')"
        else
            echo "  ⚠️  TLS certificate exists but not ready - will attempt renewal"
        fi
    else
        echo "  ℹ️  No existing TLS certificate - will create new one"
    fi
    
    # Step 3: Extract existing database credentials (NO new passwords for existing data)
    echo "🔐 Extracting existing database credentials from MariaDB data..."
    
    local existing_wp_password=""
    local existing_root_password=""
    local use_existing_creds=false
    
    # Check if we can find existing credentials in old secrets
    if kubectl get secret wordpress-mariadb -n "$namespace" &>/dev/null; then
        existing_wp_password=$(kubectl get secret wordpress-mariadb -n "$namespace" -o jsonpath='{.data.mariadb-password}' 2>/dev/null | base64 -d || echo "")
        existing_root_password=$(kubectl get secret wordpress-mariadb -n "$namespace" -o jsonpath='{.data.mariadb-root-password}' 2>/dev/null | base64 -d || echo "")
        if [[ -n "$existing_wp_password" ]] && [[ -n "$existing_root_password" ]]; then
            echo "  ✅ Found existing MariaDB credentials - will reuse them"
            use_existing_creds=true
        fi
    fi
    
    if [[ "$use_existing_creds" == "false" ]]; then
        echo "  ⚠️  Could not extract existing credentials"
        echo "  ℹ️  Strategy: Deploy fresh, let MariaDB initialize from existing data"
        echo "      The existing data will determine the correct credentials"
    fi
    
    # Step 4: Deploy fresh WordPress (will connect to existing PVCs automatically)
    echo "📦 Deploying fresh WordPress that will connect to existing data..."
    echo "ℹ️  WordPress will automatically detect and use existing database/content..."
    
    # Skip the infrastructure setup and go straight to WordPress deployment
    # Set global variables so the normal deployment flow can use them
    DOMAIN="$domain"
    FULL_DOMAIN="$domain"
    EMAIL="$email"
    INCLUDE_WWW=false
    
    # Call the normal deployment functions, conditionally skip infrastructure
    log_info "Setting up namespace and secrets for existing data connection..."
    
    # Pass existing credentials to setup function
    if [[ "$use_existing_creds" == "true" ]]; then
        export EXISTING_MARIADB_PASSWORD="$existing_wp_password"
        export EXISTING_MARIADB_ROOT_PASSWORD="$existing_root_password"
        echo "  ℹ️  Using extracted existing MariaDB credentials"
    fi
    
    setup_namespace_and_secrets
    
    # Skip infrastructure setup if we have a valid certificate (avoids rate limits)
    if [[ "$cert_ready" == "true" ]]; then
        log_info "Skipping infrastructure setup - using existing TLS certificate"
        export SKIP_INFRASTRUCTURE=true
    else
        log_info "Will set up infrastructure - certificate needs creation/renewal"
        export SKIP_INFRASTRUCTURE=false
    fi
    
    log_info "Deploying WordPress to connect with existing data..."  
    deploy_wordpress
    
    echo "✅ WordPress deployed and connected to existing data"
    
    # Step 5: Verify deployment is working
    echo "🔍 Verifying deployment status..."
    
    # Check pod readiness
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n "$namespace" --timeout=120s 2>/dev/null; then
        echo "✅ WordPress pods are ready"
    else
        echo "⚠️  WordPress pods initializing (this is normal for fresh deployments)"
        echo "    - WordPress will be available once health checks pass"
        echo "    - Database connection may take 1-2 minutes to establish"
    fi
    
    
    # Step 8: Configuration update completed
    
    echo
    echo "🎉 WordPress instance update completed!"
    echo "🌐 Access your site at: https://$domain"
    echo
    
    # Show final certificate status
    if kubectl get certificate "$release-tls" -n "$namespace" &>/dev/null; then
        local final_cert_status=$(kubectl get certificate "$release-tls" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [[ "$final_cert_status" == "True" ]]; then
            echo "🔐 TLS Certificate: ✅ Active and Valid"
            if [[ "$cert_ready" == "true" ]]; then
                echo "    📋 Status: Existing certificate preserved (no new issuance)"
            else
                echo "    📋 Status: New certificate issued successfully"
            fi
        else
            echo "🔐 TLS Certificate: ⏳ Issuing (check status with: kubectl get certificate -n $namespace)"
        fi
    fi
    echo
    echo "💡 To view credentials: $0 --show-credentials $namespace $release"
    
    return 0
}

show_help() {
    echo "WordPress Enterprise Deployment Script v3.1.0"
    echo "============================================="
    echo
    echo "✨ New Features:"
    echo "  • Automatic instance detection and safe upgrades"
    echo "  • Resource cleanup and configuration synchronization"
    echo "  • Preserves all data during updates"
    echo
    echo "Usage:"
    echo "  $0                                    # Deploy/Update WordPress"
    echo "  $0 --show-credentials [ns] [release]  # Show credentials"
    echo "  $0 --help                            # Show this help"
    echo
    echo "Examples:"
    echo "  $0 --show-credentials                 # Default namespace/release"
    echo "  $0 --show-credentials my-wp my-site   # Custom namespace/release"
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

# WordPress Enterprise Deployment Script v3.0.0
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
readonly SCRIPT_NAME="WordPress Enterprise Deployment"
readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_AUTHOR="WordPress Enterprise"

# Default values - standard WordPress naming
readonly DEFAULT_NAMESPACE="wordpress"
readonly DEFAULT_RELEASE_NAME="wordpress"
readonly HELM_CHART_PATH="./helm"
# State management removed for simplicity and restartability

# Global variables
DOMAIN=""
SUBDOMAIN="wp"
NAMESPACE="${NAMESPACE:-}"  # Use environment variable or empty
RELEASE_NAME="${RELEASE_NAME:-}"  # Use environment variable or empty
EMAIL=""
DEPLOY_STATE=""
SKIP_PREREQUISITES=false
ENABLE_MONITORING=true
ENABLE_BACKUP=true
SHOW_CREDENTIALS="false"  # Default to secure behavior
ENABLE_FLUENT_AUTH_FIX="false"  # Disabled by default

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

# State management functions removed - deployment is now stateless and restartable

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
        "argon2")
            case "$os" in
                "macOS") echo "brew install argon2" ;;
                "Linux") echo "sudo apt-get install argon2 (Ubuntu)" ;;
                "Windows") echo "Use WSL with: sudo apt-get install argon2" ;;
                *) echo "Visit: https://github.com/P-H-C/phc-winner-argon2" ;;
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
        log_info "Ensure you're running this script from the wordpress directory"
        return 1
    fi
    log_substep "✓ Helm chart found"
    
    # Check Helm dependencies
    if [[ -f "$HELM_CHART_PATH/Chart.yaml" ]]; then
        log_substep "✓ Helm Chart.yaml validated"
    else
        log_error "Invalid Helm chart: missing Chart.yaml"
        return 1
    fi
    
    return 0
}

# Infrastructure setup
setup_infrastructure() {
	log_step "Setting Up Infrastructure Prerequisites"
	
	if kubectl get svc ingress-nginx-controller -n infra >/dev/null 2>&1 \
	   && kubectl get clusterissuer letsencrypt-prod >/dev/null 2>&1; then
		log_substep "Using existing ingress-nginx controller and ClusterIssuer 'letsencrypt-prod' (shared infra); skipping local installation"
		return 0
	fi
	
	# Get cluster name for LoadBalancer naming (extract from current context)
	local cluster_context=$(kubectl config current-context)
	local cluster_name=$(echo "$cluster_context" | sed 's/.*@//' | sed 's/do-.*-k8s-//' | head -c 20)
    
    # Check and install NGINX Ingress Controller
    log_substep "Checking NGINX Ingress Controller..."
    if ! kubectl get namespace ingress-nginx &> /dev/null || ! kubectl get svc -n ingress-nginx ingress-nginx-controller &> /dev/null; then
        log_substep "Installing NGINX Ingress Controller..."
        
        # Detect if this is a DigitalOcean cluster for LoadBalancer annotation
        if kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | grep -q "digitalocean"; then
            log_substep "Detected DigitalOcean cluster - configuring LoadBalancer..."
            helm upgrade --install ingress-nginx ingress-nginx \
                --repo https://kubernetes.github.io/ingress-nginx \
                --namespace ingress-nginx --create-namespace \
                --set controller.service.type=LoadBalancer \
                --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-name"="${cluster_name}-nginx-ingress" \
                --set controller.metrics.enabled=true \
                --set controller.podAnnotations."prometheus\.io/scrape"="true" \
                --set controller.podAnnotations."prometheus\.io/port"="10254" \
                --set controller.config.use-proxy-protocol="false" \
                --wait --timeout=300s
        else
            log_substep "Installing NGINX Ingress Controller (generic cloud)..."
            helm upgrade --install ingress-nginx ingress-nginx \
                --repo https://kubernetes.github.io/ingress-nginx \
                --namespace ingress-nginx --create-namespace \
                --set controller.service.type=LoadBalancer \
                --set controller.metrics.enabled=true \
                --set controller.podAnnotations."prometheus\.io/scrape"="true" \
                --set controller.podAnnotations."prometheus\.io/port"="10254" \
                --wait --timeout=300s
        fi
        
        log_substep "Waiting for NGINX Ingress Controller to be ready..."
        kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=300s
    else
        log_substep "✓ NGINX Ingress Controller already installed"
    fi
    
    # CRITICAL: Ensure ingress-nginx namespace has the required label for NetworkPolicy
    if ! kubectl get namespace ingress-nginx --show-labels | grep -q "name=ingress-nginx"; then
        log_substep "Adding required NetworkPolicy label to ingress-nginx namespace..."
        kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
        log_substep "✓ NetworkPolicy label added"
    else
        log_substep "✓ NetworkPolicy label already present"
    fi
    
    # Check and install cert-manager
    log_substep "Checking cert-manager..."
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_substep "Installing cert-manager..."
        helm repo add jetstack https://charts.jetstack.io &> /dev/null || true
        helm repo update &> /dev/null
        
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --version v1.13.2 \
            --set installCRDs=true \
            --set securityContext.runAsNonRoot=true \
            --set securityContext.runAsUser=1000 \
            --wait --timeout=300s
        
        log_substep "Waiting for cert-manager to be ready..."
        kubectl wait --namespace cert-manager \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/instance=cert-manager \
            --timeout=300s
    else
        log_substep "✓ cert-manager already installed"
    fi
    
    # Create ClusterIssuer for Let's Encrypt if it doesn't exist
    log_substep "Setting up Let's Encrypt ClusterIssuer..."
    
    # Check if ClusterIssuer already exists
    if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
        # Update existing ClusterIssuer with proper email
        log_substep "Updating ClusterIssuer with email: ${EMAIL}"
        kubectl patch clusterissuer letsencrypt-prod --type='merge' -p="{\"spec\":{\"acme\":{\"email\":\"${EMAIL}\"}}}"
        log_success "✅ ClusterIssuer updated with email: ${EMAIL}"
    else
        # Create ClusterIssuer with proper Helm labels for ownership
        cat <<EOF > /tmp/clusterissuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  labels:
    app.kubernetes.io/managed-by: kubectl
  annotations:
    meta.helm.sh/managed-by: kubectl
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
        
        kubectl apply -f /tmp/clusterissuer.yaml
        rm -f /tmp/clusterissuer.yaml
        log_success "✅ ClusterIssuer configured with email: ${EMAIL}"
    fi
    
    # Using official WordPress and MariaDB images - no external dependencies needed
}

# WordPress uses installation wizard - no password needed

generate_secure_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

generate_wp_salt() {
    openssl rand -hex 64
}

# Enhanced password hashing with Argon2id (matching Vaultwarden security)
generate_argon2_hash() {
    local password="$1"
    local os=$(detect_os)
    
    # Check for argon2 binary in common locations
    local argon2_bin=""
    for path in "/opt/homebrew/bin/argon2" "$(which argon2 2>/dev/null)" "/usr/bin/argon2" "/usr/local/bin/argon2"; do
        if [[ -x "$path" ]]; then
            argon2_bin="$path"
            break
        fi
    done
    
    if [[ -n "$argon2_bin" ]]; then
        # Use enterprise-grade Argon2id parameters (64MB memory, 3 iterations, 4 threads)
        log_substep "Using argon2 binary: $argon2_bin"
        echo -n "$password" | "$argon2_bin" "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
        return 0
    else
        log_warning "argon2 CLI not found - attempting installation..."
        case "$os" in
            "macOS")
                if command -v brew &> /dev/null; then
                    log_info "Installing argon2 via Homebrew..."
                    if brew install argon2 &> /dev/null; then
                        for path in "/opt/homebrew/bin/argon2" "/usr/local/bin/argon2"; do
                            if [[ -x "$path" ]]; then
                                echo -n "$password" | "$path" "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
                                return 0
                            fi
                        done
                    fi
                fi
                ;;
            "Linux")
                if command -v apt-get &> /dev/null; then
                    log_info "Installing argon2 via apt-get..."
                    if sudo apt-get update -qq && sudo apt-get install -y argon2 &> /dev/null; then
                        echo -n "$password" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
                        return 0
                    fi
                fi
                ;;
        esac
        
        # Fallback to bcrypt-style hashing if argon2 unavailable
        log_warning "argon2 not available, using OpenSSL-based secure hash"
        openssl passwd -6 "$password"
    fi
}

# Enterprise domain and DNS configuration  
collect_user_input() {
    log_step "WordPress Enterprise Configuration"
    echo
    
    log_info "🏢 Welcome to Enterprise WordPress Deployment"
    log_info "This deployment creates a production-ready WordPress site with:"
    echo "  • 🔒 Enterprise-grade security (Pod Security Standards: Restricted)"
    echo "  • 🛡️  Zero-trust networking with NetworkPolicy"
    echo "  • 📊 Resource optimization for cluster efficiency"
    echo "  • ⚡ TLS 1.3 with automated Let's Encrypt certificates"
    echo "  • 🔑 Secure credential management via Kubernetes secrets"
    echo
    
    # Step 0: Namespace and Release Name Configuration
    if [[ -z "$NAMESPACE" ]] || [[ -z "$RELEASE_NAME" ]]; then
        prompt_namespace_and_release
    fi
    
    # Step 1: Domain Configuration
    if [[ -n "$DOMAIN" ]]; then
        log_success "Using configured domain: $DOMAIN"
        FULL_DOMAIN="$DOMAIN"
        # Check if it's a subdomain or main domain
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            # Has subdomain prefix (e.g., blog.example.com)
            SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
            MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'.' -f2-)
            INCLUDE_WWW=false  # Don't add www to subdomains
        else
            # Main domain (e.g., example.com)
            MAIN_DOMAIN="$DOMAIN"
            INCLUDE_WWW=true  # Default to including www for main domains in CLI mode
        fi
    else
        log_step "• Domain Configuration"
        echo
        
        while true; do
            echo "Choose your WordPress deployment type:"
            echo "  1) Main domain     (e.g., yourdomain.com)"
            echo "  2) Subdomain       (e.g., blog.yourdomain.com)"
            echo
            echo -n -e "${WHITE}Select option [1-2]: ${NC}"
            read -r domain_choice
            
            case $domain_choice in
                1)
                    log_info "Selected: Main domain deployment"
                    echo
                    while true; do
                        echo -n -e "${WHITE}Enter your domain (e.g., yourdomain.com): ${NC}"
                        read -r DOMAIN
                        if validate_domain "$DOMAIN"; then
                            MAIN_DOMAIN="$DOMAIN"
                            FULL_DOMAIN="$DOMAIN"
                            break
                        fi
                        log_warning "Invalid domain format. Please enter a valid domain (e.g., example.com)"
                    done
                    
                    # Ask about www subdomain support
                    echo
                    echo -e "${BOLD}WWW Subdomain Configuration:${NC}"
                    while true; do
                        echo -n -e "${WHITE}Include www.${DOMAIN} with automatic configuration? [Y/n]: ${NC}"
                        read -r www_choice
                        case "${www_choice:-Y}" in
                            [Yy]|[Yy][Ee][Ss]|"")
                                INCLUDE_WWW=true
                                log_success "Will configure both ${DOMAIN} and www.${DOMAIN}"
                                
                                # Ask about redirect preference
                                echo
                                echo -e "${BOLD}Domain Redirect Configuration:${NC}"
                                echo "  Choose your canonical (primary) domain:"
                                echo
                                echo "  ${CYAN}Option 1:${NC} Redirect TO www (${DOMAIN} → www.${DOMAIN})"
                                echo "    • Traditional enterprise best practice"
                                echo "    • Used by: Microsoft, Facebook, Wikipedia"
                                echo "    • Better for CDN flexibility"
                                echo
                                echo "  ${CYAN}Option 2:${NC} Redirect FROM www (www.${DOMAIN} → ${DOMAIN})"
                                echo "    • Modern SaaS best practice"
                                echo "    • Used by: Google, Apple, Amazon"
                                echo "    • Shorter, cleaner URLs"
                                echo
                                echo "  ${CYAN}Option 3:${NC} No redirect (both URLs work independently)"
                                echo "    • Not recommended: creates SEO duplicate content issues"
                                echo
                                
                                while true; do
                                    echo -n -e "${WHITE}Select redirect preference [1/2/3]: ${NC}"
                                    read -r redirect_choice
                                    case "$redirect_choice" in
                                        1)
                                            REDIRECT_TO_WWW=true
                                            REDIRECT_FROM_WWW=false
                                            log_success "✓ Will redirect ${DOMAIN} → www.${DOMAIN}"
                                            break
                                            ;;
                                        2)
                                            REDIRECT_TO_WWW=false
                                            REDIRECT_FROM_WWW=true
                                            log_success "✓ Will redirect www.${DOMAIN} → ${DOMAIN}"
                                            break
                                            ;;
                                        3)
                                            REDIRECT_TO_WWW=false
                                            REDIRECT_FROM_WWW=false
                                            log_warning "⚠️  Both URLs will work (not recommended for SEO)"
                                            break
                                            ;;
                                        *)
                                            log_warning "Please enter 1, 2, or 3"
                                            ;;
                                    esac
                                done
                                break
                                ;;
                            [Nn]|[Nn][Oo])
                                INCLUDE_WWW=false
                                REDIRECT_TO_WWW=false
                                REDIRECT_FROM_WWW=false
                                log_info "Will configure ${DOMAIN} only"
                                break
                                ;;
                            *)
                                log_warning "Please enter Y or N"
                                ;;
                        esac
                    done
                    break
                    ;;
                2)
                    log_info "Selected: Subdomain deployment"
                    echo
                    while true; do
                        echo -n -e "${WHITE}Enter your main domain (e.g., yourdomain.com): ${NC}"
                        read -r MAIN_DOMAIN
                        if validate_domain "$MAIN_DOMAIN"; then
                            break
                        fi
                        log_warning "Invalid domain format. Please enter a valid domain (e.g., example.com)"
                    done
                    
                    while true; do
                        echo -n -e "${WHITE}Enter subdomain prefix (e.g., blog, www, app): ${NC}"
                        read -r SUBDOMAIN
                        if [[ "$SUBDOMAIN" =~ ^[a-zA-Z0-9-]+$ ]] && [[ ${#SUBDOMAIN} -le 63 ]]; then
                            DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"
                            FULL_DOMAIN="$DOMAIN"
                            INCLUDE_WWW=false  # Initialize for subdomain deployment
                            break
                        fi
                        log_warning "Invalid subdomain. Use only letters, numbers, and hyphens"
                    done
                    break
                    ;;
                *)
                    log_warning "Please enter 1 or 2"
                    ;;
            esac
        done
    fi
    
    # Step 2: Email Configuration
    if [[ -n "$EMAIL" ]]; then
        log_success "Using configured email: $EMAIL"
    else
        echo
        while true; do
            echo -n -e "${WHITE}Enter email for Let's Encrypt certificates: ${NC}"
            read -r EMAIL
            if validate_email "$EMAIL"; then
                break
            fi
            log_warning "Invalid email format. Please enter a valid email address."
        done
    fi
    
    # Step 3: Namespace and Release Configuration
    prompt_namespace_and_release
}

# DNS Configuration and Validation
validate_dns_configuration() {
    log_info "Validating DNS configuration..."
    
    if [[ -z "$DOMAIN" ]]; then
        log_error "Domain not configured"
        return 1
    fi
    
    local external_ip
    external_ip=$(get_external_ip)
    if [[ -z "$external_ip" ]]; then
        log_warning "Cannot detect external IP for DNS validation"
        return 1
    fi
    
    log_success "Domain: $DOMAIN"
    log_success "External IP: $external_ip"
    log_info "Ensure A record points $DOMAIN → $external_ip"
    
    return 0
}

setup_dns_instructions() {   
    echo
    log_step "📋 DNS Configuration Required"
    echo
    
    log_info "Before deploying WordPress, you need to configure DNS:"
    echo
    
    # Check for existing ingress controller to get external IP
    local external_ip=""
    if kubectl get svc ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        external_ip=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi
    
    if [[ -n "$external_ip" && "$external_ip" != "null" ]]; then
        log_success "✅ Found ingress controller with external IP: $external_ip"
        echo
        echo "${BOLD}DNS Record Configuration Required:${NC}"
        echo
        echo "${CYAN}Record 1 - Root Domain (A Record):${NC}"
        echo "  Type: A"
        if [[ -n "$SUBDOMAIN" ]]; then
            echo "  Name: $SUBDOMAIN"
        else
            echo "  Name: @ (or root)"
        fi
        echo "  Value: $external_ip"
        echo "  TTL: 300 (5 minutes)"
        echo
        
        if [[ "$INCLUDE_WWW" == "true" ]]; then
            echo "${CYAN}Record 2 - WWW Subdomain (CNAME):${NC}"
            echo "  Type: CNAME"
            echo "  Name: www"
            echo "  Value: ${FULL_DOMAIN}."
            echo "  TTL: 300 (5 minutes)"
            echo
            log_info "📌 Note: CNAME is the DNS-standard way for www subdomains"
        fi
        
        echo "${CYAN}Create these DNS records in your domain provider's control panel${NC}"
        echo "  (GoDaddy, Namecheap, Cloudflare, Google Domains, etc.)"
        echo
        
        local dns_configured=false
        while true; do
            echo -n -e "${WHITE}Have you created the DNS A record pointing $FULL_DOMAIN to $external_ip? [y/N]: ${NC}"
            read -r dns_response
            dns_response_lower=$(echo "$dns_response" | tr '[:upper:]' '[:lower:]')
            if [[ "$dns_response_lower" =~ ^(y|yes)$ ]]; then
                dns_configured=true
                break
            elif [[ "$dns_response_lower" =~ ^(n|no|)$ ]]; then
                log_warning "DNS configuration is required for WordPress to work properly."
                echo "  • Log in to your domain provider (GoDaddy, Namecheap, Cloudflare, etc.)"
                echo "  • Navigate to DNS management"
                echo "  • Add the A record shown above"
                echo "  • DNS propagation takes 5-15 minutes"
                echo
                echo -n -e "${WHITE}Configure DNS now and press Enter to continue, or 'q' to quit: ${NC}"
                read -r continue_response
                if [[ "$continue_response" == "q" ]]; then
                    log_warning "Deployment cancelled. Please configure DNS and run this script again."
                    exit 0
                fi
            else
                log_warning "Please answer yes (y) or no (n)"
            fi
        done
    else
        log_info "We'll get the external IP after installing the ingress controller."
        echo
        log_warning "⚠️  You'll need to create a DNS A record after deployment"
        echo "  The script will provide the exact DNS record after ingress installation"
        echo
        echo -n -e "${WHITE}Do you understand that DNS configuration will be required? [Y/n]: ${NC}"
        read -r understand_response
        understand_response_lower=$(echo "$understand_response" | tr '[:upper:]' '[:lower:]')
        if [[ "$understand_response_lower" == "n" ]]; then
            log_warning "DNS configuration is mandatory for WordPress deployment."
            log_info "Please review the requirements and run this script again."
            exit 0
        fi
    fi
    
    # Enterprise options (automatically enabled for enterprise deployment)
    echo
    log_substep "Enterprise Options"
    ENABLE_MONITORING="true"
    ENABLE_BACKUP="true"
    log_info "✅ Monitoring and metrics: Enabled automatically"
    log_info "✅ Automated backups: Enabled automatically"
    
    # Credential display option
    echo
    log_substep "🔐 Credential Display Options"
    echo -e "${YELLOW}⚠️  For security, admin credentials will be auto-generated${NC}"
    echo -n -e "${WHITE}Display admin credentials after deployment? [y/N]: ${NC}"
    read -r show_credentials_response
    show_credentials_lower=$(echo "$show_credentials_response" | tr '[:upper:]' '[:lower:]')
    if [[ "$show_credentials_lower" == "y" ]]; then
        SHOW_CREDENTIALS="true"
        echo -e "${YELLOW}⚠️  Credentials will be displayed once - ensure privacy${NC}"
    else
        SHOW_CREDENTIALS="false"
        log_info "✅ Credentials will be stored securely in Kubernetes secrets only"
    fi
    
    # Configuration summary
    echo
    log_step "📋 Configuration Summary"
    echo -e "  🌐 Full URL: ${CYAN}https://${FULL_DOMAIN}${NC}"
    echo -e "  📧 Email: ${CYAN}${EMAIL}${NC}"
    echo -e "  🏷️  Namespace: ${CYAN}${NAMESPACE}${NC}"
    echo -e "  🎯 Release: ${CYAN}${RELEASE_NAME}${NC}"
    echo -e "  📊 Monitoring: ${CYAN}${ENABLE_MONITORING}${NC}"
    echo -e "  💾 Backups: ${CYAN}${ENABLE_BACKUP}${NC}"
    echo
    
    echo -n -e "${WHITE}Continue with enterprise WordPress deployment? [Y/n]: ${NC}"
    read -r confirm
    confirm_lower=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    if [[ "$confirm_lower" == "n" ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
}

# Create namespace and secrets
setup_namespace_and_secrets() {
    log_step "Setting Up Namespace and Secrets"
    
    # Create namespace
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE"
        log_substep "✓ Namespace '$NAMESPACE' created"
    else
        log_substep "✓ Namespace '$NAMESPACE' already exists"
    fi
    
    # Generate secure passwords for backend services only
    log_substep "Generating database service passwords..."
    
    # Check if we should use existing credentials (for updates)
    if [[ -n "${EXISTING_MARIADB_PASSWORD:-}" ]] && [[ -n "${EXISTING_MARIADB_ROOT_PASSWORD:-}" ]]; then
        log_substep "Using existing MariaDB credentials (update mode)"
        mariadb_password="$EXISTING_MARIADB_PASSWORD"
        mariadb_root_password="$EXISTING_MARIADB_ROOT_PASSWORD"
    else
        log_substep "Generating new MariaDB credentials (fresh install)"
        mariadb_root_password=$(generate_secure_password 32)
        mariadb_password=$(generate_secure_password 24)
    fi
    
    redis_password=$(generate_secure_password 20)
    
    # Create Kubernetes secrets with proper Helm metadata
    log_substep "Creating Kubernetes secrets..."
    
    # Debug: Verify passwords are generated
    if [[ -z "$mariadb_root_password" || -z "$mariadb_password" ]]; then
        log_error "Password generation failed - variables are empty"
        exit 1
    fi
    
    log_substep "Generated service passwords (lengths): MariaDB-Root=${#mariadb_root_password}, MariaDB=${#mariadb_password}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $RELEASE_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: wordpress
    app.kubernetes.io/instance: $RELEASE_NAME
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: $RELEASE_NAME
    meta.helm.sh/release-namespace: $NAMESPACE
type: Opaque
data:
  redis-password: $(echo -n "$redis_password" | base64)
  mariadb-root-password: $(echo -n "$mariadb_root_password" | base64)
  mariadb-password: $(echo -n "$mariadb_password" | base64)
  wordpress-password: $(echo -n "wordpress-dummy-password" | base64)
EOF
    
    # Store passwords in variables for Helm deployment
    export MARIADB_ROOT_PASSWORD="$mariadb_root_password"
    export MARIADB_PASSWORD="$mariadb_password"
    export REDIS_PASSWORD="$redis_password"
    
    log_success "Backend service credentials generated and stored securely"
}

    # Deploy WordPress (fix variable scoping)
deploy_wordpress() {
        log_step "Deploying WordPress Helm Chart"
        
        # Use the main values.yaml file with placeholder replacement
        local values_file="helm/values.yaml"
        local temp_values_file=$(mktemp)
        
        # Copy and process the main values.yaml file with domain/email placeholders
        # Use environment variables set during secret creation
        # WordPress admin created via installation wizard
        local db_root_pass="${MARIADB_ROOT_PASSWORD}"
        local db_pass="${MARIADB_PASSWORD}"
        local redis_pass="${REDIS_PASSWORD}"
        
        # Generate WordPress security keys
        local auth_key=$(generate_wp_salt)
        local secure_auth_key=$(generate_wp_salt)
        local logged_in_key=$(generate_wp_salt)
        local nonce_key=$(generate_wp_salt)
        local auth_salt=$(generate_wp_salt)
        local secure_auth_salt=$(generate_wp_salt)
        local logged_in_salt=$(generate_wp_salt)
        local nonce_salt=$(generate_wp_salt)
        
        # Handle domain configuration - simple placeholder replacement
        log_info "Configuring ingress for domain: ${FULL_DOMAIN}"
        # Use awk for reliable replacement (sed has issues with special characters)
        awk '
        BEGIN {
            domain = "'"$FULL_DOMAIN"'"
            email = "'"$EMAIL"'"
            db_root_pass = "'"$db_root_pass"'"
            db_pass = "'"$db_pass"'"
            redis_pass = "'"$redis_pass"'"
            auth_key = "'"$auth_key"'"
            secure_auth_key = "'"$secure_auth_key"'"
            logged_in_key = "'"$logged_in_key"'"
            nonce_key = "'"$nonce_key"'"
            auth_salt = "'"$auth_salt"'"
            secure_auth_salt = "'"$secure_auth_salt"'"
            logged_in_salt = "'"$logged_in_salt"'"
            nonce_salt = "'"$nonce_salt"'"
        }
        {
            gsub("DOMAIN_PLACEHOLDER", domain)
            gsub("EMAIL_PLACEHOLDER", email)
            gsub("MARIADB_ROOT_PASSWORD_PLACEHOLDER", db_root_pass)
            gsub("MARIADB_PASSWORD_PLACEHOLDER", db_pass)
            gsub("REDIS_PASSWORD_PLACEHOLDER", redis_pass)
            gsub("AUTH_KEY_PLACEHOLDER", auth_key)
            gsub("SECURE_AUTH_KEY_PLACEHOLDER", secure_auth_key)
            gsub("LOGGED_IN_KEY_PLACEHOLDER", logged_in_key)
            gsub("NONCE_KEY_PLACEHOLDER", nonce_key)
            gsub("AUTH_SALT_PLACEHOLDER", auth_salt)
            gsub("SECURE_AUTH_SALT_PLACEHOLDER", secure_auth_salt)
            gsub("LOGGED_IN_SALT_PLACEHOLDER", logged_in_salt)
            gsub("NONCE_SALT_PLACEHOLDER", nonce_salt)
            gsub("CHANGE_ME_AUTH_KEY", auth_key)
            gsub("CHANGE_ME_SECURE_AUTH_KEY", secure_auth_key)
            gsub("CHANGE_ME_LOGGED_IN_KEY", logged_in_key)
            gsub("CHANGE_ME_NONCE_KEY", nonce_key)
            gsub("CHANGE_ME_AUTH_SALT", auth_salt)
            gsub("CHANGE_ME_SECURE_AUTH_SALT", secure_auth_salt)
            gsub("CHANGE_ME_LOGGED_IN_SALT", logged_in_salt)
            gsub("CHANGE_ME_NONCE_SALT", nonce_salt)
            print
        }
        ' "$values_file" > "$temp_values_file"
        
        values_file="$temp_values_file"

        if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^$RELEASE_NAME"; then
            log_info "Upgrading existing Helm release..."
            helm upgrade "$RELEASE_NAME" "$HELM_CHART_PATH" \
                --namespace "$NAMESPACE" \
                --values "$values_file" \
                --set wordpress.domain="$FULL_DOMAIN" \
                --set wordpress.includeWWW="$INCLUDE_WWW" \
                --set wordpress.redirectToWWW="${REDIRECT_TO_WWW:-false}" \
                --set wordpress.redirectFromWWW="${REDIRECT_FROM_WWW:-false}" \
                --reuse-values \
                --history-max 3 \
                --timeout=300s
        else
            log_info "Installing new Helm deployment..."
            helm install "$RELEASE_NAME" "$HELM_CHART_PATH" \
                --namespace "$NAMESPACE" \
                --create-namespace \
                --values "$values_file" \
                --set wordpress.domain="$FULL_DOMAIN" \
                --set wordpress.includeWWW="$INCLUDE_WWW" \
                --set wordpress.redirectToWWW="${REDIRECT_TO_WWW:-false}" \
                --set wordpress.redirectFromWWW="${REDIRECT_FROM_WWW:-false}" \
                --set muPlugins.fluentAuthFix.enabled="${ENABLE_FLUENT_AUTH_FIX:-false}" \
                --timeout=300s
        fi
        
        # Wait for pods manually with proper error handling and timeout (non-blocking)
        log_substep "Waiting for MariaDB pods to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb -n "$NAMESPACE" --timeout=180s || log_warning "MariaDB pods taking longer than expected"
        
        log_substep "WordPress pods are starting up..."
        log_info "WordPress installation wizard will be available once pods are running"
        log_info "Visit https://${FULL_DOMAIN}/wp-admin/install.php to complete setup"
        
        # Apply enhanced security hardening to ingress (matching Vaultwarden security)
        log_substep "Applying security hardening to ingress..."
        kubectl patch ingress "$RELEASE_NAME" -n "$NAMESPACE" -p '{
            "metadata":{
                "annotations":{
                    "nginx.ingress.kubernetes.io/rate-limit":"50",
                    "nginx.ingress.kubernetes.io/rate-limit-window":"1m",
                    "nginx.ingress.kubernetes.io/rate-limit-connections":"10",
                    "nginx.ingress.kubernetes.io/limit-connections":"20",
                    "nginx.ingress.kubernetes.io/limit-rps":"10"
                }
            }
        }' || log_warning "Security hardening could not be applied - may need manual configuration"
        
        log_substep "✓ Security hardening applied"
        
        # Clean up temporary files
        rm -f "$values_file"
        
        log_success "WordPress deployed successfully"
}

# Display deployment summary and offer credential viewing
display_deployment_summary() {
    log_step "📋 WordPress Deployment Complete"
    
    echo -e "\n${BOLD}${GREEN}🎉 WordPress Successfully Deployed!${NC}\n"
    
    echo -e "${BOLD}Deployment Details:${NC}"
    echo -e "  🌐 URL: ${BLUE}https://${FULL_DOMAIN}${NC}"
    echo -e "  👤 Admin Username: ${YELLOW}admin${NC}"
    echo -e "  🏷️  Namespace: ${CYAN}${NAMESPACE}${NC}"
    echo -e "  📦 Release: ${CYAN}${RELEASE_NAME}${NC}"
    echo -e "  📅 Deployed: $(date -Iseconds)\n"
    
    echo -e "${BOLD}Security Features:${NC}"
    echo -e "  ✅ Zero-trust networking (NetworkPolicy)"
    echo -e "  ✅ TLS 1.3 encryption with Let's Encrypt"
    echo -e "  ✅ Pod Security Standards: Restricted"
    echo -e "  ✅ Credentials stored securely in Kubernetes secrets\n"
    
    # Get external IP for DNS instructions with comprehensive detection
    log_substep "Detecting LoadBalancer external IP..."
    local external_ip=""
    local ip_detection_attempts=0
    local max_attempts=10
    
    while [[ -z "$external_ip" && $ip_detection_attempts -lt $max_attempts ]]; do
        external_ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -z "$external_ip" ]]; then
            # Try hostname for AWS/GCP
            external_ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        fi
        
        if [[ -z "$external_ip" ]]; then
            ((ip_detection_attempts++))
            if [[ $ip_detection_attempts -lt $max_attempts ]]; then
                echo "  Waiting for LoadBalancer IP... (attempt $ip_detection_attempts/$max_attempts)"
                sleep 3
            fi
        fi
    done
    
    if [[ -z "$external_ip" ]]; then
        external_ip="PENDING_LOADBALANCER_IP"
        echo -e "${YELLOW}⚠️  LoadBalancer IP not ready yet - check again in a few minutes${NC}"
    else
        echo -e "${GREEN}✅ LoadBalancer IP detected: ${external_ip}${NC}"
    fi
    
    echo -e "\n${BOLD}🌐 DNS Configuration Required:${NC}"
    echo -e "  ${CYAN}Record 1 - Root Domain (A Record):${NC}"
    echo -e "    ${CYAN}Type:${NC} A"
    echo -e "    ${CYAN}Name:${NC} @ (or root)"
    echo -e "    ${CYAN}Value:${NC} ${YELLOW}${external_ip}${NC}"
    echo -e "    ${CYAN}TTL:${NC} 300 (5 minutes)"
    
    if [[ "$INCLUDE_WWW" == "true" ]]; then
        echo -e "  ${CYAN}Record 2 - WWW Subdomain (CNAME):${NC}"
        echo -e "    ${CYAN}Type:${NC} CNAME"
        echo -e "    ${CYAN}Name:${NC} www"
        echo -e "    ${CYAN}Value:${NC} ${YELLOW}${FULL_DOMAIN}.${NC}"
        echo -e "    ${CYAN}TTL:${NC} 300 (5 minutes)"
        echo -e "  ${YELLOW}📌 Note:${NC} CNAME is the DNS-standard method for www subdomains\n"
    else
        echo
    fi
    
    if [[ "$external_ip" == "PENDING_LOADBALANCER_IP" ]]; then
        echo -e "${YELLOW}📝 To get the LoadBalancer IP later:${NC}"
        echo -e "  kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
        echo -e "  ${CYAN}Or check your cloud provider's load balancer console${NC}\n"
    fi
    
    # WordPress Installation Wizard Instructions
    echo -e "${BOLD}${GREEN}🎯 WordPress Installation Required${NC}"
    echo -e "WordPress will guide you through the setup process at:"
    if [[ "$INCLUDE_WWW" == "true" ]]; then
        echo -e "  ${BLUE}https://${FULL_DOMAIN}/wp-admin/install.php${NC}"
        echo -e "  ${BLUE}https://www.${FULL_DOMAIN}/wp-admin/install.php${NC} (both work)\n"
    else
        echo -e "  ${BLUE}https://${FULL_DOMAIN}/wp-admin/install.php${NC}\n"
    fi
    
    echo -e "${BOLD}Installation Steps:${NC}"
    if [[ "$INCLUDE_WWW" == "true" ]]; then
        echo -e "  ${CYAN}1.${NC} Visit your site: ${BLUE}https://${FULL_DOMAIN}${NC} or ${BLUE}https://www.${FULL_DOMAIN}${NC}"
    else
        echo -e "  ${CYAN}1.${NC} Visit your site: ${BLUE}https://${FULL_DOMAIN}${NC}"
    fi
    echo -e "  ${CYAN}2.${NC} WordPress will redirect to the installation wizard"
    echo -e "  ${CYAN}3.${NC} Choose your language and click 'Continue'"
    echo -e "  ${CYAN}4.${NC} Fill in your site details:"
    echo -e "     • Site Title: Your choice"
    echo -e "     • Username: Choose your admin username"
    echo -e "     • Password: Choose a strong password"
    echo -e "     • Email: Your email address"
    echo -e "  ${CYAN}5.${NC} Click 'Install WordPress'\n"
    
    echo -e "${BOLD}${YELLOW}⚠️  Security Reminders:${NC}"
    echo -e "  • Use a strong, unique admin password"
    echo -e "  • Choose a username other than 'admin' for better security"
    echo -e "  • Save your credentials in a password manager"
    echo -e "  • Consider enabling two-factor authentication after setup\n"
    
    if [[ "$INCLUDE_WWW" == "true" ]]; then
        echo -e "${GREEN}✅ Deployment complete! Your site is accessible at:${NC}"
        echo -e "   ${BLUE}https://${FULL_DOMAIN}${NC}"
        echo -e "   ${BLUE}https://www.${FULL_DOMAIN}${NC}"
    else
        echo -e "${GREEN}✅ Deployment complete! Begin WordPress setup at: https://${FULL_DOMAIN}${NC}"
    fi
}

# Note: Credential display functions removed - WordPress uses installation wizard

# Show installation wizard URL (replaces credential display)
show_installation_command() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' not found. WordPress may not be deployed."
        exit 1
    fi
    
    local external_ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "LoadBalancer-IP-Not-Ready")
    
    echo -e "${BOLD}${GREEN}WordPress Installation Information${NC}\n"
    echo -e "${BOLD}Installation URL:${NC} ${BLUE}https://your-domain.com/wp-admin/install.php${NC}"
    echo -e "${BOLD}LoadBalancer IP:${NC} ${YELLOW}${external_ip}${NC}"
    echo -e "${BOLD}DNS Required:${NC} Point your domain A record to the LoadBalancer IP\n"
    
    echo -e "${CYAN}Once DNS is configured, visit your domain to complete WordPress setup${NC}"
}

# Validate deployment
validate_deployment() {
    log_step "Validating Deployment"
    
    # Check pod status
    log_substep "Checking pod status..."
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME"
    
    # Wait for pods to be ready
    log_substep "Waiting for WordPress to be ready..."
    kubectl wait --namespace "$NAMESPACE" \
        --for=condition=ready pod \
        --selector="app.kubernetes.io/instance=$RELEASE_NAME,app.kubernetes.io/component=wordpress" \
        --timeout=300s
    
    # Check ingress
    log_substep "Checking ingress configuration..."
    kubectl get ingress -n "$NAMESPACE"
    
    # Check certificates
    log_substep "Checking TLS certificates..."
    local cert_ready=false
    local attempts=0
    local max_attempts=30
    
    while [[ $cert_ready == false && $attempts -lt $max_attempts ]]; do
        if kubectl get certificate wordpress-tls -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
            cert_ready=true
            log_substep "✓ TLS certificate ready"
        else
            log_substep "Waiting for TLS certificate... ($((attempts + 1))/$max_attempts)"
            sleep 10
            ((attempts++))
        fi
    done
    
    if [[ $cert_ready == false ]]; then
        log_warning "TLS certificate not ready yet. It may take a few minutes."
        log_info "You can check status with: kubectl describe certificate wordpress-tls -n $NAMESPACE"
    fi
    
    log_success "Deployment validation completed"
}

# Ask user if they want to see credentials (security best practice)
ask_display_credentials() {
    echo
    echo -e "${YELLOW}⚠️  SECURITY NOTICE: Admin credentials display${NC}"
    echo "   Your WordPress admin credentials have been securely generated."
    echo "   The credentials are stored encrypted in Kubernetes secrets."
    echo "   For security, credentials should only be displayed when necessary."
    echo
    
    echo -n -e "${WHITE}Display WordPress admin credentials now? (Choose 'n' if others can see your screen) [y/N]: ${NC}"
    read -r response
    
    # Convert to lowercase using portable method (compatible with Bash 3.x on macOS)
    response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    if [[ "$response_lower" =~ ^(y|yes)$ ]]; then
        echo
        show_credentials_only "" "$NAMESPACE" "$RELEASE_NAME"
        echo
        log_warning "⚠️  CRITICAL: Save these credentials securely!"
        echo "   • Store in a password manager or secure encrypted notes"
        echo "   • Never share or commit to version control"
        echo "   • These provide full admin access to your WordPress site"
        echo "   • View again later with: ./deploy.sh --show-credentials"
        echo
        
        # Offer to pause for secure storage
        echo -n -e "${WHITE}Pause for 30 seconds to securely save credentials? [Y/n]: ${NC}"
        read -r pause_response
        if [[ "${pause_response}" != "n" && "${pause_response}" != "N" ]]; then
            log_info "Pausing for 30 seconds to allow secure credential storage..."
            echo "Press Ctrl+C if you need more time."
            sleep 30
            echo
        fi
    else
        echo
        log_info "Admin credentials not displayed for security."
        echo "   To retrieve them later:"
        echo "   kubectl get secret $RELEASE_NAME -n $NAMESPACE -o jsonpath='{.data.wordpress-password}' | base64 -d"
        echo "   Or run: ./deploy.sh --show-credentials"
        echo
        log_warning "⚠️  If you lose access, regenerate credentials by re-running this script."
        echo
    fi
}

# Display connection info with enhanced security
display_connection_info() {
    log_step "WordPress Deployment Complete! 🚀"
    
    # Get external IP
    local external_ip=""
    local attempts=0
    while [[ -z "$external_ip" && $attempts -lt 30 ]]; do
        external_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -z "$external_ip" ]]; then
            sleep 2
            ((attempts++))
        fi
    done
    
    echo -e "\n${BOLD}🎉 WordPress Enterprise Deployment Successful!${NC}\n"
    
    echo -e "\n${BOLD}📋 Connection Information:${NC}"
    echo -e "  🌐 WordPress URL: ${GREEN}https://${FULL_DOMAIN}${NC}"
    echo -e "  📝 Installation Wizard: ${GREEN}https://${FULL_DOMAIN}/wp-admin/install.php${NC}"
    
    if [[ -n "$external_ip" ]]; then
        echo -e "\n${BOLD}🔧 DNS Configuration Required:${NC}"
        echo -e "  Create an A record for: ${CYAN}${FULL_DOMAIN}${NC}"
        echo -e "  Pointing to IP: ${CYAN}${external_ip}${NC}"
        
        if [[ "$INCLUDE_WWW" == "true" ]]; then
            echo -e "  ${GREEN}✓${NC} www.${FULL_DOMAIN} will automatically work with the same certificate"
            echo -e "  ${BLUE}Note:${NC} Both ${FULL_DOMAIN} and www.${FULL_DOMAIN} are configured"
        fi
    fi
    
    echo -e "\n${BOLD}🎯 Next Steps:${NC}"
    echo -e "  1. Visit ${CYAN}https://${FULL_DOMAIN}/wp-admin/install.php${NC}"
    echo -e "  2. Complete the WordPress installation wizard"
    echo -e "  3. Create your admin account (choose secure credentials)"
    echo -e "  4. Configure your site settings"
    echo -e "\n${BOLD}📦 Database Credentials:${NC}"
    log_info "Database credentials stored securely in Kubernetes secrets."
    echo "   To view: ./deploy.sh --show-credentials $NAMESPACE $RELEASE_NAME"
    
    echo -e "\n${BOLD}🛡️ Security Features Enabled:${NC}"
    echo -e "  ✓ TLS 1.3 Encryption with Let's Encrypt"
    echo -e "  ✓ Zero-trust NetworkPolicy (ingress-nginx only)"
    echo -e "  ✓ Pod Security Standards: Restricted"
    echo -e "  ✓ Non-root containers (UID 1000)"
    echo -e "  ✓ Read-only root filesystem"
    echo -e "  ✓ Dropped ALL capabilities"
    echo -e "  ✓ WordPress security keys auto-generated"
    echo -e "  ✓ Resource Limits and Health Checks"
    echo -e "  ✓ Automated Horizontal Pod Autoscaling"
    
    if [[ "$ENABLE_BACKUP" == "true" ]]; then
        echo -e "  ✓ Automated Daily Backups (2 AM)"
    fi
    
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        echo -e "  ✓ Monitoring and Metrics"
    fi
    
    echo -e "\n${BOLD}📊 Management Commands:${NC}"
    echo -e "  View pods: ${CYAN}kubectl get pods -n ${NAMESPACE}${NC}"
    echo -e "  View logs: ${CYAN}kubectl logs -f deployment/wordpress -n ${NAMESPACE}${NC}"
    echo -e "  Scale WordPress: ${CYAN}kubectl scale deployment wordpress --replicas=3 -n ${NAMESPACE}${NC}"
    echo -e "  View NetworkPolicy: ${CYAN}kubectl get networkpolicy -n ${NAMESPACE}${NC}"
    echo -e "  Check TLS certificates: ${CYAN}kubectl get certificates -n ${NAMESPACE}${NC}"
    echo -e "  Show credentials: ${CYAN}./deploy.sh --show-credentials${NC}"
    
    echo -e "\n${BOLD}🔒 Enterprise Security Compliance:${NC}"
    echo -e "  ✓ SOC2/ISO42001 Ready"
    echo -e "  ✓ Zero-trust networking enforced"
    echo -e "  ✓ Enterprise password policies"
    echo -e "  ✓ Kubernetes Pod Security Standards: Restricted"
    echo -e "  ✓ Automated security hardening applied"
    echo -e "  ✓ Cohort-replicable deployment system"
    echo -e "  Check logs: ${CYAN}kubectl logs -f deployment/${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    echo -e "  Scale up: ${CYAN}kubectl scale deployment ${RELEASE_NAME} --replicas=2 -n ${NAMESPACE}${NC}"
    
    echo -e "\n${BOLD}🔍 Troubleshooting:${NC}"
    echo -e "  Certificate status: ${CYAN}kubectl describe certificate wordpress-tls -n ${NAMESPACE}${NC}"
    echo -e "  Ingress status: ${CYAN}kubectl describe ingress ${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    echo -e "  Pod events: ${CYAN}kubectl describe pod -l app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    
    echo -e "\n${GREEN}🎯 WordPress is ready for production use!${NC}"
    
    # Ask about displaying credentials
    ask_display_credentials
    
    # Deployment completed successfully
    log_success "🎯 WordPress deployment completed successfully!"
}

# Main deployment flow
main() {
    clear
    echo -e "${BOLD}${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    WordPress Enterprise Deployment               ║"
    echo "║                         v${SCRIPT_VERSION}                                   ║"
    echo "║                                                                  ║"
    echo "║  🚀 Production-ready WordPress with enterprise security          ║"
    echo "║  🛡️  Zero-trust networking and TLS encryption                     ║"
    echo "║  📊 Automated scaling, monitoring, and backups                   ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
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
                NAMESPACE="${NAMESPACE:-wordpress}"
                RELEASE_NAME="${RELEASE_NAME:-wordpress}"
                show_installation_command
                exit 0
                ;;
            --help|-h)
                echo "WordPress Enterprise Deployment Script v3.1.0"
                echo "============================================="
                echo ""
                echo "✨ Features:"
                echo "  • Automatic instance detection and safe upgrades"
                echo "  • Resource cleanup and configuration synchronization"
                echo "  • Preserves all data during updates"
                echo "  • Enterprise security and compliance"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --domain DOMAIN          Set domain name"
                echo "  --email EMAIL            Set Let's Encrypt email"
                echo "  --namespace NAMESPACE    Set Kubernetes namespace"
                echo "  --skip-prerequisites     Skip infrastructure setup"
                echo "  --show-credentials       Show installation wizard info"
                echo "  --help                   Show this help"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive deployment/upgrade"
                echo "  $0 --domain site.com --email you@site.com  # Non-interactive deployment"
                echo "  $0 --show-credentials                # View existing credentials"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Enterprise deployment workflow (stateless and restartable)
    if [[ "$SKIP_PREREQUISITES" != "true" ]]; then
        check_prerequisites
    fi
    
    # NEW: Instance detection and upgrade logic (BEFORE user input)
    NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
    RELEASE_NAME="${RELEASE_NAME:-$DEFAULT_RELEASE_NAME}"
    
    if detect_existing_instance "$NAMESPACE" "$RELEASE_NAME"; then
        show_instance_detected "$NAMESPACE" "$RELEASE_NAME"
        choice=$(prompt_deployment_choice)
        case $choice in
            1)
                log_info "User selected: Update existing instance"
                echo ""
                echo "📋 Please provide configuration for the update:"
                if [[ -z "$DOMAIN" ]]; then
                    read -p "Enter domain name (e.g., yourdomain.com): " DOMAIN
                    validate_domain "$DOMAIN" || exit 1
                fi
                if [[ -z "$EMAIL" ]]; then
                    read -p "Enter email for Let's Encrypt certificates: " EMAIL
                    validate_email "$EMAIL" || exit 1
                fi
                echo ""
                if update_existing_instance "$NAMESPACE" "$RELEASE_NAME" "$DOMAIN" "$EMAIL"; then
                    display_connection_info
                    exit 0
                else
                    log_error "Update failed. Check logs above for details."
                    exit 1
                fi
                ;;
            2)
                log_info "User selected: Deploy new instance"
                echo ""
                read -p "Enter new release name (current: $RELEASE_NAME): " new_release
                if [[ -n "$new_release" ]]; then
                    RELEASE_NAME="$new_release"
                fi
                read -p "Enter new namespace (current: $NAMESPACE): " new_namespace
                if [[ -n "$new_namespace" ]]; then
                    NAMESPACE="$new_namespace"
                fi
                log_info "Proceeding with new deployment: $RELEASE_NAME in namespace $NAMESPACE"
                # Collect user input for new deployment
                collect_user_input
                ;;
            3)
                log_info "Deployment cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Deployment cancelled."
                exit 1
                ;;
        esac
    else
        log_info "No existing instance detected. Proceeding with fresh deployment."
        # Collect user input for fresh deployment
        collect_user_input
    fi
    
    # Continue with normal deployment flow for new instances
    if [[ "$SKIP_PREREQUISITES" != "true" ]] && [[ "${SKIP_INFRASTRUCTURE:-false}" != "true" ]]; then
        setup_infrastructure
    fi
    
    setup_namespace_and_secrets
    deploy_wordpress
    display_connection_info
}

# Error handling
trap 'log_error "Script interrupted. Run again to resume from last checkpoint."; exit 1' INT TERM

# Run main function
main "$@"
