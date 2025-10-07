#!/bin/bash

# Local Testing Script for WeOwn Cluster Backup
# Tests the cluster backup solution on local Kubernetes

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}  WeOwn Cluster Backup - Local Testing${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing_tools=()
    
    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm >/dev/null 2>&1; then
        missing_tools+=("helm")
    fi
    
    if ! command -v minikube >/dev/null 2>&1 && ! command -v kind >/dev/null 2>&1; then
        missing_tools+=("minikube or kind")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Install instructions:${NC}"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                kubectl) echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/" ;;
                helm) echo "  - helm: https://helm.sh/docs/intro/install/" ;;
                "minikube or kind") echo "  - minikube: https://minikube.sigs.k8s.io/docs/start/" ;;
            esac
        done
        return 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
    return 0
}

# Function to start local cluster
start_local_cluster() {
    echo -e "${YELLOW}Starting local Kubernetes cluster...${NC}"
    
    if command -v minikube >/dev/null 2>&1; then
        echo "Using Minikube..."
        minikube start --memory=4096 --cpus=2 --driver=docker
        minikube addons enable storage-provisioner
        minikube addons enable default-storageclass
    elif command -v kind >/dev/null 2>&1; then
        echo "Using kind..."
        kind create cluster --name weown-test --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF
    else
        echo -e "${RED}❌ No local Kubernetes cluster found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Local cluster started${NC}"
}

# Function to setup local S3 storage (MinIO)
setup_local_s3() {
    echo -e "${YELLOW}Setting up local S3 storage (MinIO)...${NC}"
    
    # Create MinIO namespace
    kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy MinIO
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: minio
type: Opaque
data:
  access-key: bWluaW9hZG1pbg==  # minioadmin
  secret-key: bWluaW9hZG1pbg==  # minioadmin
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  type: NodePort
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30000
  selector:
    app: minio
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        command:
        - minio
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: access-key
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: secret-key
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
EOF
    
    # Wait for MinIO to be ready
    echo "Waiting for MinIO to be ready..."
    kubectl wait --for=condition=available deployment/minio -n minio --timeout=300s
    
    # Create bucket
    kubectl run mc --image=minio/mc --rm -i --restart=Never --command -- sh -c "
      mc alias set local http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin
      mc mb local/weown-cluster-backups --ignore-existing
      mc ls local/
    "
    
    echo -e "${GREEN}✅ Local S3 storage (MinIO) ready${NC}"
    echo -e "${BLUE}MinIO Console: http://localhost:30000${NC}"
    echo -e "${BLUE}Access Key: minioadmin${NC}"
    echo -e "${BLUE}Secret Key: minioadmin${NC}"
}

# Function to deploy cluster backup
deploy_cluster_backup() {
    echo -e "${YELLOW}Deploying cluster backup...${NC}"
    
    # Set local configuration
    export TENANT="weown-test"
    export CLUSTER="local-cluster"
    export ENVIRONMENT="dev"
    export S3_BUCKET="weown-cluster-backups"
    export S3_REGION="us-east-1"
    export S3_ENDPOINT="http://minio.minio.svc.cluster.local:9000"
    export S3_ACCESS_KEY="minioadmin"
    export S3_SECRET_KEY="minioadmin"
    
    # Run deployment script
    ./deploy.sh
    
    echo -e "${GREEN}✅ Cluster backup deployed${NC}"
}

# Function to test backup functionality
test_backup_functionality() {
    echo -e "${YELLOW}Testing backup functionality...${NC}"
    
    # Create test namespace and deployment
    kubectl create namespace test-app --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-app
  namespace: test-app
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config
  namespace: test-app
data:
  test-key: "test-value"
---
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: test-app
type: Opaque
data:
  test-secret: dGVzdC1zZWNyZXQ=  # test-secret
EOF
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available deployment/test-app -n test-app --timeout=300s
    
    # Create backup
    echo "Creating test backup..."
    kubectl create backup test-local-backup --include-namespaces test-app -n velero
    
    # Wait for backup to complete
    echo "Waiting for backup to complete..."
    sleep 30
    
    # Check backup status
    kubectl get backup test-local-backup -n velero
    
    echo -e "${GREEN}✅ Backup functionality tested${NC}"
}

# Function to test restore functionality
test_restore_functionality() {
    echo -e "${YELLOW}Testing restore functionality...${NC}"
    
    # Delete test namespace
    kubectl delete namespace test-app --ignore-not-found=true
    
    # Wait a moment
    sleep 10
    
    # Restore from backup
    echo "Restoring from backup..."
    kubectl create restore test-local-restore --from-backup test-local-backup -n velero
    
    # Wait for restore to complete
    echo "Waiting for restore to complete..."
    sleep 30
    
    # Check restore status
    kubectl get restore test-local-restore -n velero
    
    # Verify restored resources
    kubectl get all -n test-app
    kubectl get configmap test-config -n test-app
    kubectl get secret test-secret -n test-app
    
    echo -e "${GREEN}✅ Restore functionality tested${NC}"
}

# Function to show test results
show_test_results() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  Local Testing Results${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    
    echo -e "${GREEN}✅ Tested Components:${NC}"
    echo "• Local Kubernetes cluster (Minikube/kind)"
    echo "• Local S3 storage (MinIO)"
    echo "• Cluster backup deployment"
    echo "• Backup functionality"
    echo "• Restore functionality"
    echo ""
    
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "• List backups: kubectl get backups -n velero"
    echo "• List restores: kubectl get restores -n velero"
    echo "• View logs: kubectl logs -n velero -l app.kubernetes.io/component=velero-server"
    echo "• MinIO console: http://localhost:30000"
    echo ""
    
    echo -e "${GREEN}🧹 Cleanup Commands:${NC}"
    echo "• Stop Minikube: minikube stop"
    echo "• Delete Minikube: minikube delete"
    echo "• Stop kind: kind delete cluster --name weown-test"
    echo ""
    
    echo -e "${BLUE}🔒 Local Testing: COMPLETE${NC}"
}

# Main execution
print_header

# Check prerequisites
if ! check_prerequisites; then
    exit 1
fi

# Start local cluster
if ! start_local_cluster; then
    exit 1
fi

# Setup local S3
if ! setup_local_s3; then
    exit 1
fi

# Deploy cluster backup
if ! deploy_cluster_backup; then
    exit 1
fi

# Test backup functionality
if ! test_backup_functionality; then
    echo -e "${RED}❌ Backup test failed${NC}"
    exit 1
fi

# Test restore functionality
if ! test_restore_functionality; then
    echo -e "${RED}❌ Restore test failed${NC}"
    exit 1
fi

# Show test results
show_test_results

echo "==========================================="
echo -e "✅ ${GREEN}LOCAL TESTING COMPLETE!${NC}"
echo "==========================================="

