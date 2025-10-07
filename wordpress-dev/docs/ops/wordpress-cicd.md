# WordPress CI/CD Operations Guide

## Overview

This guide covers the operational procedures for the WordPress Kubernetes CI/CD system built for the WeOwn cohort infrastructure. The system provides a Git-first development and deployment workflow with enterprise-grade security, modular site management, and automated deployment pipelines.

## Architecture

### Core Components

- **Template System**: Reusable master template with `weown-starter` child theme
- **Site Overlays**: Per-site branding and configuration with minimal overrides
- **Assembly Scripts**: Automated wp-content composition from template + overlays
- **Container Images**: Site-specific Docker images built via CI/CD
- **Helm Integration**: InitContainer rsync pattern for code deployment
- **CI/CD Workflows**: GitHub Actions for linting and staged deployments

### Infrastructure Dependencies

- DigitalOcean Kubernetes (DOKS) clusters
- Existing `switch-cluster.sh` for cluster context management
- Helm for package management
- GitHub Container Registry for image storage
- Let's Encrypt for TLS certificates

## Cluster Access & Context Management

### Switching Clusters

All cluster operations use the existing `switch-cluster.sh` script as the single source of truth:

```bash
# Switch to staging cluster
./k8s/cluster-switching/switch-cluster.sh staging-cluster

# Switch to production cluster  
./k8s/cluster-switching/switch-cluster.sh production-cluster

# Verify current context
kubectl config current-context
```

### Available Cluster Aliases

The system supports all cluster aliases defined in `switch-cluster.sh`. Common aliases:
- `staging-cluster` - Staging environment
- `production-cluster` - Production environment
- `development-cluster` - Development environment

## Site Management

### Creating New Sites

Generate a new site overlay using the scaffold script:

```bash
cd wordpress-dev
./scripts/generate-site.sh beta
```

This creates:
- `sites/beta/site.config.yaml` - Site configuration and branding
- `sites/beta/values-staging.yaml` - Staging Helm values
- `sites/beta/values-prod.yaml` - Production Helm values
- `sites/beta/overrides/` - Directory for site-specific overrides

### Site Configuration

Edit `sites/{site}/site.config.yaml` to customize:
- Site metadata (name, domain, description)
- Color palette and branding
- Feature toggles
- Logo and asset paths

### Site Overrides

Place site-specific files in `sites/{site}/overrides/wp-content/`:
- Theme template overrides
- Plugin modifications
- Custom CSS/JS assets
- Site-specific images

## Development Workflow

### Local Development

1. **Assemble wp-content for testing:**
   ```bash
   cd wordpress-dev
   ./scripts/assemble-wp-content.sh alpha
   ls .build/alpha/wp-content/  # Verify assembly
   ```

2. **Run PHP CodeSniffer locally:**
   ```bash
   # Install dependencies
   composer global require squizlabs/php_codesniffer:^3.9
   composer global require wp-coding-standards/wpcs:^3.1
   
   # Run linting
   ~/.composer/vendor/bin/phpcs --standard=phpcs.xml .
   ```

3. **Test changes in child theme or plugins:**
   - Edit files in `template/wp-content/`
   - Add site-specific overrides in `sites/{site}/overrides/`
   - Re-assemble to test changes

### Code Quality

The CI pipeline enforces WordPress coding standards:
- PHP CodeSniffer with WordPress rules
- VIP Go performance standards
- Security best practices
- 120-character line limits

## CI/CD Pipeline

### Continuous Integration

**Triggers:**
- Pull requests to `main` or `develop`
- Pushes to `main` branch
- Manual workflow dispatch

**Pipeline Steps:**
1. PHP CodeSniffer linting
2. WordPress coding standards validation
3. Security and performance checks

### Deployment Pipeline

**Staging Deployment (Automatic):**
- Triggered on merge to `main`
- Builds images for all sites
- Deploys to staging environment
- No manual approval required

**Production Deployment (Manual):**
- Requires manual approval via GitHub environment
- Uses same images from staging
- Deploys to production clusters
- Full rollback capability

### Image Management

Images are built and stored in GitHub Container Registry:
```
ghcr.io/{org}/wordpress-site:{site}-{commit-hash}
```

Example:
```
ghcr.io/weown/wordpress-site:alpha-a1b2c3d4
```

## Deployment Operations

### Manual Deployment

Deploy specific sites using the management script:

```bash
# Deploy alpha site to staging
./scripts/manage-deployments.sh \
  -c staging-cluster \
  -n wp-staging \
  -r wordpress-alpha \
  -f wordpress-dev/sites/alpha/values-staging.yaml

# Deploy alpha site to production
./scripts/manage-deployments.sh \
  -c production-cluster \
  -n wp-prod \
  -r wordpress-alpha \
  -f wordpress-dev/sites/alpha/values-prod.yaml
```

### Dry Run Deployments

Test deployments without applying changes:

```bash
./scripts/manage-deployments.sh \
  -c staging-cluster \
  -n wp-staging \
  -r wordpress-alpha \
  -f wordpress-dev/sites/alpha/values-staging.yaml \
  --dry-run
```

### Deployment Verification

After deployment, verify the application:

```bash
# Check pod status
kubectl get pods -n wp-staging -l app.kubernetes.io/instance=wordpress-alpha

# Check ingress and certificates
kubectl get ingress -n wp-staging
kubectl get certificates -n wp-staging

# View logs
kubectl logs -f deployment/wordpress-alpha -n wp-staging

# Check initContainer sync logs
kubectl logs -f deployment/wordpress-alpha -c sync-wp-content -n wp-staging
```

## Rollback Procedures

### Helm Rollback

Roll back to previous release:

```bash
# Switch to appropriate cluster
./k8s/cluster-switching/switch-cluster.sh production-cluster

# List release history
helm history wordpress-alpha -n wp-prod

# Rollback to previous version
helm rollback wordpress-alpha -n wp-prod

# Rollback to specific revision
helm rollback wordpress-alpha 2 -n wp-prod
```

### Image Rollback

Update Helm values with previous image tag:

```bash
# Edit values file
vim wordpress-dev/sites/alpha/values-prod.yaml

# Update image tag to previous version
# Then redeploy
./scripts/manage-deployments.sh \
  -c production-cluster \
  -n wp-prod \
  -r wordpress-alpha \
  -f wordpress-dev/sites/alpha/values-prod.yaml
```

## Persistent Volume Management

### PVC Operations

```bash
# List persistent volumes
kubectl get pvc -n wp-staging

# Check volume usage
kubectl describe pvc wordpress-alpha -n wp-staging

# Backup PVC data (if needed)
kubectl create job backup-pvc --image=busybox -- sh -c "cp -r /data/* /backup/"
```

### Content Sync Process

The initContainer sync process:
1. Runs on every pod restart/deployment
2. Syncs `/app/wp-content/` from image to PVC
3. Uses `rsync --delete` for exact replica
4. Ensures code changes flow through CI/CD only

## Observability & Monitoring

### Health Checks

```bash
# Check all WordPress deployments
kubectl get deployments -A -l app.kubernetes.io/name=wordpress

# Check resource usage
kubectl top pods -n wp-staging
kubectl top nodes

# Monitor certificate status
kubectl get certificates -A
```

### Log Access

```bash
# Application logs
kubectl logs -f deployment/wordpress-alpha -n wp-staging

# Previous container logs (after restart)
kubectl logs deployment/wordpress-alpha -n wp-staging --previous

# Multiple containers
kubectl logs -f deployment/wordpress-alpha -c wordpress -n wp-staging
kubectl logs -f deployment/wordpress-alpha -c sync-wp-content -n wp-staging
```

### Troubleshooting

**Common Issues:**

1. **initContainer sync failures:**
   ```bash
   kubectl describe pod -l app.kubernetes.io/instance=wordpress-alpha -n wp-staging
   kubectl logs -f deployment/wordpress-alpha -c sync-wp-content -n wp-staging
   ```

2. **Certificate issues:**
   ```bash
   kubectl describe certificate wordpress-alpha-tls -n wp-staging
   kubectl describe clusterissuer letsencrypt-prod
   ```

3. **Ingress connectivity:**
   ```bash
   kubectl describe ingress wordpress-alpha -n wp-staging
   kubectl get service -n ingress-nginx
   ```

## Staging to Production Workflow

### Standard Promotion Process

1. **Deploy to staging** (automatic on merge to main)
2. **Validate staging deployment:**
   - Functional testing
   - Performance verification
   - Security checks
3. **Approve production deployment** (manual via GitHub)
4. **Monitor production deployment**
5. **Verify production functionality**

### Emergency Hotfix Process

1. **Create hotfix branch from main**
2. **Apply critical fixes**
3. **Deploy directly to staging for validation**
4. **Fast-track production approval**
5. **Immediate rollback plan ready**

## Security Considerations

### Network Policies

All deployments include zero-trust NetworkPolicy:
- Ingress: Only NGINX Ingress Controller
- Egress: DNS, HTTPS, MariaDB, Redis only

### Pod Security Standards

Restricted security context:
- Non-root containers (UID 33 for sync container)
- Dropped capabilities
- Read-only root filesystem where possible
- No privilege escalation

### Secret Management

- WordPress credentials via Kubernetes secrets
- TLS certificates via cert-manager
- No secrets in Git repository
- External secret management integration ready

### Image Security

- Images built from minimal Alpine base
- No root access required for sync operations
- Immutable image tags with Git commit hashes
- Registry scanning via GitHub Security

## Performance Optimization

### Resource Tuning

Monitor and adjust resource limits:
- WordPress: 25m CPU / 96Mi memory requests
- Sync container: 10m CPU / 32Mi memory requests
- Scale based on actual usage patterns

### Caching Strategy

- Redis enabled for object caching
- W3 Total Cache plugin configured
- CDN integration ready
- Database query optimization

### Scaling Considerations

- Single replica due to RWO volumes
- Horizontal scaling requires RWX storage
- Vertical scaling for increased traffic
- Load balancer configuration

## Backup & Disaster Recovery

### Automated Backups

Configured in Helm values:
- Daily backups at 2 AM UTC
- 30-day retention policy
- Kubernetes CronJob implementation

### Manual Backup

```bash
# Create manual backup
kubectl create job manual-backup-$(date +%Y%m%d) \
  --from=cronjob/wordpress-alpha-backup \
  -n wp-staging
```

### Disaster Recovery Plan

1. **Infrastructure Recovery:**
   - Restore DOKS cluster from backup
   - Redeploy ingress-nginx and cert-manager
   - Restore PVCs from volume snapshots

2. **Application Recovery:**
   - Deploy WordPress via Helm
   - Restore database from backup
   - Restore wp-content from backup
   - Verify TLS certificates

3. **Data Recovery:**
   - Database: MariaDB backup restoration
   - Files: PVC snapshot restoration
   - Configurations: Git repository source

## Maintenance Windows

### Scheduled Maintenance

- **Kubernetes upgrades:** Monthly
- **Security patches:** Weekly
- **WordPress core updates:** As needed
- **Plugin updates:** Bi-weekly

### Maintenance Procedures

1. **Pre-maintenance:**
   - Backup verification
   - Change communication
   - Rollback plan confirmation

2. **During maintenance:**
   - Staging updates first
   - Production deployment validation
   - Monitoring and alerting

3. **Post-maintenance:**
   - Functionality verification
   - Performance monitoring
   - Documentation updates

## Automation & Integration

### GitHub Actions Integration

- **Workflows:** `.github/workflows/ci.yml` and `.github/workflows/deploy.yml`
- **Secrets:** GitHub Container Registry access
- **Environments:** Production approval gates
- **Matrix builds:** Multi-site deployments

### External Integrations

- **Monitoring:** Ready for Prometheus/Grafana
- **Alerting:** PagerDuty/Slack integration points
- **Logging:** ELK/Loki stack compatibility
- **Secrets:** Vault/External Secrets Operator ready

## Support & Escalation

### First-Line Support

1. Check deployment status and logs
2. Verify certificate and ingress status
3. Validate PVC and resource usage
4. Review recent changes in Git

### Escalation Procedures

1. **Infrastructure Issues:** DOKS support
2. **Application Issues:** WordPress expertise
3. **Security Issues:** Security team notification
4. **Performance Issues:** Capacity planning team

### Documentation Updates

Keep this guide updated with:
- New site additions
- Infrastructure changes
- Process improvements
- Lessons learned from incidents

---

**Last Updated:** $(date)
**Version:** 1.0.0
**Maintainer:** WeOwn DevOps Team
