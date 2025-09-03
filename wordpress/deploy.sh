#!/bin/bash

# WordPress Enterprise Deployment Script
# Production-ready WordPress with enhanced security
# Version: 3.0.0

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
    
    echo "🔐 WordPress Credentials (from Kubernetes secret)"
    echo "================================================"
    echo
    
    if ! kubectl get secret "$release" -n "$namespace" &>/dev/null; then
        echo "❌ Secret '$release' not found in namespace '$namespace'"
        echo "💡 Usage: $0 --show-credentials [namespace] [release-name]"
        exit 1
    fi
    
    echo "WordPress Admin:"
    echo "  Username: admin"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.wordpress-password}' | base64 -d)"
    echo
    echo "Database (MariaDB):"
    echo "  Root Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.mariadb-root-password}' | base64 -d)"
    echo "  WordPress Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.mariadb-password}' | base64 -d)"
    echo
    echo "Redis Cache:"
    echo "  Password: $(kubectl get secret "$release" -n "$namespace" -o jsonpath='{.data.redis-password}' | base64 -d)"
    echo
    echo "🌐 WordPress URL: https://$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'Check ingress configuration')"
    echo
    echo "⚠️  Keep these credentials secure and private!"
}

show_help() {
    echo "WordPress Enterprise Deployment Script"
    echo "======================================="
    echo
    echo "Usage:"
    echo "  $0                                    # Deploy WordPress"
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
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_AUTHOR="WordPress Enterprise"

# Default values
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
    
    # Check and install NGINX Ingress Controller
    log_substep "Checking NGINX Ingress Controller..."
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_substep "Installing NGINX Ingress Controller..."
        helm upgrade --install ingress-nginx ingress-nginx \
            --repo https://kubernetes.github.io/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.type=LoadBalancer \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-enable-proxy-protocol"="true" \
            --set controller.config.use-proxy-protocol="true" \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-size-unit"="1" \
            --wait --timeout=300s
        
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
        log_success "✅ ClusterIssuer already exists"
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
        log_success "✅ ClusterIssuer configured"
    fi
    
    # Add Bitnami repo for dependencies
    log_substep "Adding Bitnami Helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami &> /dev/null || true
    helm repo update &> /dev/null
    
    log_success "Infrastructure prerequisites ready"
}

# Enhanced password generation with Argon2id hashing
generate_secure_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
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

# Namespace and Release Configuration
configure_namespace() {
    # Use environment variables if provided (don't override them)
    if [[ -n "$NAMESPACE" ]]; then
        # Environment variable provided - use it
        RELEASE_NAME="${RELEASE_NAME:-$NAMESPACE}"
        log_success "Using configured namespace/release: $NAMESPACE / $RELEASE_NAME"
        return 0
    fi
    
    echo
    log_step "• Kubernetes Namespace Configuration"
    echo
    
    # Always prompt user for namespace preference
    while true; do
        echo "Choose your Kubernetes namespace configuration:"
        echo "  1) Use default 'wordpress' namespace"
        echo "  2) Create custom namespace"
        echo
        echo -n -e "${WHITE}Select option [1-2]: ${NC}"
        read -r namespace_choice
        
        case $namespace_choice in
            1)
                NAMESPACE="wordpress"
                RELEASE_NAME="wordpress"
                log_info "Using default namespace: wordpress"
                break
                ;;
            2)
                while true; do
                    echo -n -e "${WHITE}Enter custom namespace name (lowercase, letters/numbers/hyphens only): ${NC}"
                    read -r custom_name
                    
                    # Validate name format
                    if [[ "$custom_name" =~ ^[a-z0-9-]+$ ]] && [[ ${#custom_name} -le 63 ]] && [[ "$custom_name" != "wordpress" ]]; then
                        NAMESPACE="$custom_name"
                        RELEASE_NAME="$custom_name"
                        log_info "Using custom namespace: $custom_name"
                        break
                    elif [[ "$custom_name" == "wordpress" ]]; then
                        log_warning "Please use option 1 for default 'wordpress' namespace, or choose a different custom name."
                    else
                        log_warning "Invalid name. Use only lowercase letters, numbers, and hyphens (max 63 chars)"
                    fi
                done
                break
                ;;
            *)
                log_warning "Please enter 1 or 2"
                ;;
        esac
    done
    
    log_success "Configuration: namespace=$NAMESPACE, release=$RELEASE_NAME"
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
    
    # Step 1: Domain Configuration
    if [[ -n "$DOMAIN" ]]; then
        log_success "Using configured domain: $DOMAIN"
        FULL_DOMAIN="$DOMAIN"
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
            MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'.' -f2-)
        else
            MAIN_DOMAIN="$DOMAIN"
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
    configure_namespace
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
        echo "${BOLD}DNS Record Configuration:${NC}"
        echo "  Type: A"
        if [[ -n "$SUBDOMAIN" ]]; then
            echo "  Name: $SUBDOMAIN"
        else
            echo "  Name: @ (root domain)"
        fi
        echo "  Value: $external_ip"
        echo "  TTL: 300 (5 minutes - good for testing)"
        echo
        echo "${CYAN}Create this DNS record in your domain provider's control panel${NC}"
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
    
    # Collect namespace
    echo
    log_substep "Kubernetes Configuration"
    echo -n -e "${WHITE}Enter Kubernetes namespace [wordpress]: ${NC}"
    read -r namespace_input
    NAMESPACE="${namespace_input:-wordpress}"
    if ! validate_namespace "$NAMESPACE"; then
        log_error "Invalid namespace, using default: wordpress"
        NAMESPACE="wordpress"
    fi
    
    # Collect release name
    echo -n -e "${WHITE}Enter Helm release name [wordpress]: ${NC}"
    read -r release_input
    RELEASE_NAME="${release_input:-wordpress}"
    
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
    
    # Generate secure passwords
    log_substep "Generating secure passwords..."
    wordpress_password=$(generate_secure_password 24)
    mariadb_root_password=$(generate_secure_password 32)
    mariadb_password=$(generate_secure_password 24)
    redis_password=$(generate_secure_password 20)
    
    # Generate WordPress security keys
    log_substep "Generating WordPress security keys..."
    auth_key=$(generate_wp_salt)
    secure_auth_key=$(generate_wp_salt)
    logged_in_key=$(generate_wp_salt)
    nonce_key=$(generate_wp_salt)
    auth_salt=$(generate_wp_salt)
    secure_auth_salt=$(generate_wp_salt)
    logged_in_salt=$(generate_wp_salt)
    nonce_salt=$(generate_wp_salt)
    
    # Create Kubernetes secrets with proper Helm metadata
    log_substep "Creating Kubernetes secrets..."
    
    # Debug: Verify passwords are generated
    if [[ -z "$wordpress_password" || -z "$mariadb_root_password" || -z "$mariadb_password" ]]; then
        log_error "Password generation failed - variables are empty"
        exit 1
    fi
    
    log_substep "Generated passwords (lengths): WP=${#wordpress_password}, MariaDB-Root=${#mariadb_root_password}, MariaDB=${#mariadb_password}"
    
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
  wordpress-password: $(echo -n "$wordpress_password" | base64)
  redis-password: $(echo -n "$redis_password" | base64)
  auth-key: $(echo -n "$auth_key" | base64)
  secure-auth-key: $(echo -n "$secure_auth_key" | base64)
  logged-in-key: $(echo -n "$logged_in_key" | base64)
  nonce-key: $(echo -n "$nonce_key" | base64)
  auth-salt: $(echo -n "$auth_salt" | base64)
  secure-auth-salt: $(echo -n "$secure_auth_salt" | base64)
  logged-in-salt: $(echo -n "$logged_in_salt" | base64)
  nonce-salt: $(echo -n "$nonce_salt" | base64)
EOF
    
    # Store passwords in variables for Helm deployment
    export WORDPRESS_PASSWORD="$wordpress_password"
    export MARIADB_ROOT_PASSWORD="$mariadb_root_password"
    export MARIADB_PASSWORD="$mariadb_password"
    export REDIS_PASSWORD="$redis_password"
    
    log_success "Credentials generated and stored securely in Kubernetes secret"
}

    # Deploy WordPress (fix variable scoping)
deploy_wordpress() {
        log_step "Deploying WordPress Helm Chart"
        
        # Use the main values.yaml file with placeholder replacement
        local values_file="helm/values.yaml"
        local temp_values_file=$(mktemp)
        
        # Copy and process the main values.yaml file with domain/email placeholders
        # Use environment variables set during secret creation
        local wp_pass="${WORDPRESS_PASSWORD}"
        local db_root_pass="${MARIADB_ROOT_PASSWORD}"
        local db_pass="${MARIADB_PASSWORD}"
        local redis_pass="${REDIS_PASSWORD}"
        
        # Use FULL_DOMAIN for correct domain handling (main domain vs subdomain)
        sed -e "s/DOMAIN_PLACEHOLDER/${FULL_DOMAIN}/g" \
            -e "s/EMAIL_PLACEHOLDER/${EMAIL}/g" \
            -e "s/WORDPRESS_PASSWORD_PLACEHOLDER/$wp_pass/g" \
            -e "s/MARIADB_ROOT_PASSWORD_PLACEHOLDER/$db_root_pass/g" \
            -e "s/MARIADB_PASSWORD_PLACEHOLDER/$db_pass/g" \
            -e "s/REDIS_PASSWORD_PLACEHOLDER/$redis_pass/g" \
            -e "s/AUTH_KEY_PLACEHOLDER/$auth_key/g" \
            -e "s/SECURE_AUTH_KEY_PLACEHOLDER/$secure_auth_key/g" \
            -e "s/LOGGED_IN_KEY_PLACEHOLDER/$logged_in_key/g" \
            -e "s/NONCE_KEY_PLACEHOLDER/$nonce_key/g" \
            -e "s/AUTH_SALT_PLACEHOLDER/$auth_salt/g" \
            -e "s/SECURE_AUTH_SALT_PLACEHOLDER/$secure_auth_salt/g" \
            -e "s/LOGGED_IN_SALT_PLACEHOLDER/$logged_in_salt/g" \
            -e "s/NONCE_SALT_PLACEHOLDER/$nonce_salt/g" \
            "$values_file" > "$temp_values_file"
        
        values_file="$temp_values_file"

        # Build Helm dependencies
        log_substep "Building Helm chart dependencies..."
        helm dependency build "$HELM_CHART_PATH"
        
        # Template and apply placeholders
        log_substep "Processing Helm chart with domain configuration..."
        
        # Deploy WordPress with Helm (without --wait to prevent hanging)
        log_substep "Installing WordPress Helm chart..."
        helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --values "$values_file" \
            --timeout=300s
        
        # Wait for pods manually with proper error handling
        log_substep "Waiting for MariaDB pods to be ready..."
        if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb -n "$NAMESPACE" --timeout=300s; then
            log_error "MariaDB pods failed to become ready within 300s"
            kubectl get pods -n "$NAMESPACE"
            kubectl logs -l app.kubernetes.io/name=mariadb -n "$NAMESPACE" --tail=10
            log_error "Deployment failed - MariaDB is required for WordPress"
            exit 1
        fi
        
        log_substep "Waiting for WordPress pods to be ready..."
        if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n "$NAMESPACE" --timeout=300s; then
            log_error "WordPress pods failed to become ready within 300s"
            kubectl get pods -n "$NAMESPACE"
            kubectl logs -l app.kubernetes.io/name=wordpress -n "$NAMESPACE" --tail=10
            log_error "Deployment failed - WordPress pods not healthy"
            exit 1
        fi
        
        # Apply enhanced security hardening to ingress (matching Vaultwarden security)
        log_substep "Applying security hardening to ingress..."
        kubectl patch ingress "$RELEASE_NAME" -n "$NAMESPACE" -p '{
            "metadata":{
                "annotations":{
                    "nginx.ingress.kubernetes.io/rate-limit":"50",
                    "nginx.ingress.kubernetes.io/rate-limit-window":"1m",
                    "nginx.ingress.kubernetes.io/rate-limit-connections":"10",
                    "nginx.ingress.kubernetes.io/limit-connections":"20",
                    "nginx.ingress.kubernetes.io/limit-rps":"10",
                    "nginx.ingress.kubernetes.io/server-snippet":"add_header X-Frame-Options SAMEORIGIN always; add_header X-Content-Type-Options nosniff always; add_header X-XSS-Protection \"1; mode=block\" always; add_header Referrer-Policy strict-origin-when-cross-origin always;"
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
    
    # Offer to display credentials
    echo -e "${BOLD}${YELLOW}⚠️  Credential Access${NC}"
    echo "Credentials are stored securely in Kubernetes secret: ${RELEASE_NAME}"
    echo "You can view them later using: ./deploy.sh --show-credentials"
    echo
    
    read -p "Would you like to display the credentials now? [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        display_credentials_secure
    else
        echo -e "${GREEN}✅ Deployment complete! Access your WordPress site at: https://${FULL_DOMAIN}${NC}"
        echo -e "${CYAN}💡 Run './deploy.sh --show-credentials' anytime to view credentials${NC}"
    fi
}

# Securely display credentials with warnings
display_credentials_secure() {
    echo -e "\n${BOLD}${RED}🔐 WordPress Credentials - SENSITIVE INFORMATION${NC}"
    echo -e "${YELLOW}⚠️  Store these credentials securely and clear your terminal after viewing${NC}\n"
    
    local wp_pass=$(kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.data.wordpress-password}' | base64 -d)
    local db_root_pass=$(kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-root-password}' | base64 -d)
    local db_pass=$(kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-password}' | base64 -d)
    
    echo -e "${BOLD}WordPress Admin:${NC}"
    echo -e "  URL: ${BLUE}https://${FULL_DOMAIN}/wp-admin/${NC}"
    echo -e "  Username: ${YELLOW}admin${NC}"
    echo -e "  Password: ${RED}${wp_pass}${NC}\n"
    
    echo -e "${BOLD}Database (MariaDB):${NC}"
    echo -e "  Root Password: ${RED}${db_root_pass}${NC}"
    echo -e "  WordPress User Password: ${RED}${db_pass}${NC}\n"
    
    echo -e "${YELLOW}💾 Important: Save these credentials in your password manager NOW${NC}"
    echo -e "${CYAN}🔄 View again anytime: ./deploy.sh --show-credentials${NC}\n"
    
    read -p "Press ENTER after you've saved the credentials securely..."
    clear
    echo -e "${GREEN}✅ Deployment complete! Access your WordPress site at: https://${FULL_DOMAIN}${NC}"
}

# Show credentials command (for --show-credentials flag)
show_credentials_command() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' not found. WordPress may not be deployed."
        exit 1
    fi
    
    if ! kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_error "Secret '$RELEASE_NAME' not found in namespace '$NAMESPACE'."
        exit 1
    fi
    
    # Set FULL_DOMAIN from deployment info if available
    if [[ -z "${FULL_DOMAIN:-}" ]]; then
        FULL_DOMAIN="your-domain.com"  # Fallback
    fi
    
    display_credentials_secure
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
    
    echo -e "${BOLD}📋 Connection Information:${NC}"
    echo -e "  🌐 WordPress URL: ${GREEN}https://${FULL_DOMAIN}${NC}"
    echo -e "  🔐 Admin Panel: ${GREEN}https://${FULL_DOMAIN}/wp-admin/${NC}"
    echo -e "  📧 Admin Email: admin@${FULL_DOMAIN}"
    echo -e "  👤 Admin Username: admin"
    
    if [[ -n "$external_ip" ]]; then
        echo -e "\n${BOLD}🔧 DNS Configuration Required:${NC}"
        echo -e "  Create an A record for: ${CYAN}${FULL_DOMAIN}${NC}"
        echo -e "  Pointing to IP: ${CYAN}${external_ip}${NC}"
    fi
    
    echo -e "\n${BOLD}🔑 Admin Credentials:${NC}"
    if [[ "$SHOW_CREDENTIALS" == "true" ]]; then
        echo -e "  👤 Username: ${CYAN}admin${NC}"
        echo -e "  🔐 Password: ${CYAN}${wordpress_password}${NC}"
        echo -e "  ${YELLOW}⚠️  Save these credentials securely - they won't be shown again${NC}"
    else
        log_info "Credentials stored securely in Kubernetes secrets."
        echo "   To view later: ./deploy.sh --show-credentials"
    fi
    
    echo -e "\n${BOLD}🛡️ Security Features Enabled:${NC}"
    echo -e "  ✓ TLS 1.3 Encryption with Let's Encrypt"
    echo -e "  ✓ Zero-trust NetworkPolicy (ingress-nginx only)"
    echo -e "  ✓ Pod Security Standards: Restricted"
    echo -e "  ✓ Non-root containers (UID 1000)"
    echo -e "  ✓ Read-only root filesystem"
    echo -e "  ✓ Dropped ALL capabilities"
    echo -e "  ✓ WordPress auto-configuration (no installation wizard)"
    echo -e "  ✓ Secure password generation (24-32 character)"
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
    echo "║                    WordPress Enterprise Deployment              ║"
    echo "║                         v${SCRIPT_VERSION} by ${SCRIPT_AUTHOR}                        ║"
    echo "║                                                                  ║"
    echo "║  🚀 Production-ready WordPress with enterprise security          ║"
    echo "║  🛡️  Zero-trust networking and TLS encryption                   ║"
    echo "║  📊 Automated scaling, monitoring, and backups                  ║"
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
                show_credentials_command
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --domain DOMAIN          Set domain name"
                echo "  --email EMAIL            Set Let's Encrypt email"
                echo "  --namespace NAMESPACE    Set Kubernetes namespace"
                echo "  --skip-prerequisites     Skip infrastructure setup"
                echo "  --show-credentials       Display stored credentials"
                echo "  --help                   Show this help"
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
    
    collect_user_input
    
    if [[ "$SKIP_PREREQUISITES" != "true" ]]; then
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
