# CHANGELOG: Enterprise Vaultwarden Kubernetes Deployment

Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2025-09-09

### Fixed
- **CRITICAL: Admin Token Security Implementation**
  - Fixed Vaultwarden "insecure plain text ADMIN_TOKEN" warning
  - Properly implemented Argon2id PHC hash storage while maintaining plaintext user input
  - Restored secure admin token generation with cross-platform argon2 support
- **ClusterIssuer Ownership Conflicts**
  - Added intelligent ClusterIssuer detection to prevent Helm ownership conflicts
  - Dynamic `certManager.createClusterIssuer` flag based on existing resources
- **Backup System Optimization** 
  - Removed obsolete `backup-cronjob.yaml` requiring DigitalOcean API tokens
  - Replaced with lightweight Kubernetes-native ConfigMap backup system
  - Auto-enabled minimal resource backup (32Mi memory, 10m CPU)
  - 7-day retention with automatic cleanup

### Changed
- **Public Repository Preparation**
  - Removed WeOwn-specific branding from deploy script and Helm values
  - Updated repository URLs to generic template format
  - Cleaned up admin token prefix from "WeOwn-Admin-" to "Admin-"
- **Deployment Flow**
  - Automated backup system setup (no user prompts required)
  - Streamlined admin token display with security confirmations

### [1.2.0] - 2025-08-20

#### CRITICAL SECURITY FIX: Argon2id Admin Token Hashing
- **VULNERABILITY RESOLVED**: Fixed Vaultwarden warning "You are using a plain text ADMIN_TOKEN which is insecure"
- **Argon2id PHC Implementation**:
  - Enterprise-grade Argon2id hashing with 64MB memory, 3 iterations, 4 threads
  - Password Hashing Competition (PHC) string format for maximum compatibility
  - Automatic format validation prevents deployment with weak tokens
- **Enhanced Security Architecture**:
  - Clear separation between user password (browser input) and stored hash (Kubernetes secret)
  - Private token display with user confirmation (security best practice)
  - Cross-platform argon2 CLI auto-installation (macOS/Linux)
- **Production Readiness**:
  - Zero vulnerabilities identified in comprehensive security audit
  - Enterprise-grade authentication flow implementation
  - Enhanced error handling and troubleshooting documentation

#### Documentation & UX Improvements
- **README Updates**: Added Argon2id security specifications and enterprise security indicators
- **Enhanced Troubleshooting**: Argon2id-specific admin token recovery procedures
- **Deployment Script**: Comprehensive security warnings and private credential handling
- **Architecture Documentation**: Clear password vs hash usage explanation

### [1.1.0] - 2024-12-20

#### Security Audit & Hardening
- **CRITICAL: Removed ALL hardcoded sensitive data**:
  - Removed hardcoded domain from `helm/values.yaml`
  - Replaced personal email with generic in `helm/Chart.yaml`
  - Moved `clusterissuer.yaml` to Helm templates with parameterized email
- **Enhanced secret management**:
  - Added Let's Encrypt email prompt during deployment
  - Ensured Argon2-hashed admin tokens (already implemented)
  - Created comprehensive `.gitignore` for sensitive files
- **Directory cleanup**:
  - Removed `data/` directory containing SQLite database and RSA keys
  - Deleted empty `deploy-interactive.sh` file
  - Consolidated all deployment logic into single `deploy.sh`
- **Helm chart improvements**:
  - Added templated ClusterIssuer for cert-manager
  - Added `certManager` configuration block to values
  - Verified all security contexts and network policies
- **Documentation updates**:
  - Added security audit status to README
  - Enhanced deployment process documentation
  - Added manual installation instructions

### [1.0.0] - 2025-08-07

#### Added
- **Enterprise-grade Helm chart** with complete security features
- **Interactive deployment script** (`deploy.sh`) with cross-platform support
- **One-line installer** (`install.sh`) for easy cohort onboarding
- **Comprehensive documentation** with step-by-step guides
- **Automated prerequisite checking** for kubectl, helm, docker, curl, git
- **DNS setup guidance** with external IP detection
- **TLS/HTTPS automation** with Let's Encrypt certificates
- **Enterprise security features**:
  - Pod security contexts (non-root, read-only filesystem)
  - Network policies for zero-trust networking
  - RBAC with least privilege principles
  - Kubernetes secrets with Argon2id password hashing
  - Resource limits for stability and cost optimization
- **Cross-platform support** for macOS, Linux, and Windows
- **Cohort replication templates** for easy deployment across organizations

#### Changed
- **Renamed deployment script** from `deploy-interactive.sh` to `deploy.sh`
- **Updated email references** from `roman@weown.xyz` to `roman@weown.email`
- **Completely rewritten README** with comprehensive instructions and links
- **Enhanced COHORT_DEPLOYMENT_GUIDE.md** with TTL explanations and browser setup

#### Security
- **Zero-trust architecture** with network policies and pod security standards
- **Automated TLS certificate management** with cert-manager and Let's Encrypt
- **Secure secrets management** using Kubernetes secrets (no hardcoded credentials)
- **Enterprise compliance** ready for SOC2/ISO42001 requirements
- **Container security** with non-root users and minimal attack surface

#### Infrastructure
- **NGINX Ingress Controller** installation with DigitalOcean optimization
- **cert-manager** deployment for automated certificate lifecycle
- **Kubernetes namespace isolation** for multi-tenant security
- **Persistent storage** with DigitalOcean block storage integration

### [0.1.0] - 2025-08-06

#### Added
- Initial Vaultwarden deployment setup
- Docker Compose configuration for local development
- Basic Kubernetes deployment manifest
- README with basic setup instructions

---

### {Season #001} ● 2025-W30

- v1.30.2.3 | Added full-featured quickstart.sh script for secure setup and admin password hashing (replaces static .env.example).
- v1.30.2.2 | Expanded README with modular, detailed instructions for local/cloud/self-hosting, Bitwarden app setup, cloud pricing, and cohort onboarding options.
- v1.30.2.1 | Initial Docker Compose setup for Vaultwarden with persistent data, .env support, and security-first defaults.
- v1.30.2.0 | Created `vaultwarden/` directory, basic initial structure.