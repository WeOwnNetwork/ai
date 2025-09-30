# Changelog

All notable changes to the Matomo Enterprise Kubernetes deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-29

### Added - WeOwn Cloud v0.9 Initial Release

#### **Core Features**
- Complete Helm chart for Matomo Analytics 5.3.2
- Enterprise-grade deployment script with interactive UX
- WordPress integration documentation and guidance
- Hourly analytics archiving via Kubernetes CronJob
- MariaDB database with persistent storage
- Comprehensive README with troubleshooting guide

#### **Security Features (SOC2/ISO42001/GDPR Compliant)**
- Zero-Trust NetworkPolicy (micro-segmentation)
- Pod Security Standards: Restricted profile
  - Non-root user (UID 1001)
  - Dropped capabilities (ALL)
  - Read-only root filesystem where possible
  - seccompProfile: RuntimeDefault
- TLS 1.3 encryption with Let's Encrypt automation
- Strong cipher suites enforcement
- Rate limiting (100 req/min, 20 connections max)
- Kubernetes-native secrets management
- Automated ingress-nginx namespace labeling (prevents 504 errors)

#### **Enterprise Architecture**
- Resource optimization (256Mi-1Gi memory, 100m-500m CPU)
- Persistent storage with DigitalOcean block storage
- Health checks and readiness probes
- Pod Disruption Budget for high availability
- Service Account with automount disabled
- NetworkPolicy for MariaDB isolation

#### **Deployment Automation**
- Cross-platform prerequisite auto-installation (macOS, Linux)
- Automatic NGINX Ingress Controller installation
- Automatic cert-manager installation
- ClusterIssuer creation with error handling
- External IP detection and DNS configuration guidance
- Secure credential generation (openssl rand -base64 24)
- Interactive domain and email configuration
- Deployment resumption capability

#### **WordPress Integration**
- Detailed plugin installation guide (Connect Matomo / WP-Piwik)
- Auth token generation instructions
- Manual tracking code option
- Step-by-step verification process

#### **Management & Operations**
- Credential retrieval command (--show-credentials)
- Backup and restore procedures
- Database access commands
- Performance optimization guidelines
- Resource monitoring commands
- Update procedures

#### **Documentation**
- Comprehensive README (500+ lines)
- Troubleshooting guide with common issues
- Architecture diagrams
- Security best practices
- GDPR compliance checklist
- WordPress integration walkthrough

### Technical Specifications

**Kubernetes Requirements:**
- Kubernetes 1.23+
- NGINX Ingress Controller
- cert-manager for TLS automation
- Persistent volume provisioner

**Resource Requirements:**
- Matomo: 256Mi-1Gi memory, 100m-500m CPU
- MariaDB: 128Mi-512Mi memory, 50m-250m CPU
- Storage: 10Gi (Matomo) + 8Gi (MariaDB)

**Dependencies:**
- Bitnami MariaDB Helm chart (subchart)
- Matomo container image 5.3.2-debian-12-r12

### Compliance & Standards

- **SOC2 Type II**: Ready for audit with comprehensive controls
- **ISO 42001**: AI/data management compliance ready
- **GDPR**: Privacy-first design with data ownership
- **WeOwn Security Standards**: Matches n8n, Vaultwarden, WordPress patterns

### Known Limitations

- Single replica deployment (Matomo file locks don't support horizontal scaling)
- Requires external DNS configuration (not automated)
- Initial setup wizard must be completed via web UI
- WordPress plugin requires manual auth token generation

### Future Enhancements (Planned)

- [ ] Automated GeoIP database updates
- [ ] Prometheus ServiceMonitor for monitoring
- [ ] Grafana dashboard templates
- [ ] Multi-website management documentation
- [ ] Automated backup to S3/Object Storage
- [ ] Migration tools from Matomo Cloud/other installations
- [ ] Custom plugin installation guide
- [ ] Performance tuning for high-traffic sites

---

## Version History

**v1.0.0** - Initial WeOwn Cloud v0.9 release (2025-09-29)
- Complete enterprise-grade Matomo deployment
- WordPress integration ready
- Production-certified security architecture

---

## Upgrade Notes

### From Future Versions

Upgrade notes will be added here as new versions are released.

### Breaking Changes

None in v1.0.0 (initial release).

---

## Contributors

- WeOwn Cloud Team
- Based on Bitnami Matomo Helm chart
- Community contributions welcome

---

**For detailed release notes and migration guides, see [GitHub Releases](https://github.com/WeOwn/ai/releases).**
