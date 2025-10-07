#!/bin/bash

# WeOwn Tenant Cluster Creation Script
# Creates a dedicated Kubernetes cluster for a new team member
# Version: 1.0.0 - WeOwn Enterprise Standard

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
TEAM_MEMBER=""
CLUSTER_NAME=""
ENVIRONMENT="dev"
REGION="nyc3"
NODE_SIZE="s-2vcpu-4gb"
NODE_COUNT=2
DOMAIN=""

print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}  WeOwn Tenant Cluster Creation v1.0.0${NC}"
    echo -e "${BLUE}  👥 Team Member Onboarding | 🚀 Production-Ready${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing_tools=()
    
    if ! command -v doctl >/dev/null 2>&1; then
        missing_tools+=("doctl")
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm >/dev/null 2>&1; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Install instructions:${NC}"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                doctl) echo "  - doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/" ;;
                kubectl) echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/" ;;
                helm) echo "  - helm: https://helm.sh/docs/intro/install/" ;;
            esac
        done
        return 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
    return 0
}

# Function to get team member information
get_team_member_info() {
    echo -e "${YELLOW}Gathering team member information...${NC}"
    
    # Get team member name
    read -p "Enter team member name (e.g., AnnaF): " TEAM_MEMBER
    if [ -z "$TEAM_MEMBER" ]; then
        echo -e "${RED}❌ Team member name is required${NC}"
        return 1
    fi
    
    # Generate cluster name
    CLUSTER_NAME="weown-${TEAM_MEMBER,,}-cluster"
    echo -e "${CYAN}Generated cluster name: $CLUSTER_NAME${NC}"
    
    # Get environment
    read -p "Enter environment (dev/staging/prod) [dev]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-dev}
    
    # Get region
    read -p "Enter region (nyc3/sfo3/fra1) [nyc3]: " REGION
    REGION=${REGION:-nyc3}
    
    # Get node size
    read -p "Enter node size (s-2vcpu-4gb/s-4vcpu-8gb) [s-2vcpu-4gb]: " NODE_SIZE
    NODE_SIZE=${NODE_SIZE:-s-2vcpu-4gb}
    
    # Get node count
    read -p "Enter node count [2]: " NODE_COUNT
    NODE_COUNT=${NODE_COUNT:-2}
    
    # Get domain (optional)
    read -p "Enter domain for custom URLs (optional): " DOMAIN
    
    echo -e "${GREEN}✅ Team member information gathered${NC}"
}

# Function to create DigitalOcean cluster
create_digitalocean_cluster() {
    echo -e "${YELLOW}Creating DigitalOcean Kubernetes cluster...${NC}"
    
    # Create cluster
    doctl kubernetes cluster create $CLUSTER_NAME \
        --region $REGION \
        --version latest \
        --node-pool "name=worker-pool;size=$NODE_SIZE;count=$NODE_COUNT;auto-scale=false" \
        --wait
    
    echo -e "${GREEN}✅ DigitalOcean cluster created${NC}"
}

# Function to configure kubectl
configure_kubectl() {
    echo -e "${YELLOW}Configuring kubectl...${NC}"
    
    # Save kubeconfig
    doctl kubernetes cluster kubeconfig save $CLUSTER_NAME
    
    # Verify connection
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ kubectl configured successfully${NC}"
    else
        echo -e "${RED}❌ kubectl configuration failed${NC}"
        return 1
    fi
}

# Function to install cluster prerequisites
install_cluster_prerequisites() {
    echo -e "${YELLOW}Installing cluster prerequisites...${NC}"
    
    # Install NGINX Ingress Controller
    echo "Installing NGINX Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    # Wait for ingress controller to be ready
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
    
    # Install cert-manager
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/name=cert-manager --timeout=300s
    
    # Install Metrics Server
    echo "Installing Metrics Server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    echo -e "${GREEN}✅ Cluster prerequisites installed${NC}"
}

# Function to create team member namespace
create_team_member_namespace() {
    echo -e "${YELLOW}Creating team member namespace...${NC}"
    
    # Create namespace
    kubectl create namespace $TEAM_MEMBER --dry-run=client -o yaml | kubectl apply -f -
    
    # Create team member service account
    kubectl create serviceaccount $TEAM_MEMBER -n $TEAM_MEMBER --dry-run=client -o yaml | kubectl apply -f -
    
    # Create team member role
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $TEAM_MEMBER-role
  namespace: $TEAM_MEMBER
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
    
    # Create role binding
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $TEAM_MEMBER-rolebinding
  namespace: $TEAM_MEMBER
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $TEAM_MEMBER-role
subjects:
- kind: ServiceAccount
  name: $TEAM_MEMBER
  namespace: $TEAM_MEMBER
EOF
    
    echo -e "${GREEN}✅ Team member namespace and RBAC created${NC}"
}

# Function to deploy standard applications
deploy_standard_applications() {
    echo -e "${YELLOW}Deploying standard applications...${NC}"
    
    # Deploy AnythingLLM
    echo "Deploying AnythingLLM..."
    cd ../anythingllm
    ./deploy.sh
    cd ../cluster-backup
    
    # Deploy Vaultwarden
    echo "Deploying Vaultwarden..."
    cd ../vaultwarden
    ./deploy.sh
    cd ../cluster-backup
    
    # Deploy monitoring
    echo "Deploying monitoring..."
    cd ../k8s/monitoring
    ./setup-verification.sh
    cd ../../cluster-backup
    
    echo -e "${GREEN}✅ Standard applications deployed${NC}"
}

# Function to deploy cluster backup
deploy_cluster_backup() {
    echo -e "${YELLOW}Deploying cluster backup...${NC}"
    
    # Set configuration for cluster backup
    export TENANT="weown-$TEAM_MEMBER"
    export CLUSTER="$CLUSTER_NAME"
    export ENVIRONMENT="$ENVIRONMENT"
    export S3_BUCKET="weown-$TEAM_MEMBER-backups"
    export S3_REGION="$REGION"
    export S3_ENDPOINT="https://$REGION.digitaloceanspaces.com"
    export S3_ACCESS_KEY=""
    export S3_SECRET_KEY=""
    
    echo -e "${CYAN}Cluster backup configuration:${NC}"
    echo "Tenant: $TENANT"
    echo "Cluster: $CLUSTER"
    echo "Environment: $ENVIRONMENT"
    echo "S3 Bucket: $S3_BUCKET"
    echo "S3 Region: $S3_REGION"
    echo "S3 Endpoint: $S3_ENDPOINT"
    echo ""
    echo -e "${YELLOW}Note: S3 credentials need to be configured separately${NC}"
    
    # Deploy cluster backup
    ./deploy.sh
    
    echo -e "${GREEN}✅ Cluster backup deployed${NC}"
}

# Function to create team member access
create_team_member_access() {
    echo -e "${YELLOW}Creating team member access...${NC}"
    
    # Get service account token
    SECRET_NAME=$(kubectl get serviceaccount $TEAM_MEMBER -n $TEAM_MEMBER -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret $SECRET_NAME -n $TEAM_MEMBER -o jsonpath='{.data.token}' | base64 -d)
    
    # Get cluster info
    CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    CLUSTER_CA=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    
    # Create kubeconfig for team member
    cat > ${TEAM_MEMBER}-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    user: $TEAM_MEMBER
    namespace: $TEAM_MEMBER
  name: $TEAM_MEMBER-context
current-context: $TEAM_MEMBER-context
users:
- name: $TEAM_MEMBER
  user:
    token: $TOKEN
EOF
    
    echo -e "${GREEN}✅ Team member access created${NC}"
}

# Function to show cluster information
show_cluster_information() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  Team Member Cluster Information${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    
    echo -e "${GREEN}👤 Team Member:${NC}"
    echo "Name: $TEAM_MEMBER"
    echo "Namespace: $TEAM_MEMBER"
    echo "Service Account: $TEAM_MEMBER"
    echo ""
    
    echo -e "${GREEN}🏗️ Cluster Details:${NC}"
    echo "Name: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo "Node Size: $NODE_SIZE"
    echo "Node Count: $NODE_COUNT"
    echo "Environment: $ENVIRONMENT"
    echo ""
    
    echo -e "${GREEN}🔐 Access Information:${NC}"
    echo "Kubeconfig: ${TEAM_MEMBER}-kubeconfig.yaml"
    echo "Namespace: $TEAM_MEMBER"
    echo "Permissions: Full access to $TEAM_MEMBER namespace"
    echo ""
    
    echo -e "${GREEN}🚀 Deployed Applications:${NC}"
    echo "• AnythingLLM (AI assistant)"
    echo "• Vaultwarden (Password manager)"
    echo "• Monitoring (Portainer + Metrics Server)"
    echo "• Cluster Backup (Velero + Restic)"
    echo ""
    
    if [ -n "$DOMAIN" ]; then
        echo -e "${GREEN}🌐 Custom URLs:${NC}"
        echo "• AnythingLLM: https://anythingllm.$DOMAIN"
        echo "• Vaultwarden: https://vaultwarden.$DOMAIN"
        echo "• Portainer: https://portainer.$DOMAIN"
        echo ""
    fi
    
    echo -e "${GREEN}📚 Next Steps for $TEAM_MEMBER:${NC}"
    echo "1. Download kubeconfig: ${TEAM_MEMBER}-kubeconfig.yaml"
    echo "2. Set KUBECONFIG: export KUBECONFIG=\$(pwd)/${TEAM_MEMBER}-kubeconfig.yaml"
    echo "3. Test access: kubectl get pods -n $TEAM_MEMBER"
    echo "4. Deploy applications: kubectl create deployment test --image=nginx -n $TEAM_MEMBER"
    echo ""
    
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "• Check cluster status: doctl kubernetes cluster get $CLUSTER_NAME"
    echo "• Scale cluster: doctl kubernetes cluster node-pool update $CLUSTER_NAME <pool-id> --count <new-count>"
    echo "• Delete cluster: doctl kubernetes cluster delete $CLUSTER_NAME"
    echo ""
    
    echo -e "${BLUE}🔒 Security Status: PRODUCTION READY${NC}"
}

# Function to show help
show_help() {
    cat << EOF
WeOwn Tenant Cluster Creation Script v1.0.0

Usage: $0 [OPTIONS]

OPTIONS:
    --help              Show this help message
    --team-member       Team member name (e.g., AnnaF)
    --cluster-name      Cluster name (default: weown-<team-member>-cluster)
    --environment       Environment (dev/staging/prod) [dev]
    --region            Region (nyc3/sfo3/fra1) [nyc3]
    --node-size         Node size (s-2vcpu-4gb/s-4vcpu-8gb) [s-2vcpu-4gb]
    --node-count        Node count [2]
    --domain            Domain for custom URLs (optional)

EXAMPLE:
    # Interactive creation
    $0
    
    # Create cluster for AnnaF
    $0 --team-member AnnaF --environment dev --region nyc3
    
    # Create production cluster
    $0 --team-member AnnaF --environment prod --node-size s-4vcpu-8gb --node-count 3

FEATURES:
    ✅ Dedicated Kubernetes cluster
    ✅ Team member namespace with RBAC
    ✅ Standard applications (AnythingLLM, Vaultwarden, Monitoring)
    ✅ Cluster backup with Velero + Restic
    ✅ Custom domain support
    ✅ Production-ready security
EOF
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --help)
            show_help
            exit 0
            ;;
        --team-member=*)
            TEAM_MEMBER="${arg#*=}"
            shift
            ;;
        --cluster-name=*)
            CLUSTER_NAME="${arg#*=}"
            shift
            ;;
        --environment=*)
            ENVIRONMENT="${arg#*=}"
            shift
            ;;
        --region=*)
            REGION="${arg#*=}"
            shift
            ;;
        --node-size=*)
            NODE_SIZE="${arg#*=}"
            shift
            ;;
        --node-count=*)
            NODE_COUNT="${arg#*=}"
            shift
            ;;
        --domain=*)
            DOMAIN="${arg#*=}"
            shift
            ;;
    esac
done

# Main execution starts here
echo
print_header
echo

# Check prerequisites
if ! check_prerequisites; then
    exit 1
fi

# Get team member information (if not provided via command line)
if [ -z "$TEAM_MEMBER" ]; then
    if ! get_team_member_info; then
        exit 1
    fi
else
    # Set default values if not provided
    CLUSTER_NAME=${CLUSTER_NAME:-"weown-${TEAM_MEMBER,,}-cluster"}
    ENVIRONMENT=${ENVIRONMENT:-dev}
    REGION=${REGION:-nyc3}
    NODE_SIZE=${NODE_SIZE:-s-2vcpu-4gb}
    NODE_COUNT=${NODE_COUNT:-2}
fi

# Create DigitalOcean cluster
if ! create_digitalocean_cluster; then
    exit 1
fi

# Configure kubectl
if ! configure_kubectl; then
    exit 1
fi

# Install cluster prerequisites
if ! install_cluster_prerequisites; then
    exit 1
fi

# Create team member namespace
if ! create_team_member_namespace; then
    exit 1
fi

# Deploy standard applications
if ! deploy_standard_applications; then
    exit 1
fi

# Deploy cluster backup
if ! deploy_cluster_backup; then
    exit 1
fi

# Create team member access
if ! create_team_member_access; then
    exit 1
fi

# Show cluster information
show_cluster_information

echo "==========================================="
echo -e "✅ ${GREEN}TEAM MEMBER CLUSTER CREATION COMPLETE!${NC}"
echo "==========================================="

