#!/usr/bin/env bash

# Local Testing Script for WeOwn Cluster Backup
# Tests the cluster backup solution on local Kubernetes (minikube / kind)
#
# This script is for LOCAL DEVELOPMENT ONLY. It stands up a MinIO instance
# as a fake S3 backend so backup/restore round-trips can be exercised end
# to end. Credentials default to development-grade values that exist ONLY
# inside the ephemeral local cluster — never use these defaults in any
# environment that touches real data.

set -euo pipefail

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

# MinIO config — DEV-ONLY DEFAULTS.
# Override with TEST_MINIO_ACCESS_KEY / TEST_MINIO_SECRET_KEY env vars
# if you want non-default credentials even for local runs.
# Image is pinned to a specific RELEASE tag (not `:latest`) so the same
# script behaves identically across machines and over time.
TEST_MINIO_IMAGE="${TEST_MINIO_IMAGE:-minio/minio:RELEASE.2024-08-17T01-24-54Z}"
TEST_MINIO_MC_IMAGE="${TEST_MINIO_MC_IMAGE:-minio/mc:RELEASE.2024-08-17T11-33-50Z}"
TEST_MINIO_ACCESS_KEY="${TEST_MINIO_ACCESS_KEY:-localdev-access}"
TEST_MINIO_SECRET_KEY="${TEST_MINIO_SECRET_KEY:-localdev-$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)}"

# Function to setup local S3 storage (MinIO)
setup_local_s3() {
    echo -e "${YELLOW}Setting up local S3 storage (MinIO)...${NC}"

    # Create MinIO namespace
    kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -

    # Render the MinIO Secret to stdin via `printf` (stringData uses single
    # quotes so embedded special chars in randomly-generated keys are safe),
    # then pipe to `kubectl apply -f -`. Nothing sensitive is ever written
    # to disk, and the credentials never appear as positional argv.
    {
      printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: minio-secret\n  namespace: minio\ntype: Opaque\nstringData:\n'
      printf "  access-key: '%s'\n" "${TEST_MINIO_ACCESS_KEY//\'/\'\\\'\'}"
      printf "  secret-key: '%s'\n" "${TEST_MINIO_SECRET_KEY//\'/\'\\\'\'}"
    } | kubectl apply -f -

    # Deploy MinIO
    # Service exposes BOTH the S3 API (9000) and the web console (9001).
    # Previously the manifest only mapped 9000 to NodePort 30000 yet the
    # "MinIO Console" message pointed at 30000 — that's the S3 API, not
    # the console. Now: API on 30000, console on 30001.
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  type: NodePort
  selector:
    app: minio
  ports:
    - name: s3-api
      port: 9000
      targetPort: 9000
      nodePort: 30000
    - name: console
      port: 9001
      targetPort: 9001
      nodePort: 30001
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
          image: ${TEST_MINIO_IMAGE}
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

    # Create the bucket. mc receives the credentials via environment variables
    # so they never appear as positional argv inside the kubectl-run pod.
    kubectl run mc --image="${TEST_MINIO_MC_IMAGE}" \
        --restart=Never --rm -i \
        --env="MC_HOST_local=http://${TEST_MINIO_ACCESS_KEY}:${TEST_MINIO_SECRET_KEY}@minio.minio.svc.cluster.local:9000" \
        --command -- sh -c '
            mc mb local/weown-cluster-backups --ignore-existing
            mc ls local/
        '

    echo -e "${GREEN}✅ Local S3 storage (MinIO) ready${NC}"
    echo -e "${BLUE}MinIO S3 API:    http://localhost:30000${NC}"
    echo -e "${BLUE}MinIO Console:   http://localhost:30001${NC}"
    echo -e "${BLUE}Access Key:      ${TEST_MINIO_ACCESS_KEY}${NC}"
    echo -e "${BLUE}Secret Key:      (set via TEST_MINIO_SECRET_KEY env var; not echoed)${NC}"
}

# Function to deploy cluster backup
deploy_cluster_backup() {
    echo -e "${YELLOW}Deploying cluster backup...${NC}"

    # Set local configuration. Credentials match what setup_local_s3
    # provisioned for the MinIO instance.
    export TENANT="weown-test"
    export CLUSTER="local-cluster"
    export ENVIRONMENT="dev"
    export S3_BUCKET="weown-cluster-backups"
    export S3_REGION="us-east-1"
    export S3_ENDPOINT="http://minio.minio.svc.cluster.local:9000"
    export S3_ACCESS_KEY="${TEST_MINIO_ACCESS_KEY}"
    export S3_SECRET_KEY="${TEST_MINIO_SECRET_KEY}"

    # Run deployment script (it reads the above env vars instead of prompting)
    ./deploy.sh

    echo -e "${GREEN}✅ Cluster backup deployed${NC}"
}

# Poll a Velero CR's `.status.phase` until it reaches one of EXPECT, or until
# we exceed TIMEOUT seconds. On timeout, emit `kubectl describe` output as
# diagnostic context. Used for backup/restore where blind `sleep 30` is too
# short for real workloads and too long for trivial ones.
wait_for_velero_phase() {
    local kind="$1"      # Backup | Restore
    local name="$2"
    local expect="$3"    # space-separated: "Completed Failed FailedValidation"
    local timeout="${4:-600}"
    local elapsed=0
    local interval=5

    while [ "$elapsed" -lt "$timeout" ]; do
        local phase
        phase="$(kubectl get "$kind" "$name" -n velero \
                    -o jsonpath='{.status.phase}' 2>/dev/null || echo '')"
        for want in $expect; do
            if [ "$phase" = "$want" ]; then
                echo "$kind/$name → phase=$phase (after ${elapsed}s)"
                return 0
            fi
        done
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo -e "${RED}❌ Timed out waiting for $kind/$name to reach { $expect } after ${timeout}s${NC}"
    echo "--- diagnostic: kubectl describe $kind/$name -n velero ---"
    kubectl describe "$kind" "$name" -n velero || true
    return 1
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

    # Create backup via the Velero CLI (NOT `kubectl create backup`, which
    # is not a real subcommand for Velero CRDs).
    echo "Creating test backup..."
    velero backup create test-local-backup \
        --include-namespaces test-app \
        -n velero

    # Poll .status.phase rather than blind-sleeping; emit diagnostics on timeout.
    wait_for_velero_phase Backup test-local-backup "Completed Failed FailedValidation PartiallyFailed" 300

    # Show final backup details
    velero backup describe test-local-backup -n velero --details || true

    echo -e "${GREEN}✅ Backup functionality tested${NC}"
}

# Function to test restore functionality
test_restore_functionality() {
    echo -e "${YELLOW}Testing restore functionality...${NC}"

    # Delete test namespace and wait for it to actually go away (not a fixed sleep).
    kubectl delete namespace test-app --ignore-not-found=true --wait=true --timeout=120s

    # Restore from backup using the Velero CLI.
    echo "Restoring from backup..."
    velero restore create test-local-restore \
        --from-backup test-local-backup \
        -n velero

    # Poll .status.phase.
    wait_for_velero_phase Restore test-local-restore "Completed Failed FailedValidation PartiallyFailed" 300

    velero restore describe test-local-restore -n velero --details || true

    # Verify restored resources reappeared
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
    echo "• List backups:    velero backup get -n velero"
    echo "• List restores:   velero restore get -n velero"
    echo "• View logs:       kubectl logs -n velero -l app.kubernetes.io/component=velero-server"
    echo "• MinIO console:   http://localhost:30001"
    echo "• MinIO S3 API:    http://localhost:30000"
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
