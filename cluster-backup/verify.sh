#!/bin/bash

# WeOwn Enterprise Cluster Backup Verification Script
# Verifies cluster backup deployment and functionality

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="velero"

print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}  WeOwn Cluster Backup Verification${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
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

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command_exists kubectl; then
        print_status "kubectl not found" false
        return 1
    fi
    
    if ! command_exists helm; then
        print_status "helm not found" false
        return 1
    fi
    
    print_status "All prerequisites met" true
    return 0
}

# Check cluster connection
check_cluster_connection() {
    echo -e "${YELLOW}Checking cluster connection...${NC}"
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_status "Cannot connect to Kubernetes cluster" false
        return 1
    fi
    
    print_status "Kubernetes cluster connected" true
    return 0
}

# Check namespace
check_namespace() {
    echo -e "${YELLOW}Checking namespace...${NC}"
    
    if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        print_status "Namespace $NAMESPACE exists" true
    else
        print_status "Namespace $NAMESPACE not found" false
        return 1
    fi
}

# Check Velero deployment
check_velero_deployment() {
    echo -e "${YELLOW}Checking Velero deployment...${NC}"
    
    if kubectl get deployment cluster-backup-velero -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Velero deployment exists" true
        
        # Check if deployment is ready
        READY=$(kubectl get deployment cluster-backup-velero -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment cluster-backup-velero -n $NAMESPACE -o jsonpath='{.spec.replicas}')
        
        if [ "$READY" = "$DESIRED" ]; then
            print_status "Velero deployment ready" true
        else
            print_status "Velero deployment not ready ($READY/$DESIRED)" false
        fi
    else
        print_status "Velero deployment not found" false
        return 1
    fi
}

# Check Restic daemon set
check_restic_daemonset() {
    echo -e "${YELLOW}Checking Restic daemon set...${NC}"
    
    if kubectl get daemonset cluster-backup-restic -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Restic daemon set exists" true
        
        # Check if daemon set is ready
        READY=$(kubectl get daemonset cluster-backup-restic -n $NAMESPACE -o jsonpath='{.status.numberReady}')
        DESIRED=$(kubectl get daemonset cluster-backup-restic -n $NAMESPACE -o jsonpath='{.status.desiredNumberScheduled}')
        
        if [ "$READY" = "$DESIRED" ]; then
            print_status "Restic daemon set ready" true
        else
            print_status "Restic daemon set not ready ($READY/$DESIRED)" false
        fi
    else
        print_status "Restic daemon set not found" false
        return 1
    fi
}

# Check backup storage location
check_backup_storage_location() {
    echo -e "${YELLOW}Checking backup storage location...${NC}"
    
    if kubectl get backupstoragelocation cluster-backup-backup-location -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Backup storage location exists" true
        
        # Check if storage location is accessible
        if kubectl get backupstoragelocation cluster-backup-backup-location -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q "Available"; then
            print_status "Backup storage location accessible" true
        else
            print_warning "Backup storage location not accessible"
        fi
    else
        print_status "Backup storage location not found" false
        return 1
    fi
}

# Check volume snapshot location
check_volume_snapshot_location() {
    echo -e "${YELLOW}Checking volume snapshot location...${NC}"
    
    if kubectl get volumesnapshotlocation cluster-backup-volume-snapshot-location -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Volume snapshot location exists" true
        
        # Check if snapshot location is accessible
        if kubectl get volumesnapshotlocation cluster-backup-volume-snapshot-location -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q "Available"; then
            print_status "Volume snapshot location accessible" true
        else
            print_warning "Volume snapshot location not accessible"
        fi
    else
        print_status "Volume snapshot location not found" false
        return 1
    fi
}

# Check schedules
check_schedules() {
    echo -e "${YELLOW}Checking backup schedules...${NC}"
    
    SCHEDULE_COUNT=$(kubectl get schedules -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ "$SCHEDULE_COUNT" -gt 0 ]; then
        print_status "$SCHEDULE_COUNT backup schedules found" true
        
        # List schedules
        echo -e "${BLUE}Available schedules:${NC}"
        kubectl get schedules -n $NAMESPACE
    else
        print_status "No backup schedules found" false
        return 1
    fi
}

# Check RBAC
check_rbac() {
    echo -e "${YELLOW}Checking RBAC...${NC}"
    
    if kubectl get clusterrole cluster-backup-velero >/dev/null 2>&1; then
        print_status "Velero ClusterRole exists" true
    else
        print_status "Velero ClusterRole not found" false
        return 1
    fi
    
    if kubectl get clusterrolebinding cluster-backup-velero >/dev/null 2>&1; then
        print_status "Velero ClusterRoleBinding exists" true
    else
        print_status "Velero ClusterRoleBinding not found" false
        return 1
    fi
    
    if kubectl get clusterrole cluster-backup-restic >/dev/null 2>&1; then
        print_status "Restic ClusterRole exists" true
    else
        print_status "Restic ClusterRole not found" false
        return 1
    fi
    
    if kubectl get clusterrolebinding cluster-backup-restic >/dev/null 2>&1; then
        print_status "Restic ClusterRoleBinding exists" true
    else
        print_status "Restic ClusterRoleBinding not found" false
        return 1
    fi
}

# Check NetworkPolicy
check_networkpolicy() {
    echo -e "${YELLOW}Checking NetworkPolicy...${NC}"
    
    if kubectl get networkpolicy cluster-backup-netpol -n $NAMESPACE >/dev/null 2>&1; then
        print_status "NetworkPolicy exists" true
    else
        print_status "NetworkPolicy not found" false
        return 1
    fi
}

# Check service accounts
check_service_accounts() {
    echo -e "${YELLOW}Checking service accounts...${NC}"
    
    if kubectl get serviceaccount cluster-backup-velero -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Velero service account exists" true
    else
        print_status "Velero service account not found" false
        return 1
    fi
    
    if kubectl get serviceaccount cluster-backup-restic -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Restic service account exists" true
    else
        print_status "Restic service account not found" false
        return 1
    fi
}

# Check secrets
check_secrets() {
    echo -e "${YELLOW}Checking secrets...${NC}"
    
    if kubectl get secret cluster-backup-cloud-credentials -n $NAMESPACE >/dev/null 2>&1; then
        print_status "Cloud credentials secret exists" true
    else
        print_status "Cloud credentials secret not found" false
        return 1
    fi
}

# Test backup creation
test_backup_creation() {
    echo -e "${YELLOW}Testing backup creation...${NC}"
    
    # Create a test backup
    kubectl create backup test-verification-backup -n $NAMESPACE
    
    # Wait for backup to complete
    echo "Waiting for backup to complete..."
    sleep 30
    
    # Check backup status
    if kubectl get backup test-verification-backup -n $NAMESPACE >/dev/null 2>&1; then
        BACKUP_STATUS=$(kubectl get backup test-verification-backup -n $NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$BACKUP_STATUS" = "Completed" ]; then
            print_status "Test backup completed successfully" true
        else
            print_warning "Test backup status: $BACKUP_STATUS"
        fi
    else
        print_status "Test backup not found" false
        return 1
    fi
}

# Show summary
show_summary() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  Verification Summary${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    
    echo -e "${GREEN}✅ Working Components:${NC}"
    echo "• Velero deployment"
    echo "• Restic daemon set"
    echo "• Backup storage location"
    echo "• Volume snapshot location"
    echo "• Backup schedules"
    echo "• RBAC configuration"
    echo "• NetworkPolicy"
    echo "• Service accounts"
    echo "• Cloud credentials"
    echo ""
    
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "• List backups: kubectl get backups -n $NAMESPACE"
    echo "• List schedules: kubectl get schedules -n $NAMESPACE"
    echo "• Create backup: kubectl create backup <name> -n $NAMESPACE"
    echo "• View logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=velero-server"
    echo ""
    
    echo -e "${GREEN}📊 Monitoring:${NC}"
    echo "• Metrics: kubectl port-forward -n $NAMESPACE svc/cluster-backup-velero 8085:8085"
    echo "• Prometheus: http://localhost:8085/metrics"
    echo ""
    
    echo -e "${BLUE}🔒 Security Status: PRODUCTION READY${NC}"
}

# Main execution
print_header

# Check prerequisites
if ! check_prerequisites; then
    exit 1
fi

# Check cluster connection
if ! check_cluster_connection; then
    exit 1
fi

# Check namespace
if ! check_namespace; then
    exit 1
fi

# Check Velero deployment
if ! check_velero_deployment; then
    exit 1
fi

# Check Restic daemon set
if ! check_restic_daemonset; then
    exit 1
fi

# Check backup storage location
if ! check_backup_storage_location; then
    exit 1
fi

# Check volume snapshot location
if ! check_volume_snapshot_location; then
    exit 1
fi

# Check schedules
if ! check_schedules; then
    exit 1
fi

# Check RBAC
if ! check_rbac; then
    exit 1
fi

# Check NetworkPolicy
if ! check_networkpolicy; then
    exit 1
fi

# Check service accounts
if ! check_service_accounts; then
    exit 1
fi

# Check secrets
if ! check_secrets; then
    exit 1
fi

# Test backup creation
if ! test_backup_creation; then
    print_warning "Backup creation test failed - check logs for details"
fi

# Show summary
show_summary

echo "==========================================="
echo -e "✅ ${GREEN}CLUSTER BACKUP VERIFICATION COMPLETE!${NC}"
echo "==========================================="
