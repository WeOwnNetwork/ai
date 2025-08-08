#!/bin/bash

# AnythingLLM Deployment Script - WeOwn MVP-0.1
# Secure, automated deployment with proper secrets management

set -euo pipefail

# Get script directory for sourcing functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source deployment functions
if [[ -f "$SCRIPT_DIR/deploy-functions.sh" ]]; then
    source "$SCRIPT_DIR/deploy-functions.sh"
else
    echo "Error: deploy-functions.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Version and metadata
SCRIPT_VERSION="1.0.0"
REQUIRED_TOOLS=("kubectl" "helm" "curl" "git" "openssl")

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
REPO_URL="https://github.com/WeOwnNetwork/ai.git"
ANYTHINGLLM_DIR="anythingllm"

# Functions
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    WeOwn AnythingLLM                         ║"
    echo "║              Enterprise AI Assistant Platform               ║"
    echo "║                                                              ║"
    echo "║    🤖 Self-hosted • 🛡️  Enterprise Security • 🚀 Automated    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
    echo
    echo -e "${PURPLE}🔐 Privacy-First AI Platform${NC}"
    echo "• Complete privacy - your data never leaves your infrastructure"
    echo "• Enterprise security with Kubernetes-native deployment"
    echo "• OpenRouter integration with free models available"
    echo "• Document processing and RAG capabilities"
    echo "• Multi-user support with role-based access"
    echo
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

ask_user() {
    local question="$1"
    local default="${2:-}"
    local response
    
    if [[ -n "$default" ]]; then
        read -p "$question [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$question: " response
        echo "$response"
    fi
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$question [Y/n]: " response
            response=${response:-y}
        else
            read -p "$question [y/N]: " response
            response=${response:-n}
        fi
        
        # Convert to lowercase using portable method (compatible with Bash 3.x on macOS)
        response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
        case "$response_lower" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Linux"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "Windows"
    else
        echo "Unknown"
    fi
}

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

check_prerequisites() {
    log_step "Checking prerequisites and system requirements"
    echo
    
    local os=$(detect_os)
    log_info "Detected operating system: $os"
    echo
    
    log_info "This script will check for required tools and guide you through installation if needed."
    echo
    
    # Check kubectl
    check_tool "kubectl" "Kubernetes command-line tool for managing clusters"
    
    # Check helm
    check_tool "helm" "Kubernetes package manager for deploying applications"
    
    # Check curl
    check_tool "curl" "Command-line tool for downloading files and making HTTP requests"
    
    # Check git
    check_tool "git" "Version control system for downloading source code"
    
    # Check openssl
    check_tool "openssl" "Cryptographic toolkit for generating secure passwords and certificates"
    
    echo
    log_success "All prerequisites are installed!"
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
    
    # Generate secure admin password
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    log_success "Secure admin password generated: ${ADMIN_PASSWORD}"
    
    # Generate JWT secret
    JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    log_success "JWT secret generated ✓"
    
    # LLM Provider configuration
    echo
    log_info "🤖 LLM Provider Configuration"
    echo "AnythingLLM needs an AI language model to function. Choose your preferred option:"
    echo
    echo "1. OpenRouter (Recommended) - Access to multiple models, often cheaper than OpenAI"
    echo "2. OpenAI - Direct OpenAI API access"
    echo "3. Skip for now - Configure later in the web interface"
    echo
    
    local llm_choice
    while true; do
        llm_choice=$(ask_user "Choose your LLM provider [1-3]" "1")
        case "$llm_choice" in
            1|"openrouter")
                log_info "OpenRouter selected - Great choice for cost-effective AI!"
                echo
                echo "📝 To get your OpenRouter API key:"
                echo "  1. Visit: https://openrouter.ai/keys"
                echo "  2. Sign up/login (free account)"
                echo "  3. Create a new API key"
                echo "  4. Fund your account (as little as \$1 works)"
                echo
                echo "💡 OpenRouter offers free models too! Look for models marked 'Free'."
                echo
                OPENAI_API_KEY=$(ask_user "Enter your OpenRouter API key (or press Enter to skip)")
                OPENAI_API_BASE="https://openrouter.ai/api/v1"
                break
                ;;
            2|"openai")
                log_info "OpenAI selected - Premium option with excellent performance!"
                echo
                echo "📝 To get your OpenAI API key:"
                echo "  1. Visit: https://platform.openai.com/api-keys"
                echo "  2. Sign up/login"
                echo "  3. Create a new API key"
                echo "  4. Add billing information (required for API access)"
                echo
                OPENAI_API_KEY=$(ask_user "Enter your OpenAI API key (or press Enter to skip)")
                OPENAI_API_BASE="https://api.openai.com/v1"
                break
                ;;
            3|"skip")
                log_info "Skipping LLM configuration - you can set this up later in the web interface."
                OPENAI_API_KEY="placeholder-configure-in-ui"
                OPENAI_API_BASE="https://api.openai.com/v1"
                break
                ;;
            *)
                echo "Please choose 1, 2, or 3."
                ;;
        esac
    done
    
    # Configuration summary
    echo
    log_info "📋 Configuration Summary:"
    echo "  Full URL: https://$FULL_DOMAIN"
    echo "  Email: $EMAIL"
    echo "  Admin Password: $ADMIN_PASSWORD"
    echo "  LLM Provider: $([ "$OPENAI_API_BASE" == "https://openrouter.ai/api/v1" ] && echo "OpenRouter" || echo "OpenAI")"
    echo "  API Key: $([ -n "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "placeholder-configure-in-ui" ] && echo "✓ Provided" || echo "⚠ Will configure later")"
    echo
    
    if ! ask_yes_no "Continue with this configuration?" "y"; then
        log_info "Deployment cancelled."
        exit 0
    fi
}

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

check_and_install_cluster_prerequisites() {
    log_step "Checking and installing cluster prerequisites"
    echo
    
    log_info "AnythingLLM requires NGINX Ingress Controller and cert-manager for HTTPS."
    log_info "I'll check if these are installed and install them if needed."
    echo
    
    # Check for NGINX Ingress Controller
    if kubectl get namespace ingress-nginx &> /dev/null && kubectl get deployment ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        log_success "NGINX Ingress Controller is already installed ✓"
    else
        log_warning "NGINX Ingress Controller not found"
        if ask_yes_no "Install NGINX Ingress Controller now?" "y"; then
            log_info "Installing NGINX Ingress Controller..."
            helm upgrade --install ingress-nginx ingress-nginx \
                --repo https://kubernetes.github.io/ingress-nginx \
                --namespace ingress-nginx --create-namespace \
                --set controller.service.type=LoadBalancer \
                --wait --timeout=10m
            
            log_success "NGINX Ingress Controller installed ✓"
            
            # Wait for external IP
            log_info "Waiting for load balancer to get external IP..."
            local timeout=300  # 5 minutes
            local elapsed=0
            while [[ $elapsed -lt $timeout ]]; do
                local external_ip=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                if [[ -n "$external_ip" ]]; then
                    log_success "External IP assigned: $external_ip"
                    echo
                    log_warning "🌐 DNS SETUP REQUIRED NOW:"
                    echo "Create a DNS A record:"
                    echo "  Name: $SUBDOMAIN"
                    echo "  Type: A"
                    echo "  Value: $external_ip"
                    echo "  TTL: 300"
                    echo
                    if ! ask_yes_no "Have you created the DNS A record pointing $SUBDOMAIN.$DOMAIN_BASE to $external_ip?"; then
                        log_warning "Please create the DNS record before continuing."
                        log_info "The deployment will fail without proper DNS configuration."
                        exit 0
                    fi
                    break
                fi
                sleep 10
                elapsed=$((elapsed + 10))
                echo -n "."
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                log_error "Timeout waiting for external IP. Please check your cluster configuration."
                exit 1
            fi
        else
            log_error "NGINX Ingress Controller is required for AnythingLLM. Exiting."
            exit 1
        fi
    fi
    
    # Check for cert-manager
    if kubectl get namespace cert-manager &> /dev/null && kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
        log_success "cert-manager is already installed ✓"
    else
        log_warning "cert-manager not found"
        if ask_yes_no "Install cert-manager for automatic HTTPS certificates?" "y"; then
            log_info "Installing cert-manager..."
            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
            
            log_info "Waiting for cert-manager to be ready..."
            kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
            kubectl wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s
            kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s
            
            log_success "cert-manager installed ✓"
        else
            log_error "cert-manager is required for HTTPS certificates. Exiting."
            exit 1
        fi
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

deploy_anythingllm() {
    log_step "Deploying AnythingLLM"
    echo
    
    # Create namespace if it doesn't exist
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create or update secrets
    log_info "Creating Kubernetes secrets..."
    kubectl create secret generic anythingllm-secrets \
        --from-literal=ADMIN_EMAIL="$EMAIL" \
        --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        --from-literal=OPENAI_API_BASE="$OPENAI_API_BASE" \
        --from-literal=JWT_SECRET="$JWT_SECRET" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secrets created successfully"
    
    # Deploy with Helm using secure inline values (no temporary files)
    log_info "Deploying AnythingLLM with Helm..."
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
    
    if [ $? -eq 0 ]; then
        log_success "AnythingLLM deployed successfully!"
    else
        log_error "Deployment failed. Checking pod status..."
        kubectl get pods -n "$NAMESPACE"
        kubectl describe pods -n "$NAMESPACE" | tail -20
        return 1
    fi
    
    # Show deployment summary
    echo
    log_success "🎉 DEPLOYMENT SUMMARY"
    echo "  Namespace: $NAMESPACE"
    echo "  Release: $RELEASE_NAME"
    echo "  URL: https://$FULL_DOMAIN"
    echo "  Admin Email: $EMAIL"
    echo "  Admin Password: [Stored securely in Kubernetes secrets]"
    echo
    
    log_info "🔍 Checking deployment status..."
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    log_info "🌐 Testing ingress connectivity..."
    kubectl get ingress -n "$NAMESPACE"
    echo
    log_info "🔐 TLS Certificate Status:"
    local cert_status=$(kubectl get certificate -n "$NAMESPACE" -o jsonpath='{.items[0].status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    if [ "$cert_status" = "True" ]; then
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
    echo
    log_warning "🚨 CRITICAL SECURITY NOTICE 🚨"
    echo "${RED}Your AnythingLLM instance is currently PUBLIC and accessible to anyone!${NC}"
    echo
    echo "${YELLOW}IMMEDIATE ACTION REQUIRED:${NC}"
    echo "  1. Visit: https://$FULL_DOMAIN"
    echo "  2. Click Settings (⚙️) → Security"
    echo "  3. Enable 'Multi-User Mode' IMMEDIATELY"
    echo "  4. Create admin account with your credentials"
    echo "  5. Configure your preferred LLM provider in Settings"
    echo
    log_info "📋 Next steps:"
    echo "  1. SECURE YOUR INSTANCE (see above - CRITICAL!)"
    echo "  2. Wait for TLS certificate if not ready (2-5 minutes)"
    echo "  3. Test login with your admin credentials"
    echo "  4. Create workspaces and upload documents"
    echo
    
    # Secure credential display - only show if user confirms
    echo
    if ask_yes_no "Would you like to display the admin credentials now? (They are stored securely in Kubernetes secrets)"; then
        echo
        log_info " ADMIN CREDENTIALS:"
        log_info "🔐 ADMIN CREDENTIALS:"
        echo "  Email: $EMAIL"
        echo -n "  Password: "
        
        # Show masked password first
        local masked_password=$(echo "$ADMIN_PASSWORD" | sed 's/./*/g')
        echo "$masked_password"
        echo
        
        if ask_yes_no "Show actual password?"; then
            echo "  Actual Password: $ADMIN_PASSWORD"
            echo
            log_warning "⚠️  SAVE THESE CREDENTIALS SECURELY!"
            echo "  You'll need them to enable multi-user mode and secure your instance."
            echo
            # Offer to open browser for immediate security setup
            if ask_yes_no "Would you like to open your AnythingLLM instance now to complete security setup?"; then
                if command -v open >/dev/null 2>&1; then
                    open "https://$FULL_DOMAIN"
                    log_success "Opening https://$FULL_DOMAIN in your browser..."
                elif command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "https://$FULL_DOMAIN"
                    log_success "Opening https://$FULL_DOMAIN in your browser..."
                else
                    log_info "Please manually open: https://$FULL_DOMAIN"
                fi
                echo
                log_info "🔒 Security Setup Steps:"
                echo "  1. Click Settings (⚙️) in the bottom left"
                echo "  2. Navigate to 'Security' in the sidebar"
                echo "  3. Enable 'Multi-User Mode' (CRITICAL!)"
                echo "  4. Create admin account with your credentials above"
                echo "  5. Go to Settings → LLM Preference to configure your preferred AI provider"
            fi
        else
            echo "  💡 To retrieve password later:"
            echo "    kubectl get secret anythingllm-secrets -n $NAMESPACE -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d"
        fi
    else
        echo
        log_info "📋 To retrieve admin credentials later:"
        echo "  Email: kubectl get secret anythingllm-secrets -n $NAMESPACE -o jsonpath='{.data.ADMIN_EMAIL}' | base64 -d"
        echo "  Password: kubectl get secret anythingllm-secrets -n $NAMESPACE -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d"
    fi
    echo
    
    # Integrated Security Setup
    setup_security_interactive
    
    # Wait for deployment to be ready
    log_info "🚀 Monitoring deployment..."
    echo "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=anythingllm -n "$NAMESPACE" --timeout=300s
    
    if [ $? -eq 0 ]; then
        log_success "✅ AnythingLLM is ready and running!"
    else
        log_error "❌ Deployment failed or timed out. Check pod status:"
        kubectl get pods -n "$NAMESPACE"
        return 1
    fi
}

# Function to generate secure random string
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to validate email
validate_email() {
    if [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN        Domain for AnythingLLM (e.g., ai.yourdomain.xyz)"
    echo "  -e, --email EMAIL          Admin email address"
    echo "  -p, --password PASSWORD    Admin password (will be generated if not provided)"
    echo "  -k, --api-key KEY          OpenAI API key"
    echo "  -b, --api-base URL         OpenAI API base URL (default: https://api.openai.com/v1)"
    echo "  -n, --namespace NAMESPACE  Kubernetes namespace (default: anything-llm)"
    echo "  -r, --release RELEASE      Helm release name (default: anythingllm)"
    echo "  -f, --values-file FILE     Custom values file (default: values.yaml)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -d ai.romandid.xyz -e admin@romandid.xyz -k sk-your-openai-key"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -p|--password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        -k|--api-key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        -b|--api-base)
            OPENAI_API_BASE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        -h|--help)
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
if [[ $# -eq 0 ]]; then
    main
else
    # Handle command line arguments for advanced users
    log_error "Command line arguments are not yet supported. Please run without arguments for interactive deployment."
    echo
    log_info "For interactive deployment, simply run:"
    echo "  ./deploy.sh"
    echo
    exit 1
fi
