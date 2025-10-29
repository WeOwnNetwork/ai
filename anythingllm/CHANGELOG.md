# Changelog

All notable changes to the AnythingLLM Kubernetes deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2025-10-27

### Fixed
- **Deployment Template Error**
  - Fixed nil pointer error in ClusterIssuer template evaluation
  - Added `--set "letsencrypt.email=$EMAIL"` to Helm deployment command
  - Email now properly passed from deploy script to Helm templates
  - Resolves: "nil pointer evaluating interface {}.email" deployment failure

## [2.0.0] - 2025-10-24

### 🎯 **CRITICAL PRODUCTION RELEASE - BREAKING CHANGES**

This is a major release fixing critical backup system failures and standardizing all configurations across deployments.

### 🔴 **Critical Fixes**

#### **Backup System Restoration**
- **FIXED**: Missing ServiceAccount causing all backup CronJobs to fail for 28-72 days
- **FIXED**: Broken RBAC permissions preventing backups from executing
- **ADDED**: Complete backup ServiceAccount, Role, and RoleBinding templates
- **ADDED**: Configurable backup retention (default: 30 days SOC2/ISO42001 compliant)
- **ADDED**: Automatic cleanup of old backups based on retention policy
- **ADDED**: Configurable successful/failed job history limits

#### **Version Management**
- **CHANGED**: Upgraded from `latest` tag to specific version `1.9.0` (October 15, 2025)
- **CHANGED**: Image pull policy from `IfNotPresent` to `Always` for security patches
- **FIXED**: Stale cached images causing instances to run 21-57 day old versions

#### **Helm Revision Management**
- **ADDED**: Automatic cleanup of old Helm revisions (keeps last 10)
- **ADDED**: Revision cleanup integrated into deployment script
- **FIXED**: Excessive revision accumulation (some instances had 23+ revisions)

### ✨ **Enhancements**

#### **Configuration Standardization**
- **STANDARDIZED**: Backup PVC size to 10Gi across all instances
- **STANDARDIZED**: Backup schedule to 2 AM UTC for all deployments
- **STANDARDIZED**: Namespace to `anything-llm` for all instances
- **STANDARDIZED**: Resource limits and requests across all clusters
- **IMPROVED**: values.yaml documentation with inline comments

#### **Security Improvements**
- **ADDED**: Pod security context to backup CronJob (runAsUser: 1000, non-root)
- **ENHANCED**: Backup job uses dedicated ServiceAccount with minimal RBAC permissions
- **MAINTAINED**: All existing enterprise security features (NetworkPolicy, TLS 1.3, etc.)

#### **Operational Excellence**
- **IMPROVED**: Backup CronJob with better error handling and logging
- **IMPROVED**: Backup status reporting with size calculations
- **IMPROVED**: Cleanup operations with deleted backup counts
- **ADDED**: Comprehensive audit logging in backup operations

### 📊 **Chart Changes**

```yaml
Chart Version: 1.0.0 → 2.0.0
App Version: latest → 1.9.0
```

### 🗃️ **Database/Storage**

- **PVC Size**: Standardized to 10Gi for backup volumes
- **Retention Policy**: Configurable via `values.yaml` (default: 30 days)
- **Job History**: 3 successful + 3 failed jobs retained for debugging

### 📝 **Template Changes**

#### **New Templates**
- `backup-serviceaccount.yaml` - ServiceAccount, Role, and RoleBinding for backup operations

#### **Modified Templates**
- `backup-cronjob.yaml` - Uses new ServiceAccount, configurable retention, improved error handling
- `backup-pvc.yaml` - Uses values from values.yaml for size and storage class
- `values.yaml` - Added version 1.9.0, standardized backup config, improved documentation

#### **Updated Files**
- `Chart.yaml` - Version bump to 1.0.0, appVersion to 1.9.0
- `deploy.sh` - Added Helm revision cleanup function

### 🔄 **Migration Guide**

#### **For Existing Deployments:**

1. **Backup System Will Auto-Fix**
   - ServiceAccount and RBAC will be created automatically
   - Existing stuck backup jobs will be cleaned up
   - New backups will start working immediately

2. **Image Update Requires Pod Restart**
   - Helm upgrade will update deployment spec
   - Rolling restart will pull new v1.9.0 image
   - Zero downtime during update

3. **Helm Revisions Auto-Cleanup**
   - Old revisions automatically deleted (keeps last 10)
   - No manual intervention required
   - Reduces secret clutter in namespace

#### **Update Command:**
```bash
# Update existing installation
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --wait --timeout=10m

# Verify backup system
kubectl get serviceaccount anythingllm-backup -n anything-llm
kubectl get cronjob anythingllm-backup -n anything-llm

# Monitor next backup (2 AM UTC)
kubectl get jobs -n anything-llm
```

### 🐛 **Bug Fixes**

- **FIXED**: Backup CronJob referencing non-existent ServiceAccount
- **FIXED**: Backup jobs stuck in "Running" state for weeks/months
- **FIXED**: Inconsistent backup configurations across clusters
- **FIXED**: No automatic cleanup of old Helm revision secrets
- **FIXED**: Pods running outdated images despite using `latest` tag

### 📚 **Documentation**

- **ADDED**: Comprehensive audit report documenting all issues
- **ADDED**: Configuration standards documentation
- **UPDATED**: README with version management best practices
- **UPDATED**: Deployment guide with backup verification steps

### 🏗️ **Infrastructure**

#### **Tested Clusters**
- ✅ personal (ai.romandid.xyz)
- ✅ yonks (ai.yonksteam.xyz)
- ✅ adepablo (ai.adepablo.xyz)
- ✅ vegas (ai.vegascrypto.group)
- ✅ infra (ai.weown.app)

#### **Deployment Results**
- All 5 instances successfully updated
- Zero downtime upgrades confirmed
- Backup systems restored and operational
- Performance improvements verified

### ⚠️ **Breaking Changes**

1. **Image Tag Change**: Applications will restart with v1.9.0 instead of cached `latest`
2. **Backup ServiceAccount**: New RBAC resources created (backward compatible)
3. **Values Structure**: Added new backup configuration options (backward compatible with defaults)

### 🔐 **Security**

- **No Security Vulnerabilities** in this release
- **Enhanced**: Backup job runs as non-root user (1000:1000)
- **Maintained**: All existing enterprise security standards
- **Compliance**: SOC2/ISO42001 ready with 30-day backup retention

### 📦 **Dependencies**

- **AnythingLLM**: 1.9.0 (October 15, 2025)
- **Kubernetes**: 1.28+ (tested on 1.33.1)
- **Helm**: 3.0+
- **cert-manager**: 1.x
- **ingress-nginx**: 1.x

### 🙏 **Acknowledgments**

This release addresses critical production issues discovered during comprehensive multi-cluster audit on October 24, 2025.

---

## [1.0.0] - 2025-08 to 2025-10-23 (Pre-Audit)

### Features
- Production Helm chart deployment across 5 clusters
- Enterprise security stack (NetworkPolicy, TLS 1.3, Pod Security)
- Automated daily backup CronJob (2 AM UTC schedule)
- Comprehensive deployment automation script
- Multi-cluster deployment capability

### Known Issues (Fixed in 2.0.0)
- ❌ Backup CronJob missing ServiceAccount (backups failing silently)
- ❌ Using `latest` image tag with stale cached versions
- ❌ Excessive Helm revision accumulation
- ❌ Inconsistent configurations across clusters

### Deployments
- 5 production instances: personal, yonks, adepablo, vegas, infra
- Running for 72+ days with partial functionality

---

## [0.2.0] - 2025-08 (Historical)

### Added
- Initial Helm chart for AnythingLLM deployment
- Enterprise security features (NetworkPolicy, TLS 1.3)
- Automated backup CronJob (had issues, fixed in 2.0.0)
- Comprehensive deployment script

### Security
- Zero-trust networking with NetworkPolicy
- Pod Security Standards: Restricted profile
- TLS 1.3 with Let's Encrypt automation

---

## Version History Summary

- **2.0.0** (2025-10-24): Critical backup fixes, version standardization, Helm cleanup
- **1.0.0** (2025-08 to 2025-10-23): Initial production deployment with known issues
- **0.2.0** (2025-08): Initial chart development
