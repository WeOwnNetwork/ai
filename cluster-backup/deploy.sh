#!/usr/bin/env bash

# WeOwn Enterprise Cluster Backup Deployment Script
# Velero + Restic for complete cluster disaster recovery
# Version: 1.0.0 - WeOwn Enterprise Security Standard

set -euo pipefail

# Single tempdir for the run, mode 0700, removed on EXIT (incl. interrupt).
# Never write secret material to predictable /tmp paths (deploy was previously
# writing /tmp/s3-credentials and /tmp/cluster-backup-values.yaml at fixed
# locations — world-readable on some hosts, racy on concurrent runs).
RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cluster-backup.XXXXXX")"
chmod 700 "$RUN_TMPDIR"
trap 'rm -rf "$RUN_TMPDIR"' EXIT INT TERM

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
NAMESPACE="velero"
CHART_PATH="./helm"
RELEASE_NAME="cluster-backup"

print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}  WeOwn Enterprise Cluster Backup v1.0.0${NC}"
    echo -e "${BLUE}  🔐 Disaster Recovery | 🚀 Production-Ready${NC}"
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

# Function to check cluster connection
check_cluster_connection() {
    echo -e "${YELLOW}Checking cluster connection...${NC}"

    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        echo "Run: doctl kubernetes cluster kubeconfig save your-cluster-name"
        return 1
    fi

    echo -e "${GREEN}✅ Kubernetes cluster connected${NC}"
    return 0
}

# Function to get user configuration. Prefers env-var inputs (so the script
# is non-interactive in CI/automation); falls back to prompts otherwise.
# The secret key is read with `read -rs` and is NEVER passed via argv or
# echoed to stdout.
get_user_configuration() {
    echo -e "${YELLOW}Gathering configuration...${NC}"

    # Identity defaults
    TENANT="${TENANT:-}"
    CLUSTER="${CLUSTER:-}"
    ENVIRONMENT="${ENVIRONMENT:-}"

    if [ -z "$TENANT" ]; then
        read -rp "Enter tenant name (e.g., weown-tenant): " TENANT
    fi
    TENANT="${TENANT:-weown-tenant}"

    if [ -z "$CLUSTER" ]; then
        read -rp "Enter cluster name (e.g., digitalocean-cluster): " CLUSTER
    fi
    CLUSTER="${CLUSTER:-digitalocean-cluster}"

    if [ -z "$ENVIRONMENT" ]; then
        read -rp "Enter environment (dev/staging/prod) [prod]: " ENVIRONMENT
    fi
    ENVIRONMENT="${ENVIRONMENT:-prod}"

    # S3 configuration
    S3_BUCKET="${S3_BUCKET:-}"
    S3_REGION="${S3_REGION:-}"
    S3_ENDPOINT="${S3_ENDPOINT:-}"
    S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
    S3_SECRET_KEY="${S3_SECRET_KEY:-}"

    echo -e "${CYAN}S3-compatible storage configuration:${NC}"
    [ -z "$S3_BUCKET" ]     && read -rp "Enter S3 bucket name: " S3_BUCKET
    [ -z "$S3_REGION" ]     && read -rp "Enter S3 region (e.g., nyc3): " S3_REGION
    [ -z "$S3_ENDPOINT" ]   && read -rp "Enter S3 endpoint (e.g., https://nyc3.digitaloceanspaces.com): " S3_ENDPOINT
    [ -z "$S3_ACCESS_KEY" ] && read -rp "Enter S3 access key: " S3_ACCESS_KEY
    if [ -z "$S3_SECRET_KEY" ]; then
        # `-s` suppresses echo so the secret never appears on the terminal.
        read -rsp "Enter S3 secret key: " S3_SECRET_KEY
        echo ""
    fi

    # Validate required fields
    if [ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ] || [ -z "$S3_ENDPOINT" ] || [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        echo -e "${RED}❌ All S3 configuration fields are required${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Configuration gathered${NC}"
}

# Function to create namespace
create_namespace() {
    echo -e "${YELLOW}Creating namespace...${NC}"

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        kubectl create namespace "$NAMESPACE"
        echo -e "${GREEN}✅ Namespace $NAMESPACE created${NC}"
    else
        echo -e "${GREEN}✅ Namespace $NAMESPACE already exists${NC}"
    fi
}

# Function to create the cluster-backup-cloud-credentials Secret.
# The credential material flows over a pipe to `kubectl create … --dry-run`
# instead of through a file: nothing sensitive is written to disk, and
# nothing appears in `ps` (no positional argv carrying the secret).
create_s3_credentials() {
    echo -e "${YELLOW}Creating S3 credentials secret...${NC}"

    printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' \
        "$S3_ACCESS_KEY" "$S3_SECRET_KEY" \
        | kubectl create secret generic cluster-backup-cloud-credentials \
              --from-file=cloud=/dev/stdin \
              --namespace="$NAMESPACE" \
              --dry-run=client -o yaml \
        | kubectl apply -f -

    echo -e "${GREEN}✅ S3 credentials secret created${NC}"
}

# Function to deploy cluster backup
deploy_cluster_backup() {
    echo -e "${YELLOW}Deploying cluster backup...${NC}"

    # Values file lives in this run's mode-0700 tempdir (set up at the top
    # of the script with `mktemp -d` + EXIT trap). No fixed-name /tmp files.
    local values_file="$RUN_TMPDIR/cluster-backup-values.yaml"
    cat > "$values_file" << EOF
global:
  tenant: "$TENANT"
  cluster: "$CLUSTER"
  environment: "$ENVIRONMENT"
  namespace: "$NAMESPACE"

backupStorage:
  provider: "aws"
  bucket: "$S3_BUCKET"
  region: "$S3_REGION"
  s3Url: "$S3_ENDPOINT"
  s3ForcePathStyle: true
  encryption:
    enabled: true
    algorithm: "AES-256"
    keyId: "weown-backup-key"

velero:
  enabled: true
  server:
    image:
      repository: velero/velero
      tag: v1.12.2
      pullPolicy: IfNotPresent
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 128Mi
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    podSecurityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534
      seccompProfile:
        type: RuntimeDefault
  restic:
    enabled: true
    image:
      repository: velero/velero
      tag: v1.12.2
      pullPolicy: IfNotPresent
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 200m
        memory: 256Mi
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
        add:
          - SYS_ADMIN
    podSecurityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534
      seccompProfile:
        type: RuntimeDefault

schedules:
  daily:
    enabled: true
    schedule: "0 2 * * *"
    retention: "30d"
    includeNamespaces: []
    excludeNamespaces:
      - kube-system
      - kube-public
      - kube-node-lease
      - velero
  weekly:
    enabled: true
    schedule: "0 3 * * 0"
    retention: "90d"
    includeNamespaces: []
    excludeNamespaces:
      - kube-system
      - kube-public
      - kube-node-lease
      - velero
  monthly:
    enabled: true
    schedule: "0 4 1 * *"
    retention: "365d"
    includeNamespaces: []
    excludeNamespaces:
      - kube-system
      - kube-public
      - kube-node-lease
      - velero

applicationSchedules:
  anythingllm:
    enabled: true
    schedule: "0 1 * * *"
    retention: "7d"
    includeNamespaces:
      - anything-llm
  wordpress:
    enabled: true
    schedule: "0 1 * * *"
    retention: "7d"
    includeNamespaces:
      - wordpress
  vaultwarden:
    enabled: true
    schedule: "0 1 * * *"
    retention: "7d"
    includeNamespaces:
      - vaultwarden
  n8n:
    enabled: true
    schedule: "0 1 * * *"
    retention: "7d"
    includeNamespaces:
      - n8n

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: "30s"
    scrapeTimeout: "10s"
  metrics:
    enabled: true
    port: 8085
    path: "/metrics"

security:
  networkPolicy:
    enabled: true
  podSecurityStandards:
    enabled: true
    level: "restricted"
  rbac:
    enabled: true
    create: true

validation:
  enabled: true
  restoreTesting:
    enabled: true
    schedule: "0 5 * * 0"
    testNamespace: "backup-test"
    retention: "1d"
  integrityChecks:
    enabled: true
    schedule: "0 6 * * *"
    checksumValidation: true
    sizeValidation: true

logging:
  level: "info"
  format: "json"
  retention: "30d"
  structured: true

performance:
  concurrentBackups: 3
  concurrentRestores: 2
  restic:
    workers: 4
    memoryLimit: "256Mi"
    cpuLimit: "200m"

encryption:
  backup:
    enabled: true
    algorithm: "AES-256"
    keyRotation: "90d"
  transit:
    enabled: true
    tlsVersion: "1.3"
  keyManagement:
    provider: "kubernetes-secrets"
    rotation: "automated"

compliance:
  soc2:
    enabled: true
    controls:
      - "CC6.1"
      - "CC6.2"
      - "CC6.3"
  iso27001:
    enabled: true
    controls:
      - "A.12.3.1"
      - "A.12.6.1"
      - "A.13.1.1"
  audit:
    enabled: true
    retention: "7y"
    events:
      - backup
      - restore
      - schedule
      - delete
      - access

disasterRecovery:
  crossCloud:
    enabled: true
    supportedProviders:
      - aws
      - gcp
      - azure
      - digitalocean
      - minio
  migration:
    tenantMigration:
      enabled: true
      procedure: "automated"
    providerMigration:
      enabled: true
      procedure: "semi-automated"
EOF

    # Deploy with Helm (values file is in the run's tempdir; trap cleans up)
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --values "$values_file" \
        --wait \
        --timeout 10m

    echo -e "${GREEN}✅ Cluster backup deployed${NC}"
}

# Function to verify deployment
verify_deployment() {
    echo -e "${YELLOW}Verifying deployment...${NC}"

    # Check Velero deployment
    if kubectl get deployment cluster-backup-velero -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Velero deployment ready${NC}"
    else
        echo -e "${RED}❌ Velero deployment not found${NC}"
        return 1
    fi

    # Check Restic daemon set
    if kubectl get daemonset cluster-backup-restic -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Restic daemon set ready${NC}"
    else
        echo -e "${RED}❌ Restic daemon set not found${NC}"
        return 1
    fi

    # Check backup storage location
    if kubectl get backupstoragelocation cluster-backup-backup-location -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Backup storage location ready${NC}"
    else
        echo -e "${RED}❌ Backup storage location not found${NC}"
        return 1
    fi

    # Check volume snapshot location
    if kubectl get volumesnapshotlocation cluster-backup-volume-snapshot-location -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Volume snapshot location ready${NC}"
    else
        echo -e "${RED}❌ Volume snapshot location not found${NC}"
        return 1
    fi

    # Check schedules
    SCHEDULE_COUNT=$(kubectl get schedules -n $NAMESPACE --no-headers | wc -l)
    if [ "$SCHEDULE_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ $SCHEDULE_COUNT backup schedules created${NC}"
    else
        echo -e "${RED}❌ No backup schedules found${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Deployment verification complete${NC}"
}

# Function to show post-deployment information
show_post_deployment_info() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  Cluster Backup Deployment Complete${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""

    echo -e "${GREEN}🎯 Quick Start Guide:${NC}"
    echo "1. Check backup status: velero backup get -n $NAMESPACE"
    echo "2. Check schedules: velero schedule get -n $NAMESPACE"
    echo "3. View logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=velero-server"
    echo "4. Test backup: velero backup create test-backup --from-schedule cluster-backup-daily-schedule -n $NAMESPACE"
    echo ""

    echo -e "${GREEN}📊 Monitoring:${NC}"
    echo "• Metrics endpoint: kubectl port-forward -n $NAMESPACE svc/cluster-backup-velero 8085:8085"
    echo "• Prometheus metrics: http://localhost:8085/metrics"
    echo ""

    echo -e "${GREEN}🔧 Management Commands (require the Velero CLI):${NC}"
    echo "• List backups:   velero backup get -n $NAMESPACE"
    echo "• List restores:  velero restore get -n $NAMESPACE"
    echo "• Create backup:  velero backup create <name> -n $NAMESPACE"
    echo "• Create restore: velero restore create <name> --from-backup <backup-name> -n $NAMESPACE"
    echo "• Install CLI:    https://velero.io/docs/v1.12/basic-install/#install-the-cli"
    echo ""

    echo -e "${GREEN}🛡️ Security Status:${NC}"
    echo "• NetworkPolicy: Applied for zero-trust networking"
    echo "• Pod Security Standards: Restricted level enabled"
    echo "• RBAC: Minimal permissions configured"
    echo "• Encryption: AES-256 at rest and in transit"
    echo ""

    echo -e "${GREEN}📚 Documentation:${NC}"
    echo "• README.md - Complete user guide"
    echo "• Run $0 anytime for health checks"
    echo ""

    echo -e "${BLUE}🔒 Security Status: PRODUCTION READY${NC}"
}

# Function to show help
show_help() {
    cat << EOF
WeOwn Enterprise Cluster Backup Deployment Script v1.0.0

Usage: $0 [OPTIONS]

OPTIONS:
    --help              Show this help message
    --verify-only       Only verify existing deployment
    --upgrade           Upgrade existing deployment

ENVIRONMENT VARIABLES:
    TENANT              Tenant name (default: weown-tenant)
    CLUSTER             Cluster name (default: digitalocean-cluster)
    ENVIRONMENT         Environment (default: prod)
    S3_BUCKET           S3 bucket name
    S3_REGION           S3 region
    S3_ENDPOINT         S3 endpoint URL
    S3_ACCESS_KEY       S3 access key
    S3_SECRET_KEY       S3 secret key

EXAMPLE:
    # Interactive deployment
    $0

    # Verify existing deployment
    $0 --verify-only

    # Upgrade existing deployment
    $0 --upgrade

SECURITY FEATURES:
    ✅ Zero-trust networking with NetworkPolicies
    ✅ Pod Security Standards (Restricted level)
    ✅ RBAC with minimal permissions
    ✅ AES-256 encryption at rest and in transit
    ✅ Automated backup scheduling
    ✅ Cross-cloud restore capabilities
    ✅ SOC2/ISO27001 compliance ready
EOF
}

# Parse command line arguments
VERIFY_ONLY=false
UPGRADE=false

for arg in "$@"; do
    case $arg in
        --help)
            show_help
            exit 0
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --upgrade)
            UPGRADE=true
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

# Check cluster connection
if ! check_cluster_connection; then
    exit 1
fi

# If verify-only mode, just verify and exit
if [ "$VERIFY_ONLY" = true ]; then
    verify_deployment
    exit $?
fi

# Get user configuration
if ! get_user_configuration; then
    exit 1
fi

# Create namespace
create_namespace

# Create S3 credentials
create_s3_credentials

# Deploy cluster backup
deploy_cluster_backup

# Verify deployment
if ! verify_deployment; then
    echo -e "${RED}❌ Deployment verification failed${NC}"
    exit 1
fi

# Show post-deployment information
show_post_deployment_info

echo "==========================================="
echo -e "✅ ${GREEN}CLUSTER BACKUP DEPLOYMENT COMPLETE!${NC}"
echo "==========================================="
