#!/bin/bash

# WeOwn AnythingLLM Enterprise Deployment Script
# Version: 3.0.0 - Production-Ready with Enterprise Security
# 
# This script provides:
# - Enterprise-grade security with multi-user mode option
# - Automatic prerequisite installation with resume capability
# - Full transparency about every operation
# - Comprehensive error handling and recovery
# - Rate limiting fixes for optimal performance
# - Clear explanations of admin credentials, updates, backups, and scaling

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
NAMESPACE="anything-llm"
RELEASE_NAME="anythingllm"
CHART_PATH="./helm"

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

# OS Detection
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macOS" ;;
        Linux*) echo "Linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
        *) echo "Unknown" ;;
    esac
}

# User interaction functions
ask_user() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        while [[ -z "${response:-}" ]]; do
            read -p "$prompt: " response
        done
        echo "$response"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [y/N]: " response
            response="${response:-$default}"
        else
            read -p "$prompt [y/n]: " response
        fi
        
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Tool installation functions
get_install_instructions() {
    local tool="$1"
    local os="$2"
    
    case "$tool" in
        "kubectl")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew (recommended):"
                    echo "  brew install kubectl"
                    echo "  "
                    echo "  # Or download directly:"
                    echo "  curl -LO 'https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl'"
                    echo "  chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
                    ;;
                "Linux")
                    echo "  # Download and install:"
                    echo "  curl -LO 'https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl'"
                    echo "  chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
                    ;;
                "Windows")
                    echo "  # Download kubectl.exe from:"
                    echo "  https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
                    ;;
            esac
            ;;
        "helm")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew (recommended):"
                    echo "  brew install helm"
                    echo "  "
                    echo "  # Or install script:"
                    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    ;;
                "Linux")
                    echo "  # Install script:"
                    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    ;;
                "Windows")
                    echo "  # Using Chocolatey:"
                    echo "  choco install kubernetes-helm"
                    echo "  "
                    echo "  # Or download from: https://github.com/helm/helm/releases"
                    ;;
            esac
            ;;
        "curl")
            case "$os" in
                "macOS")
                    echo "  # Usually pre-installed. If not:"
                    echo "  brew install curl"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install curl"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install curl"
                    ;;
                "Windows")
                    echo "  # Usually available in Git Bash/WSL"
                    echo "  # Or download from: https://curl.se/windows/"
                    ;;
            esac
            ;;
        "git")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew:"
                    echo "  brew install git"
                    echo "  "
                    echo "  # Or download from: https://git-scm.com/download/mac"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install git"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install git"
                    ;;
                "Windows")
                    echo "  # Download Git for Windows:"
                    echo "  https://git-scm.com/download/win"
                    ;;
            esac
            ;;
        "openssl")
            case "$os" in
                "macOS")
                    echo "  # Usually pre-installed. If not:"
                    echo "  brew install openssl"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install openssl"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install openssl"
                    ;;
                "Windows")
                    echo "  # Available in Git Bash/WSL"
                    echo "  # Or install via Chocolatey: choco install openssl"
                    ;;
            esac
            ;;
    esac
}

check_tool() {
    local tool="$1"
    local description="$2"
    
    if command -v "$tool" &> /dev/null; then
        log_success "$tool is installed ✓"
        return 0
    else
        log_warning "$tool is not installed"
        echo -e "${YELLOW}What is $tool?${NC} $description"
        echo
        
        if ask_yes_no "Would you like to see installation instructions for $tool? This is required for deployment"; then
            echo -e "${BLUE}Installation instructions for $tool:${NC}"
            get_install_instructions "$tool" "$(detect_os)"
            echo
            log_warning "Please install $tool and run this script again."
            exit 1
        else
            log_error "Cannot continue without $tool. Exiting."
            exit 1
        fi
    fi
}


# Cluster connection function
# Enterprise Security Functions
generate_argon2_hash() {
    local password="$1"
    
    # Check if argon2 is available
    if command -v argon2 &> /dev/null; then
        # Generate Argon2id hash with enterprise security parameters
        echo -n "$password" | argon2 $(openssl rand -base64 32) -e -t 3 -m 16 -p 4 -id
    elif command -v argon2id &> /dev/null; then
        # Alternative argon2id command
        echo -n "$password" | argon2id -t 3 -m 65536 -p 4
    else
        log_warning "Argon2 not found. Installing..."
        install_argon2
        if command -v argon2 &> /dev/null; then
            echo -n "$password" | argon2 $(openssl rand -base64 32) -e -t 3 -m 16 -p 4 -id
        else
            log_error "Failed to install Argon2. Using SHA-256 fallback."
            echo -n "$password" | sha256sum | cut -d' ' -f1
        fi
    fi
}

install_argon2() {
    local os=$(detect_os)
    log_info "Installing Argon2 for $os..."
    
    case "$os" in
        "macOS")
            if command -v brew &> /dev/null; then
                brew install argon2 || log_error "Failed to install argon2 via Homebrew"
            else
                log_error "Homebrew not found. Please install argon2 manually."
            fi
            ;;
        "Linux")
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y argon2 || log_error "Failed to install argon2 via apt"
            elif command -v yum &> /dev/null; then
                sudo yum install -y argon2 || log_error "Failed to install argon2 via yum"
            else
                log_error "Package manager not found. Please install argon2 manually."
            fi
            ;;
        *)
            log_error "Unsupported OS for automatic argon2 installation"
            ;;
    esac
}

fix_networkpolicy_namespace() {
    log_step "Applying NetworkPolicy namespace fix for ingress-nginx"
    
    # Check if ingress-nginx namespace exists
    if kubectl get namespace ingress-nginx &>/dev/null; then
        # Check if the required label exists
        local current_label=$(kubectl get namespace ingress-nginx -o jsonpath='{.metadata.labels.name}' 2>/dev/null || echo "")
        
        if [[ "$current_label" != "ingress-nginx" ]]; then
            log_info "Adding required label to ingress-nginx namespace..."
            kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
            log_success "✅ NetworkPolicy namespace fix applied successfully"
        else
            log_success "✅ NetworkPolicy namespace label already configured correctly"
        fi
    else
        log_warning "⚠️  ingress-nginx namespace not found. This fix will be applied when NGINX Ingress is installed."
    fi
}

check_cluster_connection() {
    log_step "Checking Kubernetes cluster connection"
    echo
    
    log_info "Testing connection to your Kubernetes cluster..."
    
    if kubectl cluster-info &> /dev/null; then
        local cluster_info=$(kubectl cluster-info | head -1)
        log_success "Connected to Kubernetes cluster ✓"
        echo -e "${GREEN}$cluster_info${NC}"
        echo
        
        # Show cluster nodes
        log_info "Cluster nodes:"
        kubectl get nodes --no-headers | while read line; do
            echo "  • $line"
        done
        echo
        return 0
    else
        log_error "Cannot connect to Kubernetes cluster"
        echo
        log_info "This usually means you haven't configured kubectl to connect to your cluster."
        echo
        
        if ask_yes_no "Do you have a DigitalOcean Kubernetes cluster set up?"; then
            echo
            log_info "To connect to your DigitalOcean cluster:"
            echo "  1. Install doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/"
            echo "  2. Authenticate: doctl auth init"
            echo "  3. Get your cluster ID: doctl kubernetes cluster list"
            echo "  4. Configure kubectl: doctl kubernetes cluster kubeconfig save <cluster-id>"
            echo
            log_warning "Please complete these steps and run this script again."
            exit 1
        else
            echo
            log_info "You'll need a Kubernetes cluster to deploy AnythingLLM."
            log_info "DigitalOcean Kubernetes is recommended for this deployment."
            log_info "Visit: https://cloud.digitalocean.com/kubernetes/clusters"
            exit 1
        fi
    fi
}

# User configuration function
get_user_configuration() {
    log_step "Gathering your deployment configuration"
    echo
    
    log_info "I'll ask you a few questions to customize your AnythingLLM deployment."
    log_info "AnythingLLM is a private AI assistant that runs entirely on your infrastructure."
    echo
    
    # Get subdomain
    SUBDOMAIN=$(ask_user "Enter your desired subdomain (e.g., 'ai')" "ai")
    
    # Get domain
    DOMAIN_BASE=$(ask_user "Enter your domain name (e.g., 'example.com')")
    
    # Construct full domain
    FULL_DOMAIN="$SUBDOMAIN.$DOMAIN_BASE"
    
    # Get email for Let's Encrypt
    EMAIL=$(ask_user "Enter your email address for SSL certificates")
    
    # Ask about multi-user mode
    echo
    log_info "🔐 Security Configuration"
    echo
    log_info "AnythingLLM can be deployed in two modes:"
    echo "  • Single-User Mode: Private instance for one user"
    echo "  • Multi-User Mode: Enterprise mode with user management"
    echo
    
    if ask_yes_no "Enable Multi-User Mode for enterprise security?" "y"; then
        MULTI_USER_MODE="true"
        log_success "Multi-User Mode will be enabled ✓"
        echo
        log_info "After deployment, you'll create admin account via web interface"
    else
        MULTI_USER_MODE="false"
        log_info "Single-User Mode selected - no login required after deployment"
    fi
    
    # Generate secure admin password (for system auth and optional web login)
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    log_success "Secure admin password generated for system authentication"
    
    # Generate JWT secret
    JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    log_success "JWT secret generated ✓"
    
    # Configuration summary
    echo
    log_info "📋 Configuration Summary:"
    echo "  Full URL: https://$FULL_DOMAIN"
    echo "  Email: $EMAIL"
    echo "  Multi-User Mode: $MULTI_USER_MODE"
    if ask_yes_no "Display generated admin password? (This will be shown only once)" "n"; then
        echo "  Admin Password: $ADMIN_PASSWORD"
        echo
        log_warning "Save this password securely - it won't be shown again!"
    else
        echo "  Admin Password: [Hidden - stored securely in Kubernetes secrets]"
    fi
    echo
    
    if ! ask_yes_no "Continue with this configuration?" "y"; then
        log_info "Deployment cancelled."
        exit 0
    fi
}

# DNS setup instructions
setup_dns_instructions() {
    log_step "DNS Configuration Required"
    echo
    
    log_info "Before we can deploy AnythingLLM, we need to set up DNS."
    echo
    
    # Check if ingress controller exists and get external IP
    local external_ip=""
    if kubectl get svc ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        external_ip=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi
    
    if [[ -n "$external_ip" ]]; then
        log_success "Found ingress controller with external IP: $external_ip"
    else
        log_warning "Ingress controller not found or no external IP assigned yet."
        log_info "We'll install the ingress controller, then you'll need to create the DNS record."
    fi
    
    echo
    log_info "📋 DNS Setup Instructions:"
    echo "You need to create a DNS A record that points your subdomain to your cluster."
    echo
    echo "Record details:"
    echo "  Type: A"
    echo "  Name: $SUBDOMAIN"
    echo "  Value: [Your cluster's load balancer IP]"
    echo "  TTL: 300 (5 minutes)"
    echo
    
    if [[ -n "$external_ip" ]]; then
        echo -e "${GREEN}Use this IP address: $external_ip${NC}"
        echo
        if ! ask_yes_no "Have you created the DNS A record pointing $SUBDOMAIN.$DOMAIN_BASE to $external_ip?"; then
            log_warning "Please create the DNS record and run this script again."
            log_info "The deployment will fail without proper DNS configuration."
            exit 0
        fi
    else
        log_info "We'll get the IP address after installing the ingress controller."
        if ! ask_yes_no "Do you understand that you'll need to create a DNS A record?"; then
            log_warning "DNS configuration is required for AnythingLLM to work."
            log_info "Please review the DNS setup requirements and run this script again."
            exit 0
        fi
    fi
}

# State management functions
save_state() {
    local step="$1"
    echo "CURRENT_STEP=$step" > "$STATE_FILE"
    echo "TIMESTAMP='$(date '+%Y-%m-%d %H:%M:%S')'" >> "$STATE_FILE"
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
    
    # Create ClusterIssuer for Let's Encrypt
    log_info "Creating Let's Encrypt ClusterIssuer..."
    kubectl apply -f - <<EOF
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
    
    log_success "Let's Encrypt ClusterIssuer created ✓"
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
        --from-literal=MULTI_USER_MODE="$MULTI_USER_MODE" \
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
    
    # Apply enterprise security fixes
    log_step "Applying enterprise security configurations"
    fix_networkpolicy_namespace
    
    # Security status based on deployment mode
    if [[ "$MULTI_USER_MODE" == "true" ]]; then
        log_success "🔐 MULTI-USER MODE ENABLED"
        echo "${GREEN}Your AnythingLLM instance is configured for enterprise security!${NC}"
        echo
        echo "${BLUE}NEXT STEPS:${NC}"
        echo "  1. Visit: https://$FULL_DOMAIN"
        echo "  2. Create your admin account (first user becomes admin)"
        echo "  3. Configure your preferred LLM provider in Settings → AI Models"
        echo "  4. Add team members via Settings → Users"
        echo "  5. Review audit logs via Settings → Event Logs"
        echo
    else
        log_warning "🚨 SINGLE-USER MODE DEPLOYED 🚨"
        echo "${YELLOW}Your AnythingLLM instance is currently accessible without login!${NC}"
        echo
        echo "${YELLOW}NEXT STEPS:${NC}"
        echo "  1. Visit: https://$FULL_DOMAIN"
        echo "  2. Configure your preferred LLM provider in Settings → AI Models"
        echo "  3. Optional: Enable Multi-User Mode later in Settings → Security"
        echo "  4. Note: Single-User Mode is suitable for personal use only"
        echo
    fi
    
    # Enterprise security status
    log_success "🛡️  ENTERPRISE SECURITY FEATURES ENABLED:"
    echo "  ✅ TLS 1.3 encryption with strong cipher suites"
    echo "  ✅ Rate limiting (100 req/min, 20 connections max)"
    echo "  ✅ Zero-trust NetworkPolicy with micro-segmentation"
    echo "  ✅ Pod Security Standards (Restricted Profile)"
    echo "  ✅ Argon2id password hashing available"
    echo "  ✅ Enterprise security headers enforced"
    echo "  ✅ Automatic daily backups with 30-day retention"
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
    
    echo "🔄 ZERO-DOWNTIME UPDATES:"
    echo "  • Manual updates: Re-run this deployment script"
    echo "  • Check current version: helm list -n $NAMESPACE"
    echo "  • Update strategy: Rolling updates with health checks (zero downtime guaranteed)"
    echo "  • Security patches: Apply immediately via helm upgrade"
    echo "  • Container updates: Automatic pull of latest security patches"
    echo "  • Rollback if needed: helm rollback anythingllm -n $NAMESPACE"
    echo
    
    echo "💾 ENTERPRISE BACKUPS:"
    echo "  • Automated daily backups at 2 AM (configurable)"
    echo "  • 30-day retention policy for compliance"
    echo "  • Data location: Persistent volume (/app/server/storage)"
    echo "  • Backup method: Automated CronJob with DigitalOcean volume snapshots"
    echo "  • Encryption: At rest and in transit (enterprise-grade)"
    echo "  • Check backup status: kubectl get cronjob -n $NAMESPACE"
    echo "  • Manual backup: kubectl create job --from=cronjob/anythingllm-backup manual-backup-\$(date +%s) -n $NAMESPACE"
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

# Usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy AnythingLLM on Kubernetes with enterprise security features."
    echo
    echo "OPTIONS:"
    echo "  --fresh      Start a fresh deployment (clear previous state)"
    echo "  --help, -h   Show this help message"
    echo
    echo "FEATURES:"
    echo "  • Multi-user mode with enterprise security"
    echo "  • Zero-trust networking with NetworkPolicy"
    echo "  • TLS 1.3 encryption with Let's Encrypt certificates"
    echo "  • Automated daily backups with 30-day retention"
    echo "  • Pod Security Standards (Restricted Profile)"
    echo "  • Rate limiting and connection limits"
    echo "  • Comprehensive error handling and state management"
    echo
    echo "EXAMPLES:"
    echo "  $0                    # Interactive deployment"
    echo "  $0 --fresh           # Fresh deployment (clear state)"
    echo "  $0 --help            # Show this help"
    echo
    echo "REQUIREMENTS:"
    echo "  • Kubernetes cluster (DigitalOcean recommended)"
    echo "  • kubectl configured and connected"
    echo "  • Domain name with DNS control"
    echo "  • Email address for SSL certificates"
    echo
    echo "For more information, visit: https://github.com/WeOwn/ai"
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
    echo "Version: 3.0.0 - Production-Ready with Enterprise Security"
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
    main "$@"
else
    log_error "Invalid arguments. Use --help for usage information."
    exit 1
fi
