# WeOwn Vaultwarden Deployment Guide for Cohort Members

**🔐 Enterprise-Grade, Self-Hosted Password Management**

This guide will walk you through deploying your own secure Vaultwarden instance on Kubernetes with automated TLS certificates and enterprise security features.

## Prerequisites

### Required Tools
- **kubectl** - Kubernetes command-line tool
- **helm** - Kubernetes package manager  
- **docker** - For password hashing (if not using the automated script)
- **Access to a Kubernetes cluster** (DigitalOcean recommended)
- **Domain name** with DNS management access

### Required Access
- Kubernetes cluster admin access
- DNS management for your domain
- Email address for Let's Encrypt certificates

## Quick Start (Automated Deployment)

### Option 1: One-Line Installation (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/vaultwarden/install.sh | bash
```

**This will:**
- ✅ Download only the vaultwarden deployment files
- ✅ Check all prerequisites and guide installation
- ✅ Run the interactive deployment script
- ✅ Work on any machine with any Kubernetes cluster

### Option 2: Manual Installation
```bash
# Clone only the vaultwarden directory
git clone --filter=blob:none --sparse https://github.com/WeOwnNetwork/ai.git
cd ai && git sparse-checkout set vaultwarden && cd vaultwarden

# Run the deployment script
./deploy.sh
```

### What the Script Does
The deployment script will:
1. ✅ **Check prerequisites** - Verify kubectl, helm, docker, curl, git are installed
2. 🔗 **Test cluster connection** - Ensure you're connected to your Kubernetes cluster
3. 📝 **Collect configuration** - Prompt for subdomain, domain, email
4. 🔐 **Generate admin password** - Create secure password automatically
5. 🌐 **Guide DNS setup** - Get external IP and provide exact DNS instructions
6. 🔧 **Install infrastructure** - NGINX Ingress Controller and cert-manager if needed
7. 🚀 **Deploy Vaultwarden** - With enterprise security features
8. 🔒 **Set up TLS certificates** - Automated Let's Encrypt certificates

### Step 3: Configure DNS
When prompted, create an A record in your DNS provider:
- **Type**: A
- **Name**: `[your-subdomain]` (e.g., `vault`)
- **Value**: `[provided-external-ip]`
- **TTL**: 300 (5 minutes - fast for setup, increase to 3600+ for production)

**About TTL (Time To Live):**
- **TTL 300**: Fast DNS propagation (5 minutes) - ideal for setup and testing
- **TTL 3600+**: More stable for production, reduces DNS server load
- **Recommendation**: Start with 300, increase to 3600 once everything works

### Step 4: Access Your Vault
After deployment completes:
- **Web Vault**: `https://[subdomain].[domain]`
- **Admin Panel**: `https://[subdomain].[domain]/admin`
- **Admin Password**: Provided by the deployment script

## Manual Deployment (Advanced Users)

### Step 1: Install Prerequisites
```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/do/deploy.yaml

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

# Wait for components to be ready
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s
```

### Step 2: Create Namespace and Secrets
```bash
# Create namespace
kubectl create namespace vaultwarden

# Generate admin password hash
ADMIN_PASSWORD="your-secure-password"
ADMIN_TOKEN_HASH=$(docker run --rm vaultwarden/server:latest /vaultwarden hash "${ADMIN_PASSWORD}")

# Create admin secret
kubectl create secret generic vaultwarden-admin \
  --from-literal=token="${ADMIN_TOKEN_HASH}" \
  --namespace=vaultwarden
```

### Step 3: Configure and Deploy
```bash
# Update values.yaml with your configuration
cp helm/values.yaml helm/values-custom.yaml

# Edit the values file
vim helm/values-custom.yaml
# Update:
# - global.subdomain: "your-subdomain"
# - global.domain: "your-domain.com"

# Update Let's Encrypt email in cluster issuer
sed -i 's/roman@weown.xyz/your-email@domain.com/g' helm/templates/clusterissuer.yaml

# Deploy with Helm
helm install vaultwarden ./helm \
  --namespace vaultwarden \
  --values helm/values-custom.yaml \
  --wait
```

## Security Features Included

### 🛡️ Enterprise Security Standards
- **Pod Security Context**: Non-root containers, read-only filesystem
- **Network Policies**: Zero-trust networking, ingress/egress controls
- **RBAC**: Role-based access control with least privilege
- **Resource Limits**: CPU/memory constraints for stability
- **Security Contexts**: Dropped capabilities, seccomp profiles

### 🔒 TLS/HTTPS
- **Automated TLS**: Let's Encrypt certificates with auto-renewal
- **Force HTTPS**: All traffic redirected to HTTPS
- **Modern TLS**: Strong cipher suites and protocols

### 🔐 Secrets Management
- **Kubernetes Secrets**: Admin tokens stored securely
- **No Hardcoded Credentials**: All sensitive data in secrets
- **Argon2id Hashing**: Secure password hashing for admin access

## Browser Extension Setup

### Chrome/Edge/Firefox
1. Install the [official Bitwarden extension](https://bitwarden.com/download/)
2. Click the extension icon
3. Click the settings gear ⚙️
4. Set **Server URL** to: `https://[your-subdomain].[your-domain]`
5. Click **Save**
6. Create your account or log in

### Mobile Apps
1. Download the official Bitwarden app
2. On the login screen, tap the settings gear
3. Set **Server URL** to: `https://[your-subdomain].[your-domain]`
4. Save and log in with your account

## Post-Deployment Security Checklist

### Immediate Actions (First 24 Hours)
- [ ] **Save admin password** in a secure location
- [ ] **Access admin panel** and verify configuration
- [ ] **Create your user account** through the web vault
- [ ] **Disable user registration** in admin panel (after creating accounts)
- [ ] **Test browser extension** login and sync
- [ ] **Verify TLS certificate** is valid and auto-renewing

### Ongoing Security
- [ ] **Regular backups** of vault data (admin panel > Backup)
- [ ] **Monitor certificate expiry** (should auto-renew)
- [ ] **Update Vaultwarden** regularly for security patches
- [ ] **Review access logs** in admin panel
- [ ] **Audit user accounts** and remove unused accounts

## Troubleshooting

### Common Issues

**DNS Not Resolving**
```bash
# Test DNS resolution
nslookup [subdomain].[domain]
# Should return your ingress controller IP
```

**TLS Certificate Issues**
```bash
# Check certificate status
kubectl get certificate -n vaultwarden
kubectl describe certificate vaultwarden-tls -n vaultwarden

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

**Pod Not Starting**
```bash
# Check pod status
kubectl get pods -n vaultwarden
kubectl describe pod -n vaultwarden [pod-name]
kubectl logs -n vaultwarden [pod-name]
```

**Ingress Issues**
```bash
# Check ingress status
kubectl get ingress -n vaultwarden
kubectl describe ingress -n vaultwarden vaultwarden

# Check NGINX ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

## Backup and Recovery

### Creating Backups
1. Access admin panel: `https://[subdomain].[domain]/admin`
2. Navigate to **Backup** section
3. Click **Backup Database**
4. Store backup file securely (encrypted storage recommended)

### Restoring from Backup
1. Stop the current deployment: `helm uninstall vaultwarden -n vaultwarden`
2. Replace data in persistent volume with backup data
3. Redeploy: `helm install vaultwarden ./helm -n vaultwarden`

## Support and Resources

### WeOwn Resources
- **Knowledge Base**: Internal WeOwn documentation
- **Cohort Support**: Ask in cohort channels
- **Technical Issues**: Contact Roman Di Domizio

### External Resources
- **Vaultwarden Wiki**: https://github.com/dani-garcia/vaultwarden/wiki
- **Bitwarden Help**: https://bitwarden.com/help/
- **Kubernetes Docs**: https://kubernetes.io/docs/

## Advanced Configuration

### Custom Environment Variables
Edit `helm/values.yaml` to add custom Vaultwarden environment variables:

```yaml
vaultwarden:
  config:
    # Add custom settings here
    orgCreationUsers: "admin@yourdomain.com"
    invitationsAllowed: false
    # See Vaultwarden wiki for all options
```

### High Availability Setup
For production environments requiring HA:
1. Use external database (PostgreSQL recommended)
2. Configure shared storage (NFS/EFS)
3. Enable horizontal pod autoscaling
4. Set up monitoring and alerting

### Monitoring Integration
To integrate with Prometheus/Grafana:
```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
```

---

**Security Classification: WeOwn Internal**  
**Last Updated**: 2025-08-07  
**Version**: 1.0.0
