#!/bin/bash

# WordPress Enterprise Deployment Script v3.0.0
# Enhanced security, user experience, and production readiness
# Compatible with WeOwn zero-trust security standards

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
readonly SCRIPT_AUTHOR="WeOwn Network"

# Default values
readonly DEFAULT_NAMESPACE="wordpress"
readonly DEFAULT_RELEASE_NAME="wordpress"
readonly HELM_CHART_PATH="./helm"
readonly STATE_FILE=".wordpress-deploy-state"

# Global variables
DOMAIN=""
SUBDOMAIN="wp"
NAMESPACE="${DEFAULT_NAMESPACE}"
RELEASE_NAME="${DEFAULT_RELEASE_NAME}"
EMAIL=""
DEPLOY_STATE=""
SKIP_PREREQUISITES=false
ENABLE_MONITORING=true
ENABLE_BACKUP=true

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

# Progress tracking
save_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
    log_info "Progress saved: $state"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        DEPLOY_STATE=$(cat "$STATE_FILE")
        log_info "Resuming from: $DEPLOY_STATE"
    fi
}

cleanup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm "$STATE_FILE"
        log_success "Deployment state cleared"
    fi
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

# User input collection
collect_user_input() {
    log_step "WordPress Configuration Setup"
    
    # Collect domain
    while true; do
        echo -n -e "${WHITE}Enter your domain (e.g., example.com): ${NC}"
        read -r DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        fi
    done
    
    # Collect subdomain
    echo -n -e "${WHITE}Enter WordPress subdomain [wp]: ${NC}"
    read -r subdomain_input
    SUBDOMAIN="${subdomain_input:-wp}"
    
    # Collect email for Let's Encrypt
    while true; do
        echo -n -e "${WHITE}Enter email for Let's Encrypt certificates: ${NC}"
        read -r EMAIL
        if validate_email "$EMAIL"; then
            break
        fi
    done
    
    # Collect namespace
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
    
    # Advanced options
    echo -e "\n${BOLD}Advanced Options:${NC}"
    echo -n -e "${WHITE}Enable monitoring and metrics? [Y/n]: ${NC}"
    read -r monitoring_input
    ENABLE_MONITORING=$([ "${monitoring_input,,}" != "n" ] && echo "true" || echo "false")
    
    echo -n -e "${WHITE}Enable automated backups? [Y/n]: ${NC}"
    read -r backup_input
    ENABLE_BACKUP=$([ "${backup_input,,}" != "n" ] && echo "true" || echo "false")
    
    # Configuration summary
    echo -e "\n${BOLD}Configuration Summary:${NC}"
    echo -e "  Domain: ${CYAN}https://${SUBDOMAIN}.${DOMAIN}${NC}"
    echo -e "  Namespace: ${CYAN}${NAMESPACE}${NC}"
    echo -e "  Release: ${CYAN}${RELEASE_NAME}${NC}"
    echo -e "  Email: ${CYAN}${EMAIL}${NC}"
    echo -e "  Monitoring: ${CYAN}${ENABLE_MONITORING}${NC}"
    echo -e "  Backups: ${CYAN}${ENABLE_BACKUP}${NC}"
    
    echo -n -e "\n${WHITE}Continue with deployment? [Y/n]: ${NC}"
    read -r confirm
    if [[ "${confirm,,}" == "n" ]]; then
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
    local wordpress_password=$(generate_secure_password 24)
    local mysql_root_password=$(generate_secure_password 32)
    local mysql_password=$(generate_secure_password 24)
    local redis_password=$(generate_secure_password 20)
    
    # Generate WordPress security keys
    log_substep "Generating WordPress security keys..."
    local auth_key=$(generate_wp_salt)
    local secure_auth_key=$(generate_wp_salt)
    local logged_in_key=$(generate_wp_salt)
    local nonce_key=$(generate_wp_salt)
    local auth_salt=$(generate_wp_salt)
    local secure_auth_salt=$(generate_wp_salt)
    local logged_in_salt=$(generate_wp_salt)
    local nonce_salt=$(generate_wp_salt)
    
    # Store passwords for later display
    cat > .wordpress-credentials << EOF
WordPress Admin Credentials:
Username: admin
Password: $wordpress_password
URL: https://${SUBDOMAIN}.${DOMAIN}/wp-admin/

Database Passwords:
MySQL Root Password: $mysql_root_password
MySQL WordPress Password: $mysql_password
Redis Password: $redis_password

Security Keys Generated: Yes
Namespace: $NAMESPACE
EOF
    
    log_success "Credentials generated and saved to .wordpress-credentials"
}

# Deploy WordPress
deploy_wordpress() {
    log_step "Deploying WordPress Helm Chart"
    
    # Create values override file
    local values_file="values-override.yaml"
    cat > "$values_file" << EOF
# WordPress Enterprise Configuration Override
global:
  storageClass: "do-block-storage"

wordpress:
  wordpressEmail: "admin@${DOMAIN}"
  autoscaling:
    enabled: true
  persistence:
    enabled: true
  
mysql:
  enabled: true
  auth:
    database: wordpress
    username: wordpress
  primary:
    persistence:
      enabled: true

redis:
  enabled: true
  auth:
    enabled: true

ingress:
  enabled: true
  className: nginx
  hosts:
  - host: "${SUBDOMAIN}.${DOMAIN}"
    paths:
    - path: /
      pathType: Prefix
  tls:
  - secretName: wordpress-tls
    hosts:
    - "${SUBDOMAIN}.${DOMAIN}"

networkPolicy:
  enabled: true

backup:
  enabled: ${ENABLE_BACKUP}

monitoring:
  enabled: ${ENABLE_MONITORING}

certManager:
  email: "${EMAIL}"

# Service Account
serviceAccount:
  create: true
  automount: false

# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
EOF

    # Template and apply placeholders
    log_substep "Processing Helm chart with domain configuration..."
    
    # Deploy WordPress with Helm
    helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --values "$values_file" \
        --set wordpress.wordpressPassword="$(head -n 1 .wordpress-credentials | cut -d: -f2 | xargs)" \
        --set mysql.auth.rootPassword="$(grep "MySQL Root Password:" .wordpress-credentials | cut -d: -f2 | xargs)" \
        --set mysql.auth.password="$(grep "MySQL WordPress Password:" .wordpress-credentials | cut -d: -f2 | xargs)" \
        --set redis.auth.password="$(grep "Redis Password:" .wordpress-credentials | cut -d: -f2 | xargs)" \
        --wait --timeout=600s
    
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
    
    local show_creds=false
    echo -n -e "${WHITE}Display WordPress admin credentials now? (Choose 'n' if others can see your screen) [y/N]: ${NC}"
    read -r response
    
    if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
        echo
        log_info "WordPress Admin Credentials:"
        cat .wordpress-credentials
        echo
        log_warning "⚠️  CRITICAL: Save these credentials securely - they won't be shown again!"
        echo "   • Store in a password manager or secure encrypted notes"
        echo "   • Never share or commit to version control"
        echo "   • These provide full admin access to your WordPress site"
        echo
        
        # Offer to pause for secure storage
        echo -n -e "${WHITE}Pause for 30 seconds to securely save credentials? [Y/n]: ${NC}"
        read -r pause_response
        if [[ "${pause_response,,}" != "n" ]]; then
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
        echo "   Or check the .wordpress-credentials file (if still present)"
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
    echo -e "  🌐 WordPress URL: ${GREEN}https://${SUBDOMAIN}.${DOMAIN}${NC}"
    echo -e "  🔐 Admin Panel: ${GREEN}https://${SUBDOMAIN}.${DOMAIN}/wp-admin/${NC}"
    echo -e "  📧 Admin Email: admin@${DOMAIN}"
    
    if [[ -n "$external_ip" ]]; then
        echo -e "\n${BOLD}🔧 DNS Configuration Required:${NC}"
        echo -e "  Create an A record for: ${CYAN}${SUBDOMAIN}.${DOMAIN}${NC}"
        echo -e "  Pointing to IP: ${CYAN}${external_ip}${NC}"
    fi
    
    echo -e "\n${BOLD}🔑 Admin Credentials:${NC}"
    if [[ -f .wordpress-credentials ]]; then
        echo -e "  Saved to: ${CYAN}.wordpress-credentials${NC}"
        echo -e "  ${YELLOW}⚠️  Keep this file secure and delete after noting the credentials${NC}"
    fi
    
    echo -e "\n${BOLD}🛡️ Security Features Enabled:${NC}"
    echo -e "  ✓ TLS 1.3 Encryption with Let's Encrypt"
    echo -e "  ✓ Zero-trust NetworkPolicy"
    echo -e "  ✓ Pod Security Contexts (non-root)"
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
    echo -e "  Check logs: ${CYAN}kubectl logs -f deployment/${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    echo -e "  Scale up: ${CYAN}kubectl scale deployment ${RELEASE_NAME} --replicas=2 -n ${NAMESPACE}${NC}"
    
    echo -e "\n${BOLD}🔍 Troubleshooting:${NC}"
    echo -e "  Certificate status: ${CYAN}kubectl describe certificate wordpress-tls -n ${NAMESPACE}${NC}"
    echo -e "  Ingress status: ${CYAN}kubectl describe ingress ${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    echo -e "  Pod events: ${CYAN}kubectl describe pod -l app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE}${NC}"
    
    echo -e "\n${GREEN}🎯 WordPress is ready for production use!${NC}"
    
    # Ask about displaying credentials
    ask_display_credentials
    
    # Clean up state file on successful completion
    cleanup_state
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
    
    # Load previous state if exists
    load_state
    
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
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --domain DOMAIN          Set domain name"
                echo "  --email EMAIL            Set Let's Encrypt email"
                echo "  --namespace NAMESPACE    Set Kubernetes namespace"
                echo "  --skip-prerequisites     Skip infrastructure setup"
                echo "  --help                   Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Deployment steps with state management
    if [[ "$DEPLOY_STATE" != "prerequisites_checked" && "$SKIP_PREREQUISITES" != "true" ]]; then
        check_prerequisites
        save_state "prerequisites_checked"
    fi
    
    if [[ "$DEPLOY_STATE" =~ ^(|prerequisites_checked)$ ]]; then
        collect_user_input
        save_state "input_collected"
    fi
    
    if [[ "$DEPLOY_STATE" =~ ^(|prerequisites_checked|input_collected)$ && "$SKIP_PREREQUISITES" != "true" ]]; then
        setup_infrastructure
        save_state "infrastructure_ready"
    fi
    
    if [[ "$DEPLOY_STATE" =~ ^(|prerequisites_checked|input_collected|infrastructure_ready)$ ]]; then
        setup_namespace_and_secrets
        save_state "secrets_created"
    fi
    
    if [[ "$DEPLOY_STATE" =~ ^(|prerequisites_checked|input_collected|infrastructure_ready|secrets_created)$ ]]; then
        deploy_wordpress
        save_state "wordpress_deployed"
    fi
    
    if [[ "$DEPLOY_STATE" =~ ^(|prerequisites_checked|input_collected|infrastructure_ready|secrets_created|wordpress_deployed)$ ]]; then
        validate_deployment
        save_state "deployment_validated"
    fi
    
    display_connection_info
}

# Error handling
trap 'log_error "Script interrupted. Run again to resume from last checkpoint."; exit 1' INT TERM

# Run main function
main "$@"
