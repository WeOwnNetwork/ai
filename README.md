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

**[WordPress-Docker](./wordpress-docker/)** - Copier Template for WordPress on DigitalOcean Droplets

- **Purpose**: Templated WordPress deployments on DigitalOcean droplets with Docker + OpenTofu
- **Use Cases**: Standalone WordPress sites, rapid site provisioning, cohort deployments
- **Stack**: Docker Compose, Caddy (TLS), MariaDB, OpenTofu (IaC)
- **Features**: Copier templating, Wordfence WAF auto-config, skinny backups, Infisical secrets
- **Sites**: [burnedout.xyz](./wordpress-docker/sites/burnedout-xyz/), [ptoken.agency](./wordpress-docker/sites/ptoken-agency/)

**[WordPress](./wordpress/)** - Enterprise Content Management (Kubernetes)

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
├── wordpress-docker/                   # WordPress on DigitalOcean Droplets (Copier Template)
│   ├── copier.yaml                     # Copier template configuration
│   ├── README.md                       # Template usage and documentation
│   ├── docs/
│   │   └── INFISICAL_INTEGRATION.md    # Secrets management integration guide
│   ├── template/                       # Jinja2 templates for site generation
│   │   ├── docker/                     # Docker Compose, Caddyfile, Wordfence WAF
│   │   ├── terraform/                  # OpenTofu infrastructure code
│   │   └── scripts/                    # Deploy, backup, restore scripts
│   └── sites/                          # Pre-generated site configurations
│       ├── burnedout-xyz/              # burnedout.xyz (apex domain style)
│       └── ptoken-agency/              # ptoken.agency (www domain style)
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

## 🛡️ **Compliance & Governance**

WeOwn AI infrastructure follows a layered, phased compliance program progressing through NIST CSF 2.0 + CIS Controls v8 → CSA CCM v4 → ISO/IEC 27001:2022 → SOC 2 Type II → ISO/IEC 42001:2023. Current baseline: **Phase 1** (NIST CSF 2.0 + CIS v8 IG1), version **v3.3.4.1** per [#WeOwnVer](docs/VERSIONING_WEOWNVER.md).

### Core Documents

- **[Compliance Roadmap](docs/COMPLIANCE_ROADMAP.md)** — Detailed 5-phase strategy with CI/CD integration, controls, and success metrics per phase
- **[Copilot AI Review Instructions](.github/copilot-instructions.md)** — Phase-aware review directives, NIST CSF mapping, forward-looking guardrails
- **[Workflows Operations Reference](.github/workflows/README.md)** — Architecture, `weown-bot` service account usage, PAT rotation, alert stack, transition checklist, replication for other repos
- **[Security Assessment](.github/SECURITY_ASSESSMENT.md)** — Threat model, risk register, compliance mapping
- **[Incident Response Runbook](.github/INCIDENT_RESPONSE.md)** — SEV-1..4 scenarios with RTO/RPO and step-by-step response
- **[CI/CD Workflows](.github/CI_CD_WORKFLOWS.md)** — Validation workflow architecture
- **[Versioning (#WeOwnVer)](docs/VERSIONING_WEOWNVER.md)** — Calendar-driven `vSEASON.MONTH.WEEK.ITERATION` methodology
- **[Changelog](CHANGELOG.md)** — Repository-level change history (indexes all per-directory CHANGELOGs)

### Architecture Decision Records (ADRs)

- **[ADR-001: Ecosystem Service Account + Fine-Grained PATs](.github/ADR-001-service-account-pat.md)** — Why `weown-bot` and not a GitHub App
- **[ADR-002: Infisical as Primary Secret Store via GitHub Sync](.github/ADR-002-infisical-github-sync.md)** — Centralized secret management

### Code Review Model

Every PR to `main` requires:

- ✅ GitHub Copilot AI code review (automatic on PRs from `weown-bot`)
- ✅ 2 human approvals (enforced by branch protection + CODEOWNERS)
- ✅ Review from Code Owners per [`.github/CODEOWNERS`](.github/CODEOWNERS)
- ✅ All conversations resolved before merge
- ✅ `branch-name-check.yml` status check passes

### Branch Strategy — GitHub Flow

Short-lived branches off `main`, merged back via reviewed PRs. Naming convention:

```
<type>/<dev>-<short-description>
e.g., feature/roman-add-pat-health-check
      fix/ncimino-resolve-tls-warning
      docs/mohammed-update-compliance-roadmap
      hotfix/shahid-patch-auth-bypass
```

Enforced by [`.github/workflows/branch-name-check.yml`](.github/workflows/branch-name-check.yml). See [`.github/workflows/README.md` §3](.github/workflows/README.md#3-branch-naming-convention--developer-attribution) for full convention and [§8.2](.github/workflows/README.md#82-branch-naming-enforcement) for enforcement layers.

### Replicating `weown-bot` for Other Repos / Workflows

The `weown-bot` service account is **ecosystem-wide**. Adding it to another repo takes ~10 minutes. Full step-by-step instructions — including coverage for different workflow types (auto-PR, release, cross-repo dispatch, issue automation) and per-workflow least-privilege PAT scopes — live in [`.github/workflows/README.md` §5](.github/workflows/README.md#5-replicating-weown-bot-for-other-repos--workflows).

Quick summary:

1. Generate a fine-grained PAT scoped only to the new repo with **minimum** permissions per [§5.2–§5.5](.github/workflows/README.md#52-variant--auto-pr-workflow-same-as-this-repo)
2. Store in Infisical project `weown-bot GitHub PATs` as `WEOWN_BOT_PAT__<ORG>_<REPO>`
3. Extend the Infisical GitHub App to the new repo; create a new Secret Sync mapping to GitHub secret name `WEOWN_BOT_PAT`
4. Copy the relevant workflow(s) and configure branch protection + naming enforcement per [§8](.github/workflows/README.md#8-required-branch-protection--naming-enforcement)

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
1. Create `cli/.env` with at least:

   - `DO_TOKEN`, `DO_REGION`, `PROJECT_NAME`, `CLUSTER_NAME`
   - `BASE_DOMAIN`, `WP_DOMAIN`, `MATOMO_DOMAIN`, `LETSENCRYPT_EMAIL`
   - `WP_ADMIN_PASSWORD`, `MATOMO_DB_ROOT_PASSWORD`, `MATOMO_DB_PASSWORD`
1. From the repository root, run:

   ```bash
   ./cli/weown
   ```

Use the interactive menu to manage node pools, deploy infrastructure and
applications, and verify cluster health for your WeOwn cloud instance.