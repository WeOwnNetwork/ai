#!/bin/bash
set -e

# Braintrust Proxy Deploy Script for WeOwn AI Stack
# Simple kubectl deployment (no Helm required)
# Usage: ./deploy.sh

NAMESPACE="${NAMESPACE:-braintrust}"
APP_NAME="braintrust-proxy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Will be set during registry setup
IMAGE=""

print_banner() {
    echo "=============================================="
    echo "  🧠 Braintrust Proxy Deployment"
    echo "  WeOwn AI Observability Stack"
    echo "=============================================="
}

check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

setup_container_registry() {
    echo ""
    echo "🐳 Container Registry Setup"
    echo "============================"
    echo ""
    echo "The proxy needs a container image. Choose an option:"
    echo ""
    echo "  1) DigitalOcean Container Registry (DOCR) - recommended if using DO K8s"
    echo "  2) GitHub Container Registry (GHCR)"
    echo "  3) Image already exists - I'll provide the URL"
    echo ""
    read -p "Select option (1/2/3): " REGISTRY_CHOICE
    
    case "${REGISTRY_CHOICE}" in
        1)
            setup_docr
            ;;
        2)
            setup_ghcr
            ;;
        3)
            read -p "Enter full image URL (e.g., registry.digitalocean.com/my-registry/braintrust-proxy:latest): " IMAGE
            if [[ -z "${IMAGE}" ]]; then
                echo "❌ Image URL is required"
                exit 1
            fi
            echo "✅ Using existing image: ${IMAGE}"
            ;;
        *)
            echo "❌ Invalid option"
            exit 1
            ;;
    esac
}

setup_docr() {
    echo ""
    echo "🔵 DigitalOcean Container Registry Setup"
    echo ""
    
    # Check if doctl is available
    if ! command -v doctl &> /dev/null; then
        echo "❌ doctl not found. Install it: brew install doctl"
        exit 1
    fi
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker not found or not running."
        echo "   Please start Docker Desktop: open /Applications/Docker.app"
        echo "   Then run this script again."
        exit 1
    fi
    
    # Check if docker daemon is running
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running."
        echo "   Please start Docker Desktop: open /Applications/Docker.app"
        echo "   Wait for it to start, then run this script again."
        exit 1
    fi
    
    # Get registry name
    echo "Enter your DOCR registry name (e.g., my-registry):"
    read -p "Registry name: " DOCR_REGISTRY_NAME
    
    if [[ -z "${DOCR_REGISTRY_NAME}" ]]; then
        echo "❌ Registry name is required"
        exit 1
    fi
    
    IMAGE="registry.digitalocean.com/${DOCR_REGISTRY_NAME}/braintrust-proxy:latest"
    
    echo ""
    echo "📝 Registry: ${DOCR_REGISTRY_NAME}"
    echo "📝 Image will be: ${IMAGE}"
    echo ""
    
    # Login to DOCR
    echo "🔑 Logging into DOCR..."
    if ! doctl registry login; then
        echo ""
        echo "❌ Failed to login to DOCR."
        echo "   If you see 'docker-credential-desktop' error:"
        echo "   1. Make sure Docker Desktop is running"
        echo "   2. Try: open /Applications/Docker.app"
        echo "   3. Wait 30 seconds, then run this script again"
        exit 1
    fi
    echo "✅ Logged into DOCR"
    
    # Build and push
    build_and_push_image
    
    # Remind about cluster integration
    echo ""
    echo "⚠️  Make sure your K8s cluster is integrated with this DOCR registry!"
    echo "   DigitalOcean Console → Container Registry → Settings → Kubernetes Integration"
    echo ""
    read -p "Is the cluster integrated with DOCR? (y/N): " DOCR_INTEGRATED
    if [[ ! "${DOCR_INTEGRATED}" =~ ^[Yy]$ ]]; then
        echo ""
        echo "❌ Please integrate your cluster with DOCR first, then run this script again."
        echo "   Go to: https://cloud.digitalocean.com/registry"
        exit 1
    fi
}

setup_ghcr() {
    echo ""
    echo "🐙 GitHub Container Registry Setup"
    echo ""
    
    # Check if docker is available and running
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker not found or not running."
        echo "   Please start Docker Desktop: open /Applications/Docker.app"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running."
        echo "   Please start Docker Desktop: open /Applications/Docker.app"
        exit 1
    fi
    
    # Get GitHub username
    read -p "Enter your GitHub username or org: " GITHUB_USER
    if [[ -z "${GITHUB_USER}" ]]; then
        echo "❌ GitHub username is required"
        exit 1
    fi
    
    IMAGE="ghcr.io/${GITHUB_USER}/braintrust-proxy:latest"
    
    echo ""
    echo "📝 Image will be: ${IMAGE}"
    echo ""
    
    # Login to GHCR
    echo "🔑 Logging into GHCR..."
    echo "   You need a GitHub Personal Access Token with 'write:packages' scope."
    echo "   Create one at: https://github.com/settings/tokens"
    echo ""
    read -sp "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
    echo ""
    
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo "❌ GitHub token is required"
        exit 1
    fi
    
    echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_USER}" --password-stdin
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to login to GHCR"
        exit 1
    fi
    echo "✅ Logged into GHCR"
    
    # Build and push
    build_and_push_image
    
    # Create image pull secret for K8s
    echo ""
    echo "🔒 Creating image pull secret for Kubernetes..."
    kubectl create secret docker-registry ghcr-secret \
        --docker-server=ghcr.io \
        --docker-username="${GITHUB_USER}" \
        --docker-password="${GITHUB_TOKEN}" \
        -n "${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Image pull secret created"
    
    # Set flag to use imagePullSecrets
    USE_IMAGE_PULL_SECRET="ghcr-secret"
}

build_and_push_image() {
    echo ""
    echo "🔨 Building Docker image for linux/amd64..."
    docker buildx build --platform linux/amd64 -t "${IMAGE}" --push "${SCRIPT_DIR}"
    
    echo "✅ Image built and pushed: ${IMAGE}"
}

verify_cluster() {
    echo ""
    echo "🔍 Cluster Verification"
    echo "======================="
    
    # Get current context and cluster info
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CURRENT_CONTEXT}')].context.cluster}" 2>/dev/null || echo "unknown")
    CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='${CLUSTER_NAME}')].cluster.server}" 2>/dev/null || echo "unknown")
    
    echo ""
    echo "  Current Context: ${CURRENT_CONTEXT}"
    echo "  Cluster:         ${CLUSTER_NAME}"
    echo "  Server:          ${CLUSTER_SERVER}"
    echo ""
    
    # List nodes for additional verification
    echo "  Nodes:"
    kubectl get nodes --no-headers 2>/dev/null | while read line; do
        echo "    - $(echo $line | awk '{print $1}') ($(echo $line | awk '{print $2}'))"
    done
    
    echo ""
    read -p "⚠️  Is this the correct cluster? (y/N): " CONFIRM_CLUSTER
    if [[ ! "${CONFIRM_CLUSTER}" =~ ^[Yy]$ ]]; then
        echo ""
        echo "❌ Deployment cancelled."
        echo "   Switch clusters with: kubectl config use-context <context-name>"
        echo "   List contexts with:   kubectl config get-contexts"
        exit 1
    fi
    
    echo "✅ Cluster verified"
}

check_anythingllm() {
    echo ""
    echo "🔎 Checking for AnythingLLM instance..."
    
    # Search for AnythingLLM pods across all namespaces
    ANYTHINGLLM_PODS=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=anythingllm --no-headers 2>/dev/null | head -5)
    
    # Also check for pods with 'anythingllm' in the name (in case labels differ)
    if [[ -z "${ANYTHINGLLM_PODS}" ]]; then
        ANYTHINGLLM_PODS=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -i anythingllm | head -5)
    fi
    
    if [[ -n "${ANYTHINGLLM_PODS}" ]]; then
        echo ""
        echo "✅ AnythingLLM instance(s) found:"
        echo ""
        echo "${ANYTHINGLLM_PODS}" | while read line; do
            NS=$(echo $line | awk '{print $1}')
            POD=$(echo $line | awk '{print $2}')
            STATUS=$(echo $line | awk '{print $4}')
            echo "   - ${POD} (namespace: ${NS}, status: ${STATUS})"
        done
        echo ""
        
        # Store namespace for later reference
        ANYTHINGLLM_NAMESPACE=$(echo "${ANYTHINGLLM_PODS}" | head -1 | awk '{print $1}')
        export ANYTHINGLLM_NAMESPACE
    else
        echo ""
        echo "⚠️  No AnythingLLM instance found in this cluster."
        echo ""
        echo "   The Braintrust proxy requires AnythingLLM to be running"
        echo "   and configured to use the proxy as its LLM provider."
        echo ""
        read -p "   Continue anyway? (y/N): " CONTINUE_WITHOUT_ALLM
        if [[ ! "${CONTINUE_WITHOUT_ALLM}" =~ ^[Yy]$ ]]; then
            echo ""
            echo "❌ Deployment cancelled."
            echo "   Deploy AnythingLLM first, then run this script again."
            exit 1
        fi
        echo ""
        echo "⚠️  Continuing without AnythingLLM verification..."
    fi
}

create_namespace() {
    echo "📁 Creating namespace ${NAMESPACE}..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
}

prompt_for_secrets() {
    echo ""
    echo "🔐 API Key Configuration"
    echo "========================"
    
    if kubectl get secret ${APP_NAME}-secrets -n "${NAMESPACE}" &> /dev/null; then
        echo "⚠️  Secrets already exist in namespace ${NAMESPACE}"
        read -p "Do you want to update them? (y/N): " UPDATE_SECRETS
        if [[ ! "${UPDATE_SECRETS}" =~ ^[Yy]$ ]]; then
            echo "✅ Using existing secrets"
            return
        fi
    fi
    
    read -sp "Enter your Braintrust API Key: " BRAINTRUST_API_KEY
    echo ""
    
    if [[ -z "${BRAINTRUST_API_KEY}" ]]; then
        echo "❌ Braintrust API Key is required"
        exit 1
    fi
    
    read -sp "Enter your OpenRouter API Key: " OPENROUTER_API_KEY
    echo ""
    
    if [[ -z "${OPENROUTER_API_KEY}" ]]; then
        echo "❌ OpenRouter API Key is required"
        exit 1
    fi
    
    echo "🔒 Creating Kubernetes secret..."
    kubectl create secret generic ${APP_NAME}-secrets \
        --from-literal=BRAINTRUST_API_KEY="${BRAINTRUST_API_KEY}" \
        --from-literal=OPENROUTER_API_KEY="${OPENROUTER_API_KEY}" \
        -n "${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✅ Secrets created successfully"
}

deploy() {
    echo ""
    echo "🚀 Deploying Braintrust Proxy..."
    
    # Build imagePullSecrets section if needed
    IMAGE_PULL_SECRETS=""
    if [[ -n "${USE_IMAGE_PULL_SECRET}" ]]; then
        IMAGE_PULL_SECRETS="imagePullSecrets:
      - name: ${USE_IMAGE_PULL_SECRET}"
    fi
    
    # Apply deployment
    kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
      ${IMAGE_PULL_SECRETS}
      containers:
      - name: ${APP_NAME}
        image: ${IMAGE}
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        - name: BRAINTRUST_PROJECT_NAME
          value: "${BRAINTRUST_PROJECT_NAME:-AnythingLLM}"
        envFrom:
        - secretRef:
            name: ${APP_NAME}-secrets
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: ${APP_NAME}
EOF
    
    echo "⏳ Waiting for deployment..."
    kubectl rollout status deployment/${APP_NAME} -n "${NAMESPACE}" --timeout=120s
    
    echo "✅ Deployment complete"
}

show_status() {
    echo ""
    echo "📊 Deployment Status"
    echo "===================="
    
    kubectl get pods -n "${NAMESPACE}" -l app=${APP_NAME}
    
    echo ""
    echo "=============================================="
    echo "  ✅ Braintrust Proxy Deployed!"
    echo "=============================================="
    echo ""
    echo "📋 Configure AnythingLLM:"
    echo "   Settings → AI Providers → LLM → Generic OpenAI"
    echo ""
    echo "   Base URL: http://${APP_NAME}.${NAMESPACE}.svc.cluster.local:8080/v1"
    echo "   API Key: any-value (proxy handles auth)"
    echo ""
    echo "📊 View traces: https://www.braintrust.dev/app/projects"
    echo ""
    echo "📝 Check logs: kubectl logs -f -l app=${APP_NAME} -n ${NAMESPACE}"
    echo ""
}

main() {
    print_banner
    check_prerequisites
    verify_cluster
    check_anythingllm
    create_namespace
    setup_container_registry
    prompt_for_secrets
    deploy
    show_status
}

main "$@"
