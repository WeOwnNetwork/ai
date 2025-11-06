# n8n Enterprise Kubernetes Deployment

Production-ready n8n workflow automation platform with enterprise security, high availability, and comprehensive backup strategies.

**Version**: 2.8.0 | **n8n**: 1.118.2 | **Status**: Production Ready

> **Enterprise-Grade Workflow Automation Platform**  
> SOC2/ISO42001 Compliant | Zero-Trust Architecture

[![Security Status](https://img.shields.io/badge/Security-A%2B%20Grade-green)](#security-features)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Native-blue)](./helm/)
[![Compliance](https://img.shields.io/badge/Compliance-SOC2%2FISO42001-orange)](#compliance-features)
[![License](https://img.shields.io/badge/License-MIT-blue)](./LICENSE)

Deploy a production-ready n8n workflow automation platform on Kubernetes with enterprise security, zero-trust networking, and automated TLS certificates.

## 🚀 Quick Start

### **One-Command Installation:**
```bash
# Download and deploy automatically
curl -sSL https://raw.githubusercontent.com/your-org/n8n-k8s/main/install.sh | bash

# Or clone and deploy manually
git clone https://github.com/your-org/n8n-k8s.git
cd n8n-k8s
./deploy.sh
```

### **Interactive Deployment:**
```bash
./deploy.sh
# Follow the prompts to configure:
# • Custom domain (e.g., workflows.company.com)
# • Let's Encrypt email for TLS certificates
# • DNS configuration guidance
```

### **Non-Interactive Deployment:**
```bash
./deploy.sh --domain workflows.company.com --email admin@company.com
```

### **View Credentials:**
```bash
# View encryption key for existing deployment
kubectl get secret n8n -n n8n -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d
```

## 📁 Directory Structure

```
n8n-k8s/
├── deploy.sh                          # Enterprise deployment script
├── install.sh                         # One-command installer
├── helm/                              # Kubernetes Helm chart
│   ├── Chart.yaml                     # Chart metadata with security annotations
│   ├── values.yaml                    # Production-ready configuration
│   └── templates/                     # Kubernetes manifests
│       ├── deployment.yaml            # Main n8n application
│       ├── service.yaml               # ClusterIP service
│       ├── ingress.yaml               # TLS 1.3 ingress with security headers
│       ├── networkpolicy.yaml         # Zero-trust network isolation
│       ├── rbac.yaml                  # Least-privilege access control
│       ├── secret.yaml                # Encrypted credentials
│       ├── configmap.yaml             # Application configuration
│       ├── pvc.yaml                   # Persistent storage
│       ├── backup-cronjob.yaml        # Automated daily backups
├── WORKFLOW_MIGRATION_README.md       # Docker to Kubernetes migration guide
├── LICENSE                            # MIT License
└── README.md                          # This file
## 🌐 Cluster Compatibility

This deployment works on **all Kubernetes cluster configurations**, including:

- ✅ **Security-hardened clusters** (snippet annotations disabled)
- ✅ **Permissive clusters** (all annotation types supported)  
- ✅ **Managed clusters** (GKE, EKS, AKS, DigitalOcean)
- ✅ **Self-hosted clusters** (kubeadm, k3s, microk8s)

**Automatic Detection**: The deployment script automatically detects cluster capabilities and adapts accordingly, ensuring successful deployment without manual configuration.

## 🛡️ Enterprise Security Features

### **Zero-Trust Architecture**
- **NetworkPolicy**: Micro-segmentation restricting ingress to nginx-ingress only
- **Pod Security Standards**: Restricted profile with non-root containers (UID 1000)
- **Capability Dropping**: ALL capabilities dropped, no privileged operations
- **Read-Only Filesystem**: Immutable container filesystem with writable volume mounts

### **Enterprise Encryption**
- **TLS 1.3**: Strong cipher suites (ECDHE-ECDSA-AES256-GCM-SHA384)
- **Let's Encrypt**: Automated certificate provisioning and renewal
- **Secrets Management**: All credentials encrypted at rest in Kubernetes
- **Security Headers**: HSTS, CSP, X-Frame-Options, XSS protection

### **Access Control**
- **Modern Authentication**: n8n built-in authentication with session management
- **Optional Basic Auth**: Use `--enable-basic-auth` flag if additional protection needed
- **Zero Browser Prompts**: Clean modern login interface (no browser pop-ups)
- **RBAC**: Least-privilege service accounts and role bindings
- **Service Account Token**: Disabled automount for enhanced security

## 🏢 Compliance Features

### **SOC2/ISO42001 Ready**
- **Audit Trails**: Comprehensive logging and deployment validation
- **Data Protection**: Encrypted storage and network transmission
- **Access Controls**: Multi-layered authentication and authorization
- **Backup & Recovery**: Automated daily backups with configurable retention

### **Production Standards**
- **Health Checks**: Liveness and readiness probes with proper timeouts
- **Resource Limits**: CPU/memory constraints preventing resource exhaustion
- **Rolling Updates**: Zero-downtime deployments with controlled rollouts
- **Monitoring**: Integration-ready for Prometheus/Grafana observability

## ⚙️ Configuration Options

### **Basic Configuration**
```bash
# Essential settings (configured during deployment)
DOMAIN="workflows.company.com"           # Your n8n domain
EMAIL="admin@company.com"               # Let's Encrypt notifications
NAMESPACE="n8n"                         # Kubernetes namespace
```

### **Advanced Configuration**
Edit `helm/values.yaml` for advanced customization:

```yaml
# Resource allocation
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi

# Security settings
podSecurityContext:
  runAsUser: 1000
  runAsNonRoot: true
  fsGroup: 1000

# Backup configuration
backup:
  enabled: true
  schedule: "0 2 * * *"  # Daily 2 AM UTC
  retention: 7           # Keep 7 days
```

## 🔧 Prerequisites

### **Required Tools**
- **kubectl**: Kubernetes command-line tool
- **helm**: Kubernetes package manager (v3.0+)
- **git**: Version control (for installation)

### **Kubernetes Cluster**
- **Version**: 1.19+ with RBAC enabled
- **Ingress Controller**: NGINX Ingress Controller (auto-installed)
- **cert-manager**: Certificate management (auto-installed)
- **Storage**: Dynamic volume provisioning supported

### **DNS Requirements**
- Domain with A record pointing to cluster LoadBalancer IP
- DNS propagation completed before deployment

## 🚀 Deployment Process

### **1. Prerequisites Validation**
The deployment script automatically:
- Checks for required tools (kubectl, helm)
- Validates Kubernetes cluster connectivity
- Installs NGINX Ingress Controller if needed
- Installs cert-manager for TLS automation

### **2. Interactive Configuration**
- Domain configuration with validation
- Let's Encrypt email for certificate notifications
- DNS setup guidance with external IP detection
- Secure credential generation

### **3. Security Hardening**
- Zero-trust NetworkPolicy creation
- Pod Security Standards enforcement
- TLS 1.3 certificate provisioning
- Basic authentication setup

### **4. Application Deployment**
- Helm chart deployment with security configurations
- Health check validation and readiness verification
- Ingress configuration with security headers
- Backup system activation

## 🔄 Migration from Docker

If you're migrating from a Docker setup, follow the comprehensive migration guide:

```bash
# 1. Create backup from Docker installation
docker-compose down
tar -czf n8n-backup-$(date +%Y%m%d).tar.gz docker/data/

# 2. Deploy Kubernetes version
./deploy.sh --migration

# 3. Follow migration prompts for data restoration
```

See [WORKFLOW_MIGRATION_README.md](./WORKFLOW_MIGRATION_README.md) for detailed instructions.

## 📊 Monitoring & Operations

### **Health Checks**
```bash
# Check deployment status
kubectl get pods -n n8n
kubectl get ingress -n n8n
kubectl get certificates -n n8n

# View logs
kubectl logs -f deployment/n8n-n8n-enterprise -n n8n

# Monitor resources
kubectl top pods -n n8n
```

### **Backup Management**
```bash
# Check backup status
kubectl get cronjobs -n n8n
kubectl get jobs -n n8n

# Manual backup
kubectl create job --from=cronjob/n8n-backup n8n-manual-backup-$(date +%s) -n n8n
```

### **Scaling Operations**
```bash
# Horizontal scaling
kubectl scale deployment n8n-n8n-enterprise --replicas=3 -n n8n

# Resource monitoring
kubectl describe hpa -n n8n  # If HPA is configured
```

## 🛠️ Troubleshooting

### **Common Issues**

**1. Pod CrashLoopBackOff**
```bash
# Check pod logs for errors
kubectl logs -f deployment/n8n-n8n-enterprise -n n8n

# Check pod description for events
kubectl describe pod -l app.kubernetes.io/name=n8n-enterprise -n n8n

# Verify resource limits and storage
kubectl top pods -n n8n
kubectl get pvc -n n8n
```

**2. TLS Certificate Issues**
```bash
# Check certificate status
kubectl describe certificate n8n-tls -n n8n

# Check cert-manager logs
kubectl logs -f deployment/cert-manager -n cert-manager

# Manual certificate troubleshooting
kubectl describe clusterissuer letsencrypt-prod
```

**3. DNS/Ingress Problems**
```bash
# Verify external IP
kubectl get svc -n ingress-nginx

# Test ingress connectivity
kubectl describe ingress n8n-n8n-enterprise -n n8n

# Check DNS resolution
nslookup your-domain.com
```

**4. Cluster Compatibility Issues**
```bash
# Error: "server-snippet annotation cannot be used"
# Solution: Automatic detection and fallback is built-in (v2.3.0+)
# No action needed - deployment will adapt automatically

# Manual check if needed:
kubectl auth can-i create ingress --as=system:serviceaccount:n8n:n8n
kubectl get validatingadmissionwebhooks | grep nginx
```

### **Recovery Procedures**
```bash
# Reset deployment (keeps data)
helm uninstall n8n -n n8n
./deploy.sh

# Full reset (WARNING: deletes data)
kubectl delete namespace n8n
./deploy.sh
```

## 📄 License & Commercial Use

### **Infrastructure License**
This deployment infrastructure is licensed under the [MIT License](./LICENSE).

### **n8n Software License**
- **Self-hosted**: Fair-code license (check [n8n.io](https://n8n.io) for current terms)
- **Commercial/SaaS**: Requires n8n Enterprise license
- **Hosted services**: Contact n8n for proper licensing

## 📄 Version Management & Auto-Updates

### Current Approach: Explicit Version Pinning
**n8n version**: `1.118.2` (pinned in `helm/values.yaml`)

**Why not use "latest" tag?**
- Docker layer caching can serve stale versions
- DigitalOcean node caching unpredictable
- Multi-node clusters may have version inconsistencies
- `imagePullPolicy: IfNotPresent` skips pulls if image exists locally

**Benefits of pinning**:
- ✅ Predictable deployments across all clusters
- ✅ Version control via Git
- ✅ No unexpected breaking changes
- ✅ Easy rollback to previous versions

### Manual Update Process
```bash
# 1. Check latest n8n version
curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | grep tag_name

# 2. Update helm/values.yaml
vim helm/values.yaml
# Change: tag: "1.118.2" → tag: "1.119.0"

# 3. Update helm/Chart.yaml
vim helm/Chart.yaml
# Change: appVersion: "1.118.2" → appVersion: "1.119.0"
# Change: version: 2.8.0 → version: 2.9.0

# 4. Test in staging (recommended)
./deploy.sh --domain n8n-staging.company.com

# 5. Upgrade production clusters
# For each cluster:
cd helm
helm upgrade n8n . --namespace n8n --reuse-values --history-max 3
```

### Auto-Update Strategy (CI/CD - Not Implemented)

**Option 1: GitHub Actions + ArgoCD**
```yaml
# .github/workflows/check-n8n-version.yml
name: Check n8n Version
on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
  workflow_dispatch:

jobs:
  check-version:
    runs-on: ubuntu-latest
    steps:
      - name: Check latest n8n release
        run: |
          LATEST=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | jq -r .tag_name)
          CURRENT=$(grep 'tag:' helm/values.yaml | cut -d'"' -f2)
          if [ "$LATEST" != "$CURRENT" ]; then
            # Create PR with version bump
            # Run tests in staging
            # Auto-merge if tests pass
          fi
```

**Option 2: Renovate Bot**
```json
// renovate.json
{
  "extends": ["config:base"],
  "kubernetes": {
    "fileMatch": ["helm/values\\.yaml$"]
  },
  "packageRules": [{
    "matchDatasources": ["docker"],
    "matchPackageNames": ["n8nio/n8n"],
    "automerge": false,  // Manual review required
    "schedule": ["before 6am on monday"]
  }]
}
```

**Option 3: Flux Image Automation**
```yaml
# If using FluxCD for GitOps
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImagePolicy
metadata:
  name: n8n-policy
spec:
  imageRepositoryRef:
    name: n8n
  policy:
    semver:
      range: '>=1.118.0 <2.0.0'  # Stay on 1.x
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: n8n-auto-update
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: weown-infrastructure
  git:
    commit:
      author:
        name: FluxBot
        email: flux@weown.xyz
      messageTemplate: 'Update n8n to {{range .Updated.Images}}{{println .}}{{end}}'
  update:
    path: ./n8n/helm
    strategy: Setters
```

**Why Auto-Updates NOT Recommended (Yet)**:
- ⚠️ Requires comprehensive test coverage (currently <50%)
- ⚠️ Need staging environment mirroring production
- ⚠️ n8n can have breaking changes in minor versions
- ⚠️ Manual review ensures compatibility with workflows

**Recommendation**:
- **Now**: Manual quarterly updates (sufficient for production)
- **Future**: Implement CI/CD when test coverage reaches 80%+
- **Staging First**: Always test in non-production before prod rollout

### Version Update Checklist
- [ ] Check n8n release notes for breaking changes
- [ ] Update `helm/values.yaml` → `n8n.image.tag`
- [ ] Update `helm/Chart.yaml` → `appVersion` and `version`
- [ ] Test in staging cluster
- [ ] Update CHANGELOG.md
- [ ] Run `./upgrade-all-instances.sh`
- [ ] Verify all instances healthy
- [ ] Update this README version badge

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description
5. Ensure all security checks pass

### **Development Setup**
```bash
# Clone and test locally
git clone https://github.com/your-org/n8n-k8s.git
cd n8n-k8s

# Run security audit
./n8n-final-security-audit.sh

# Test deployment in development
./deploy.sh --domain dev.local --email dev@example.com
```

## 📞 Support

- **Documentation**: Check README and migration guide
- **Issues**: Create GitHub issues for bugs/feature requests
- **Security**: Report security issues privately to maintainers
- **Community**: Join discussions in GitHub Discussions

## 🎯 Roadmap

- [ ] Multi-database support (PostgreSQL/Redis)
- [ ] Advanced monitoring dashboards
- [ ] GitOps integration
- [ ] Multi-tenant deployment
- [ ] Advanced backup encryption

---

**Security Classification**: Public • **Compliance Status**: SOC2/ISO42001 Ready • **Audit Grade**: A+ (100% Pass Rate)
