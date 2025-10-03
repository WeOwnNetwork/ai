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

```bash
# Get MariaDB password
export MARIADB_PASSWORD=$(kubectl get secret matomo-mariadb -n matomo -o jsonpath='{.data.mariadb-password}' | base64 -d)

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
