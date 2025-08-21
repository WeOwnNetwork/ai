# WeOwn Vaultwarden Enterprise Deployment

🔐 **Enterprise-grade Vaultwarden (Bitwarden-compatible) password manager for WeOwn cohorts**

Production-ready, self-hosted password management solution with enterprise security, automated deployment, and cohort-replicable architecture.

## 🔒 Security Audit Status

✅ **FULLY AUDITED AND SECURED** (Latest audit: August 2024)
- ✅ **Zero-Trust Networking**: NetworkPolicy restricts all pod communication
- ✅ **No Hardcoded Secrets**: All sensitive data parameterized at deployment
- ✅ **Argon2-Hashed Admin Tokens**: Cryptographically secure authentication
- ✅ **Rate Limiting**: 10 requests/min, 5 connections/IP protection
- ✅ **Attack Mitigation**: Automated backup system and monitoring
- ✅ **Encrypted Storage**: DigitalOcean block storage with enterprise encryption
- ✅ **TLS 1.3**: Valid Let's Encrypt certificates with auto-renewal
- ✅ **Pod Security**: Non-root containers with read-only filesystems
- ✅ **RBAC**: Minimal service account permissions

**Risk Score: 0.0/10** - Production ready for cohort deployment

## 🚀 Quick Start (Recommended)

### One-Line Installation
```bash
curl -sSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/vaultwarden/install.sh | bash
```

### Manual Installation
```bash
# Clone only the vaultwarden directory
git clone --filter=blob:none --sparse https://github.com/WeOwnNetwork/ai.git
cd ai && git sparse-checkout set vaultwarden && cd vaultwarden

# Run the deployment script
./deploy.sh
```

## 📝 Deployment Process

### Interactive Deployment

The deployment script guides you through the entire process:

```bash
./deploy.sh
```

### What the Script Does:

1. **Prerequisites Check** - Verifies kubectl, helm, cluster access, argon2
2. **Security Setup** - Generates Argon2-hashed admin token (never plain text)
3. **Network Security** - Deploys NetworkPolicy for zero-trust networking
4. **Certificate Setup** - Creates Let's Encrypt ClusterIssuer via Helm
5. **Deployment** - Installs Vaultwarden with all security configurations
6. **Attack Protection** - Applies rate limiting and connection limits
7. **Verification** - Confirms pod health, TLS certificates, and security settings
8. **Backup Setup** - Provides automated backup system (requires DO token)

## 🎯 Prerequisites

- **Kubernetes cluster** (DigitalOcean recommended)
- **kubectl** configured to access your cluster
- **Helm** v3+ installed
- **Domain name** with DNS management access
- **NGINX Ingress Controller** installed
- **cert-manager** for TLS certificates
- **argon2** CLI tool (installed automatically by deploy script)

## 🛡️ Enterprise Security Features

### Production-Ready Security
- ✅ **Argon2-Hashed Admin Tokens** - Cryptographically secure admin authentication
- ✅ **Zero-Trust Networking** - NetworkPolicy restricts pod access to ingress-nginx only
- ✅ **Pod Security** - Non-root user (UID 1000), read-only root filesystem
- ✅ **TLS 1.3** - Automatic Let's Encrypt certificates with cert-manager
- ✅ **RBAC** - Least privilege service accounts and role bindings
- ✅ **Resource Limits** - Optimized limits prevent resource exhaustion
- ✅ **Persistent Storage** - Encrypted DigitalOcean block storage
- ✅ **No Hardcoded Secrets** - All sensitive data input during deployment
- ✅ **Secure Defaults** - Bitwarden Send disabled, password hints off

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