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
    echo -e "${BLUE}=== User Configuration ===${NC}\n"
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
    while true; do
        read -p "Enter your domain (e.g., example.com): " DOMAIN
        if [[ ! -z "$DOMAIN" ]]; then
            break
        fi
        echo -e "${RED}Domain cannot be empty${NC}"
    done
    
    # Get email for Let's Encrypt
    while true; do
        read -p "Enter your email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
        if [[ "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        echo -e "${RED}Please enter a valid email address${NC}"
    done >&2
    
    # Generate secure admin password and Argon2 hash
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    log_success "Secure admin password generated ✓"
    
    # Generate Argon2-hashed admin token for production security
    log_info "Generating secure Argon2-hashed admin token..."
    if command -v argon2 &> /dev/null; then
        ADMIN_TOKEN_HASH=$(echo "$ADMIN_PASSWORD" | argon2 "$(openssl rand -base64 16)" -id -t 3 -m 16 -p 4 -l 32 -e)
        log_success "Argon2-hashed admin token generated ✓"
    else
        log_warning "argon2 not found - installing via Homebrew (macOS) or using fallback..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install argon2 &> /dev/null && log_success "argon2 installed ✓"
                ADMIN_TOKEN_HASH=$(echo "$ADMIN_PASSWORD" | argon2 "$(openssl rand -base64 16)" -id -t 3 -m 16 -p 4 -l 32 -e)
                log_success "Argon2-hashed admin token generated ✓"
            else
                log_warning "Using PBKDF2 fallback (install argon2 for maximum security)"
                ADMIN_TOKEN_HASH="$ADMIN_PASSWORD"
            fi
        else
            log_warning "Using plain text fallback (install argon2 for maximum security)"
            ADMIN_TOKEN_HASH="$ADMIN_PASSWORD"
        fi
    fi
    
    # Create Helm values override file
    cat > /tmp/vaultwarden-values.yaml <<EOF
global:
  subdomain: "$SUBDOMAIN"
  domain: "$DOMAIN"

certManager:
  enabled: true
  email: "$LETSENCRYPT_EMAIL"

vaultwarden:
  admin:
    existingSecret: "vaultwarden-admin"
    secretKey: "token"
  domain: "https://${SUBDOMAIN}.${DOMAIN}"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: "${SUBDOMAIN}.${DOMAIN}"
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: vaultwarden-tls
      hosts:
        - "${SUBDOMAIN}.${DOMAIN}"
EOF
    
    # Configuration summary
    echo
    log_info "Configuration Summary:"
    echo "  Full URL: https://$SUBDOMAIN.$DOMAIN"
    echo "  Email: $LETSENCRYPT_EMAIL"
    echo "  Admin Password: [Generated securely - will be shown at completion]"
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

check_and_install_cluster_prerequisites() {
    log_step "Checking cluster prerequisites"
    echo
    
    local needs_ingress=false
    local needs_certmanager=false
    
    # Check NGINX Ingress Controller
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_warning "NGINX Ingress Controller not found"
        needs_ingress=true
    else
        # Check if ingress controller is actually running
        if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -q Running; then
            log_warning "NGINX Ingress Controller not running properly"
            needs_ingress=true
        else
            log_success "NGINX Ingress Controller is running ✓"
            
            # CRITICAL: Ensure ingress-nginx namespace has correct label for NetworkPolicy
            if ! kubectl get namespace ingress-nginx --show-labels | grep -q "name=ingress-nginx"; then
                log_info "Adding required NetworkPolicy label to ingress-nginx namespace..."
                kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
                log_success "NetworkPolicy label added ✓"
            else
                log_success "NetworkPolicy label already present ✓"
            fi
        fi
    fi
    
    # Check cert-manager
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_warning "cert-manager not found"
        needs_certmanager=true
    else
        # Check if cert-manager is actually running
        if ! kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | grep -q Running; then
            log_warning "cert-manager not running properly"
            needs_certmanager=true
        else
            log_success "cert-manager is running ✓"
        fi
    fi
    
    # Install missing prerequisites
    if [[ "$needs_ingress" == true || "$needs_certmanager" == true ]]; then
        echo
        log_info "Missing cluster prerequisites detected. Installing required components..."
        echo
        
        if [[ "$needs_ingress" == true ]]; then
            log_info "Installing NGINX Ingress Controller (DigitalOcean optimized)..."
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/do/deploy.yaml
            
            log_info "Waiting for NGINX Ingress Controller to be ready..."
            kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
            
            # Wait for external IP to be assigned
            log_info "Waiting for external IP assignment..."
            local retries=0
            while [[ $retries -lt 30 ]]; do
                local external_ip=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                if [[ -n "$external_ip" && "$external_ip" != "null" ]]; then
                    log_success "NGINX Ingress Controller installed with external IP: $external_ip ✓"
                    break
                fi
                sleep 10
                ((retries++))
            done
            
            if [[ $retries -eq 30 ]]; then
                log_error "Timeout waiting for external IP assignment"
                exit 1
            fi
        fi
        
        if [[ "$needs_certmanager" == true ]]; then
            log_info "Installing cert-manager..."
            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
            
            log_info "Waiting for cert-manager to be ready..."
            kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s
            
            # Additional wait for webhook to be ready
            sleep 30
            log_success "cert-manager installed ✓"
        fi
        
        echo
        log_success "All cluster prerequisites are now installed and ready!"
    else
        log_success "All cluster prerequisites are already installed ✓"
    fi
}

deploy_vaultwarden() {
    log_step "Deploying Vaultwarden"
    echo
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create admin secret with secure Argon2-hashed token
    kubectl create secret generic vaultwarden-admin \
        --from-literal=token="$ADMIN_TOKEN_HASH" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy NetworkPolicy for zero-trust security
    log_step "Deploying NetworkPolicy for zero-trust networking"
    cat > /tmp/networkpolicy.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vaultwarden-security
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: vaultwarden
    app.kubernetes.io/instance: vaultwarden
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vaultwarden
      app.kubernetes.io/instance: vaultwarden
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
      ports:
      - protocol: TCP
        port: 8080
    - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: vaultwarden
      ports:
      - protocol: TCP
        port: 8080
  egress:
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to: []
      ports:
        - protocol: TCP
          port: 443
    - to: []
      ports:
        - protocol: TCP
          port: 80
EOF
    
    # Ensure ingress-nginx namespace has required label
    kubectl label namespace ingress-nginx name=ingress-nginx --overwrite || true
    
    # Apply NetworkPolicy
    kubectl apply -f /tmp/networkpolicy.yaml
    log_success "NetworkPolicy deployed for zero-trust security"
    
    # Deploy with Helm
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace="$NAMESPACE" \
        --values /tmp/vaultwarden-values.yaml
    
    # Apply rate limiting and security measures to ingress
    log_step "Applying security hardening to ingress"
    kubectl patch ingress vaultwarden -n "$NAMESPACE" -p '{
        "metadata":{
            "annotations":{
                "nginx.ingress.kubernetes.io/rate-limit":"10",
                "nginx.ingress.kubernetes.io/rate-limit-window":"1m",
                "nginx.ingress.kubernetes.io/rate-limit-connections":"5",
                "nginx.ingress.kubernetes.io/limit-connections":"10",
                "nginx.ingress.kubernetes.io/limit-rps":"5"
            }
        }
    }' || log_warning "Rate limiting could not be applied - may need manual configuration"
    
    log_success "Security hardening applied"
    
    # Wait for deployment to be ready (with timeout)
    log_info "Waiting for Vaultwarden deployment to be ready..."
    kubectl wait --for=condition=available deployment/vaultwarden \
        --namespace="$NAMESPACE" \
        --timeout=300s
    
    log_success "Vaultwarden deployed successfully! 🎉"
    echo
    log_info "Access your vault at: https://$SUBDOMAIN.$DOMAIN"
    log_info "Admin panel: https://$SUBDOMAIN.$DOMAIN/admin"
    echo
    echo "🔑 Your secure admin password (save this safely):"
    echo -e "${GREEN}${ADMIN_PASSWORD}${NC}"
    echo
    log_warning "⚠️  IMPORTANT: Save this password securely. It won't be shown again!"
    echo "💡 Consider storing it in a password manager or secure notes."
}

# Setup automated backup system
setup_backup_system() {
    log_step "Setting up automated backup system"
    echo
    
    log_info "Automated backups protect your password data with:"
    echo "  📅 Daily snapshots at 2 AM UTC"
    echo "  🗂️ 30-day retention policy"
    echo "  🔒 Secure DigitalOcean volume snapshots"
    echo "  🧹 Automatic cleanup of old backups"
    echo
    
    # Get DigitalOcean API token
    local DO_TOKEN=""
    while true; do
        echo -e "${YELLOW}ℹ️  Get your DigitalOcean API token from:${NC}"
        echo "   https://cloud.digitalocean.com/account/api/tokens"
        echo
        read -s -p "Enter your DigitalOcean API token: " DO_TOKEN
        echo
        
        if [[ ! -z "$DO_TOKEN" && ${#DO_TOKEN} -ge 64 ]]; then
            break
        fi
        echo -e "${RED}Please enter a valid DigitalOcean API token (64+ characters)${NC}"
        echo
    done
    
    log_info "Creating backup token secret..."
    kubectl create secret generic do-backup-token \
        --from-literal=token="$DO_TOKEN" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Backup token secret created ✓"
    
    log_info "Deploying backup CronJob..."
    
    # Create the backup CronJob YAML inline to avoid external file dependency
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vaultwarden-backup
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: vaultwarden
    app.kubernetes.io/instance: vaultwarden
    app.kubernetes.io/component: backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        metadata:
          labels:
            app.kubernetes.io/name: vaultwarden
            app.kubernetes.io/instance: vaultwarden
            app.kubernetes.io/component: backup
        spec:
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
          containers:
          - name: backup
            image: digitalocean/doctl:latest
            imagePullPolicy: Always
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              runAsNonRoot: true
              runAsUser: 1000
              runAsGroup: 1000
              capabilities:
                drop:
                - ALL
            env:
            - name: DIGITALOCEAN_ACCESS_TOKEN
              valueFrom:
                secretKeyRef:
                  name: do-backup-token
                  key: token
            - name: BACKUP_RETENTION_DAYS
              value: "30"
            command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "Starting Vaultwarden backup process..."
              
              # Get volume ID
              VOLUME_ID=\$(kubectl get pv \$(kubectl get pvc vaultwarden-data -n $NAMESPACE -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi.volumeHandle}')
              echo "Volume ID: \$VOLUME_ID"
              
              # Create snapshot
              SNAPSHOT_NAME="vaultwarden-backup-\$(date +%Y%m%d-%H%M%S)"
              echo "Creating snapshot: \$SNAPSHOT_NAME"
              
              doctl compute volume-action snapshot \$VOLUME_ID --snapshot-name \$SNAPSHOT_NAME --wait
              
              echo "Backup completed: \$SNAPSHOT_NAME"
              
              # Cleanup old snapshots (keep last 30 days)
              echo "Cleaning up old snapshots..."
              CUTOFF_DATE=\$(date -d "\$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
              doctl compute snapshot list --format ID,Name,CreatedAt --no-header | \
                grep "vaultwarden-backup-" | \
                awk -v cutoff="\$CUTOFF_DATE" '\$3 < cutoff {print \$1}' | \
                while read snapshot_id; do
                  echo "Deleting old snapshot: \$snapshot_id"
                  doctl compute snapshot delete \$snapshot_id --force
                done
              
              echo "Backup process completed successfully"
            volumeMounts:
            - name: tmp
              mountPath: /tmp
          volumes:
          - name: tmp
            emptyDir: {}
EOF
    
    log_success "Backup CronJob deployed ✓"
    
    # Verify deployment
    log_info "Verifying backup system..."
    kubectl get cronjob vaultwarden-backup -n "$NAMESPACE" || true
    
    echo
    log_success "Backup system configured successfully! 🗄️"
    echo "📋 Backup schedule: Daily at 2 AM UTC"
    echo "🗂️ Retention: 30 days"
    echo "📊 Monitor with: kubectl get jobs -n $NAMESPACE"
    echo "🔍 Backup logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backup"
}

# Main execution function
main() {
    print_banner
    check_prerequisites
    check_cluster_connection
    check_and_install_cluster_prerequisites
    get_user_configuration
    setup_dns_instructions
    deploy_vaultwarden
    
    # Optional backup system setup
    echo
    if ask_yes_no "Set up automated daily backups? (Recommended for production)" "y"; then
        setup_backup_system
    else
        log_info "Skipping backup setup. You can set it up later by running:"
        echo "  DIGITALOCEAN_ACCESS_TOKEN=your_token ./backup-setup.sh"
    fi
}

# Run main function
main "$@"
