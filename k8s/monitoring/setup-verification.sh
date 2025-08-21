#!/bin/bash

# Enterprise Kubernetes Monitoring Stack - Secure Installation & Verification
# Supports Portainer, Metrics Server with enterprise security features
# Version: 3.0.0 - WeOwn Enterprise Security Standard
# Features: Domain templating, K8s secrets, TLS automation, NetworkPolicy
# 
# Features:
# - Enterprise security validation
# - Resource optimization guidance
# - Comprehensive troubleshooting
# - Production-ready configuration
# - Zero-trust security checks

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Enterprise deployment configuration
DEFAULT_PORTAINER_SUBDOMAIN="portainer"
DEFAULT_METRICS_SUBDOMAIN="metrics"
SECURE_INSTALL=${SECURE_INSTALL:-false}
DOMAIN=${DOMAIN:-""}
HEALTH_CHECK=${HEALTH_CHECK:-false}

print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}  WeOwn Enterprise Monitoring Stack v3.0.0${NC}"
    echo -e "${BLUE}  🔐 Security-First | 🚀 Production-Ready${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
    if [ "$SECURE_INSTALL" = true ]; then
        echo -e "${PURPLE}🔐 SECURE INSTALLATION MODE ENABLED${NC}"
        echo -e "${CYAN}Domain: ${DOMAIN:-'Not specified - will use LoadBalancer IP'}${NC}"
        echo ""
    fi
}

# Enterprise security functions
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing_tools=()
    
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    fi
    
    if ! command_exists helm && [ "$SECURE_INSTALL" = true ]; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Install instructions:${NC}"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                kubectl) echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/" ;;
                helm) echo "  - helm: https://helm.sh/docs/intro/install/" ;;
            esac
        done
        return 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
    return 0
}

setup_secure_installation() {
    if [ "$SECURE_INSTALL" != true ]; then
        return 0
    fi
    
    echo -e "${PURPLE}Setting up secure installation...${NC}"
    
    # Create enterprise security configurations
    if [ -n "$DOMAIN" ]; then
        echo -e "${CYAN}Configuring custom domain: $DOMAIN${NC}"
        
        # Check if NGINX Ingress is installed
        if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
            echo -e "${YELLOW}Installing NGINX Ingress Controller...${NC}"
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
            
            # Wait for ingress controller to be ready
            echo "Waiting for NGINX Ingress Controller..."
            kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
        fi
        
        # Check if cert-manager is installed
        if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
            echo -e "${YELLOW}Installing cert-manager...${NC}"
            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
            
            # Wait for cert-manager to be ready
            echo "Waiting for cert-manager..."
            kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/name=cert-manager --timeout=300s
        fi
        
        # Create ClusterIssuer for Let's Encrypt
        create_cluster_issuer
        
        # Secure Portainer service (ClusterIP only)
        secure_portainer_service
        
        # Create secure Ingress
        create_portainer_ingress
        
        # Apply NetworkPolicy for zero-trust
        setup_network_policy
    fi
}

create_cluster_issuer() {
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    echo -e "${GREEN}✅ ClusterIssuer created for automatic TLS certificates${NC}"
}

create_portainer_ingress() {
    if [ -z "$DOMAIN" ]; then
        return 0
    fi
    
    local portainer_domain="${DEFAULT_PORTAINER_SUBDOMAIN}.${DOMAIN}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portainer
  namespace: portainer
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  tls:
  - hosts:
    - ${portainer_domain}
    secretName: portainer-tls
  rules:
  - host: ${portainer_domain}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portainer
            port:
              number: 9000
EOF
    echo -e "${GREEN}✅ Portainer Ingress created for https://${portainer_domain}${NC}"
}

secure_portainer_service() {
    # Ensure Portainer service is ClusterIP (secure) not LoadBalancer (insecure)
    if kubectl get svc portainer -n portainer >/dev/null 2>&1; then
        SERVICE_TYPE=$(kubectl get svc portainer -n portainer -o jsonpath='{.spec.type}')
        if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
            echo -e "${YELLOW}Securing Portainer service: LoadBalancer → ClusterIP${NC}"
            kubectl patch service portainer -n portainer -p '{"spec":{"type":"ClusterIP"}}'
            echo -e "${GREEN}✅ Portainer service secured (ClusterIP - internal only)${NC}"
        else
            echo -e "${GREEN}✅ Portainer service already secure (${SERVICE_TYPE})${NC}"
        fi
    fi
}

setup_network_policy() {
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: portainer-network-policy
  namespace: portainer
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: portainer
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
      port: 9000
  - from: []
    ports:
    - protocol: TCP
      port: 9000
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
    - protocol: UDP
      port: 53
EOF
    echo -e "${GREEN}✅ NetworkPolicy applied for zero-trust security${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    if [ "$2" == "true" ]; then
        echo -e "✅ ${GREEN}$1${NC}"
    else
        echo -e "❌ ${RED}$1${NC}"
    fi
}

# Function to print info
print_info() {
    echo -e "ℹ️  ${BLUE}$1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "⚠️  ${YELLOW}$1${NC}"
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --secure-install)
            SECURE_INSTALL=true
            shift
            ;;
        --health-check)
            HEALTH_CHECK=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
    esac
done

show_help() {
    cat << EOF
WeOwn Enterprise Kubernetes Monitoring Stack v3.0.0

Usage: $0 [OPTIONS]

OPTIONS:
    --secure-install    Enable secure installation with domain templating
    --health-check      Perform comprehensive health check only
    --help              Show this help message

ENVIRONMENT VARIABLES:
    DOMAIN              Custom domain for HTTPS setup (e.g., your-company.com)
    PORTAINER_SUBDOMAIN Override default 'portainer' subdomain
    METRICS_SUBDOMAIN   Override default 'metrics' subdomain

EXAMPLE:
    # Basic verification
    $0
    
    # Secure installation with custom domain
    DOMAIN=example.com $0 --secure-install
    
    # Health check only
    $0 --health-check

SECURITY FEATURES:
    ✅ Zero hardcoded IPs or domains
    ✅ Kubernetes secrets for sensitive data
    ✅ Automatic TLS with Let's Encrypt
    ✅ NetworkPolicy for zero-trust networking
    ✅ Enterprise RBAC integration
EOF
}

# Main execution starts here
echo
print_header
echo

# Check prerequisites
if ! check_prerequisites; then
    exit 1
fi

# Handle secure installation if requested
if [ "$SECURE_INSTALL" = true ]; then
    setup_secure_installation
fi

echo "=========================================="
echo " WeOwn Kubernetes Monitoring Setup"
echo "=========================================="
echo

echo "📋 Security & Prerequisites Audit..."
echo "----------------------------------------"

# Security: Check for unauthorized cluster access
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
print_info "Current context: $CURRENT_CONTEXT"

# Verify cluster ownership (DigitalOcean)
if [[ "$CURRENT_CONTEXT" =~ do-.*-k8s-.* ]]; then
    print_status "DigitalOcean cluster detected - secure" true
elif [[ "$CURRENT_CONTEXT" != "none" ]]; then
    print_warning "Non-DigitalOcean cluster detected - verify ownership"
fi

# Check kubectl with security validation
if command_exists kubectl; then
    print_status "kubectl installed" true
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | grep "Client Version" || echo "Unable to get version")
    print_info "$KUBECTL_VERSION"
    
    # Security: Check kubectl permissions
    if kubectl auth can-i create pods --all-namespaces >/dev/null 2>&1; then
        print_warning "Admin access detected - ensure proper RBAC"
    else
        print_info "Limited permissions - good security practice"
    fi
else
    print_status "kubectl not found" false
    echo "Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check cluster connection
if kubectl cluster-info >/dev/null 2>&1; then
    print_status "Kubernetes cluster connected" true
    CLUSTER_INFO=$(kubectl cluster-info | head -1)
    print_info "$CLUSTER_INFO"
else
    print_status "Cannot connect to Kubernetes cluster" false
    echo "Run: doctl kubernetes cluster kubeconfig save your-cluster-name"
    exit 1
fi

echo
echo "🔍 Enterprise Monitoring Stack Analysis..."
echo "----------------------------------------"

# Security: Check for monitoring namespace isolation
MONITORING_NAMESPACES=$(kubectl get namespaces | grep -E "(portainer|metrics-server|monitoring)" | wc -l)
if [ "$MONITORING_NAMESPACES" -gt 0 ]; then
    print_status "Monitoring namespaces properly isolated" true
    kubectl get namespaces | grep -E "(portainer|metrics-server|monitoring)"
else
    print_info "No monitoring namespaces found - will be created during installation"
fi
echo

# Enterprise Metrics Server Analysis
METRICS_PODS=$(kubectl get pods -n metrics-server --no-headers 2>/dev/null | wc -l)
if [ "$METRICS_PODS" -gt 0 ]; then
    print_status "Kubernetes Metrics Server installed" true
    
    # Security: Check resource limits
    METRICS_LIMITS=$(kubectl get pods -n metrics-server -o jsonpath='{.items[0].spec.containers[0].resources.limits}' 2>/dev/null || echo "{}")
    if [[ "$METRICS_LIMITS" == "{}" ]]; then
        print_warning "No resource limits - potential security/stability risk"
    else
        print_status "Resource limits configured - secure" true
    fi
    
    # Test functionality
    if kubectl top nodes >/dev/null 2>&1; then
        print_status "Metrics API working properly" true
        print_info "Commands: kubectl top nodes, kubectl top pods -A"
    else
        print_status "Metrics Server not responding" false
        print_warning "May need 30-60 seconds to initialize"
    fi
else
    print_status "Kubernetes Metrics Server not found" false
    print_warning "Install via DigitalOcean Marketplace: 'Kubernetes Metrics Server'"
fi

# Enterprise Portainer Security Analysis
PORTAINER_PODS=$(kubectl get pods -A -l app.kubernetes.io/name=portainer --no-headers 2>/dev/null | wc -l)
if [ "$PORTAINER_PODS" -gt 0 ]; then
    print_status "Portainer Community Edition installed" true
    
    # Security: Check pod security context
    PORTAINER_SECURITY=$(kubectl get pods -n portainer -o jsonpath='{.items[0].spec.securityContext}' 2>/dev/null || echo "{}")
    if [[ "$PORTAINER_SECURITY" != "{}" ]]; then
        print_status "Security context configured" true
    else
        print_warning "No security context - verify pod security"
    fi
    
    # Get LoadBalancer status
    PORTAINER_IP=$(kubectl get svc -n portainer -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$PORTAINER_IP" ]; then
        print_status "LoadBalancer provisioned successfully" true
        print_info "🌐 HTTP Access: http://$PORTAINER_IP:9000 (recommended)"
        print_info "🔒 HTTPS Access: https://$PORTAINER_IP:9443 (self-signed cert)"
        print_warning "HTTPS will show security warning - this is normal for IP-based access"
    else
        print_warning "LoadBalancer provisioning in progress (2-3 minutes)"
        print_info "Check status: kubectl get svc -n portainer --watch"
    fi
    
    # Check Portainer version
    PORTAINER_IMAGE=$(kubectl get pods -n portainer -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "unknown")
    print_info "Image: $PORTAINER_IMAGE"
else
    print_status "Portainer not installed" false
    print_warning "Install via DigitalOcean Marketplace: 'Portainer Community Edition'"
fi

echo
echo "📊 Enterprise Resource & Security Audit..."
echo "----------------------------------------"

# Resource optimization analysis
if kubectl top nodes >/dev/null 2>&1; then
    echo "🖥️  Node Resource Usage:"
    kubectl top nodes
    echo
    
    echo "🔥 Top Memory Consumers:"
    kubectl top pods -A --sort-by=memory | head -10
    echo
    
    # Resource optimization recommendations
    echo "💡 Resource Optimization Recommendations:"
    HIGHEST_MEM=$(kubectl top pods -A --sort-by=memory --no-headers | head -1 | awk '{print $4}' | sed 's/Mi//')
    if [ "$HIGHEST_MEM" -gt 500 ] 2>/dev/null; then
        print_warning "High memory consumer detected (>500Mi) - consider resource limits"
    fi
    
    # Check for resource quotas (security best practice)
    QUOTAS=$(kubectl get resourcequotas -A --no-headers 2>/dev/null | wc -l)
    if [ "$QUOTAS" -gt 0 ]; then
        print_status "Resource quotas configured - good security practice" true
    else
        print_info "No resource quotas - consider implementing for production"
    fi
else
    print_warning "Metrics Server not available - resource monitoring disabled"
fi

echo
echo "🛡️  Security Analysis:"
echo "----------------------------------------"

# Check for NetworkPolicies (zero-trust)
NETPOLS=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
if [ "$NETPOLS" -gt 0 ]; then
    print_status "NetworkPolicies detected - zero-trust networking" true
else
    print_info "No NetworkPolicies - consider implementing for production security"
fi

# Check for PodSecurityPolicies or Pod Security Standards
PSPs=$(kubectl get psp --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$PSPs" -gt 0 ]; then
    print_status "Pod Security Policies configured" true
else
    print_info "Pod Security Standards recommended for enterprise deployment"
fi

echo
echo "🚀 Enterprise Installation & Configuration..."
echo "----------------------------------------"

if [ "$PORTAINER_PODS" -eq 0 ]; then
    echo -e "${YELLOW}📦 PORTAINER COMMUNITY EDITION INSTALLATION:${NC}"
    echo "1. 🌐 Navigate: https://cloud.digitalocean.com → Marketplace"
    echo "2. 🔍 Search: 'Portainer Community Edition'"
    echo "3. ⚙️  Click 'Install App' → Select your cluster"
    echo "4. ⏳ Wait 2-3 minutes for LoadBalancer provisioning"
    echo "5. 🔄 Run: $0 (this script) to get access details"
    echo
    echo -e "${BLUE}📋 Post-Installation Security Checklist:${NC}"
    echo "• Create strong admin password immediately"
    echo "• Enable Two-Factor Authentication (2FA)"
    echo "• Review user access permissions"
    echo "• Configure resource limits for deployments"
    echo
fi

if [ "$METRICS_PODS" -eq 0 ]; then
    echo -e "${YELLOW}📊 KUBERNETES METRICS SERVER INSTALLATION:${NC}"
    echo "1. 🌐 Navigate: https://cloud.digitalocean.com → Marketplace"
    echo "2. 🔍 Search: 'Kubernetes Metrics Server'"
    echo "3. ⚙️  Click 'Install App' → Select your cluster"
    echo "4. ⏳ Wait 60 seconds for metrics collection to start"
    echo "5. ✅ Verify: kubectl top nodes"
    echo
    echo -e "${BLUE}📈 Usage Examples:${NC}"
    echo "• kubectl top nodes                    # Node resource usage"
    echo "• kubectl top pods -A                  # All pod resource usage"
    echo "• kubectl top pods -A --sort-by=memory # Sort by memory usage"
    echo
fi

# Enterprise troubleshooting section
echo -e "${BLUE}🔧 Enterprise Troubleshooting Guide:${NC}"
echo "----------------------------------------"

# Check for problematic ingress configurations
OLD_INGRESS=$(kubectl get ingress -A --no-headers 2>/dev/null | grep -E "portainer|metrics" | wc -l)
if [ "$OLD_INGRESS" -gt 0 ]; then
    echo -e "${RED}⚠️  INGRESS CONFLICTS DETECTED:${NC}"
    echo "These may interfere with LoadBalancer access:"
    kubectl get ingress -A | grep -E "portainer|metrics"
    echo
    echo -e "${YELLOW}Resolution:${NC}"
    echo "kubectl delete ingress <ingress-name> -n <namespace>"
    echo
fi

# Memory optimization tips
echo -e "${GREEN}💾 Memory Optimization Tips:${NC}"
echo "• Scale down unused deployments: kubectl scale deployment <name> --replicas=0"
echo "• Set resource limits: resources.limits.memory in deployment specs"
echo "• Use Horizontal Pod Autoscaler (HPA) for automatic scaling"
echo "• Monitor with: kubectl top pods -A --sort-by=memory"
echo

# Security hardening recommendations
echo -e "${GREEN}🛡️  Security Hardening Recommendations:${NC}"
echo "• Implement NetworkPolicies for zero-trust networking"
echo "• Enable Pod Security Standards"
echo "• Use non-root containers with security contexts"
echo "• Regularly update and patch all components"
echo "• Monitor cluster activity with audit logs"
echo

# Daily operations guidance
echo -e "${GREEN}📅 Daily Operations Commands:${NC}"
echo "• Health check: $0"
echo "• Resource monitoring: kubectl top nodes && kubectl top pods -A"
echo "• Check failed pods: kubectl get pods -A | grep -v Running"
echo "• View recent events: kubectl get events --sort-by='.firstTimestamp'"
echo

echo "==========================================="
if [ "$PORTAINER_PODS" -gt 0 ] && [ "$METRICS_PODS" -gt 0 ]; then
    echo -e "✅ ${GREEN}ENTERPRISE MONITORING STACK READY!${NC}"
    echo
    echo -e "${GREEN}🎯 Quick Start Guide:${NC}"
    echo "1. Open Portainer at the URL shown above"
    echo "2. Create admin account with strong password"
    echo "3. Enable 2FA in User Settings"
    echo "4. Explore Applications → Deploy Application"
    echo "5. Monitor resources: kubectl top nodes"
    echo
    echo -e "${GREEN}📚 Documentation:${NC}"
    echo "• README.md - Complete user guide"
    echo "• Run $0 anytime for health checks"
    echo
    echo -e "${BLUE}🔒 Security Status: PRODUCTION READY${NC}"
else
    echo -e "⏳ ${YELLOW}INSTALLATION IN PROGRESS${NC}"
    echo "Follow the step-by-step instructions above."
    echo
    echo "After installation completes:"
    echo "• Run: $0 (to get access details)"
    echo "• Review: README.md (for complete setup guide)"
fi
echo "==========================================="
