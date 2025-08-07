# WeOwn Vaultwarden Enterprise Deployment

**🔐 Enterprise-Grade, Self-Hosted Password Manager for WeOwn Cohorts**

[![Security](https://img.shields.io/badge/Security-Enterprise%20Grade-green)](https://github.com/WeOwnNetwork/ai/tree/main/vaultwarden)
[![Platform](https://img.shields.io/badge/Platform-Kubernetes-blue)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-WeOwn%20Internal-orange)](LICENSE)

Complete, production-ready deployment system for Vaultwarden (Bitwarden-compatible) password manager, designed for WeOwn cohort members. Deploy your own secure, self-hosted password manager in **under 10 minutes** with enterprise security features.

## 🚀 Quick Start (Recommended)

### One-Line Installation
```bash
curl -sSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/vaultwarden/install.sh | bash
```

**This will:**
- ✅ Download only the vaultwarden deployment files
- ✅ Check all prerequisites and guide installation
- ✅ Run the interactive deployment script
- ✅ Work on any machine with any Kubernetes cluster

### Manual Installation
```bash
# Clone only the vaultwarden directory
git clone --filter=blob:none --sparse https://github.com/WeOwnNetwork/ai.git
cd ai && git sparse-checkout set vaultwarden && cd vaultwarden

# Run the deployment script
./deploy.sh
```

## 📋 Prerequisites

The deployment script will check for and guide you through installing:
- **kubectl** - Kubernetes command-line tool
- **helm** - Kubernetes package manager
- **docker** - Container platform (for password hashing)
- **curl** - Command-line tool for downloads
- **git** - Version control system

**Required Infrastructure:**
- Kubernetes cluster (DigitalOcean recommended)
- Domain name with DNS management access
- Email address for SSL certificates

## 🛡️ Enterprise Security Features

### Zero-Trust Architecture
- **Pod Security Contexts**: Non-root containers, read-only filesystem
- **Network Policies**: Zero-trust networking with ingress/egress controls
- **RBAC**: Role-based access control with least privilege
- **Resource Limits**: CPU/memory constraints for stability

### Automated Security
- **TLS/HTTPS**: Let's Encrypt certificates with auto-renewal
- **Secrets Management**: Kubernetes secrets with Argon2id hashing
- **Security Scanning**: Container security best practices
- **Compliance Ready**: SOC2/ISO42001 aligned

## 📖 Documentation

### Key Files
- **[COHORT_DEPLOYMENT_GUIDE.md](COHORT_DEPLOYMENT_GUIDE.md)** - Complete step-by-step guide
- **[deploy.sh](deploy.sh)** - Interactive deployment script
- **[install.sh](install.sh)** - One-line installer
- **[helm/](helm/)** - Production Helm chart
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

### Deployment Process
1. **Prerequisites Check** - Automated tool verification
2. **Cluster Connection** - Kubernetes connectivity test
3. **Configuration** - Interactive setup (subdomain, domain, email)
4. **DNS Setup** - Guided A record creation
5. **Infrastructure** - NGINX Ingress + cert-manager installation
6. **Deployment** - Secure Vaultwarden deployment
7. **Verification** - SSL certificate and access validation

## 🌐 Browser Extension Setup

### Chrome/Firefox/Safari
1. Install [official Bitwarden extension](https://bitwarden.com/download/)
2. Click extension icon → Settings gear ⚙️
3. Set **Server URL** to: `https://[your-subdomain].[your-domain]`
4. Save and create/login to your account

### Mobile Apps
1. Download official Bitwarden app
2. Login screen → Settings gear
3. Set **Server URL** to your domain
4. Login with web vault account

## 🔧 Advanced Configuration

### Custom Settings
Edit `helm/values.yaml` for advanced configuration:
```yaml
vaultwarden:
  config:
    signupsAllowed: false  # Disable after setup
    invitationsAllowed: true
    emergencyAccessAllowed: true
```

### High Availability
For production HA deployments:
- External PostgreSQL database
- Shared storage (NFS/EFS)
- Multiple replicas with load balancing

## 🔍 Troubleshooting

### Common Issues
- **DNS not resolving**: Check A record creation and propagation
- **SSL certificate issues**: Verify DNS and check cert-manager logs
- **Pod not starting**: Check resource limits and security contexts

### Support Commands
```bash
# Check deployment status
kubectl get pods -n vaultwarden

# Check SSL certificate
kubectl get certificate -n vaultwarden

# View logs
kubectl logs -n vaultwarden deployment/vaultwarden
```

## 📊 Monitoring & Maintenance

### Regular Tasks
- **Backup vault data** via admin panel
- **Monitor SSL certificate renewal** (automatic)
- **Update Vaultwarden image** for security patches
- **Review access logs** in admin panel

### Prometheus Integration
Enable monitoring in `helm/values.yaml`:
```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
```

## 🏢 Enterprise Features

### Multi-Tenant Support
- Namespace isolation per cohort/organization
- Resource quotas and limits
- Network policy segmentation

### Compliance
- **SOC2 Ready**: Comprehensive audit logging
- **ISO42001 Aligned**: Data protection controls
- **GDPR Compliant**: Data minimization and privacy

## 📞 Support

### WeOwn Resources
- **Cohort Support**: Ask in cohort channels
- **Technical Issues**: Contact Roman Di Domizio (roman@weown.email)
- **Documentation**: [COHORT_DEPLOYMENT_GUIDE.md](COHORT_DEPLOYMENT_GUIDE.md)

### External Resources
- **Vaultwarden Wiki**: https://github.com/dani-garcia/vaultwarden/wiki
- **Bitwarden Help**: https://bitwarden.com/help/
- **Kubernetes Docs**: https://kubernetes.io/docs/

---

**Security Classification**: WeOwn Internal  
**Maintainer**: Roman Di Domizio (roman@weown.email)  
**Last Updated**: 2025-08-07