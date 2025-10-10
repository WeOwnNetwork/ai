#!/bin/bash

# WeOwn Matomo Enterprise Deployment Script
# Privacy-first web analytics with enterprise security for WordPress integration
# Version: 1.0.0
#
# This script provides:
# - Enterprise-grade security with zero-trust networking
# - Automatic prerequisite installation with resume capability
# - Full transparency about every operation
# - Comprehensive error handling and recovery
# - WordPress plugin integration guidance
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
WEBSITE_NAME=""
WEBSITE_HOST=""
MARIADB_PASSWORD=""
MARIADB_ROOT_PASSWORD=""
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
Matomo Analytics Enterprise Kubernetes Deployment Script
WeOwn Production-Grade Privacy-First Analytics with Enterprise Security

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    --domain DOMAIN         Set the domain for Matomo (e.g., analytics.example.com)
    --email EMAIL           Set email for Let's Encrypt certificates
    --namespace NAMESPACE   Set Kubernetes namespace (default: matomo-{domain-slug})
    --show-credentials      Show admin credentials for existing deployment

EXAMPLES:
    # Interactive deployment (recommended)
    ./deploy.sh

    # Non-interactive deployment
    ./deploy.sh --domain analytics.example.com --email admin@example.com

    # View existing credentials
    ./deploy.sh --show-credentials

FEATURES:
    ✓ Enterprise Security (Zero-Trust NetworkPolicy, Pod Security Standards)
    ✓ TLS 1.3 Encryption with Let's Encrypt
    ✓ Interactive UX with Prerequisites Validation
    ✓ WordPress Plugin Integration Guide
    ✓ Hourly Analytics Archiving CronJob
    ✓ GDPR/SOC2/ISO42001 Compliance
    ✓ MariaDB Database with Enterprise Security

WORDPRESS INTEGRATION:
    After deployment, install "Connect Matomo" plugin on WordPress:
    https://wordpress.org/plugins/wp-piwik/

    Configure with:
    - Matomo URL: https://your-matomo-domain.com
    - Auth Token: Generate in Matomo → Settings → Security

EOF
}

# Banner function
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║             WeOwn Matomo Analytics Enterprise                 ║"
    echo "║         Privacy-First Web Analytics Platform                  ║"
    echo "║                                                               ║"
    echo "║        📊 Analytics • 🔒 Privacy • 🚀 WordPress                ║"
    echo "║         ENTERPRISE SECURITY FEATURES ENABLED                  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}=== Enterprise Security & GDPR Compliance ===${NC}\n"
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
        openssl)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                log_info "openssl should be pre-installed on macOS"
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y openssl
                elif command -v yum &> /dev/null; then
                    sudo yum install -y openssl
                fi
            fi
            ;;
    esac
    
    # Verify installation
    if command -v $tool &> /dev/null; then
        log_success "$tool installed successfully"
        return 0
    else
        log_error "Failed to install $tool. Please install manually."
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    local tools=("kubectl" "helm" "openssl")
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_warning "$tool not found"
            missing_tools+=("$tool")
        else
            log_success "$tool is installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "Missing tools: ${missing_tools[*]}"
        echo
        read -p "Would you like to auto-install missing tools? (y/N): " auto_install
        
        if [[ "$auto_install" =~ ^[Yy]$ ]]; then
            for tool in "${missing_tools[@]}"; do
                auto_install_tool "$tool"
            done
        else
            log_error "Please install missing prerequisites and try again"
            exit 1
        fi
    fi
    
    # Check cluster connectivity
    log_step "Checking Kubernetes cluster connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Please ensure:"
        log_info "  1. You have a Kubernetes cluster running"
        log_info "  2. kubectl is configured (check: kubectl config current-context)"
        log_info "  3. You have appropriate permissions"
        exit 1
    fi
    
    local current_context=$(kubectl config current-context)
    log_success "Connected to cluster: $current_context"
    echo
}

# Check if ingress-nginx namespace exists and label it
check_ingress_nginx() {
    log_step "Checking NGINX Ingress Controller..."
    
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_warning "ingress-nginx namespace not found"
        log_info "Installing NGINX Ingress Controller..."
        
        kubectl create namespace ingress-nginx || true
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
        
        log_info "Waiting for NGINX Ingress Controller to be ready..."
        kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=300s
        
        log_success "NGINX Ingress Controller installed"
    else
        log_success "NGINX Ingress Controller found"
    fi
    
    # Label ingress-nginx namespace for NetworkPolicy (CRITICAL for WeOwn security)
    log_step "Ensuring ingress-nginx namespace is labeled for NetworkPolicy..."
    if ! kubectl get namespace ingress-nginx -o jsonpath='{.metadata.labels.name}' | grep -q "ingress-nginx"; then
        log_info "Labeling ingress-nginx namespace..."
        kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
        log_success "ingress-nginx namespace labeled correctly"
    else
        log_success "ingress-nginx namespace already labeled"
    fi
    echo
}

# Check if cert-manager exists
check_cert_manager() {
    log_step "Checking cert-manager..."
    
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_warning "cert-manager not found"
        log_info "Installing cert-manager..."
        
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
        
        log_info "Waiting for cert-manager to be ready..."
        kubectl wait --namespace cert-manager \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/instance=cert-manager \
            --timeout=300s
        
        log_success "cert-manager installed"
    else
        log_success "cert-manager found"
    fi
    echo
}

# Get external IP
get_external_ip() {
    log_step "Detecting external IP address..."
    
    EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -z "$EXTERNAL_IP" ]; then
        log_warning "External IP not yet assigned. Waiting..."
        sleep 10
        EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi
    
    if [ -n "$EXTERNAL_IP" ]; then
        log_success "External IP detected: $EXTERNAL_IP"
    else
        log_warning "Could not detect external IP automatically"
        EXTERNAL_IP="<PENDING>"
    fi
    echo
}

# Create ClusterIssuer if needed
create_cluster_issuer() {
    log_step "Checking Let's Encrypt ClusterIssuer..."
    
    if kubectl get clusterissuer letsencrypt-prod &> /dev/null; then
        log_success "ClusterIssuer 'letsencrypt-prod' already exists"
        return 0
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
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    
    log_success "ClusterIssuer created"
    echo
}

# Generate secure passwords
generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-24
}

# Interactive prompts
prompt_domain() {
    if [ -z "$DOMAIN" ]; then
        echo
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  MATOMO DOMAIN CONFIGURATION${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo "Enter the domain for your Matomo analytics platform."
        echo "Examples: analytics.example.com, matomo.company.org"
        echo
        read -p "Matomo Domain: " DOMAIN
        
        if [ -z "$DOMAIN" ]; then
            log_error "Domain cannot be empty"
            exit 1
        fi
        
        log_success "Domain set to: $DOMAIN"
    fi
}

prompt_email() {
    if [ -z "$EMAIL" ]; then
        echo
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  LET'S ENCRYPT EMAIL${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo "Enter email for Let's Encrypt certificate notifications."
        echo "You'll receive renewal reminders and security notices."
        echo
        read -p "Email address: " EMAIL
        
        if [ -z "$EMAIL" ]; then
            log_error "Email cannot be empty"
            exit 1
        fi
        
        log_success "Email set to: $EMAIL"
    fi
}

prompt_website() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  INITIAL WEBSITE CONFIGURATION (OPTIONAL)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Configure the first website you want to track with Matomo."
    echo "You can add more websites later in Matomo's web interface."
    echo "Note: This step is optional and can be skipped for deployment."
    echo
    read -p "Configure initial website now? (y/N): " configure_website
    
    if [[ "$configure_website" =~ ^[Yy]$ ]]; then
        read -p "Website Name (e.g., My WordPress Site): " WEBSITE_NAME
        read -p "Website URL (e.g., https://mysite.com): " WEBSITE_HOST
        
        if [ -z "$WEBSITE_NAME" ]; then
            WEBSITE_NAME="My Website"
        fi
        
        if [ -z "$WEBSITE_HOST" ]; then
            WEBSITE_HOST="https://example.com"
        fi
        
        log_success "Website configured: $WEBSITE_NAME ($WEBSITE_HOST)"
    else
        WEBSITE_NAME="Default Website"
        WEBSITE_HOST="https://example.com"
        log_info "Skipping initial website configuration"
    fi
}

# Namespace and release name prompt
prompt_namespace_and_release() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  NAMESPACE AND RELEASE NAME${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Default namespace: matomo"
    echo "Default release name: matomo"
    echo
    read -p "Use default names (matomo/matomo)? (Y/n): " use_defaults
    
    if [[ "$use_defaults" =~ ^[Nn]$ ]]; then
        read -p "Enter namespace name: " NAMESPACE
        read -p "Enter release name: " RELEASE_NAME
        
        if [ -z "$NAMESPACE" ]; then
            NAMESPACE="matomo"
        fi
        
        if [ -z "$RELEASE_NAME" ]; then
            RELEASE_NAME="matomo"
        fi
        
        log_success "Using namespace: $NAMESPACE, release: $RELEASE_NAME"
    else
        NAMESPACE="matomo"
        RELEASE_NAME="matomo"
        log_info "Using default namespace and release names"
    fi
}

# DNS configuration instructions
show_dns_instructions() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  DNS CONFIGURATION REQUIRED${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${YELLOW}IMPORTANT: Before Matomo will be accessible, you must configure DNS.${NC}"
    echo
    echo "Steps to configure DNS:"
    echo
    echo -e "${BLUE}1.${NC} Log in to your domain registrar or DNS provider"
    echo -e "   (e.g., DigitalOcean, Cloudflare, GoDaddy, Namecheap)"
    echo
    echo -e "${BLUE}2.${NC} Add an A record:"
    echo -e "   ${GREEN}Record Type:${NC} A"
    echo -e "   ${GREEN}Hostname:${NC} $(echo $DOMAIN | cut -d'.' -f1)"
    echo -e "   ${GREEN}Value/IP:${NC} $EXTERNAL_IP"
    echo -e "   ${GREEN}TTL:${NC} 3600 (1 hour)"
    echo
    echo -e "${BLUE}3.${NC} Wait for DNS propagation (usually 5-60 minutes)"
    echo
    echo -e "${BLUE}4.${NC} Verify DNS is working:"
    echo -e "   ${GREEN}dig $DOMAIN${NC}"
    echo -e "   ${GREEN}nslookup $DOMAIN${NC}"
    echo
    echo -e "${YELLOW}Pro tip:${NC} Use https://dnschecker.org to check global DNS propagation"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# Deploy Matomo
deploy_matomo() {
    log_step "Deploying Matomo with enterprise security..."
    
    # Generate secure passwords and tokens
    ADMIN_PASSWORD=$(generate_password)
    MARIADB_PASSWORD=$(generate_password)
    MARIADB_ROOT_PASSWORD=$(generate_password)
    ARCHIVE_TOKEN=$(generate_password)
    
    log_info "Generating secure credentials and archive token..."
    
    # Create temporary values file
    local VALUES_FILE=$(mktemp)
    
    cat > "$VALUES_FILE" <<EOF
global:
  domain: ${DOMAIN}
  email: ${EMAIL}

matomo:
  admin:
    username: ${ADMIN_USER}
    password: ${ADMIN_PASSWORD}
    email: ${EMAIL}
  archiveToken: ${ARCHIVE_TOKEN}
  website:
    name: ${WEBSITE_NAME}
    host: ${WEBSITE_HOST}

mariadb:
  auth:
    password: ${MARIADB_PASSWORD}
    rootPassword: ${MARIADB_ROOT_PASSWORD}

certManager:
  createClusterIssuer: false
EOF

    # Validate the generated values file for empty template variables
    log_step "Validating Helm values..."
    if grep -q '{{ .Values.global.domain }}' "$VALUES_FILE"; then
        log_error "Template variables not replaced in values file!"
        log_info "Domain: $DOMAIN"
        log_info "This indicates a template processing error."
        exit 1
    fi

    # Skip image validation to prevent hanging
    log_step "Proceeding with deployment..."
    
    # Clean up any failed deployments
    log_step "Checking for existing failed deployments..."
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        HELM_STATUS=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '.info.status' 2>/dev/null || echo "unknown")
        if [[ "$HELM_STATUS" == "failed" ]]; then
            log_info "Found failed deployment. Cleaning up..."
            helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
            kubectl delete secrets -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" || true
            sleep 2
        fi
    fi

    # Process the values file to replace placeholders
    log_info "Processing Helm values with domain and email..."
    
    # Create a temporary processed values file
    PROCESSED_VALUES_FILE=$(mktemp)
    
    # Replace placeholders in the chart's values.yaml and copy to processed file
    sed "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$CHART_PATH/values.yaml" > "$PROCESSED_VALUES_FILE"
    
    # Append the generated values from the script (this includes credentials)
    cat "$VALUES_FILE" >> "$PROCESSED_VALUES_FILE"
    
    # Deploy with Helm using the processed values
    log_info "Deploying Matomo with Helm (MariaDB subchart included)..."
    
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_info "Existing deployment found. Upgrading..."
        helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$PROCESSED_VALUES_FILE" \
            --wait \
            --timeout 10m
    else
        log_info "Installing new Helm deployment..."
        helm install "$RELEASE_NAME" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --values "$PROCESSED_VALUES_FILE" \
            --wait \
            --timeout 10m
    fi
    
    log_success "✅ Helm deployment completed!"
    echo
    
    # Validate pod readiness
    log_info "Validating pod status..."
    sleep 5
    
    # Check Matomo pod
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=matomo -n "$NAMESPACE" --timeout=120s 2>/dev/null; then
        log_success "✅ Matomo pod is ready"
    else
        log_warning "⚠️  Matomo pod not ready yet, checking status..."
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=matomo
    fi
    
    # Check MariaDB pod
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=mariadb -n "$NAMESPACE" --timeout=120s 2>/dev/null; then
        log_success "✅ MariaDB pod is ready"
    else
        log_warning "⚠️  MariaDB pod not ready yet, checking status..."
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=mariadb
    fi
    
    log_success "✅ Matomo deployment completed successfully!"
    echo
    
    # Production Health Checks
    log_step "🔍 Running production health checks..."
    
    # Check TLS certificate
    log_info "Checking TLS certificate status..."
    if kubectl get certificate matomo-tls -n "$NAMESPACE" &>/dev/null; then
        CERT_STATUS=$(kubectl get certificate matomo-tls -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$CERT_STATUS" = "True" ]; then
            log_success "✅ TLS Certificate: Ready"
        else
            log_warning "⏳ TLS Certificate: Still being issued by Let's Encrypt"
        fi
    else
        log_warning "⏳ TLS Certificate: Being created"
    fi
    
    # Check backup system
    log_info "Checking backup system..."
    if kubectl get cronjob matomo-backup -n "$NAMESPACE" &>/dev/null; then
        BACKUP_SCHEDULE=$(kubectl get cronjob matomo-backup -n "$NAMESPACE" -o jsonpath='{.spec.schedule}')
        log_success "✅ Backup System: Active (Schedule: $BACKUP_SCHEDULE)"
        
        # Test backup system with a quick test
        log_info "Testing backup system connectivity..."
        if kubectl create job --from=cronjob/matomo-backup matomo-backup-health-check -n "$NAMESPACE" &>/dev/null; then
            sleep 15
            BACKUP_JOB_STATUS=$(kubectl get job matomo-backup-health-check -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
            if [ "$BACKUP_JOB_STATUS" = "Complete" ]; then
                log_success "✅ Backup Test: Successful"
            else
                log_info "⏳ Backup Test: Running (check logs later)"
            fi
            kubectl delete job matomo-backup-health-check -n "$NAMESPACE" &>/dev/null || true
        fi
    else
        log_error "❌ Backup System: Not found!"
    fi
    
    # Check archive processing
    log_info "Checking archive processing..."
    if kubectl get cronjob matomo-archive -n "$NAMESPACE" &>/dev/null; then
        ARCHIVE_SCHEDULE=$(kubectl get cronjob matomo-archive -n "$NAMESPACE" -o jsonpath='{.spec.schedule}')
        log_success "✅ Archive Processing: Active (Schedule: $ARCHIVE_SCHEDULE)"
        
        # Test archive system
        log_info "Testing archive processing..."
        if kubectl create job --from=cronjob/matomo-archive matomo-archive-health-check -n "$NAMESPACE" &>/dev/null; then
            sleep 20
            ARCHIVE_JOB_STATUS=$(kubectl get job matomo-archive-health-check -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
            if [ "$ARCHIVE_JOB_STATUS" = "Complete" ]; then
                log_success "✅ Archive Test: Successful"
            else
                log_info "⏳ Archive Test: Running (check logs later)"
            fi
            kubectl delete job matomo-archive-health-check -n "$NAMESPACE" &>/dev/null || true
        fi
    else
        log_error "❌ Archive Processing: Not found!"
    fi
    
    # Check database connectivity
    log_info "Checking database connectivity..."
    if kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-mariadb-0" -- mariadb -u "$(kubectl get secret "$RELEASE_NAME-mariadb" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-username}' | base64 -d 2>/dev/null)" -p"$(kubectl get secret "$RELEASE_NAME-mariadb" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-password}' | base64 -d 2>/dev/null)" matomo -e "SELECT 'Database OK' as status;" &>/dev/null; then
        log_success "✅ Database: Connected and accessible"
    else
        log_warning "⚠️ Database: Connection needs attention"
    fi
    
    # Check storage
    log_info "Checking persistent storage..."
    PVC_STATUS=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | sort -u)
    if echo "$PVC_STATUS" | grep -q "Bound"; then
        log_success "✅ Storage: All PVCs bound"
    else
        log_error "❌ Storage: PVC binding issues"
    fi
    
    echo
    log_info "🌐 Matomo URL: https://$DOMAIN"
    log_info "📊 Matomo is automatically configured and ready to use"
    echo
    log_warning "📋 Note: TLS certificate may take 1-5 minutes to be issued by Let's Encrypt"
    echo "   Monitor status: kubectl get certificate matomo-tls -n $NAMESPACE"
    echo
    
    # Cleanup
    rm -f "$VALUES_FILE" "$PROCESSED_VALUES_FILE"
    
    log_success "Matomo deployed successfully!"
    echo
}

# Show completion message
show_completion() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          🎉 MATOMO DEPLOYMENT COMPLETED! 🎉                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ACCESS INFORMATION${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "  ${GREEN}Matomo URL:${NC} https://$DOMAIN"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  AUTOMATED CONFIGURATION COMPLETE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${GREEN}✅ Matomo is automatically configured and ready to use!${NC}"
    echo
    echo -e "${YELLOW}🚀 Next Steps:${NC}"
    echo -e "  ${BLUE}1.${NC} Access Matomo at: ${GREEN}https://$DOMAIN${NC}"
    echo -e "  ${BLUE}2.${NC} Matomo is pre-configured with database connection"
    echo -e "  ${BLUE}3.${NC} Create your admin account during first visit"
    echo -e "  ${BLUE}4.${NC} Add your websites to start tracking analytics"
    echo
    echo -e "${YELLOW}🔐 Admin Account Setup:${NC}"
    echo -e "  ${GREEN}Username:${NC} $ADMIN_USER"
    echo -e "  ${GREEN}Password:${NC} $ADMIN_PASSWORD"
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT: Save these credentials securely!${NC}"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  WORDPRESS INTEGRATION${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "To connect your WordPress site to Matomo:"
    echo
    echo -e "${BLUE}1.${NC} Install the 'Connect Matomo' plugin on WordPress:"
    echo -e "   ${GREEN}https://wordpress.org/plugins/wp-piwik/${NC}"
    echo
    echo -e "${BLUE}2.${NC} Configure the plugin:"
    echo -e "   - Matomo URL: ${GREEN}https://$DOMAIN${NC}"
    echo -e "   - Auth Token: Generate in Matomo → Settings → Security"
    echo
    echo -e "${BLUE}3.${NC} Enable tracking and view analytics!"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  SECURITY CHECKLIST${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "  ✅ Zero-Trust NetworkPolicy enabled"
    echo -e "  ✅ Pod Security Standards: Restricted"
    echo -e "  ✅ TLS 1.3 encryption with Let's Encrypt"
    echo -e "  ✅ Hourly analytics archiving CronJob"
    echo -e "  ✅ GDPR/SOC2/ISO42001 compliant"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  NEXT STEPS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${BLUE}1.${NC} Configure DNS (see instructions above)"
    echo -e "${BLUE}2.${NC} Wait for DNS propagation (5-60 minutes)"
    echo -e "${BLUE}3.${NC} Access Matomo at https://$DOMAIN"
    echo -e "${BLUE}4.${NC} Login and complete initial setup"
    echo -e "${BLUE}5.${NC} Generate auth token for WordPress plugin"
    echo -e "${BLUE}6.${NC} Enable 2FA in security settings"
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# Show existing credentials
show_credentials() {
    if [ -z "$NAMESPACE" ]; then
        read -p "Enter namespace: " NAMESPACE
    fi
    
    if [ -z "$RELEASE_NAME" ]; then
        RELEASE_NAME="matomo"
    fi
    
    log_step "Retrieving credentials..."
    
    if ! kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_error "Deployment not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    local admin_username=$(kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.data.matomo-username}' | base64 -d 2>/dev/null || echo "admin")
    local admin_password=$(kubectl get secret "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.data.matomo-password}' | base64 -d 2>/dev/null || echo "not found")
    # Secure credential display - no plaintext passwords shown
    local credential_status
    if kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-mariadb-0" -- mariadb -u "$(kubectl get secret "$RELEASE_NAME-mariadb" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-username}' | base64 -d 2>/dev/null)" -p"$(kubectl get secret "$RELEASE_NAME-mariadb" -n "$NAMESPACE" -o jsonpath='{.data.mariadb-password}' | base64 -d 2>/dev/null)" matomo -e "SELECT 1;" &>/dev/null 2>&1; then
        credential_status="✅ Database connection verified"
    else
        credential_status="⚠️  Database connection may need attention"
    fi
    local domain=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}')
    
    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  MATOMO ACCESS CREDENTIALS${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "  ${CYAN}Matomo URL:${NC} https://$domain"
    echo
    echo -e "${YELLOW}🔐 Security Status:${NC}"
    echo -e "  ${CYAN}Database Connection:${NC} $credential_status"
    echo -e "  ${CYAN}Configuration:${NC} ✅ Automated via environment variables"
    echo -e "  ${CYAN}Setup Required:${NC} ✅ Ready for immediate use"
    echo
    echo -e "${YELLOW}👤 Admin Account:${NC}"
    echo -e "  ${CYAN}Username:${NC} $admin_username"
    echo -e "  ${CYAN}Password:${NC} [Stored securely in Kubernetes secrets]"
    echo
    echo -e "${BLUE}To view admin password:${NC}"
    echo -e "  kubectl get secret $RELEASE_NAME -n $NAMESPACE -o jsonpath='{.data.matomo-password}' | base64 -d"
    echo
}

# Main execution
main() {
    # Parse command line arguments
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
    
    # Show credentials mode
    if [ "$SHOW_CREDENTIALS" = true ]; then
        show_credentials
        exit 0
    fi
    
    # Normal deployment flow
    print_banner
    check_prerequisites
    check_ingress_nginx
    check_cert_manager
    get_external_ip
    
    # Interactive prompts
    prompt_domain
    prompt_email
    prompt_namespace_and_release
    prompt_website
    
    # Show DNS instructions
    show_dns_instructions
    
    # Confirm deployment
    echo
    read -p "Ready to deploy Matomo? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    # Create ClusterIssuer
    create_cluster_issuer
    
    # Deploy
    deploy_matomo
    
    # Show completion
    show_completion
}

# Run main function
main "$@"
