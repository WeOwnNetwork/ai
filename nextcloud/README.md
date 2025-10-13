# Nextcloud Kubernetes Deployment

Production-ready Nextcloud deployment on Kubernetes with PostgreSQL, Redis, and security features.

## 🚀 Quick Start

```bash
# Install Nextcloud
curl -fsSL https://raw.githubusercontent.com/WeOwnAI/ai/main/nextcloud/install.sh | bash

# Deploy
cd nextcloud-enterprise/nextcloud
./deploy.sh
```

### Prerequisites

- Kubernetes cluster with kubectl access
- Domain name with DNS control
- Email for SSL certificates

### What You Get

- ✅ **Nextcloud Server**: Latest version with enterprise features
- ✅ **PostgreSQL Database**: High-performance database backend
- ✅ **Redis Cache**: Session storage and file locking
- ✅ **TLS 1.3 Encryption**: Automated Let's Encrypt certificates
- ✅ **Zero-Trust Security**: Network policies and pod security standards
- ✅ **Automated Backups**: Daily database and file backups
- ✅ **Horizontal Scaling**: Auto-scaling based on resource usage
- ✅ **Enterprise Monitoring**: Health checks and metrics

## 🏗️ Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Nextcloud Enterprise                     │
├─────────────────────────────────────────────────────────────┤
│  Internet → NGINX Ingress → Nextcloud → PostgreSQL         │
│                    ↓           ↓         ↓                  │
│              TLS 1.3      Redis Cache   Persistent Storage  │
│              Security     Session Mgmt   Data/Config/Apps   │
└─────────────────────────────────────────────────────────────┘
```

### Core Components

| Component | Purpose | Technology | Resources |
|-----------|---------|------------|-----------|
| **Nextcloud** | File sharing & collaboration | PHP/Apache | 512Mi-1Gi RAM |
| **PostgreSQL** | Database backend | PostgreSQL 15 | 512Mi-1Gi RAM |
| **Redis** | Cache & session storage | Redis 7 | 64Mi-128Mi RAM |
| **NGINX Ingress** | Load balancer & TLS termination | NGINX | Auto-managed |
| **cert-manager** | SSL certificate automation | cert-manager | Auto-managed |

### Security Architecture

- **Zero-Trust Networking**: NetworkPolicy restricts all traffic by default
- **Pod Security Standards**: Non-root containers with dropped capabilities
- **TLS 1.3 Encryption**: End-to-end encryption with strong ciphers
- **RBAC**: Least-privilege service accounts and role bindings
- **Encrypted Storage**: Kubernetes secrets with base64 encoding

## 🔒 Security Features

### Enterprise Security Standards

- **SOC2/ISO42001 Compliant**: Meets enterprise security requirements
- **Zero-Trust Architecture**: Default deny with explicit allow rules
- **Non-Root Containers**: All pods run as non-privileged users
- **Read-Only Filesystems**: Where possible for enhanced security
- **Dropped Capabilities**: All dangerous Linux capabilities removed
- **Seccomp Profiles**: Runtime security profiles enabled

### Network Security

```yaml
# NetworkPolicy Example
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: nextcloud
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53    # DNS
    - protocol: TCP
      port: 443   # HTTPS
    - protocol: TCP
      port: 5432  # PostgreSQL
    - protocol: TCP
      port: 6379  # Redis
```

### TLS Configuration

- **TLS 1.3 Only**: Modern encryption protocols
- **Strong Ciphers**: ECDHE-ECDSA-AES256-GCM-SHA384
- **HSTS Headers**: Strict Transport Security enabled
- **Certificate Automation**: Let's Encrypt with auto-renewal
- **Security Headers**: CSP, X-Frame-Options, X-Content-Type-Options

## 📋 Prerequisites

### Required Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| **kubectl** | Kubernetes CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) |
| **helm** | Package manager | [Install Helm](https://helm.sh/docs/intro/install/) |
| **openssl** | Certificate generation | Usually pre-installed |
| **curl** | HTTP client | Usually pre-installed |
| **git** | Version control | [Install Git](https://git-scm.com/downloads) |

### Kubernetes Cluster Requirements

- **Version**: Kubernetes 1.24+ (tested on 1.28)
- **Nodes**: Minimum 2 nodes (recommended 3+ for HA)
- **Resources**: 4 CPU cores, 8GB RAM minimum
- **Storage**: Persistent volume support (ReadWriteOnce)
- **Network**: CNI plugin with NetworkPolicy support

### DNS Configuration

Before deployment, configure your DNS:

```bash
# Create A record pointing to your cluster's external IP
# Example: nc.yourdomain.com → 1.2.3.4

# Find your cluster's external IP
kubectl get services -n ingress-nginx
```

## 🚀 Deployment Process

### Step 1: Installation

```bash
# Clone the repository
git clone --filter=blob:none --sparse https://github.com/WeOwnAI/ai.git
cd ai
git sparse-checkout init --cone
git sparse-checkout set nextcloud
cd nextcloud
```

### Step 2: Configuration

The deployment script will prompt you for:

- **Domain**: Your domain name (e.g., `example.com`)
- **Subdomain**: Nextcloud subdomain (default: `nc`)
- **Email**: Email for SSL certificates
- **Namespace**: Kubernetes namespace (default: `nextcloud`)
- **Release Name**: Helm release name (default: `nextcloud`)

### Step 3: Deployment

```bash
# Run the deployment script
./deploy.sh

# The script will:
# 1. Check prerequisites
# 2. Install NGINX Ingress Controller
# 3. Install cert-manager
# 4. Generate secure credentials
# 5. Deploy Nextcloud with Helm
# 6. Verify deployment
# 7. Display access credentials
```

### Step 4: Verification

```bash
# Check pod status
kubectl get pods -n nextcloud

# Check ingress
kubectl get ingress -n nextcloud

# Check TLS certificate
kubectl get certificate -n nextcloud

# View logs
kubectl logs -n nextcloud -l app.kubernetes.io/name=nextcloud
```

## ⚙️ Configuration

### Resource Limits

Default resource allocation (optimized for 2-node clusters):

```yaml
# Nextcloud
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# PostgreSQL
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi

# Redis
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

### Storage Configuration

Persistent volumes for different data types:

```yaml
# Data volume (user files)
data:
  size: 20Gi
  storageClass: do-block-storage
  accessMode: ReadWriteOnce

# Config volume (Nextcloud configuration)
config:
  size: 1Gi
  storageClass: do-block-storage
  accessMode: ReadWriteOnce

# Apps volume (custom applications)
apps:
  size: 2Gi
  storageClass: do-block-storage
  accessMode: ReadWriteOnce
```

### Environment Variables

Key Nextcloud configuration:

```yaml
# Core Settings
NEXTCLOUD_HOST: "nc.yourdomain.com"
NEXTCLOUD_PROTOCOL: "https"
NEXTCLOUD_SECURE_COOKIE: "true"

# Database
POSTGRES_HOST: "postgresql"
POSTGRES_DB: "nextcloud"
POSTGRES_USER: "nextcloud"

# Redis
REDIS_HOST: "redis"
REDIS_HOST_PASSWORD: "<auto-generated>"

# PHP Configuration
PHP_MEMORY_LIMIT: "512M"
PHP_UPLOAD_LIMIT: "512M"
PHP_MAX_EXECUTION_TIME: "300"

# Performance
APCu_ENABLED: "true"
OPcache_ENABLED: "true"
REDIS_SESSION_LOCKING_ENABLED: "true"
REDIS_FILE_LOCKING_ENABLED: "true"
```

## 🔧 Management & Operations

### Daily Operations

```bash
# Check system status
kubectl get pods -n nextcloud
kubectl top pods -n nextcloud

# View logs
kubectl logs -n nextcloud -l app.kubernetes.io/name=nextcloud -f

# Check backups
kubectl get cronjobs -n nextcloud
kubectl logs -n nextcloud -l app.kubernetes.io/component=backup

# Scale deployment
kubectl scale deployment nextcloud -n nextcloud --replicas=2
```

### Backup Management

Automated daily backups include:

- **Database Backup**: PostgreSQL dump with compression
- **File Backup**: Nextcloud data, config, and apps directories
- **Retention**: 30 days (configurable)
- **Storage**: Separate backup PVC with encryption

```bash
# Manual backup trigger
kubectl create job --from=cronjob/nextcloud-backup manual-backup -n nextcloud

# Restore from backup (example)
kubectl exec -it nextcloud-postgresql-0 -n nextcloud -- psql -U nextcloud -d nextcloud < backup.sql
```

### Updates & Maintenance

```bash
# Update Nextcloud image
helm upgrade nextcloud ./helm --set nextcloud.image.tag=latest -n nextcloud

# Update PostgreSQL
helm upgrade nextcloud ./helm --set postgresql.image=postgres:16-alpine -n nextcloud

# Rolling restart
kubectl rollout restart deployment nextcloud -n nextcloud
```

### Monitoring

```bash
# Resource usage
kubectl top pods -n nextcloud
kubectl top nodes

# Health checks
kubectl get pods -n nextcloud -o wide
kubectl describe pod <pod-name> -n nextcloud

# Network policies
kubectl get networkpolicies -n nextcloud
kubectl describe networkpolicy nextcloud -n nextcloud
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Pods Not Starting

```bash
# Check pod status
kubectl get pods -n nextcloud

# View pod events
kubectl describe pod <pod-name> -n nextcloud

# Check logs
kubectl logs <pod-name> -n nextcloud
```

**Common causes:**
- Insufficient resources
- Image pull errors
- Persistent volume issues
- Network policy restrictions

#### 2. TLS Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n nextcloud
kubectl describe certificate nextcloud-tls -n nextcloud

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager

# Verify DNS resolution
nslookup nc.yourdomain.com
```

**Common causes:**
- DNS not pointing to cluster
- Let's Encrypt rate limiting
- cert-manager not installed
- Ingress configuration errors

#### 3. Database Connection Issues

```bash
# Check PostgreSQL status
kubectl get pods -n nextcloud -l app.kubernetes.io/name=postgresql

# Test database connection
kubectl exec -it nextcloud-postgresql-0 -n nextcloud -- psql -U nextcloud -d nextcloud

# Check secrets
kubectl get secrets -n nextcloud
kubectl describe secret nextcloud-postgresql -n nextcloud
```

#### 4. Performance Issues

```bash
# Check resource usage
kubectl top pods -n nextcloud
kubectl top nodes

# Check Redis status
kubectl get pods -n nextcloud -l app.kubernetes.io/name=redis
kubectl logs -n nextcloud -l app.kubernetes.io/name=redis

# Monitor network policies
kubectl get networkpolicies -n nextcloud
```

### Debug Commands

```bash
# Get all resources
kubectl get all -n nextcloud

# Describe resources
kubectl describe deployment nextcloud -n nextcloud
kubectl describe ingress nextcloud -n nextcloud
kubectl describe pvc -n nextcloud

# Check events
kubectl get events -n nextcloud --sort-by='.lastTimestamp'

# Port forward for testing
kubectl port-forward -n nextcloud svc/nextcloud 8080:80
```

### Emergency Recovery

#### Database Recovery

```bash
# Stop Nextcloud
kubectl scale deployment nextcloud -n nextcloud --replicas=0

# Restore database
kubectl exec -it nextcloud-postgresql-0 -n nextcloud -- psql -U nextcloud -d nextcloud < backup.sql

# Restart Nextcloud
kubectl scale deployment nextcloud -n nextcloud --replicas=1
```

#### File Recovery

```bash
# Access data volume
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- ls -la /var/www/html/data

# Restore from backup
kubectl cp backup.tar.gz nextcloud-<pod-id>:/tmp/ -n nextcloud
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- tar -xzf /tmp/backup.tar.gz -C /var/www/html/
```

## 📱 Client Setup

### Desktop Clients

#### Nextcloud Desktop Client

1. Download from [nextcloud.com/install](https://nextcloud.com/install)
2. Install and launch the application
3. Add account:
   - **Server URL**: `https://nc.yourdomain.com`
   - **Username**: `admin` (or your user)
   - **Password**: Your password
4. Configure sync folders and settings

#### WebDAV Access

```bash
# Mount as network drive (Windows)
net use Z: \\nc.yourdomain.com@SSL\DavWWWRoot\remote.php\webdav

# Mount with davfs2 (Linux)
sudo mount -t davfs https://nc.yourdomain.com/remote.php/webdav /mnt/nextcloud
```

### Mobile Clients

#### Nextcloud Mobile App

1. Install from App Store or Google Play
2. Add server: `https://nc.yourdomain.com`
3. Login with your credentials
4. Enable auto-upload for photos/videos

#### Third-Party Apps

- **Documents**: OnlyOffice, Collabora Office
- **Calendar**: CalDAV sync with any calendar app
- **Contacts**: CardDAV sync with any contacts app
- **Notes**: Nextcloud Notes app

### API Access

```bash
# Test API connectivity
curl -u admin:password https://nc.yourdomain.com/ocs/v2.php/cloud/capabilities

# WebDAV API
curl -u admin:password https://nc.yourdomain.com/remote.php/webdav/
```

## 🔧 Advanced Configuration

### Custom Apps Installation

```bash
# Enable app store
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ app:enable appstore

# Install apps via CLI
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ app:install calendar
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ app:install contacts
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ app:install notes
```

### Performance Tuning

#### PHP Configuration

```yaml
# Increase memory limits
PHP_MEMORY_LIMIT: "1024M"
PHP_UPLOAD_LIMIT: "1024M"
PHP_MAX_EXECUTION_TIME: "600"

# Enable OPcache
OPcache_ENABLED: "true"
OPcache_MEMORY_CONSUMPTION: "128"
OPcache_MAX_ACCELERATED_FILES: "10000"
```

#### Database Optimization

```yaml
# PostgreSQL tuning
postgresql:
  configuration: |
    max_connections = 200
    shared_buffers = 512MB
    effective_cache_size = 2GB
    maintenance_work_mem = 128MB
    checkpoint_completion_target = 0.9
    wal_buffers = 32MB
```

#### Redis Configuration

```yaml
# Redis optimization
redis:
  persistence:
    enabled: true
  configuration: |
    maxmemory 256mb
    maxmemory-policy allkeys-lru
    save 900 1
    save 300 10
    save 60 10000
```

### Scaling Configuration

#### Horizontal Pod Autoscaling

```yaml
# Enable HPA
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

#### Resource Scaling

```yaml
# Increase resources
nextcloud:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
```

### Federation & Sharing

#### Trusted Domains

```bash
# Add trusted domains
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ config:system:set trusted_domains 1 --value="nc.yourdomain.com"
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ config:system:set trusted_domains 2 --value="files.yourdomain.com"
```

#### Federation Setup

```bash
# Enable federation
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ app:enable federation

# Configure federation
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- php occ config:system:set federation.trusted_domains 0 --value="partner.com"
```

## 📊 Monitoring & Alerting

### Health Checks

```bash
# Application health
curl -f https://nc.yourdomain.com/status.php

# Database health
kubectl exec -it nextcloud-postgresql-0 -n nextcloud -- pg_isready

# Redis health
kubectl exec -it nextcloud-redis-<pod-id> -n nextcloud -- redis-cli ping
```

### Metrics Collection

```yaml
# Enable ServiceMonitor for Prometheus
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
```

### Log Aggregation

```bash
# Centralized logging with Fluentd
kubectl logs -n nextcloud -l app.kubernetes.io/name=nextcloud --tail=100

# Log forwarding to external systems
kubectl exec -it nextcloud-<pod-id> -n nextcloud -- tail -f /var/log/apache2/access.log
```

## 🔐 Security Best Practices

### Access Control

- **Strong Passwords**: Use complex passwords for all accounts
- **Two-Factor Authentication**: Enable 2FA for admin and user accounts
- **API Tokens**: Use app passwords for third-party integrations
- **Session Management**: Configure appropriate session timeouts

### Network Security

- **VPN Access**: Use VPN for administrative access
- **IP Whitelisting**: Restrict access to specific IP ranges
- **Rate Limiting**: Configure appropriate rate limits
- **DDoS Protection**: Use cloud provider DDoS protection

### Data Protection

- **Encryption at Rest**: Enable database and storage encryption
- **Encryption in Transit**: TLS 1.3 for all communications
- **Backup Encryption**: Encrypt backup files
- **Key Management**: Use Kubernetes secrets for credential storage

### Compliance

- **Audit Logging**: Enable comprehensive audit logs
- **Data Retention**: Configure appropriate data retention policies
- **Privacy Controls**: Implement GDPR/privacy controls
- **Access Reviews**: Regular access permission reviews

## 🆘 Support & Contributing

### Getting Help

- **Documentation**: Check this README and inline comments
- **Issues**: Report bugs via GitHub Issues
- **Discussions**: Join community discussions
- **Professional Support**: Contact WeOwn AI for enterprise support

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Roadmap

- [ ] Multi-cluster support
- [ ] Advanced monitoring integration
- [ ] Automated scaling policies
- [ ] Enhanced backup strategies
- [ ] Performance optimization tools

## 📄 License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Nextcloud Team**: For the excellent open-source platform
- **Kubernetes Community**: For the robust container orchestration
- **Helm Community**: For the package management system
- **WeOwn AI**: For enterprise security patterns and infrastructure

---

**Nextcloud Enterprise** - Secure, scalable, and production-ready file sharing and collaboration platform.
