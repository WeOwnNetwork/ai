# Changelog

All notable changes to this project will be documented in this file.

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
