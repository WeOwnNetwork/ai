# CHANGELOG: Vaultwarden (Self-hosted Secrets for WeOwn Cohorts)

[//]: # "Tracking Vaultwarden for internal and cohort secrets"
[//]: # "Seasons as above"

Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## {Season #001} = Jun / Jul / Aug / Sep 2025

All notable changes to the WeOwn Vaultwarden deployment will be documented in this file.

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