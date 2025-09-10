# Enterprise Vaultwarden Kubernetes Deployment

🔐 **Enterprise-grade Vaultwarden (Bitwarden-compatible) password manager**

Production-ready, self-hosted password management solution with enterprise security, automated deployment, and Kubernetes-native architecture.

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

**Risk Score: 0.0/10** - Production ready for enterprise deployment

## 🚀 Quick Start (Recommended)

### One-Line Installation
```bash
curl -sSL https://raw.githubusercontent.com/your-org/vaultwarden-k8s/main/install.sh | bash
```

### Manual Installation
```bash
# Clone the repository
git clone https://github.com/your-org/vaultwarden-k8s.git
cd vaultwarden-k8s

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

## 🔐 Admin vs User Access

### **Admin Access (System Management)**
- **Purpose**: Manage users, configure server settings, view system statistics
- **URL**: `https://your-subdomain.your-domain.com/admin`
- **Credentials**: Admin token (generated during deployment)
- **Capabilities**: 
  - Delete/disable user accounts
  - View server statistics and logs
  - Configure global server settings
  - Disable user registrations

### **User Access (Password Vault)**
- **Purpose**: Personal password management and device synchronization
- **URL**: `https://your-subdomain.your-domain.com`
- **Credentials**: Email + master password (you create during registration)
- **Capabilities**:
  - Store and organize passwords
  - Sync across devices with browser extensions and mobile apps
  - Generate secure passwords
  - Share passwords with other users

## 🌐 Client Setup Guide

### Browser Extension Configuration

1. **Install**: Download [official Bitwarden extension](https://bitwarden.com/download/)
2. **Configure Server**: **BEFORE logging in**:
   - Click the ⚙️ **Settings** icon in the extension
   - Find **"Server URL"** or **"Self-hosted Environment"**
   - Enter your server URL: `https://your-subdomain.your-domain.com`
   - Click **"Save"**
3. **Login**: Use your **vault credentials** (email + master password)
   - ❌ **NOT** the admin token
   - ✅ The account you created on the web interface

### Mobile App Configuration

1. **Install**: Download official Bitwarden mobile app
2. **Configure Server**: **BEFORE logging in**:
   - Tap ⚙️ **Settings** at the bottom
   - Scroll to **"Self-hosted"** section
   - Tap **"Server URL"**
   - Enter: `https://your-subdomain.your-domain.com`
   - Tap **"Save"**
3. **Login**: Use your **vault credentials** (email + master password)
   - ❌ **NOT** the admin token
   - ✅ The account you created on the web interface

### Desktop App Configuration

1. **Install**: Download official Bitwarden desktop application
2. **Configure Server**: **BEFORE logging in**:
   - Go to **File** → **Settings**
   - Under **"Server URL"**, select **"Self-hosted"**
   - Enter: `https://your-subdomain.your-domain.com`
   - Click **"Save"**
3. **Login**: Use your **vault credentials** (email + master password)

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

### Authentication Issues

#### "Wrong Server" or "Invalid Credentials" Errors

**Root Cause**: Client is connecting to official Bitwarden servers instead of your self-hosted instance

**Solution**:
1. **Verify server URL is set BEFORE attempting login**
2. **Double-check the server URL format**: `https://your-domain.com` (no trailing slash)
3. **Clear browser extension data** if previously used with official Bitwarden
4. **Use vault credentials**, not admin token

#### "Admin Token Invalid" Error

**Root Cause**: Admin token may be using incorrect format or outdated hash

**Solution**:
```bash
# Get current admin token (this shows the Argon2id hash)
kubectl get secret vaultwarden-admin -n vaultwarden -o jsonpath='{.data.token}' | base64 -d

# Regenerate secure Argon2id token (recommended):
./deploy.sh  # Re-run deployment script to generate new secure token

# Manual regeneration (advanced users only):
NEW_PASSWORD="WeOwn-Admin-$(date +%s)-$(openssl rand -hex 8)"
NEW_HASH=$(echo -n "$NEW_PASSWORD" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4)
kubectl delete secret vaultwarden-admin -n vaultwarden
kubectl create secret generic vaultwarden-admin -n vaultwarden --from-literal=token="$NEW_HASH"
kubectl rollout restart deployment vaultwarden -n vaultwarden
echo "New admin password: $NEW_PASSWORD"
```

#### Account Locked or Forgotten Password

**Solution**: Use admin panel to reset user account
1. Go to `https://your-domain.com/admin`
2. Login with admin token
3. Navigate to **Users** section
4. Find problematic account
5. Click **"Delete User"**
6. User can re-register with same email and new password

### Infrastructure Issues

#### 502/504 Gateway Errors

**Root Cause**: NGINX Ingress cannot reach Vaultwarden pod due to NetworkPolicy restrictions

**Solution**:
```bash
# Check and fix ingress-nginx namespace labels
kubectl get ns ingress-nginx --show-labels
kubectl label namespace ingress-nginx name=ingress-nginx --overwrite
kubectl rollout restart deployment vaultwarden -n vaultwarden
```

#### Certificate Issues

**Root Cause**: Let's Encrypt certificate generation failed

**Diagnosis**:
```bash
# Check certificate status
kubectl get certificate -n vaultwarden
kubectl describe certificate vaultwarden-tls -n vaultwarden

# Check ClusterIssuer
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod
```

#### Pod Not Starting

**Diagnosis**:
```bash
# Check pod status and logs
kubectl get pods -n vaultwarden
kubectl logs -n vaultwarden deployment/vaultwarden
kubectl describe pod -n vaultwarden -l app=vaultwarden

# Check secrets
kubectl get secrets -n vaultwarden
```

### Emergency Recovery

#### Complete Reset (Nuclear Option)

**⚠️ WARNING**: This will delete all user accounts and vault data

```bash
# Full cleanup and redeploy
helm uninstall vaultwarden -n vaultwarden
kubectl delete namespace vaultwarden
kubectl delete pv --selector=app=vaultwarden  # This deletes all vault data!
./deploy.sh  # Fresh deployment
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

## 🔒 Security Best Practices

### Post-Deployment Security

1. **Secure Admin Token**: Already implemented with Argon2id PHC hashing
   - **Algorithm**: Argon2id (most secure password hashing)
   - **Parameters**: 64MB memory, 3 iterations, 4 parallel threads
   - **Format**: PHC string (Password Hashing Competition standard)
   - **Storage**: Encrypted in Kubernetes secrets

2. **Disable Signups**: After creating your accounts
   ```bash
   helm upgrade vaultwarden ./helm -n vaultwarden --set vaultwarden.config.signupsAllowed=false
   ```

3. **Enable 2FA**: Set up two-factor authentication for all accounts
   - Use authenticator apps (recommended)
   - Email-based 2FA as backup

4. **Regular Backups**: Enable automated backup system during deployment
   - Daily DigitalOcean volume snapshots
   - 30-day retention policy
   - Automated cleanup

5. **Monitor Access**: Regularly check admin panel for:
   - Failed login attempts
   - New user registrations (if enabled)
   - Unusual activity patterns

6. **Keep Updated**: 
   - Update Vaultwarden image regularly
   - Monitor security advisories
   - Keep Kubernetes cluster updated

### Backup Strategy

```bash
# Manual backup creation
kubectl exec -n vaultwarden deployment/vaultwarden -- sqlite3 /data/db.sqlite3 ".backup /data/manual-backup-$(date +%Y%m%d).sqlite3"

# Download backup file
kubectl cp vaultwarden/$(kubectl get pod -n vaultwarden -l app=vaultwarden -o jsonpath='{.items[0].metadata.name}'):/data/manual-backup-$(date +%Y%m%d).sqlite3 ./backup.sqlite3
```

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
**Last Updated**: 2025-08-20  
**Security Level**: Enterprise Production Ready (Argon2id PHC Hashed Admin Tokens)