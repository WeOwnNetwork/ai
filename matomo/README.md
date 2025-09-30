# Matomo Analytics - WeOwn Cloud v0.9

**Privacy-first, self-hosted web analytics platform with enterprise security for WordPress integration**

[![Security Rating](https://img.shields.io/badge/Security-A+-green.svg)](https://github.com/WeOwn/ai/tree/main/matomo)
[![Compliance](https://img.shields.io/badge/Compliance-SOC2%20%7C%20ISO42001%20%7C%20GDPR-blue.svg)](https://github.com/WeOwn/ai/tree/main/matomo)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.23%2B-blue.svg)](https://kubernetes.io/)
[![Matomo](https://img.shields.io/badge/Matomo-5.3.2-orange.svg)](https://matomo.org/)

## 📊 **What is Matomo?**

Matomo is the **#1 open-source alternative to Google Analytics** - providing powerful web analytics while keeping you in **100% control of your data**.

### **Why Self-Hosted Matomo?**

| Feature | Google Analytics | Matomo (Self-Hosted) |
|---------|-----------------|----------------------|
| **Data Ownership** | Google owns your data | You own 100% of data |
| **Privacy** | Tracks users across web | Privacy-first, GDPR compliant |
| **Cost** | Free (you pay with data) | Self-hosted (you control costs) |
| **WordPress Integration** | External tracking | Native WordPress plugin |
| **Compliance** | Limited control | Full SOC2/ISO42001/GDPR |
| **Customization** | Limited | Full access to raw data |

---

## 🚀 **Quick Start**

### **Prerequisites**

- Kubernetes cluster (1.23+)
- `kubectl` configured
- Domain name with DNS access
- 10-15 minutes

### **One-Command Deployment**

```bash
cd matomo
./deploy.sh
```

The script will:
1. ✅ Check prerequisites (auto-install if needed)
2. ✅ Install NGINX Ingress Controller
3. ✅ Install cert-manager for TLS
4. ✅ Configure Let's Encrypt certificates
5. ✅ Deploy Matomo with MariaDB
6. ✅ Enable enterprise security features
7. ✅ Show WordPress integration guide

---

## 🔐 **Enterprise Security Features**

### **WeOwn Security Standards**

This deployment implements **enterprise-grade security** matching n8n, Vaultwarden, and WordPress deployments:

| Security Control | Status | Description |
|-----------------|--------|-------------|
| **Zero-Trust NetworkPolicy** | ✅ Enabled | Micro-segmentation, ingress only from nginx |
| **Pod Security Standards** | ✅ Restricted | Non-root user (1001), dropped capabilities |
| **TLS 1.3 Encryption** | ✅ Enforced | Let's Encrypt with strong cipher suites |
| **Secrets Management** | ✅ Kubernetes-native | Encrypted at rest, proper RBAC |
| **Rate Limiting** | ✅ Enabled | 100 req/min DDoS protection |
| **GDPR Compliance** | ✅ Ready | Privacy-first, data ownership |
| **SOC2/ISO42001** | ✅ Ready | Audit-ready controls |

### **Resource Optimization**

```yaml
Matomo:
  Memory: 256Mi-1Gi (prevents OOMKilled)
  CPU: 100m-500m (handles traffic spikes)
  
MariaDB:
  Memory: 128Mi-512Mi (optimized for analytics)
  CPU: 50m-250m (connection pooling)
```

---

## 📈 **WordPress Integration Guide**

### **Step 1: Deploy Matomo**

```bash
./deploy.sh
```

Follow the interactive prompts to configure your Matomo domain (e.g., `analytics.example.com`).

### **Step 2: Configure DNS**

Add an A record pointing to the external IP shown by the deployment script:

```
Type: A
Hostname: analytics
Value: <EXTERNAL_IP>
TTL: 3600
```

### **Step 3: Complete Matomo Setup**

1. Access https://analytics.example.com
2. Login with credentials from deployment output
3. Complete initial Matomo setup wizard
4. Navigate to **Settings → Personal → Security**
5. Click **"Create new token"** and save it securely

### **Step 4: Install WordPress Plugin**

**Option 1: "Connect Matomo" (WP-Piwik) - Recommended**

This plugin connects your WordPress to your self-hosted Matomo:

1. In WordPress admin, go to **Plugins → Add New**
2. Search for **"Connect Matomo"** (or "WP-Piwik")
3. Install and activate the plugin
4. Go to **Settings → Matomo Analytics**
5. Configure connection:
   ```
   Matomo URL: https://analytics.example.com
   Auth Token: <token from Step 3>
   ```
6. Enable tracking and save settings

**Option 2: Manual Tracking Code**

If you prefer manual integration:

1. In Matomo, go to **Settings → Tracking Code**
2. Copy the JavaScript tracking code
3. In WordPress, install **"Insert Headers and Footers"** plugin
4. Paste tracking code in **Scripts in Header** section
5. Save changes

### **Step 5: Verify Tracking**

1. Visit your WordPress site in a new browser
2. Go to Matomo dashboard
3. Navigate to **Visitors → Real-time**
4. You should see your visit tracked!

---

## 🔧 **Configuration**

### **Custom Configuration**

Edit `helm/values.yaml` to customize:

```yaml
matomo:
  resources:
    limits:
      memory: 2Gi  # Increase for high traffic
  
mariadb:
  primary:
    persistence:
      size: 20Gi  # Increase for more historical data

cronjob:
  schedule: "5 * * * *"  # Change archiving frequency
```

### **Scaling for High Traffic**

**Horizontal Scaling** (not recommended for Matomo):
```bash
# Matomo doesn't support multiple replicas well due to file locks
# Instead, increase resources vertically
```

**Vertical Scaling** (recommended):
```bash
kubectl patch deployment matomo -n matomo -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "matomo",
          "resources": {
            "limits": {
              "memory": "2Gi",
              "cpu": "1000m"
            }
          }
        }]
      }
    }
  }
}'
```

---

## 🔄 **Archive Processing (CronJob)**

Matomo requires **hourly archiving** to generate reports efficiently. This is automated via Kubernetes CronJob:

### **Default Schedule**

```yaml
schedule: "5 * * * *"  # Every hour at 5 minutes past
```

### **Check CronJob Status**

```bash
# View CronJob configuration
kubectl get cronjob matomo-archive -n matomo

# View recent archive jobs
kubectl get jobs -n matomo

# View archive job logs
kubectl logs -l app.kubernetes.io/component=archive -n matomo
```

### **Manual Archive Trigger**

If you need to manually trigger archiving:

```bash
kubectl create job --from=cronjob/matomo-archive matomo-archive-manual -n matomo
```

---

## 🛠️ **Management Commands**

### **View Deployment Status**

```bash
# Check all resources
kubectl get all -n matomo

# Check pod logs
kubectl logs -f deployment/matomo -n matomo

# Check MariaDB logs
kubectl logs -f -l app.kubernetes.io/name=mariadb -n matomo
```

### **Access Database**

```bash
# Get MariaDB password
export MARIADB_PASSWORD=$(kubectl get secret matomo-mariadb -n matomo -o jsonpath='{.data.mariadb-password}' | base64 -d)

# Connect to database
kubectl exec -it -n matomo deployment/matomo -- mysql -h matomo-mariadb -u matomo -p"$MARIADB_PASSWORD" matomo
```

### **View Credentials**

```bash
./deploy.sh --show-credentials
```

### **Update Matomo**

```bash
# Update Helm chart
helm upgrade matomo ./helm --namespace matomo

# Force pod restart
kubectl rollout restart deployment/matomo -n matomo
```

### **Backup Analytics Data**

```bash
# Backup MariaDB database
kubectl exec -n matomo -it deployment/matomo -- bash -c '
  mysqldump -h matomo-mariadb -u matomo -p"$MARIADB_PASSWORD" matomo > /tmp/matomo-backup.sql
'

# Copy backup locally
kubectl cp matomo/matomo-<pod-id>:/tmp/matomo-backup.sql ./matomo-backup-$(date +%Y%m%d).sql
```

---

## 🔍 **Monitoring & Performance**

### **Resource Monitoring**

```bash
# Check resource usage
kubectl top pods -n matomo

# Check certificate status
kubectl get certificate -n matomo

# Check NetworkPolicy
kubectl describe networkpolicy -n matomo
```

### **Performance Optimization**

**Enable Browser Archiving (for low-traffic sites):**
```
Matomo → Settings → System → Archive Reports → 
Enable "Archive reports when viewed from the browser"
```

**GeoIP Database Updates:**
```bash
# GeoIP updates are handled automatically by Matomo
# Check Settings → Geolocation → DBIP / GeoIP 2
```

**Database Optimization:**
```sql
-- Run in MariaDB console
OPTIMIZE TABLE matomo_log_visit;
OPTIMIZE TABLE matomo_log_action;
```

---

## 🆘 **Troubleshooting**

### **Common Issues**

#### **1. 504 Gateway Timeout**

**Symptom:** Cannot access Matomo, 504 error

**Solution:**
```bash
# Check if ingress-nginx namespace is labeled
kubectl get namespace ingress-nginx --show-labels

# If "name=ingress-nginx" is missing:
kubectl label namespace ingress-nginx name=ingress-nginx --overwrite

# Restart Matomo pod
kubectl rollout restart deployment/matomo -n matomo
```

#### **2. Certificate Not Issued**

**Symptom:** HTTPS not working, certificate pending

**Solution:**
```bash
# Check certificate status
kubectl describe certificate matomo-tls -n matomo

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Verify DNS is pointing to correct IP
dig analytics.yourdomain.com
```

#### **3. Database Connection Errors**

**Symptom:** Matomo shows database connection errors

**Solution:**
```bash
# Check MariaDB is running
kubectl get pods -n matomo -l app.kubernetes.io/name=mariadb

# Check MariaDB logs
kubectl logs -f -n matomo -l app.kubernetes.io/name=mariadb

# Verify secrets are created
kubectl get secrets -n matomo
```

#### **4. Archive Processing Not Running**

**Symptom:** Analytics data not updating

**Solution:**
```bash
# Check CronJob status
kubectl get cronjob matomo-archive -n matomo

# Check recent jobs
kubectl get jobs -n matomo

# Manually trigger archive
kubectl create job --from=cronjob/matomo-archive test-archive -n matomo

# Check archive logs
kubectl logs -l app.kubernetes.io/component=archive -n matomo
```

### **Debug Mode**

Enable debug logging in Matomo:

```bash
kubectl exec -n matomo -it deployment/matomo -- bash -c '
  echo "<?php" > /bitnami/matomo/config/config.ini.php
  echo "[General]" >> /bitnami/matomo/config/config.ini.php
  echo "enable_sql_profiler = 1" >> /bitnami/matomo/config/config.ini.php
'
```

---

## 📚 **Documentation**

### **Official Matomo Documentation**

- [Matomo User Guide](https://matomo.org/docs/)
- [WordPress Integration](https://matomo.org/faq/new-to-piwik/how-do-i-manually-insert-the-matomo-tracking-code-on-wordpress/)
- [GDPR Compliance](https://matomo.org/gdpr/)
- [API Reference](https://developer.matomo.org/api-reference/reporting-api)

### **WeOwn Documentation**

- [n8n Integration](../n8n/README.md) - Automate analytics workflows
- [WordPress Deployment](../wordpress/README.md) - Self-hosted WordPress
- [Cluster Switching](../k8s/cluster-switching/README.md) - Multi-cluster management

---

## 🔒 **Security Best Practices**

### **Post-Deployment Security**

1. **Change Default Password**
   - Login to Matomo immediately
   - Go to Settings → Personal Settings
   - Change admin password

2. **Enable Two-Factor Authentication**
   - Settings → Personal Settings → Security
   - Enable 2FA with authenticator app

3. **Configure Privacy Settings**
   - Settings → Privacy → Anonymize Data
   - Enable IP anonymization
   - Set cookie lifetime appropriately

4. **Regular Updates**
   - Monitor Matomo updates: Settings → System Check
   - Update Helm chart when new versions available
   - Always backup before updates

5. **Access Control**
   - Create separate user accounts for team members
   - Use least-privilege principle
   - Review user permissions regularly

### **GDPR Compliance Checklist**

- [ ] Configure IP anonymization
- [ ] Set data retention policies
- [ ] Enable "Do Not Track" support
- [ ] Configure cookie consent
- [ ] Document data processing activities
- [ ] Provide privacy policy link

---

## 📊 **Architecture**

### **Components**

```
┌─────────────────────────────────────────────────┐
│          Internet (HTTPS Traffic)               │
└────────────────┬────────────────────────────────┘
                 │
                 │ TLS 1.3
                 ▼
┌─────────────────────────────────────────────────┐
│       NGINX Ingress Controller                  │
│    (LoadBalancer + Let's Encrypt)               │
└────────────────┬────────────────────────────────┘
                 │
                 │ NetworkPolicy (Zero-Trust)
                 ▼
┌─────────────────────────────────────────────────┐
│          Matomo Application Pod                 │
│      (Non-root, Restricted Security)            │
│  - PHP/Apache                                   │
│  - Analytics Engine                             │
│  - GeoIP Processing                             │
└────────────────┬────────────────────────────────┘
                 │
                 │ Port 3306 (MySQL Protocol)
                 ▼
┌─────────────────────────────────────────────────┐
│            MariaDB Database                     │
│      (Persistent Analytics Storage)             │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│        Kubernetes CronJob (Hourly)              │
│      Archive Processing & Reports               │
└─────────────────────────────────────────────────┘
```

### **Data Flow**

1. **Tracking**: WordPress → Matomo (HTTP POST)
2. **Storage**: Matomo → MariaDB (raw tracking data)
3. **Processing**: CronJob → Matomo → MariaDB (aggregated reports)
4. **Viewing**: User → NGINX → Matomo → MariaDB (report display)

---

## 🤝 **Contributing**

Issues, suggestions, and contributions are welcome!

1. Fork the repository
2. Create your feature branch
3. Test changes in a development cluster
4. Submit pull request with description

---

## 📝 **License**

This deployment system is licensed under MIT License.

**Note:** Matomo itself is licensed under GPL v3. See [Matomo License](https://matomo.org/free-software/) for details.

---

## 🆘 **Support**

- **Issues**: [GitHub Issues](https://github.com/WeOwn/ai/issues)
- **Discussions**: [GitHub Discussions](https://github.com/WeOwn/ai/discussions)
- **Matomo Forum**: [Official Forum](https://forum.matomo.org/)

---

## 🎉 **Success Stories**

Share your Matomo deployment story with the WeOwn community!

**Built with ❤️ by the WeOwn Cloud Team**

*Privacy-first analytics for a better web.*
