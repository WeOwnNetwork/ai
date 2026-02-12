# ♾️ WeOwn AI - Enterprise Kubernetes Infrastructure

🚀 **WeOwn AI Infrastructure** - Production-grade Kubernetes platform delivering secure, scalable AI and automation services with enterprise security, zero-trust networking, and SOC2/ISO42001 compliance.

## 📦 **Application Stack**

### 🤖 **AI & Automation Platform**

**[AnythingLLM](./anythingllm/)** - Private AI Chat & Document Processing
- **Purpose**: Secure, self-hosted AI assistant with document ingestion and RAG capabilities
- **Use Cases**: Private document Q&A, team AI assistant, knowledge base processing
- **Security**: Zero-trust networking, JWT authentication, isolated data processing
- **Integration**: Local LLMs, OpenAI, Anthropic, with enterprise compliance controls

**[n8n](./n8n/)** - Visual Workflow Automation Platform  
- **Purpose**: No-code/low-code automation and enterprise system integration
- **Use Cases**: API orchestration, data pipelines, notification workflows, CRM automation
- **Features**: 24-hour auth sessions, queue mode scaling, SQLite/PostgreSQL support
- **Enterprise**: Multi-tenant namespace isolation, comprehensive backup system

### 🔐 **Security & Infrastructure**

**[Vaultwarden](./vaultwarden/)** - Enterprise Password Management
- **Purpose**: Self-hosted Bitwarden-compatible password manager with Argon2id security
- **Use Cases**: Team password sharing, secure credential storage, enterprise compliance
- **Security**: Argon2id PHC hashing, zero-trust networking, automated backups
- **Compliance**: SOC2/ISO42001 ready with comprehensive audit trails

**[Monitoring](./k8s/monitoring/)** - Kubernetes Observability Stack
- **Purpose**: Cluster monitoring, resource optimization, and visual management
- **Components**: Portainer CE, Kubernetes Metrics Server, custom dashboards
- **Features**: Real-time resource monitoring, auto-scaling integration, enterprise security
- **Operations**: Performance baselines, scaling strategies, incident response runbooks

### 🌐 **Content & Collaboration**

**[WordPress](./wordpress/)** - Enterprise Content Management
- **Purpose**: Secure, scalable WordPress with enterprise hardening and auto-scaling
- **Use Cases**: Corporate websites, documentation portals, member content systems
- **Features**: Auto-configuration, NetworkPolicy security, HPA scaling, MySQL/Redis
- **Security**: Pod Security Standards: Restricted, automated credential management


## 📁 **Repository Structure**

```
WeOwn/ai/
├── README.md                           # This file - platform overview and architecture
├── .gitignore                          # Repository-wide Git ignore rules
│
├── anythingllm/                        # AI Document Processing & Chat Platform
│   ├── deploy.sh                       # Enterprise deployment script
│   ├── helm/                           # Kubernetes Helm chart
│   │   ├── Chart.yaml                  # Chart metadata and security annotations
│   │   ├── values.yaml                 # Production-ready configuration
│   │   └── templates/                  # Kubernetes manifests (12 files)
│   ├── README.md                       # AnythingLLM deployment guide
│   ├── CHANGELOG.md                    # Version history and security fixes
│   └── docker-compose.yml              # Local development setup
│
├── n8n/                                # Visual Workflow Automation Platform
│   ├── deploy.sh                       # Enterprise deployment script (20K+ lines)
│   ├── helm/                           # Kubernetes Helm chart
│   │   ├── Chart.yaml                  # Chart metadata with security annotations
│   │   ├── values.yaml                 # Production configuration with auth options
│   │   └── templates/                  # Kubernetes manifests (13 files)
│   ├── README.md                       # n8n deployment and management guide
│   ├── CHANGELOG.md                    # Version history including v2.3.0 compatibility
│   ├── n8n-final-security-audit.sh     # Comprehensive security audit script
│   └── WORKFLOW_MIGRATION_README.md    # Docker to Kubernetes migration guide
│
├── vaultwarden/                        # Password Manager (Bitwarden-compatible)
│   ├── deploy.sh                       # Enterprise deployment with Argon2id security
│   ├── helm/                           # Kubernetes Helm chart
│   │   ├── Chart.yaml                  # Chart metadata with security focus
│   │   ├── values.yaml                 # Security-hardened configuration
│   │   └── templates/                  # Kubernetes manifests (11 files)
│   ├── README.md                       # Vaultwarden deployment guide
│   ├── CHANGELOG.md                    # Version history and security enhancements
│   └── install.sh                      # One-command installer for rapid deployment
│
├── wordpress/                          # Enterprise Content Management System
│   ├── deploy.sh                       # Cross-platform deployment script
│   ├── helm/                           # Kubernetes Helm chart
│   │   ├── Chart.yaml                  # Chart metadata with enterprise features
│   │   ├── values.yaml                 # Production WordPress configuration
│   │   └── templates/                  # Kubernetes manifests (9 files)
│   ├── README.md                       # WordPress deployment and scaling guide
│   ├── CHANGELOG.md                    # Version history and security updates
│   └── TROUBLESHOOTING.md              # Common issues and resolution procedures
│
└── k8s/                                # Kubernetes Infrastructure Tools
    └── monitoring/                     # Cluster Monitoring & Management
        ├── deploy.sh                   # Monitoring stack deployment
        ├── enterprise-monitoring-complete.yaml  # Templated monitoring manifests
        ├── README.md                   # Monitoring setup and operations guide
        └── MONITORING_BASELINE_REPORT.md        # Resource usage and optimization
```

## 🌐 **WeOwn Cloud Architecture**

WeOwn Cloud represents a **single-tenant, multi-cluster** infrastructure that transforms individual Kubernetes clusters into unified cloud environments. Each cluster runs the complete WeOwn application stack with enterprise-grade security, enabling teams to deploy AI, automation, and productivity tools with zero-trust networking.

### **Core Concept: Single-Tenant Cloud**
Rather than traditional multi-tenant SaaS, WeOwn Cloud provides each organization with their **own dedicated cluster environment**:

- **Dedicated Resources**: No resource sharing between organizations
- **Data Sovereignty**: Complete control over data location and processing
- **Security Isolation**: Zero-trust networking with complete tenant isolation
- **Custom Configurations**: Tailored to specific organizational needs
- **Direct Kubernetes Access**: Full infrastructure control and transparency

## 📚 **Enterprise Integration**

### **Multi-Cluster Cohort Model:**
WeOwn Cloud enables **cohort-based deployment** where each team or organization receives:

1. **Dedicated Cluster**: Full Kubernetes environment with enterprise security
2. **Standard Application Stack**: AI, automation, password management, CMS
3. **Custom Domain Configuration**: Professional subdomain structure
4. **Independent Data Sovereignty**: Complete control over data and processing
5. **Unified Management Tools**: Consistent deployment and monitoring across clusters

### **Scaling Strategies:**

**Horizontal Pod Autoscaling (HPA):**
- **WordPress**: Scale replicas based on CPU/memory usage
- **n8n**: Scale workflow execution pods for high throughput

**Vertical Pod Autoscaling (VPA):**
- **AnythingLLM**: Automatic memory adjustment for AI workloads
- **All Applications**: Learn usage patterns, optimize resource requests

**Cluster Scaling:**
- **Horizontal**: Add nodes for more total capacity
- **Vertical**: Upgrade node sizes for memory-intensive workloads

## 🎯 **Why WeOwn Cloud?**

### **vs. Traditional Multi-Tenant SaaS:**
- ✅ **Data Sovereignty**: Your data never leaves your cluster
- ✅ **Security Isolation**: Zero shared infrastructure vulnerabilities  
- ✅ **Custom Configuration**: Tailor applications to specific needs
- ✅ **Compliance Ready**: SOC2, ISO42001, GDPR-compliant by design
- ✅ **Cost Transparency**: Direct infrastructure costs, no vendor markup

### **vs. Self-Managed Infrastructure:**
- ✅ **Enterprise Security**: Zero-trust networking out of the box
- ✅ **Operational Excellence**: Automated backups, monitoring, scaling
- ✅ **Proven Architecture**: Battle-tested across 6 production clusters
- ✅ **Comprehensive Documentation**: Every aspect documented and reproducible
- ✅ **Expert Support**: WeOwn AI team maintains and evolves the platform

---

## 📞 **Support & Community**

**WeOwn AI Team**: [WeOwn.xyz](https://WeOwn.xyz)
**Documentation**: This repository contains complete deployment guides
**Security**: All deployments include enterprise-grade security by default
**Scaling**: Resource optimization across all supported cluster sizes

## 🛠️ **WeOwn CLI (DigitalOcean K8s Deployer)**

The `cli/weown` module provides an interactive interface for deploying and
managing WeOwn stacks on DigitalOcean Kubernetes:

- **Cluster management**: Scale, create, and delete node pools; delete the
  entire cluster via `doctl` with confirmation prompts.
- **Infrastructure deployment**: Install shared components such as
  `ingress-nginx`, `cert-manager`, ExternalDNS, and the monitoring stack.
- **Application stacks**: Deploy WordPress, Matomo, n8n, AnythingLLM and
  other apps into their dedicated namespaces using the curated Helm values.
- **Status & visibility**: List Helm deployments and inspect cluster
  resources from a single entry point.

### CLI Setup

1. Ensure `kubectl`, `helm`, and `doctl` are installed and authenticated
   against your DigitalOcean account.
2. Create `cli/.env` with at least:
   - `DO_TOKEN`, `DO_REGION`, `PROJECT_NAME`, `CLUSTER_NAME`
   - `BASE_DOMAIN`, `WP_DOMAIN`, `MATOMO_DOMAIN`, `LETSENCRYPT_EMAIL`
   - `WP_ADMIN_PASSWORD`, `MATOMO_DB_ROOT_PASSWORD`, `MATOMO_DB_PASSWORD`
3. From the repository root, run:

   ```bash
   ./cli/weown
   ```

Use the interactive menu to manage node pools, deploy infrastructure and
applications, and verify cluster health for your WeOwn cloud instance.
