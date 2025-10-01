# WordPress Enterprise Deployment v3.2.0

Enterprise-grade WordPress deployment with **zero-trust security**, **automated TLS**, **horizontal scaling**, and **production monitoring** for WeOwn infrastructure.

## 🚀 **Quick Start**

```bash
# Clone only WordPress directory for faster setup
git clone --depth 1 --filter=blob:none --sparse https://github.com/WeOwnNetwork/ai.git
cd ai
git sparse-checkout set wordpress
cd wordpress
./deploy.sh
```

**Requirements**: Kubernetes cluster, kubectl, helm, domain name

---

## 🏗️ **Architecture Overview**

### **Enterprise Stack Components**
- **WordPress 6.8.3** with PHP 8.3 and Apache
- **MariaDB 11.7.2** with optimized configuration  
- **Redis Cache** for performance enhancement
- **NGINX Ingress** with TLS 1.3 termination
- **cert-manager** for automated Let's Encrypt certificates
- **Horizontal Pod Autoscaler** for traffic scaling
- **NetworkPolicy** for zero-trust micro-segmentation

### **Security Architecture**
```
Internet → NGINX Ingress (TLS 1.3) → WordPress Pods (non-root)
                ↓                           ↓
           cert-manager                NetworkPolicy
         (Let's Encrypt)              (Zero-trust rules)
                                           ↓
                                 MariaDB + Redis
                                  (Internal only)
```

### **File Structure**
```
wordpress/
├── deploy.sh                    # Enterprise deployment script
├── helm/                        # Helm chart directory  
│   ├── Chart.yaml              # Helm chart metadata
│   ├── values.yaml             # Configuration parameters
│   └── templates/              # Kubernetes manifests
│       ├── deployment.yaml     # WordPress deployment
│       ├── service.yaml        # Service configuration  
│       ├── ingress.yaml        # TLS ingress rules
│       ├── networkpolicy.yaml  # Zero-trust networking
│       ├── secrets.yaml        # Encrypted credentials
│       ├── pvc.yaml            # Persistent storage
│       ├── hpa.yaml            # Auto-scaling rules
│       ├── backup-cronjob.yaml # Automated backups
│       └── configmap.yaml      # WordPress hardening
├── README.md                   # This documentation
└── CHANGELOG.md               # Version history
```

---

## 🛡️ **Enterprise Security Features**

### **Zero-Trust Networking**
- **NetworkPolicy**: Default deny with explicit ingress/egress rules
- **Pod Security**: Non-root containers, read-only filesystem
- **Service Mesh Ready**: mTLS compatible architecture
- **RBAC**: Least-privilege service accounts

### **TLS & Certificate Management**  
- **TLS 1.3**: Modern encryption with Let's Encrypt automation
- **HTTPS Redirect**: All HTTP traffic redirected to HTTPS
- **Security Headers**: HSTS, CSP, XSS protection, frame options
- **Certificate Rotation**: Automated 30-day renewal cycle

### **Container Security**
```yaml
securityContext:
  runAsUser: 1000              # Non-root user
  runAsGroup: 1000             # Non-root group  
  runAsNonRoot: true           # Enforce non-root
  readOnlyRootFilesystem: true # Read-only system
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]                # Drop all Linux capabilities
```

### **WordPress Hardening**
- **File Editing Disabled**: `DISALLOW_FILE_EDIT = true`
- **Plugin Installation Blocked**: `DISALLOW_FILE_MODS = true`  
- **Force SSL Admin**: `FORCE_SSL_ADMIN = true`
- **Automatic Updates**: Core updates enabled
- **Session Security**: Secure cookies, HTTP-only flags
- **Brute Force Protection**: Rate limiting via NGINX Ingress

---

## 📊 **Scaling & Performance**

### **Horizontal Pod Autoscaler**
```yaml
HPA Configuration:
  Min Replicas: 1
  Max Replicas: 3  
  CPU Target: 70%
  Memory Target: 80%
  Scale-up Policy: Conservative
  Scale-down Policy: Gradual
```

### **Resource Optimization**
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| WordPress | 200m        | 500m      | 256Mi          | 512Mi        |
| MariaDB   | 100m        | 300m      | 128Mi          | 384Mi        |
| Redis     | 50m         | 100m      | 64Mi           | 128Mi        |

### **Persistent Storage**
- **WordPress Content**: 8Gi (wp-content, uploads, themes)
- **WordPress Config**: 100Mi (configuration files)
- **WordPress Cache**: 1Gi (temporary cache data)
- **MariaDB Data**: 8Gi (database with growth capacity)
- **Backup Storage**: 20Gi (30-day retention)

---

## 🚀 **Quick Start**

### **Standalone Installation (Recommended for New Users)**

For users who only want the WordPress deployment without the full WeOwn infrastructure:

```bash
# One-command installation
curl -fsSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/wordpress/install.sh | bash

# Or clone and run locally
git clone https://github.com/WeOwnNetwork/ai.git
cd ai/wordpress
./install.sh
```

**What the standalone installer does:**
- ✅ Clones only the WordPress directory (sparse checkout)
- ✅ Sets up clean directory structure optimized for deployment  
- ✅ Verifies all prerequisites (kubectl, helm, git)
- ✅ Provides OS-specific installation instructions
- ✅ Creates ready-to-deploy WordPress enterprise package

**After installation:**
```bash
cd weown-wordpress
./deploy.sh
```

### **Full Repository Deployment**

If you already have the full WeOwn infrastructure:

### **Interactive Deployment**
```bash
# Run the deployment script
./deploy.sh

# Follow the interactive prompts:
# 1. Domain name (e.g., example.com)  
# 2. Subdomain (e.g., wp → wp.example.com)
# 3. Let's Encrypt email
# 4. Kubernetes namespace  
# 5. Advanced options (monitoring, backups)
```

### **Automated Deployment**
```bash  
# Non-interactive deployment with parameters
./deploy.sh \
  --domain example.com \
  --email admin@example.com \
  --namespace wordpress \
  --skip-prerequisites
```

### **DNS Configuration**
After deployment, create an A record:
```
Subdomain: wp (or your chosen subdomain)
Domain: example.com  
Points to: <EXTERNAL_IP> (provided by deployment script)
TTL: 300 seconds (5 minutes)
```

---

## 🔧 **Management & Operations**

### **Daily Operations**
```bash
# Check deployment status
kubectl get pods -n wordpress
kubectl get ingress -n wordpress  
kubectl get certificates -n wordpress

# View WordPress logs  
kubectl logs -f deployment/wordpress -n wordpress

# Scale WordPress (manual)
kubectl scale deployment wordpress --replicas=2 -n wordpress

# Access WordPress admin
https://wp.yourdomain.com/wp-admin/
```

### **Backup Management**
```bash
# Check backup status (runs daily at 2 AM)
kubectl get cronjobs -n wordpress
kubectl get jobs -n wordpress

# View backup logs
kubectl logs job/wordpress-backup-<timestamp> -n wordpress

# Manual backup trigger
kubectl create job --from=cronjob/wordpress-backup manual-backup -n wordpress
```

### **Certificate Management**
```bash
# Check certificate status
kubectl describe certificate wordpress-tls -n wordpress

# Force certificate renewal (if needed)
kubectl delete certificate wordpress-tls -n wordpress
# Certificate will be automatically recreated
```

### **Performance Monitoring**
```bash
# View resource usage
kubectl top pods -n wordpress  
kubectl top nodes

# Check autoscaling status
kubectl get hpa -n wordpress

# View autoscaling events  
kubectl describe hpa wordpress -n wordpress
```

---

## 🔍 **Troubleshooting Guide**

### **Common Issues & Solutions**

#### **1. Red Padlock (Invalid Certificate)**
**Symptom**: Browser shows "Not Secure" or red padlock
**Cause**: Certificate not ready or browser cache
**Solution**:
```bash
# Check certificate status
kubectl describe certificate wordpress-tls -n wordpress

# If certificate is ready, clear browser cache:
# Chrome/Safari: Cmd+Shift+R (hard refresh)
# Or use incognito/private mode
```

#### **2. 504 Gateway Timeout**  
**Symptom**: NGINX returns 504 error
**Cause**: NetworkPolicy blocking ingress-nginx communication
**Solution**:
```bash
# Ensure ingress-nginx namespace is labeled correctly
kubectl label namespace ingress-nginx name=ingress-nginx --overwrite

# Check NetworkPolicy rules
kubectl describe networkpolicy wordpress -n wordpress
```

#### **3. WordPress Pods Not Starting**
**Symptom**: Pods stuck in Pending or CrashLoopBackOff
**Cause**: Resource constraints or configuration issues  
**Solution**:
```bash
# Check pod events
kubectl describe pod -l app.kubernetes.io/instance=wordpress -n wordpress

# Check resource availability  
kubectl top nodes
kubectl describe node <node-name>

# Review pod logs
kubectl logs -l app.kubernetes.io/instance=wordpress -n wordpress
```

#### **4. Database Connection Errors**
**Symptom**: WordPress shows "Error establishing database connection"
**Cause**: MariaDB not ready or credentials mismatch
**Solution**:
```bash
# Check MariaDB status
kubectl get pods -l app.kubernetes.io/name=mariadb -n wordpress
kubectl logs -l app.kubernetes.io/name=mariadb -n wordpress

# Verify database credentials
kubectl get secret wordpress -n wordpress -o yaml | base64 -d
```

#### **5. Slow WordPress Performance**
**Symptom**: Slow page loading or timeouts  
**Cause**: Resource limits or cache issues
**Solution**:
```bash
# Check resource usage
kubectl top pods -n wordpress

# Increase resource limits if needed:
# Edit values.yaml and run:
helm upgrade wordpress ./helm -n wordpress -f values-override.yaml

# Check Redis cache status  
kubectl exec -it deployment/wordpress-redis-master -n wordpress -- redis-cli ping
```

#### **6. Let's Encrypt Certificate Failures**
**Symptom**: Certificate stuck in "False" ready state
**Cause**: DNS not propagated or challenge failures
**Solution**:
```bash
# Check certificate challenge status
kubectl describe challenge -n wordpress

# Verify DNS propagation
nslookup wp.yourdomain.com
dig wp.yourdomain.com

# Check ACME challenge logs
kubectl logs -l app.kubernetes.io/name=cert-manager -n cert-manager
```

### **Emergency Recovery Procedures**

#### **Complete WordPress Reset**
```bash
# ⚠️ WARNING: This deletes all WordPress data
helm uninstall wordpress -n wordpress
kubectl delete namespace wordpress

# Redeploy from scratch
./deploy.sh
```

#### **Database Recovery from Backup**
```bash
# List available backups
kubectl exec -it deployment/wordpress-backup -n wordpress -- ls -la /var/backups/wordpress/

# Restore database (replace TIMESTAMP)
kubectl exec -it deployment/wordpress-mariadb -n wordpress -- \
  mariadb -u root -p < /var/backups/wordpress/wordpress_backup_db_TIMESTAMP.sql.gz
```

#### **Roll Back WordPress Version**
```bash
# View deployment history
helm history wordpress -n wordpress

# Roll back to previous version
helm rollback wordpress <revision> -n wordpress
```

---

## 📈 **Performance & Monitoring**

### **Key Metrics to Monitor**
- **Pod CPU/Memory**: Should stay under 70% average
- **Response Time**: < 2 seconds for cached pages
- **Availability**: 99.9% uptime target
- **Certificate Expiry**: Auto-renewal 30 days before expiry
- **Backup Success**: Daily backup completion
- **Security Events**: Failed login attempts, blocked requests

### **Monitoring Integration**
```bash
# If Prometheus is available in cluster:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: wordpress-monitoring
  namespace: wordpress
  labels:
    app: wordpress
    monitoring: "true"
spec:
  selector:
    app.kubernetes.io/name: wordpress
  ports:
  - port: 80
    name: http
EOF
```

### **Resource Scaling Recommendations**
- **Low Traffic (< 1000 visits/day)**: Default configuration sufficient
- **Medium Traffic (1000-10k visits/day)**: Scale to 2-3 replicas, increase MariaDB resources  
- **High Traffic (> 10k visits/day)**: Consider external MariaDB (managed database), CDN integration

---

## 🔐 **Security Best Practices**

### **Post-Deployment Security Checklist**
- [ ] **Change Admin Password**: Use generated strong password
- [ ] **Install Security Plugin**: Wordfence or similar
- [ ] **Enable 2FA**: Two-factor authentication for admin
- [ ] **Review User Permissions**: Remove unnecessary admin users
- [ ] **Update WordPress**: Keep core, themes, plugins updated
- [ ] **Configure Backup**: Verify automated backups working
- [ ] **Test Recovery**: Practice disaster recovery procedure
- [ ] **Monitor Logs**: Set up log monitoring and alerting

### **Compliance & Audit**
- **SOC 2**: Pod security contexts, encrypted secrets, audit logs
- **ISO 27001**: Network segmentation, access controls, incident response
- **GDPR**: Cookie consent, data encryption, right to deletion
- **PCI DSS**: If processing payments, additional security layers required

---

## 🚨 **Security Incident Response**

### **Immediate Actions**
1. **Isolate**: Scale down to 0 replicas to stop traffic
2. **Assess**: Check logs and identify attack vector  
3. **Contain**: Update NetworkPolicy to block suspicious IPs
4. **Investigate**: Analyze WordPress logs and access patterns
5. **Recover**: Deploy clean backup and patch vulnerabilities
6. **Monitor**: Enhanced logging and alerting post-incident

### **Emergency Commands**
```bash
# Stop all traffic immediately  
kubectl scale deployment wordpress --replicas=0 -n wordpress

# Block external access
kubectl patch ingress wordpress -n wordpress -p '{"spec":{"rules":[]}}'

# Enable maintenance mode
kubectl create configmap maintenance-mode --from-literal=enabled=true -n wordpress
```

---

## 🤝 **Support & Contributing**

### **Getting Help**
- **Documentation**: This README and inline code comments
- **Logs**: `kubectl logs` commands for troubleshooting  
- **Community**: WeOwn Network support channels
- **Issues**: GitHub Issues for bug reports

### **Contributing**
1. Fork repository and create feature branch
2. Test changes on development cluster
3. Update documentation for new features
4. Submit pull request with detailed description
5. Ensure security review for production changes

---

## 📋 **Appendix**

### **Default Credentials** 
- **WordPress Admin**: `admin` / `<generated-password>`
- **Database Root**: `root` / `<generated-password>`  
- **Database User**: `wordpress` / `<generated-password>`
- **Redis**: `<generated-password>`

### **Network Ports**
- **WordPress**: 80 (internal), 443 (external via ingress)
- **MariaDB**: 3306 (internal only)
- **Redis**: 6379 (internal only)

### **Storage Classes**
- **DigitalOcean**: `do-block-storage` (default)
- **AWS**: `gp2` or `gp3`
- **Google Cloud**: `standard` or `ssd`

### **Resource Requirements**
- **Minimum**: 2 CPU cores, 4GB RAM, 50GB storage
- **Recommended**: 4 CPU cores, 8GB RAM, 100GB storage  
- **High Availability**: 3+ nodes, distributed across zones

---

**🎯 WordPress Enterprise v3.2.0 - Production Ready**  
*Deployed with ❤️ by WeOwn Network*