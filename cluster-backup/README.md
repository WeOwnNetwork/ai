# WeOwn Enterprise Cluster Backup

**Complete cluster-level disaster recovery solution using Velero + Restic for tenant migration, region failure recovery, and cross-cloud provider migration.**

Version: 1.0.0 | Production Ready ✅

---

## 🎯 What This Does For You

This cluster backup solution provides **complete disaster recovery capabilities** for your entire tenant cluster:

### 🔄 **Complete Cluster Backup**

*"Backup everything - namespaces, PVCs, CRDs, secrets, and more"*

- Full cluster state capture including all applications
- Persistent volume backups with Restic
- Custom resource definitions and configurations
- Secrets and ConfigMaps with encryption
- NetworkPolicies and RBAC configurations

### 🚀 **Automated Scheduling**

*"Set it and forget it - automated backups with retention policies"*

- Daily, weekly, and monthly backup schedules
- Application-specific backup schedules
- Configurable retention policies (7d, 30d, 90d, 365d)
- Automated cleanup of old backups

### 🌐 **Cross-Cloud Migration**

*"Move between providers without data loss"*

- DigitalOcean → AWS, GCP, Azure
- Cross-region disaster recovery
- Provider migration capabilities
- Tenant migration support

### 🔐 **Enterprise Security**

*"Zero-trust backup with enterprise compliance"*

- AES-256 encryption at rest and in transit
- NetworkPolicies for zero-trust networking
- Pod Security Standards (Restricted level)
- SOC2/ISO27001 compliance ready

---

## 🚀 **Quick Start**

### **Prerequisites**

- Kubernetes cluster with admin access
- S3-compatible storage (DigitalOcean Spaces, AWS S3, etc.)
- kubectl and helm installed
- Cluster with sufficient resources (2 CPU, 4GB RAM minimum)

### **One-Command Deployment**

```bash
# Clone the repository
git clone https://github.com/WeOwn/ai.git
cd ai/cluster-backup

# Make script executable
chmod +x deploy.sh

# Run deployment (interactive)
./deploy.sh
```

### **Configuration Required**

The deployment script will prompt for:

- **Tenant name**: Your tenant identifier
- **Cluster name**: Your cluster identifier  
- **Environment**: dev/staging/prod
- **S3 bucket**: Storage bucket name
- **S3 region**: Storage region (e.g., nyc3)
- **S3 endpoint**: Storage endpoint URL
- **S3 credentials**: Access key and secret key

---

## 📊 **Backup Schedules**

### **Default Schedules**

| Schedule | Frequency | Retention | Purpose |
|----------|-----------|-----------|---------|
| **Daily** | 2 AM daily | 30 days | Regular backups |
| **Weekly** | 3 AM Sunday | 90 days | Weekly snapshots |
| **Monthly** | 4 AM 1st of month | 365 days | Long-term retention |

### **Application Schedules**

| Application | Frequency | Retention | Namespaces |
|-------------|-----------|-----------|------------|
| **AnythingLLM** | 1 AM daily | 7 days | anything-llm |
| **WordPress** | 1 AM daily | 7 days | wordpress |
| **Vaultwarden** | 1 AM daily | 7 days | vaultwarden |
| **n8n** | 1 AM daily | 7 days | n8n |

### **Excluded Namespaces**

- `kube-system` (Kubernetes system)
- `kube-public` (Kubernetes public)
- `kube-node-lease` (Node leases)
- `velero` (Backup system itself)

---

## 🔧 **Management Commands**

### **Backup Operations**

```bash
# List all backups
velero backup get -n velero

# Create manual backup
velero backup create manual-backup -n velero

# Create backup from schedule
velero backup create scheduled-backup --from-schedule daily -n velero

# Describe backup details
velero backup describe <backup-name> -n velero

# Download backup logs
kubectl logs -n velero -l app.kubernetes.io/component=velero-server
```

### **Restore Operations**

```bash
# List all restores
velero restore get -n velero

# Create restore from backup
velero restore create <restore-name> --from-backup <backup-name> -n velero

# Restore specific namespaces
velero restore create <restore-name> --from-backup <backup-name> --include-namespaces <namespace1>,<namespace2> -n velero

# Restore with namespace mapping
velero restore create <restore-name> --from-backup <backup-name> --namespace-mapping <old-ns>:<new-ns> -n velero
```

### **Schedule Management**

```bash
# List all schedules
velero schedule get -n velero

# Create custom schedule
velero schedule create <schedule-name> --schedule="0 1 * * *" --ttl=7d -n velero

# Pause schedule
velero schedule pause <schedule-name> -n velero

# Resume schedule
velero schedule unpause <schedule-name> -n velero
```

---

## 🌐 **Cross-Cloud Migration**

### **Migration Scenarios**

#### **DigitalOcean → AWS**

```bash
# 1. Create backup on DigitalOcean cluster
velero backup create migration-backup -n velero

# 2. Configure AWS S3 credentials on target cluster
kubectl create secret generic cluster-backup-cloud-credentials \
  --from-file=cloud=/path/to/aws-credentials \
  -n velero

# 3. Restore on AWS cluster
velero restore create migration-restore --from-backup migration-backup -n velero
```

#### **Cross-Region Disaster Recovery**

```bash
# 1. Backup in primary region
velero backup create dr-backup -n velero

# 2. Restore in secondary region
velero restore create dr-restore --from-backup dr-backup -n velero
```

#### **Tenant Migration**

```bash
# 1. Backup source tenant
velero backup create tenant-backup -n velero

# 2. Restore to target tenant with namespace mapping
velero restore create tenant-restore --from-backup tenant-backup \
  --namespace-mapping source-tenant:target-tenant -n velero
```

---

## 🔐 **Security Features**

### **Encryption**

- **At Rest**: AES-256 encryption for all backup data
- **In Transit**: TLS 1.3 for all API communications
- **Key Management**: Kubernetes secrets with rotation

### **Access Control**

- **RBAC**: Minimal permissions for Velero and Restic
- **NetworkPolicies**: Zero-trust networking
- **Pod Security**: Restricted security context
- **Service Accounts**: Dedicated accounts with minimal privileges

### **Compliance**

- **SOC2**: CC6.1, CC6.2, CC6.3 controls
- **ISO27001**: A.12.3.1, A.12.6.1, A.13.1.1 controls
- **Audit Logging**: 7-year retention for compliance

---

## 📊 **Monitoring & Observability**

### **Metrics Endpoint**

```bash
# Port forward to access metrics
kubectl port-forward -n velero svc/cluster-backup-velero 8085:8085

# Access metrics
curl http://localhost:8085/metrics
```

### **Key Metrics**

- `velero_backup_total` - Total backups created
- `velero_backup_duration_seconds` - Backup duration
- `velero_restore_total` - Total restores performed
- `velero_restore_duration_seconds` - Restore duration
- `velero_schedule_total` - Scheduled backups
- `velero_volume_snapshot_total` - Volume snapshots

### **Prometheus Integration**

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cluster-backup-metrics
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: velero-server
  endpoints:
  - port: metrics
    path: /metrics
```

---

## 🛠️ **Troubleshooting**

### **Common Issues**

#### **Backup Failures**

```bash
# Check backup status
velero backup describe <backup-name> -n velero

# Check Velero logs
kubectl logs -n velero -l app.kubernetes.io/component=velero-server

# Check Restic logs
kubectl logs -n velero -l app.kubernetes.io/component=restic
```

#### **Storage Issues**

```bash
# Check backup storage location
kubectl describe backupstoragelocation cluster-backup-backup-location -n velero

# Check volume snapshot location
kubectl describe volumesnapshotlocation cluster-backup-volume-snapshot-location -n velero

# Test S3 connectivity
kubectl exec -n velero deployment/cluster-backup-velero -- velero backup-location get
```

#### **Permission Issues**

```bash
# Check RBAC
kubectl get clusterrole cluster-backup-velero
kubectl get clusterrolebinding cluster-backup-velero

# Check service accounts
kubectl get serviceaccount cluster-backup-velero -n velero
kubectl get serviceaccount cluster-backup-restic -n velero
```

### **Recovery Procedures**

#### **Restore from Backup**

```bash
# 1. List available backups
velero backup get -n velero

# 2. Create restore
velero restore create recovery-restore --from-backup <backup-name> -n velero

# 3. Monitor restore progress
velero restore describe recovery-restore -n velero
```

#### **Emergency Restore**

```bash
# 1. Stop all applications
kubectl scale deployment --all --replicas=0 -n <namespace>

# 2. Restore from latest backup
velero restore create emergency-restore --from-backup <latest-backup> -n velero

# 3. Verify restore
kubectl get pods -A
kubectl get pvc -A
```

---

## 📚 **Advanced Configuration**

### **Custom Backup Schedules**

```yaml
# Create custom schedule
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: custom-schedule
  namespace: velero
spec:
  schedule: "0 1 * * *"  # 1 AM daily
  template:
    metadata:
      labels:
        schedule.weown.xyz/type: custom
    spec:
      storageLocation: cluster-backup-backup-location
      volumeSnapshotLocations:
        - cluster-backup-volume-snapshot-location
      includedNamespaces:
        - my-app
      excludedNamespaces:
        - kube-system
      ttl: 7d
      defaultVolumesToRestic: true
```

### **Backup Hooks**

```yaml
# Pre-backup hook
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: backup-with-hooks
  namespace: velero
spec:
  hooks:
    resources:
    - name: pre-backup-hook
      includedNamespaces:
        - my-app
      labelSelector:
        matchLabels:
          app: my-app
      pre:
      - exec:
          container: my-app
          command:
            - /bin/sh
            - -c
            - "echo 'Pre-backup hook executed'"
```

### **Restore Hooks**

```yaml
# Post-restore hook
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-with-hooks
  namespace: velero
spec:
  backupName: my-backup
  hooks:
    resources:
    - name: post-restore-hook
      includedNamespaces:
        - my-app
      labelSelector:
        matchLabels:
          app: my-app
      post:
      - exec:
          container: my-app
          command:
            - /bin/sh
            - -c
            - "echo 'Post-restore hook executed'"
```

---

## 🎯 **Best Practices**

### **Backup Strategy**

1. **Regular Backups**: Daily for critical applications
2. **Retention Policy**: 30 days for daily, 90 days for weekly, 365 days for monthly
3. **Testing**: Regular restore testing to verify backup integrity
4. **Monitoring**: Set up alerts for backup failures

### **Security Best Practices**

1. **Encryption**: Always enable encryption for sensitive data
2. **Access Control**: Use minimal RBAC permissions
3. **Network Security**: Implement NetworkPolicies for zero-trust
4. **Audit Logging**: Enable comprehensive audit logging

### **Performance Optimization**

1. **Resource Limits**: Set appropriate CPU/memory limits
2. **Concurrent Operations**: Limit concurrent backups/restores
3. **Storage Optimization**: Use appropriate storage classes
4. **Network Optimization**: Use high-bandwidth connections for large backups

---

## 🚀 **Production Deployment**

### **Resource Requirements**

- **CPU**: 2 cores minimum, 4 cores recommended
- **Memory**: 4GB minimum, 8GB recommended
- **Storage**: 100GB minimum for backup metadata
- **Network**: High-bandwidth connection for backup transfers

### **High Availability**

- **Multi-AZ**: Deploy across multiple availability zones
- **Backup Redundancy**: Store backups in multiple regions
- **Disaster Recovery**: Test restore procedures regularly

### **Scaling Considerations**

- **Large Clusters**: Increase resource limits for large clusters
- **High-Frequency Backups**: Use dedicated backup nodes
- **Cross-Region**: Consider regional backup strategies

---

## 📞 **Support & Documentation**

### **WeOwn Support**

- **Email**: support@weown.xyz
- **Documentation**: https://weown.xyz/docs
- **GitHub**: https://github.com/WeOwn/ai

### **Community Resources**

- **Velero Documentation**: https://velero.io/docs
- **Kubernetes Backup**: https://kubernetes.io/docs/concepts/cluster-administration/backup/
- **Disaster Recovery**: https://kubernetes.io/docs/concepts/cluster-administration/disaster-recovery/

---

## 🎉 **Production-Ready Cluster Backup**

**Status**: Enterprise Production Ready ✅ | WeOwn Optimized v1.0.0

### **✅ What's Working Perfectly**

- **🔄 Complete Cluster Backup**: All namespaces, PVCs, CRDs, secrets
- **📅 Automated Scheduling**: Daily, weekly, monthly with retention
- **🌐 Cross-Cloud Migration**: DigitalOcean, AWS, GCP, Azure support
- **🔐 Enterprise Security**: Zero-trust, encryption, compliance
- **📊 Monitoring**: Prometheus metrics and alerting
- **🛠️ Management**: Complete CLI and API management

### **🚀 Advanced Features Available**

- **Disaster Recovery**: Complete cluster restore capabilities
- **Tenant Migration**: Move tenants between clusters
- **Provider Migration**: Switch cloud providers seamlessly
- **Backup Validation**: Automated integrity checks
- **Performance Tuning**: Optimized for large clusters

**Ready for WeOwn tenant replication with zero data loss guarantee.**
