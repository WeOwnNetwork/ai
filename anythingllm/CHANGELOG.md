# Changelog

All notable changes to the AnythingLLM Kubernetes deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [#WeOwnVer](/docs/VERSIONING_WEOWNVER.md) (Season.Week.Day.Version).

## [2.5.0] - 2026-01-26

### Changed - Versioning System
- **Adopted #WeOwnVer**: Transitioned from Semantic Versioning to WeOwn ecosystem versioning
- **Version Format**: SEASON.WEEK.DAY.VERSION (2.5.0 = Season 2, Week 5, summary)
- **Documentation**: Added reference to `/docs/VERSIONING_WEOWNVER.md` for versioning standards
- **Chart Version**: Updated to align with WeOwn ecosystem rhythm (Season 2, Week 5)

## [2.1.0] - 2026-01-25 (Legacy SemVer)

### Added - Enterprise Secrets Management (Infisical Integration)

#### **Infisical Kubernetes Operator Integration**
- **Automated Secret Sync**: Infisical Cloud → Kubernetes secrets every 60 seconds
- **InfisicalSecret CRD**: Helm template for declarative secret management
- **Auto-Reload Annotation**: Pods automatically restart when secrets change
- **Machine Identity Authentication**: Universal Auth with Client ID/Secret
- **Configuration Management**: Complete Helm values for Infisical integration

#### **Automated Rotation Workflows (n8n)**
- **OpenRouter API Key**: 7-day rotation cycle (aggressive security posture)
- **JWT_SECRET**: 90-day rotation cycle (SOC2/ISO/IEC 42001 compliant)
- **Machine Identity Client Secret**: 30-day rotation cycle (ISO/IEC 42001 compliant)
- **Zero-downtime rotation**: Kubernetes operator handles pod restarts automatically

#### **Compliance & Security Features**
- **90-day audit logs**: Complete access history with IP tracking in Infisical Pro
- **Compromise detection**: Automated monitoring for suspicious access patterns
- **SOC2/ISO/IEC 42001 ready**: Meets enterprise compliance requirements
- **RBAC integration**: Infisical + Kubernetes role-based access control
- **Secret versioning**: Point-in-time recovery and rollback capability

#### **Documentation**
- **INFISICAL_INTEGRATION.md**: Comprehensive 5-phase setup guide (590+ lines)
  - Phase 1: Infisical project setup and Machine Identity creation
  - Phase 2: Kubernetes Operator installation and configuration
  - Phase 3: OpenRouter Provisioning API key setup
  - Phase 4: n8n workflow automation (3 separate rotation schedules)
  - Phase 5: Compliance monitoring and compromise detection
- **README.md Updates**: 
  - Automated secret management section with upgrade instructions
  - Configuration preservation guidance for Helm upgrades
  - Infisical quick start and feature overview

### Changed
- **Helm Upgrade Strategy**: Added guidance for preserving configuration during upgrades
- **Secret Management Architecture**: Separated secrets (Infisical) from config (Helm values)
- **Rotation Schedules**: Documented aggressive rotation frequencies for defense-in-depth

### Fixed
- **Configuration Persistence**: Resolved issue where model preferences and timeouts reset during upgrades
- **Sparse Deployed Values**: Added complete values file approach to prevent config loss with `--reuse-values`

### Security
- **Defense-in-Depth**: 7-day OpenRouter rotation exceeds compliance requirements
- **Automated Remediation**: n8n workflows for immediate response to compromised secrets
- **IP Allowlisting**: Restrict Machine Identity access to known infrastructure

---

## [2.0.7] - 2026-01-10

### Added
- **Community Hub Agent Skills**: Enabled agent skill imports from AnythingLLM Hub with enterprise security controls
  - Added `COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED: "1"` to allow verified/private agent skills only
  - Prevents untrusted code execution while enabling access to curated agent skills library
  - Configurable via values.yaml for deployment-wide consistency
  - Documentation added for security implications and configuration options

### Security
- **Restricted Community Hub Access**: Set to verified/private items only (not `allow_all`) to prevent untrusted code execution
- **Enterprise Security Standard**: Follows WeOwn security protocols for third-party code integration

## [2.0.6] - 2026-01-09

### Added
- **Interactive AI Configuration**: `deploy.sh` now features a comprehensive interactive setup for LLM and Embedding models.
- **OpenRouter Integration**: Native support for OpenRouter models including `Claude Opus 4.5`, `GPT-5.2`, `Gemini 3 Pro`, `DeepSeek V3.2`, `Grok 4`, and `Grok Code Fast 1`.
- **Stream Timeout Control**: Configurable `OPENROUTER_TIMEOUT_MS` to prevent timeouts with slower reasoning models or large RAG contexts (Default: 3000ms).
- **Comprehensive Embedding Library**: Expanded selection to 21+ models with detailed "How to Choose" guidance, pricing, and use-case categories (e.g., Code, Multilingual, Reasoning).
- **Enterprise Secrets Management**: Added documentation and support for **Infisical** integration to replace Kubernetes Secrets.
- **Custom Model Support**: Added option to manually input any OpenRouter Model ID or Embedding Model ID.
- **Telemetry Toggle**: Explicit option to enable/disable telemetry (Default: Disabled/True).
- **Strict OpenRouter Mode**: Refactored `values.yaml` to remove legacy `generic-openai` env vars in favor of `openrouter` provider to fix persistence issues.

### Changed
- **Default LLM**: Updated to `anthropic/claude-opus-4.5` (2026 Frontier Model).
- **Model IDs**: Updated to latest 2026 standards (e.g., `anthropic/claude-opus-4.5`, `openai/gpt-5.2`).
- **Configuration Simplified**: Removed manual `Token Budget` and `Chunk Length` inputs as they are handled automatically by models.
- **Deployment Script**: Removed unused variable injections and streamlined secret management.
- **Documentation**: Updated README with new configuration options.

### Fixed
- **OpenRouter Persistence**: Fixed an issue where API keys and model selections reverted to generic drivers on restart. Hardcoded `LLM_PROVIDER: "openrouter"` in `values.yaml` and removed legacy OpenAI env vars to enforce strict configuration persistence.
- **Large Document Embedding Crash**: Resolved OOM crashes when embedding large documents on standard nodes.
  - *Diagnosis*: Local embedding caused massive RAM spikes exceeding node limits.
  - *Resolution*: Offloaded embedding workload to OpenRouter API (via `deploy.sh` configuration) to decouple processing load from cluster resources, avoiding the need for expensive node upgrades.
- **Stream Timeout**: Fixed `LLM_STREAM_TIMEOUT` variable ignored by OpenRouter provider. Switched to `OPENROUTER_TIMEOUT_MS` to correctly apply custom timeouts (e.g., 5000ms) for slow reasoning models.
- **Model Selection Persistence**: Fixed issue where selected models were not persisting by correctly mapping OpenRouter preferences.
- **Namespace Warning**: Resolved `kubectl apply` warning by adding a check-if-exists logic for namespace creation.
- **Env Variable Cleanup**: Removed deprecated `GENERIC_OPEN_AI_API_KEY` and `EMBEDDING_OPENAI_API_KEY` usage.

## [2.0.1] - 2025-10-27

### Fixed
- **Deployment Template Error**
  - Fixed nil pointer error in ClusterIssuer template evaluation
  - Added `--set "letsencrypt.email=$EMAIL"` to Helm deployment command
  - Email now properly passed from deploy script to Helm templates
  - Resolves: "nil pointer evaluating interface {}.email" deployment failure

## [2.0.0] - 2025-10-24

### **CRITICAL PRODUCTION RELEASE - BREAKING CHANGES**

This is a major release fixing critical backup system failures and standardizing all configurations across deployments.

### 🔴 **Critical Fixes**

#### **Backup System Restoration**
- **FIXED**: Missing ServiceAccount causing all backup CronJobs to fail for 28-72 days
- **FIXED**: Broken RBAC permissions preventing backups from executing
- **ADDED**: Complete backup ServiceAccount, Role, and RoleBinding templates
- **ADDED**: Configurable backup retention (default: 30 days SOC2/ISO/IEC 42001 compliant)
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
- **Compliance**: SOC2/ISO/IEC 42001 ready with 30-day backup retention

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
