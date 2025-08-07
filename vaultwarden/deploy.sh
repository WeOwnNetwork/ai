#!/bin/bash

# WeOwn Vaultwarden Enterprise Deployment Script
# Fully interactive, transparent, and user-friendly for technical and non-technical users
# Works on macOS, Linux, and Windows (via Git Bash/WSL)

set -euo pipefail

# Version and metadata
SCRIPT_VERSION="1.0.0"
REQUIRED_TOOLS=("kubectl" "helm" "docker" "curl" "git")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="vaultwarden"
RELEASE_NAME="vaultwarden"
CHART_PATH="./helm"
REPO_URL="https://github.com/WeOwnNetwork/ai.git"
VAULTWARDEN_DIR="vaultwarden"

# Functions
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    WeOwn Vaultwarden                         ║"
    echo "║              Enterprise Password Manager                     ║"
    echo "║                                                              ║"
    echo "║    🔐 Self-hosted • 🛡️  Enterprise Security • 🚀 Automated    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}Version: ${SCRIPT_VERSION}${NC}"
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
        echo -e "${CYAN}❓ ${question} [${default}]:${NC}" >&2
    else
        echo -e "${CYAN}❓ ${question}:${NC}" >&2
    fi
    
    read -r response
    echo "${response:-$default}"
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -e "${CYAN}❓ ${question} (Y/n):${NC}" >&2
        else
            echo -e "${CYAN}❓ ${question} (y/N):${NC}" >&2
        fi
        
        read -r response
        response="${response:-$default}"
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo -e "${YELLOW}Please answer yes (y) or no (n)${NC}" ;;
        esac
    done
}

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
        "docker")
            case "$os" in
                "macOS") echo "Install Docker Desktop: https://docs.docker.com/desktop/mac/install/" ;;
                "Linux") echo "sudo apt-get install docker.io (Ubuntu) or visit https://docs.docker.com/engine/install/" ;;
                "Windows") echo "Install Docker Desktop: https://docs.docker.com/desktop/windows/install/" ;;
                *) echo "Visit: https://docs.docker.com/get-docker/" ;;
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

check_tool() {
    local tool="$1"
    local description="$2"
    local install_instructions="$3"
    
    if command -v "$tool" &> /dev/null; then
        log_success "$tool is installed ✓"
        return 0
    else
        log_warning "$tool is not installed"
        echo -e "${YELLOW}What is $tool?${NC} $description"
        echo
        
        if ask_yes_no "Would you like to install $tool now? This is required for deployment"; then
            echo -e "${BLUE}Installation instructions for $tool:${NC}"
            echo "$install_instructions"
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
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        provide_install_instructions "kubectl" "$os"
        exit 1
    fi
    log_success "kubectl is installed ✓"
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        provide_install_instructions "helm" "$os"
        exit 1
    fi
    log_success "helm is installed ✓"
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        provide_install_instructions "curl" "$os"
        exit 1
    fi
    log_success "curl is installed ✓"
    
    # Check git
    if ! command -v git &> /dev/null; then
        log_error "git is not installed"
        provide_install_instructions "git" "$os"
        exit 1
    fi
    log_success "git is installed ✓"
    
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
            log_info "You'll need a Kubernetes cluster to deploy Vaultwarden."
            log_info "DigitalOcean Kubernetes is recommended for this deployment."
            exit 1
        fi
    fi
}

get_user_configuration() {
    log_step "Gathering your deployment configuration"
    echo
    
    log_info "I'll ask you a few questions to customize your Vaultwarden deployment."
    echo
    
    # Get subdomain
    SUBDOMAIN=$(ask_user "Enter your desired subdomain (e.g., 'vault')" "vault")
    
    # Get domain
    DOMAIN=$(ask_user "Enter your domain name (e.g., 'example.com')")
    
    # Get email for Let's Encrypt
    EMAIL=$(ask_user "Enter your email address for SSL certificates")
    
    # Generate admin password
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    log_success "Secure admin password generated: ${ADMIN_PASSWORD}"
    
    # Configuration summary
    echo
    log_info "Configuration Summary:"
    echo "  Full URL: https://$SUBDOMAIN.$DOMAIN"
    echo "  Email: $EMAIL"
    echo "  Admin Password: $ADMIN_PASSWORD"
    echo
    
    if ! ask_yes_no "Continue with this configuration?" "y"; then
        log_info "Deployment cancelled."
        exit 0
    fi
}

setup_dns_instructions() {
    log_step "DNS Configuration Required"
    echo
    
    # Get ingress controller external IP
    local external_ip=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -z "$external_ip" ]]; then
        log_error "Could not get external IP from ingress controller"
        exit 1
    fi
    
    log_success "External IP: $external_ip"
    echo
    log_warning "Create DNS A record:"
    echo "  Name: $SUBDOMAIN"
    echo "  Type: A"
    echo "  Value: $external_ip"
    echo "  TTL: 300"
    echo
    
    if ! ask_yes_no "Have you created the DNS A record?"; then
        log_warning "Please create the DNS record and run this script again."
        exit 0
    fi
}

install_prerequisites() {
    log_step "Installing cluster prerequisites"
    echo
    
    # Install NGINX Ingress Controller if needed
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_info "Installing NGINX Ingress Controller..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/do/deploy.yaml
        kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
        log_success "NGINX Ingress Controller installed"
    fi
    
    # Install cert-manager if needed
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_info "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
        kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s
        log_success "cert-manager installed"
    fi
}

deploy_vaultwarden() {
    log_step "Deploying Vaultwarden"
    echo
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create admin secret (Vaultwarden will hash this internally)
    local admin_token_hash="$ADMIN_PASSWORD"
    kubectl create secret generic vaultwarden-admin \
        --from-literal=token="$admin_token_hash" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Ensure ClusterIssuer exists (create if needed)
    if ! kubectl get clusterissuer letsencrypt-prod &> /dev/null; then
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
    else
        log_info "ClusterIssuer already exists, skipping creation"
    fi
    
    # Deploy with Helm
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace="$NAMESPACE" \
        --set global.subdomain="$SUBDOMAIN" \
        --set global.domain="$DOMAIN"
    
    # Wait for deployment to be ready (with timeout)
    log_info "Waiting for Vaultwarden deployment to be ready..."
    kubectl wait --for=condition=available deployment/vaultwarden \
        --namespace="$NAMESPACE" \
        --timeout=300s
    
    log_success "Vaultwarden deployed successfully! 🎉"
    echo
    log_info "Access your vault at: https://$SUBDOMAIN.$DOMAIN"
    log_info "Admin panel: https://$SUBDOMAIN.$DOMAIN/admin"
    log_info "Admin password: $ADMIN_PASSWORD"
}

# Main execution function
main() {
    print_banner
    check_prerequisites
    check_cluster_connection
    get_user_configuration
    setup_dns_instructions
    install_prerequisites
    deploy_vaultwarden
}

# Run main function
main "$@"
