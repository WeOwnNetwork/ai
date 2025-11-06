# Changelog

All notable changes to this project will be documented in this file.

## [2.8.0] - 2025-11-06

### 🚨 BREAKING CHANGE: Nginx Basic Auth REMOVED
- **REMOVED**: All nginx basic auth configuration (values.yaml, templates, deploy script)
- **REASON**: n8n has robust built-in user management and authentication
- **BENEFIT**: Simpler deployment, better UX, no double-authentication confusion
- **MIGRATION**: Existing instances upgraded automatically - nginx auth removed
- **IMPACT**: Users now only manage accounts within n8n interface (standard n8n behavior)

### 🐛 CRITICAL FIX: Backup CronJob Node Affinity
- **PROBLEM**: Backup jobs stuck in `ContainerCreating` for days on personal & timk clusters
- **ROOT CAUSE**: DigitalOcean block storage (RWO) can only attach to ONE node at a time
- **SOLUTION**: Added podAffinity to force backup jobs onto same node as main n8n pod
- **FILES**: `helm/templates/backup-cronjob.yaml` - added affinity section
- **IMPACT**: All future backups will schedule correctly, no more stuck jobs
- **CLUSTERS AFFECTED**: Fixed on personal (5d stuck) and timk (6d stuck) clusters

### 📦 Version Management Update
- **CHANGED**: n8n version from "latest" to pinned "1.118.2" in values.yaml
- **REASON**: "latest" tag caching caused version lag (showed 1.117.3 vs 1.118.2)
- **BENEFIT**: Explicit version control, predictable upgrades across all instances
- **Chart.yaml**: Updated appVersion to "1.119.0" for documentation consistency
- **CHART VERSION**: Bumped to 2.8.0 to match deploy script version

### 🔧 Resource Management Enhancement
- **ADDED**: `--history-max 3` flag to Helm upgrade commands
- **BENEFIT**: Prevents Helm revision history from accumulating and wasting cluster resources
- **IMPACT**: Limits stored revisions to 3, automatically cleaning up old secrets and metadata
- **COMPLIANCE**: Matches WordPress deployment pattern for consistent resource management

### ✅ Deployment Validation
- **VERIFIED**: DNS validation already implemented (validates before deployment)
- **VERIFIED**: TLS 1.3 security properly configured (strong cipher suites)
- **STATUS**: All WeOwn security standards met

### 📊 Deployment Statistics
- **CLUSTERS UPGRADED**: 7 production instances across 7 clusters
- **BACKUP STATUS**: All 7 clusters now have working backups with auto-cleanup
- **BACKUP RETENTION**: 
  - Job History: Keep last 3 successful + 1 failed (auto-cleanup via K8s)
  - Backup Files: 7-day retention on persistent storage
  - Node Affinity: Forces backup pods to same node as main pod (RWO fix)
- **HELM REVISIONS**: Will enforce max 3 on next upgrade (currently 5-6)
- **ZERO DOWNTIME**: All upgrades completed successfully with data retention

## [2.7.0] - 2025-10-30

### Critical Fix - DNS Validation Before Deployment

**Problem**: Certificate issuance fails permanently if DNS is not configured before deployment, requiring manual deletion of failed certificate orders.

**Root Cause**: Let's Encrypt validates domains immediately upon certificate request. If DNS returns NXDOMAIN, the order is marked as `invalid` and won't auto-retry.

**Solution**: Deploy script now validates DNS resolution BEFORE deployment.

### Added
- `validate_dns()` function with automated DNS checking (10 attempts, 10s intervals)
- Real-time DNS validation feedback with color-coded status
- User-friendly warnings about Let's Encrypt failure consequences
- Manual fix instructions if user proceeds without DNS

### Changed
- DNS validation now required step before deployment (prevents certificate failures)
- Deployment order: DNS validation → Deploy → Verify (was: Deploy → Show DNS instructions)
- Removed post-deployment DNS instructions (now validated upfront)

### Impact
- **Prevents**: Let's Encrypt certificate order failures due to missing DNS
- **Eliminates**: Need to manually delete failed certificates with `kubectl delete certificate`
- **Improves**: User experience with immediate DNS feedback
- **Production-Ready**: All future deployments validate DNS before certificate requests

## [2.6.1] - 2025-10-27

### Fixed
- **Deployment Verification Logic**
  - Fixed false deployment failure when basic auth is disabled (default configuration)
  - Auth-secret verification now conditional on basic auth being enabled
  - Prevents script from checking for secret that doesn't exist by design
  - Resolves: "Authentication secret is missing" error on successful deployments

## [2.6.0] - 2025-10-02

### Authentication System Overhaul - COMPLETE
- **CRITICAL FIX**: Basic auth now truly disabled by default - no more browser prompts
- **DEPLOYMENT LOGIC FIX**: Fixed `${DISABLE_BASIC_AUTH:-false}` logic causing auth to be enabled by default
- **UX IMPROVEMENT**: Changed `--disable-basic-auth` to `--enable-basic-auth` flag (auth off by default)
- **PRODUCTION READY**: All existing deployments can remove basic auth instantly
- **CONSISTENCY**: Deploy script behavior now matches values.yaml configuration

### Added
- `--enable-basic-auth` flag to explicitly enable nginx basic auth if needed
- Automatic basic auth removal commands for existing deployments
- Improved help text reflecting new authentication defaults

### Fixed
- **CRITICAL**: Deploy script applying basic auth despite DISABLE_BASIC_AUTH=true
- **CRITICAL**: Default parameter expansion logic causing unintended auth enablement
- **UX**: Misleading help text suggesting basic auth was disabled by default
- **CONSISTENCY**: Mismatch between script defaults and values.yaml configuration

## [2.5.0] - 2025-10-02

### Infrastructure Auto-Installation
- **CRITICAL FIX**: Added automatic NGINX Ingress Controller installation for new clusters
- **CRITICAL FIX**: Added automatic cert-manager installation for TLS certificate management
- **ENHANCEMENT**: Improved error handling for ingress and cert-manager installation with graceful fallback
- **DEPLOYMENT**: Deploy script now fully automated for greenfield cluster deployments
- **UX**: Better progress feedback during infrastructure component installation

### Added
- `install_ingress_nginx()` now called automatically in main deployment flow
- `install_cert_manager()` now called automatically in main deployment flow
- Robust error handling with manual installation instructions on failure
- Progress indicators for long-running installation tasks
- Automatic namespace labeling for NetworkPolicy compatibility

### Fixed
- Deployment failures on clusters without pre-installed NGINX Ingress Controller
- Missing cert-manager causing TLS certificate provisioning failures
- Silent failures when infrastructure components were missing
- Deployment script assuming pre-existing cluster infrastructure

## [2.4.0] - 2025-09-26

### Version Update & Compatibility Enhancement
- **MAJOR UPDATE**: Upgraded n8n from v1.63.1 to latest (v1.112.6) - 49 versions jump
- **AUTO-UPDATES**: Changed to `latest` tag for automatic updates on pod restart
- **COMPATIBILITY**: Maintained backward compatibility with existing workflows and data
- **SECURITY**: All enterprise security features preserved in latest version

## [2.3.0] - 2025-09-26

### Cluster Compatibility & Security Enhancement
- **CRITICAL FIX**: Resolved server-snippet annotation rejection on clusters with disabled snippet directives
- **COMPATIBILITY**: Added nginx ingress controller snippet support detection
- **DEPLOYMENT**: Enhanced deploy script with proactive cluster capability detection
- **SECURITY**: Maintained enterprise security while ensuring wider cluster compatibility

### Added
- `check_nginx_snippet_support()` function for proactive cluster capability detection
- Automatic fallback for clusters with disabled nginx snippet annotations
- Enhanced logging for snippet support detection during deployment
- Wider cluster compatibility without sacrificing security standards

### Fixed
- nginx.ingress.kubernetes.io/server-snippet annotation rejection causing deployment failures
- Admission webhook "validate.nginx.ingress.kubernetes.io" denial errors
- Deployment failures on security-hardened clusters with disabled snippet directives
- Corrupted main function flow in deployment script

### Security
- Maintained A+ security grade (35/35 checks passed) despite compatibility changes
- Removed snippet dependencies while preserving TLS 1.3 and enterprise security
- Enhanced cluster detection prevents deployment failures without user intervention
- Compatible with both permissive and security-hardened cluster configurations

## [2.2.0] - 2024-09-26

### Authentication & User Experience Enhancement
- **USER EXPERIENCE**: Implemented 24-hour nginx basic auth session persistence (no more login on refresh)
- **CREDENTIAL PROMPT**: Fixed credential display to always request user permission (interactive + non-interactive)
- **FLEXIBLE AUTH**: Added `--disable-basic-auth` option for trusted internal environments
- **SECURITY**: Enhanced browser auth caching with proper cache-control headers
- **DOCUMENTATION**: Clear explanation of two-layer authentication (nginx + n8n built-in)

### Added
- 24-hour session persistence for nginx basic auth (`auth-cache-duration: "24h"`)
- Enhanced credential display with clear nginx vs n8n auth explanation
- `--disable-basic-auth` command-line option for internal deployments
- Conditional auth-secret template based on `enableBasicAuth` setting
- Improved user prompts with timeout handling for non-interactive mode
- Comprehensive auth configuration structure in values.yaml

### Fixed
- Credential display always prompts for user permission (was auto-showing in piped mode)
- Auth template Helm value references (`n8n.auth.user` and `n8n.auth.password`)
- Session persistence eliminates repetitive basic auth prompts
- Enhanced cache headers for better browser auth retention

### Security
- Maintained A+ security grade (35/35 checks passed)
- Session persistence maintains DDoS protection and access control
- Optional basic auth disabling for trusted network environments
- Two-layer security: nginx basic auth + n8n user authentication

## [2.1.0] - 2024-09-26

### Enterprise Security & Installation Enhancement
- **CRITICAL FIX**: Resolved deployment script function definition error (print_banner)
- **INSTALLER**: Added one-command installer script (`install.sh`) for easy cohort deployment  
- **SECURITY**: Maintained 100% security audit pass rate (35/35 checks) with A+ grade
- **DOCUMENTATION**: Comprehensive README update for public GitHub release
- **DEPLOYMENT**: Fixed CrashLoopBackOff issues with improved Helm chart validation

### Added
- `install.sh` - One-command installer with sparse Git clone for minimal bandwidth
- Comprehensive public README with installation, security, and troubleshooting guides
- Enhanced deployment script error handling and function scoping
- Production-ready examples and configuration options
- Commercial licensing guidance for n8n Enterprise
- Development setup and contribution guidelines

### Fixed
- Deployment script syntax error with `print_banner` function
- Helm chart compatibility issues causing pod crashes
- Interactive deployment prompts and validation
- Security audit script patterns for accurate validation

### Security
- Maintained enterprise-grade security posture (A+ audit grade)
- Zero-trust NetworkPolicy with ingress-nginx isolation
- TLS 1.3 with strong cipher suites and security headers
- Pod Security Standards: Restricted profile with non-root containers
- Automated backup system with 7-day retention policy

## [2.0.0] - 2024-01-20

### Enterprise Production Release
- **SECURITY**: Achieved 100% security audit pass rate (61/61 checks)
- **DEPLOYMENT**: Simplified to single command `./deploy.sh` with interactive prompts
- **MIGRATION**: Added comprehensive Docker to Kubernetes migration strategy
- **LICENSING**: Added commercial licensing information for n8n Enterprise
- **PERFORMANCE**: Optimized for production with concurrency settings and queue mode
- **COMPLIANCE**: SOC2/ISO42001 ready with zero-trust NetworkPolicy and Pod Security Standards

### Added
- Interactive deployment script with no command-line arguments required
- Commercial licensing notices in README, LICENSE, and deployment script
- Comprehensive Docker workflow backup and migration documentation
- Production performance optimizations (N8N_CONCURRENCY=10)
- File upload security configuration (16MB limit, filesystem mode)
- Queue mode support with PostgreSQL and Redis
- Zero-trust NetworkPolicy for micro-segmentation
- Pod Security Standards: Restricted profile enforcement
- TLS 1.3 with Let's Encrypt automation
- Stateless deployment with enhanced error handling

### Changed
- All deployment commands simplified to `./deploy.sh` only
- Security audit script updated for accurate configuration validation
- Migration guide refined with precise backup creation instructions
- LICENSE updated with MIT license and n8n commercial licensing notice

### Security
- Achieved A+ security grade with 100% audit compliance
- Implemented zero-trust networking with ingress-nginx restrictions
- Added non-root containers with dropped capabilities
- Enforced TLS 1.3 with strong cipher suites
- Added rate limiting for DDoS protection
- Removed all hardcoded sensitive data for public release readiness
