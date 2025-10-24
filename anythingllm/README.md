# AnythingLLM - Self-Hosted AI Assistant Platform

🤖 **Private AI • 🚀 Automated Deployment • 📚 Document RAG**

A privacy-first AI assistant platform that runs entirely on your Kubernetes infrastructure. Deploy your own secure instance with automatic HTTPS, multi-user support, and document processing capabilities.

## ✨ Key Features

- **🔐 Privacy-First**: Your data never leaves your infrastructure
- **🛡️ Enterprise Security**: Kubernetes-native with network isolation
- **🤖 Multi-LLM Support**: OpenAI, OpenRouter, Anthropic, local models, and more
- **📚 Document RAG**: Upload documents for context-aware conversations
- **👥 Multi-User**: Role-based access control and workspace isolation
- **🔄 Persistent Storage**: Conversations and documents persist across sessions
- **🌐 HTTPS/TLS**: Automatic Let's Encrypt certificates
- **📊 Monitoring**: Built-in health checks and observability
- **💾 Automated Deployment**: Complete infrastructure automation

## 📋 Infrastructure Overview

### Architecture Components
- **AnythingLLM Application**: Main AI assistant platform
- **PostgreSQL**: User data and conversation storage (embedded)
- **Vector Database**: Document embeddings (LanceDB)
- **NGINX Ingress**: Load balancing and TLS termination
- **cert-manager**: Automatic SSL certificate management
- **Persistent Storage**: Document and data persistence

### Security Features
- **Network Isolation**: Pod-to-pod communication controls
- **TLS Encryption**: End-to-end encryption with automatic certificates
- **Secret Management**: Kubernetes-native credential storage
- **Resource Limits**: Prevents resource exhaustion
- **Health Monitoring**: Automatic restart if unhealthy

## 🚀 Quick Start

### Prerequisites

**Required Tools:**
- **kubectl** - Kubernetes command-line tool
- **helm** - Kubernetes package manager (3.x)
- **curl** - HTTP client for downloads
- **git** - Version control (for cloning)
- **openssl** - Cryptographic toolkit

**Required Infrastructure:**
- **Kubernetes cluster** (DigitalOcean Kubernetes recommended)
- **Domain name** with DNS management access
- **Email address** for SSL certificates

**Cluster Requirements:**
- Minimum 2 nodes with 4GB RAM each
- NGINX Ingress Controller installed
- cert-manager installed for TLS certificates
- Storage class available (e.g., `do-block-storage`)

### One-Command Deployment

```bash
# Clone and deploy in one command
curl -fsSL https://raw.githubusercontent.com/WeOwnNetwork/ai/main/anythingllm/install.sh | bash
```

### Manual Deployment

```bash
# Clone the repository
git clone https://github.com/WeOwnNetwork/ai.git
cd ai/anythingllm

# Run the deployment script
./deploy.sh
```

## 🔧 Deployment Script Features

The deployment script provides automated infrastructure setup:

### ✅ **Automated Setup**
- **Auto-resume capability**: Script saves state and continues from interruption points
- **Prerequisite installation**: Installs missing tools (kubectl, helm, etc.) automatically
- **Full logging**: All operations logged with timestamps for transparency
- **Error recovery**: Handles failures gracefully with clear guidance

### 🔐 **Credential Management**
The script generates secure admin credentials for:

1. **System Authentication**: API access and system integrations
2. **Admin Access**: Initial admin account setup
3. **Kubernetes Secrets**: Stored securely in cluster secrets

**Security Setup**: After deployment, you must enable "Multi-User Mode" and create admin accounts through the web interface.

### 🌐 **DNS Configuration**
- **TTL Settings**: Configure based on your environment (300s for testing, 3600s for production)
- **A Record Setup**: Point your subdomain to the cluster load balancer IP
- **Certificate Automation**: Let's Encrypt certificates are issued automatically

### 🔄 **Updates & Maintenance**

#### **Version Information**
- **Current Version**: 1.9.0 (October 15, 2025)
- **Chart Version**: 2.0.0
- **Image**: `mintplexlabs/anythingllm:1.9.0`
- **Update Strategy**: Rolling updates with zero downtime

#### **Updates**
```bash
# Update to latest version
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --wait --timeout=10m

# Verify update
kubectl get deployment anythingllm -n anything-llm -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get pods -n anything-llm

# Check Helm status
helm list -n anything-llm
```

**Automatic Helm Cleanup**: Old Helm revisions are automatically cleaned up (keeps last 10 revisions)

#### **Automated Backups** ✅
- **Schedule**: Daily at 2 AM UTC (configurable)
- **Retention**: 30 days (SOC2/ISO42001 compliant)
- **Location**: Dedicated 10Gi backup PVC
- **Status**: `kubectl get cronjob anythingllm-backup -n anything-llm`
- **Manual Trigger**: `kubectl create job --from=cronjob/anythingllm-backup manual-backup-$(date +%s) -n anything-llm`

**Backup Verification**:
```bash
# Check backup CronJob
kubectl get cronjob anythingllm-backup -n anything-llm

# View recent backup jobs
kubectl get jobs -n anything-llm | grep backup

# Check backup logs
kubectl logs -n anything-llm job/anythingllm-backup-<timestamp>
```

#### **Scaling**

**Pod Scaling** (for more concurrent users):
```bash
# Scale to 2 replicas for higher availability
kubectl scale deployment anythingllm -n anything-llm --replicas=2

# Monitor resource usage
kubectl top pods -n anything-llm
```

**Node Scaling** (for larger AI models):
```bash
# Scale cluster nodes via your cloud provider's control panel
# For GPU workloads: Add GPU-enabled node pools for local model hosting
```

**Resource Optimization for Large Models**:
- **Memory**: Increase to 8Gi+ for large models in `values.yaml`
- **CPU**: 2-4 cores recommended for optimal performance
- **Storage**: 50Gi+ for model caching and user data
- **GPU**: Optional for local model hosting

## ⚙️ Configuration Standards

### **Standardized Configuration Across All Instances**

#### **Image & Version**
```yaml
anythingllm:
  image:
    repository: mintplexlabs/anythingllm
    tag: "1.9.0"  # Specific version (not 'latest')
    pullPolicy: Always  # Always check for security patches
```

#### **Namespace**
- **Standard**: `anything-llm` for all deployments
- **Isolation**: Each deployment in dedicated namespace
- **RBAC**: Proper service accounts and role bindings

#### **Storage**
```yaml
# Application Storage
persistence:
  size: 20Gi
  storageClass: do-block-storage
  accessMode: ReadWriteOnce

# Backup Storage  
backup:
  size: 10Gi
  storageClass: do-block-storage
  retentionDays: 30
```

#### **Resources**
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi
```

#### **Backup Configuration**
```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # 2 AM UTC daily
  retentionDays: 30
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
```

#### **Security**
- **NetworkPolicy**: Zero-trust with ingress-nginx only
- **Pod Security**: Restricted profile, non-root user (1000)
- **TLS**: 1.3 with Let's Encrypt automation
- **Secrets**: Kubernetes-native with encryption at rest

### **Multi-Cluster Deployment Consistency**

All AnythingLLM instances follow identical configurations:
- ✅ Same image version (1.9.0)
- ✅ Same resource allocations
- ✅ Same backup schedule and retention
- ✅ Same security policies
- ✅ Same namespace structure

## 📋 Deployment Process

The deployment script (`deploy.sh`) provides a fully interactive, guided experience with complete transparency:

### **What the Script Does Automatically**
1. **Prerequisites Check**: Verifies kubectl, helm, curl, git, openssl are installed
2. **Cluster Connection**: Tests Kubernetes cluster connectivity and context
3. **User Configuration**: Prompts for subdomain, domain, email, generates secure credentials
4. **DNS Setup**: Guides through A record creation with external IP detection
5. **Cluster Prerequisites**: Installs NGINX Ingress Controller and cert-manager
6. **ClusterIssuer Creation**: Creates Let's Encrypt ClusterIssuer for automatic TLS
7. **Namespace Creation**: Creates `anything-llm` namespace with proper labels
8. **Secrets Creation**: Generates and stores admin credentials, JWT secret securely
9. **Helm Deployment**: Deploys AnythingLLM with all security features enabled
10. **TLS Verification**: Confirms valid certificates are issued and active
11. **Security Guidance**: Provides post-deployment security setup instructions

### **What Requires Manual Action**
- **DNS A Record**: Point your subdomain to the provided external IP
- **Multi-User Mode**: Enable in AnythingLLM UI immediately after deployment
- **Admin Account**: Create admin account using provided credentials
- **LLM Provider**: Configure your preferred LLM API keys in the UI

### Step 1: Prerequisites Check
- Verifies all required tools are installed
- Provides installation instructions for missing tools
- Tests Kubernetes cluster connectivity

### Step 2: Configuration Gathering
- **Domain Setup**: Enter your subdomain and domain name
- **Email**: Provide email for SSL certificates
- **Credentials**: Automatically generates secure admin password and JWT secret

### Step 3: DNS Configuration
- Detects your cluster's load balancer IP
- Provides DNS setup instructions
- Waits for DNS confirmation

### Step 4: Cluster Prerequisites
- Installs NGINX Ingress Controller if needed
- Installs cert-manager if needed
- Creates Let's Encrypt ClusterIssuer

### Step 5: Deployment
- Creates Kubernetes namespace (`anything-llm`)
- Creates secure Kubernetes secrets for all sensitive data
- Deploys AnythingLLM using Helm with optimized resource limits
- Configures ingress with automatic HTTPS/TLS

### Step 6: Security Setup Guidance
- Provides critical security warnings about public access
- Shows admin credentials securely
- Offers to open browser for immediate security configuration
- Guides through multi-user mode setup

## 🔐 Security Configuration (CRITICAL)

**⚠️ Your AnythingLLM instance is PUBLIC by default until you complete security setup!**

### Immediate Security Steps (Required)

After deployment, you MUST complete these steps:

1. **Access Your Instance**
   - Visit the URL provided after deployment
   - You'll see AnythingLLM without any login prompt initially

2. **Enable Multi-User Mode**
   - Click Settings (⚙️) in the bottom left
   - Navigate to "Security" in the left sidebar
   - **Enable "Multi-User Mode"** (CRITICAL!)
   - Optionally set "Instance Password Protection" for additional security

3. **Create Admin Account**
   - After enabling multi-user mode, create an admin account
   - Use the email and password generated during deployment
   - Or create new credentials (deployment credentials remain valid for API access)

4. **Configure LLM Provider**
   - Go to Settings → LLM Preference
   - Choose your preferred provider:
     - **OpenAI**: Direct OpenAI API access
     - **OpenRouter**: Access to multiple models (often cheaper)
     - **Anthropic**: Claude models
     - **Local Models**: Ollama or self-hosted options
   - Enter your API key and select models

### Security Features

**Authentication & Access Control:**
- **Multi-User Mode**: Requires login for all access
- **Instance Password**: Additional protection layer
- **Role-Based Access**: Admin can create users with different permissions
- **Session Management**: JWT-based with configurable timeout

**Data Privacy & Persistence:**
- **✅ Private Data**: All conversations and documents stay in your cluster
- **✅ Session Persistence**: Chat history persists across devices when logged in
- **✅ User Isolation**: Each user has separate workspaces and conversations
- **✅ Document Security**: RAG documents only accessible to authorized users

**Network Security:**
- **✅ HTTPS/TLS**: All traffic encrypted with Let's Encrypt certificates
- **✅ Kubernetes Network Policies**: Pod-to-pod communication secured
- **✅ No External Leakage**: Data never leaves your infrastructure

## 👥 User Management

### Admin Capabilities
- Create and delete user accounts
- Assign workspace permissions
- Monitor system usage and health
- Configure LLM providers globally
- Manage document uploads and storage

### User Experience
- **Personal Workspaces**: Each user gets isolated AI assistants
- **Document RAG**: Upload documents for context-aware conversations
- **Conversation History**: Persistent across sessions and devices
- **Multi-Model Support**: Switch between different AI models
- **Collaborative Features**: Share workspaces with team members

## 🛠️ Configuration

### Resource Limits
The deployment is optimized for resource-constrained clusters:

```yaml
resources:
  limits:
    cpu: 1000m      # 1 CPU core
    memory: 1024Mi  # 1GB RAM
  requests:
    cpu: 200m       # 0.2 CPU cores
    memory: 256Mi   # 256MB RAM
```

### Storage
- **Persistent Volume**: 20GB by default
- **Storage Class**: `do-block-storage` (DigitalOcean)
- **Mount Path**: `/app/server/storage`
- **Backup**: Recommended for production use

### Environment Variables
All sensitive configuration is stored in Kubernetes secrets:
- `ADMIN_EMAIL`: Admin email address
- `ADMIN_PASSWORD`: Secure admin password
- `JWT_SECRET`: Session management secret
- `OPENAI_API_KEY`: LLM provider API key (if configured)
- `OPENAI_API_BASE`: LLM provider base URL (if configured)

## 🔧 Advanced Configuration

### Custom Domain
Update your DNS to point to the cluster load balancer:
```
Type: A
Name: your-subdomain
Value: [Load Balancer IP from deployment]
TTL: 300
```

### Network Policies
For enhanced security, the deployment includes network policies that:
- Allow ingress traffic only from NGINX Ingress Controller
- Restrict pod-to-pod communication
- Block unauthorized external access

### Monitoring and Observability
Check deployment health:
```bash
# Pod status
kubectl get pods -n anything-llm

# View logs
kubectl logs -n anything-llm -l app.kubernetes.io/name=anythingllm -f

# Check ingress
kubectl get ingress -n anything-llm

# Certificate status
kubectl get certificate -n anything-llm
```

## 🆘 Troubleshooting

### Common Issues

**"Can't connect to cluster"**
- Verify kubectl is configured: `kubectl cluster-info`
- Check cluster access: `kubectl get nodes`
- For DigitalOcean: `doctl kubernetes cluster kubeconfig save <cluster-id>`

**"Pod stuck in Pending state"**
- Check resource availability: `kubectl describe nodes`
- Verify storage class exists: `kubectl get storageclass`
- Check pod events: `kubectl describe pod -n anything-llm`

**"TLS certificate not issued"**
- Verify DNS is pointing to load balancer IP
- Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
- Verify ClusterIssuer: `kubectl get clusterissuer`

**"Can't access after enabling security"**
- Clear browser cache and cookies
- Use incognito/private browsing mode
- Verify admin credentials are correct

**"LLM not responding"**
- Check API key is valid and has credits
- Verify LLM provider configuration in Settings
- Try different models (some may be rate-limited)

### Getting Admin Credentials
If you lose access, retrieve credentials from Kubernetes:
```bash
# Get admin email
kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath="{.data.ADMIN_EMAIL}" | base64 -d

# Get admin password
kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath="{.data.ADMIN_PASSWORD}" | base64 -d
```

### Logs and Debugging
```bash
# Application logs
kubectl logs -n anything-llm deployment/anythingllm

# Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

## 🎯 Demo and Cohort Deployment

### Pre-Demo Checklist
- [ ] Deployment completed successfully
- [ ] HTTPS certificate is valid (green lock in browser)
- [ ] Multi-user mode enabled
- [ ] Admin account created and tested
- [ ] LLM provider configured and tested
- [ ] Sample workspace created
- [ ] Test document uploaded for RAG demonstration

### Demo Workflow
1. **Show Secure Access**: Demonstrate login requirement
2. **Document Upload**: Upload sample documents for RAG
3. **AI Conversations**: Show context-aware responses
4. **User Management**: Create demo user accounts
5. **Privacy Features**: Highlight data isolation and security

### Cohort Onboarding
For cohort members:
1. Provide them with the repository URL
2. They run: `curl -sSL https://raw.githubusercontent.com/weown/ai/main/MVP-0.1/anythingllm/install.sh | bash`
3. Follow the interactive deployment process
4. Complete security setup immediately after deployment
5. Configure their preferred LLM provider

## 📚 Architecture

### Components
- **AnythingLLM Application**: Main AI assistant platform
- **PostgreSQL**: User data and conversation storage (embedded)
- **Vector Database**: Document embeddings (LanceDB)
- **NGINX Ingress**: Load balancing and TLS termination
- **cert-manager**: Automatic SSL certificate management
- **Persistent Storage**: Document and data persistence

### Security Architecture
- **Zero-Trust Networking**: All communication encrypted
- **Pod Security Standards**: Non-root containers, read-only filesystems
- **RBAC**: Kubernetes role-based access control
- **Network Policies**: Micro-segmentation of pod communication
- **Secret Management**: All sensitive data in Kubernetes secrets

## 🔄 Maintenance

### Updates
```bash
# Update deployment
cd ai/MVP-0.1/anythingllm/helm
./deploy.sh

# Check for new versions
helm list -n anything-llm
```

### Backup
```bash
# Backup persistent data
kubectl get pvc -n anything-llm
# Use your cloud provider's volume snapshot features
```

### Scaling
```bash
# Scale pods (if needed)
kubectl scale deployment anythingllm -n anything-llm --replicas=2
```

## 🤝 Support

### WeOwn Community
- **Documentation**: This README and inline help
- **Issues**: Report via GitHub issues
- **Discussions**: WeOwn community forums

### Enterprise Support
- **Professional Services**: Available for large deployments
- **Custom Integrations**: API and webhook development
- **Training**: Cohort programs and workshops

---

## 📄 License

This project is part of the WeOwn ecosystem and follows WeOwn's open-source licensing terms.

---

**🎉 Your AnythingLLM deployment is now ready for secure, private AI assistance!**

Remember to complete the security setup immediately after deployment to ensure your instance is properly protected.
