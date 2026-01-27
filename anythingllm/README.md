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

### Interactive Deployment
Run the deployment script. It will guide you through:
- **Domain & SSL Setup**: Automatic Let's Encrypt certificate generation.
- **LLM Selection**: Choose from top 2026 models (Claude Opus 4.5, GPT-5.2, Llama 3.3, etc.).
- **Embedder Selection**: Choose between **Private/Native** (requires more RAM) or **OpenRouter API** (runs on 2GB nodes).
- **Fine-tuning**: Configure Telemetry and Stream Timeout preferences.

```bash
# Clone the repository
git clone https://github.com/WeOwnNetwork/ai.git
cd ai/anythingllm

# Run the deployment script
./deploy.sh
```

### Configuration Options

#### AI Models (OpenRouter)
The deployment script offers a **curated list** of the most popular and high-performance models. You can also manually enter **any** OpenRouter model ID if your preferred model is not listed.

**Curated Selection:**
- **Claude Opus 4.5** (`anthropic/claude-opus-4.5`): Complex reasoning, coding, and deep analysis.
- **Claude Sonnet 4.5** (`anthropic/claude-sonnet-4.5`): Best balanced daily driver for speed and intelligence.
- **GPT-5.2** (`openai/gpt-5.2`): General knowledge and creative writing.
- **Grok 4** (`x-ai/grok-4`): Massive 256k context, advanced reasoning, and scientific tasks.
- **Grok Code Fast 1** (`x-ai/grok-code-fast-1`): Ultra-fast coding agent with visible reasoning traces.
- **Gemini 3 Pro** (`google/gemini-3-pro-preview`): Infinite context window for analyzing massive documents.
- **DeepSeek V3.2** (`deepseek/deepseek-v3.2`): Incredible coding performance at a very low cost.
- **Llama 3.3 70B** (`meta-llama/llama-3.3-70b-instruct`): Top open-weights model with uncensored reasoning.

#### Embedding Engine
AnythingLLM requires an embedding model to "read" and index your documents for RAG.

**⚠️ PRIVACY WARNING:**
- **OpenAI Models**: Retain API data for 30 days. **NOT recommended** for strict privacy/confidential data.
- **OpenRouter (Mistral/Qwen/BAAI)**: Many providers offer zero-retention policies. Check individual provider terms.
- **Native (Local)**: Zero external data transfer. Safest option.

**🧠 How to Choose an Embedding Model**

Embedding models convert text into numbers (vectors) so the AI can "understand" similarity. The right choice depends on your privacy needs, document size, and language.

### **Key Terms Explained (For Non-Technical Users)**

**Context Window** (How much text fits in one "chunk"):
- **256 tokens** (~3 paragraphs): Very short. Loses context in long docs.
- **512 tokens** (~1 page): Standard for older/fast models.
- **2k tokens** (~5 pages): Good for short reports.
- **8k tokens** (~20 pages): The Modern Standard. Captures full chapters.
- **32k tokens** (~80 pages): Massive. Reads entire files or legal agreements at once.

**Dimensions (Dims)** (The "Resolution" of understanding):
- **384 Dims**: Low Res. Extremely fast, low storage. Basic matching.
- **768 Dims**: Standard Definition. The open-source baseline.
- **1024 Dims**: High Definition. Great balance for business documents.
- **1536 Dims**: Full HD. OpenAI's standard. Detailed.
- **2560 Dims**: 2K Res. Very high nuance (Qwen).
- **3072 Dims**: 4K Res. Extreme nuance (OpenAI Large).
- **4096 Dims**: 8K Res. Max nuance. Heaviest storage (Qwen Large).

### **🎯 Quick Decision Guide (All 21 Models Categorized)**

**1. General Purpose / Startup (Balance)**
*Good for: Internal wikis, standard business docs, blogs.*
- **Models**: `Text Embedding 3 Small`, `Mistral Embed`, `BGE Large`, `BGE Base`, `MPNet Base`

**2. Deep Research / Legal / Medical (Max Accuracy)**
*Good for: Contracts, medical records, dense academic papers.*
- **Models**: `Text Embedding 3 Large`, `Qwen 8B`, `GTE Large`, `GTE Base`

**3. Coding / Engineering (Code Structure)**
*Good for: Indexing repositories, API documentation, technical stacks.*
- **Models**: `Codestral Embed` (Best), `Qwen 8B`, `Qwen 4B`

**4. Multi-Language / Global**
*Good for: International companies, mixed-language datasets.*
- **Models**: `BGE M3` (Best), `Multilingual E5`, `Mistral Embed`

**5. Search / Retrieval (Query-Passage)**
*Good for: Search engines, finding specific paragraphs.*
- **Models**: `E5 Large`, `E5 Base`, `Multilingual E5`, `Multi-QA MPNet`

**6. Huge Scale / High Speed (Low Cost)**
*Good for: 1M+ documents, logs, real-time processing.*
- **Models**: `All MiniLM L12`, `All MiniLM L6`, `Paraphrase MiniLM`, `BGE Base`

**7. Legacy / Ecosystem Specific**
*Good for: Backward compatibility.*
- **Models**: `Ada 002` (Old OpenAI), `Gemini 001` (Google Only)

---

### **Detailed Model List (OpenRouter)**

#### **OpenAI (Proprietary - 30 Day Data Retention)**
*⚠️  Privacy Warning: OpenAI retains API data for 30 days. Not for strict zero-data-retention needs.*

- **Text Embedding 3 Large** (`openai/text-embedding-3-large`)
  - **Specs**: 8k Context | 3072 Dims (4K Res)
  - **Best For**: **Legal, Medical, Finance**. Max accuracy.
  - **Recommendation**: Use for high-stakes retrieval.
- **Text Embedding 3 Small** (`openai/text-embedding-3-small`)
  - **Specs**: 8k Context | 1536 Dims (Full HD)
  - **Best For**: **General Purpose**. 5x cheaper than Ada.
  - **Recommendation**: Default choice for startups.
- **Text Embedding Ada 002** (`openai/text-embedding-ada-002`)
  - **Specs**: 8k Context | 1536 Dims
  - **Best For**: **Legacy Projects**.
  - **Recommendation**: Avoid unless maintaining legacy systems.

#### **Mistral (Open Weights - Privacy Friendly)**
*Excellent privacy choice. No data retention if using compliant OpenRouter providers.*

- **Codestral Embed 2505** (`mistralai/codestral-embed-2505`)
  - **Specs**: 32k Context | 1024 Dims | **Code Optimized**
  - **Best For**: **Software Development**.
  - **Recommendation**: **MUST HAVE** for engineering teams.
- **Mistral Embed 2312** (`mistralai/mistral-embed-2312`)
  - **Specs**: 8k Context | 1024 Dims
  - **Best For**: **General Business (English/French)**.
  - **Recommendation**: Great privacy-focused alternative to OpenAI.

#### **Qwen & Google (Deep Reasoning)**
- **Qwen3 Embedding 8B** (`qwen/qwen3-embedding-8b`)
  - **Specs**: 32k Context | 4096 Dims (8K Res)
  - **Best For**: **Complex Scientific RAG**.
  - **Recommendation**: The "smartest" open model available.
- **Qwen3 Embedding 4B** (`qwen/qwen3-embedding-4b`)
  - **Specs**: 32k Context | 2560 Dims (2K Res)
  - **Best For**: **Technical Docs**.
  - **Recommendation**: Balanced speed/smarts for tech docs.
- **Gemini Embedding 001** (`google/gemini-embedding-001`)
  - **Specs**: 2k Context | 768 Dims
  - **Recommendation**: Only for Google ecosystem integration.

#### **BAAI (Multilingual & Dense)**
- **BGE M3** (`baai/bge-m3`)
  - **Specs**: 8k Context | 1024 Dims | **100+ Languages**
  - **Best For**: **Global Corporations**.
  - **Recommendation**: Best all-rounder for mixed language workspaces.
- **BGE Large En 1.5** (`baai/bge-large-en-v1.5`)
  - **Specs**: 512 Context | 1024 Dims
  - **Best For**: **Standard English Text**.
  - **Recommendation**: Reliable choice for standard docs.
- **BGE Base En 1.5** (`baai/bge-base-en-v1.5`)
  - **Specs**: 512 Context | 768 Dims
  - **Recommendation**: Use if storage is tight.

#### **Intfloat E5 (Semantic Search)**
- **Multilingual E5 Large** (`intfloat/multilingual-e5-large`)
  - **Specs**: 512 Context | 1024 Dims
  - **Best For**: **Cross-lingual Search**.
- **E5 Large V2** (`intfloat/e5-large-v2`)
  - **Specs**: 512 Context | 1024 Dims
  - **Best For**: **English Search**.
- **E5 Base V2** (`intfloat/e5-base-v2`)
  - **Specs**: 512 Context | 768 Dims

#### **Thenlper GTE (General Text)**
- **GTE Large** (`thenlper/gte-large`)
  - **Specs**: 8k Context | 1024 Dims
  - **Best For**: **Academic/Scientific**.
  - **Recommendation**: Great alternative to OpenAI.
- **GTE Base** (`thenlper/gte-base`)
  - **Specs**: 8k Context | 768 Dims

#### **Sentence Transformers (Speed & Local-Ready)**
- **All MPNet Base V2** (`sentence-transformers/all-mpnet-base-v2`)
  - **Specs**: 512 Context | 768 Dims
  - **Best For**: **Reliable Baseline**.
  - **Recommendation**: Safe choice for older systems.
- **Multi-QA MPNet** (`sentence-transformers/multi-qa-mpnet-base-dot-v1`)
  - **Specs**: 512 Context | 768 Dims
  - **Best For**: **Q&A Systems**.
- **All MiniLM L12 V2** (`sentence-transformers/all-minilm-l12-v2`)
  - **Specs**: 512 Context | 384 Dims
  - **Best For**: **Speed**.
  - **Recommendation**: Use if latency is #1 concern.
- **All MiniLM L6 V2** (`sentence-transformers/all-minilm-l6-v2`)
  - **Specs**: 256 Context | 384 Dims | **Ultra Fast**
  - **Best For**: **Massive Scale (1M+ Docs)**.
  - **Recommendation**: Fastest model available.
- **Paraphrase MiniLM L6** (`sentence-transformers/paraphrase-minilm-l6-v2`)
  - **Specs**: 256 Context | 384 Dims
  - **Best For**: **Paraphrase Matching**.

**Option 2: Native (Local)**
Runs inside your cluster.
- **Pros**: Maximum privacy (data never leaves cluster).
- **Cons**: High RAM usage (4GB+ per pod recommended). Large documents may cause OOM kills on small nodes.
- **Default Model**: `all-MiniLM-L6-v2`.

#### Telemetry
- **Disabled (Default)**: Strict privacy, no data sent to Mintplex Labs.
- **Enabled**: Sends anonymous usage stats to help improve the software.

#### Community Hub Agent Skills
- **Enabled (Default)**: Allows importing verified/private agent skills from AnythingLLM Hub
- **Security Level**: Restricted to verified and private items only (not untrusted public code)
- **Configuration**: Set via `COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED: "1"` in values.yaml
- **Alternative**: Set to `"allow_all"` to allow unverified items (NOT recommended for production)

**⚠️ SECURITY WARNING:**
Agent skills can execute code on your system. The default setting (`"1"`) only allows:
- **Verified items**: Reviewed and approved by AnythingLLM team
- **Private items**: Your own custom agent skills

To disable completely, remove the `COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED` variable from values.yaml.

### ⚙️ Helm Value Management

For comprehensive guidance on safely updating configuration values in production:

**📖 See: [`/docs/HELM_VALUE_MANAGEMENT.md`](/docs/HELM_VALUE_MANAGEMENT.md)**

This guide covers:
- ✅ **Safe upgrade strategies** (`--reuse-values` vs `--reset-values` vs `--values`)
- ✅ **Live deployment updates** without downtime
- ✅ **Common pitfalls** and how to avoid them (database connection failures, lost configuration)
- ✅ **GUI tools** (Lens, Portainer) and their limitations
- ✅ **Deploy script integration** for secure value updates
- ✅ **Emergency recovery** procedures

**Critical Rule:** Always use `--reuse-values` with stateful applications (AnythingLLM, WordPress, Matomo). Never use `--reset-values` as it regenerates all values including passwords, breaking database connections.

### 🔑 API Key Management & Rotation

#### Manual Secret Management (Current Process)

When you need to rotate API keys (OpenRouter, OpenAI, etc.) or other secrets:

**1. Retrieve Existing Secrets:**
```bash
# View secret keys (safe - no values shown)
kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath='{.data}' | jq -r 'keys[]'

# Verify current API key (shows first 20 chars only)
kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath='{.data.OPENROUTER_API_KEY}' | base64 -d | head -c 20 && echo "..."
```

**2. Update Secret with New API Key:**
```bash
# Set new API key
NEW_API_KEY="sk-or-v1-YOUR_NEW_KEY_HERE"

# Retrieve values to preserve
ADMIN_EMAIL=$(kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath='{.data.ADMIN_EMAIL}' | base64 -d)
JWT_SECRET=$(kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath='{.data.JWT_SECRET}' | base64 -d)

# Replace secret using secure env file approach (not exposed in shell history)
SECRETS_FILE="$(mktemp)"
cat > "$SECRETS_FILE" << EOF
ADMIN_EMAIL=$ADMIN_EMAIL
OPENROUTER_API_KEY=$NEW_API_KEY
JWT_SECRET=$JWT_SECRET
EOF

kubectl create secret generic anythingllm-secrets \
  --from-env-file="$SECRETS_FILE" \
  --dry-run=client -o yaml | kubectl replace -f - -n anything-llm

# Securely delete temporary file
rm -f "$SECRETS_FILE"

# Restart deployment to apply changes
kubectl rollout restart deployment anythingllm -n anything-llm
```

**3. Clean Up Shell Variables:**
```bash
# Clear sensitive data from shell
unset NEW_API_KEY ADMIN_EMAIL JWT_SECRET

# Optional: Clear from shell history
history -d $(history | grep "NEW_API_KEY" | awk '{print $1}')
```

**Security Notes:**
- ✅ **Encryption**: Secrets encrypted at rest in etcd (DigitalOcean managed)
- ✅ **Access Control**: RBAC restricts who can read secrets
- ✅ **Temporary Storage**: Shell variables cleared after use
- ⚠️ **Rotation**: Recommended every 90 days for production
- ⚠️ **Audit**: Track secret access via Kubernetes audit logs

**Common Issues:**
- **401 User not found**: API key expired/revoked - rotate immediately
- **Pod crash loops**: Verify API key is valid before deployment restart
- **Multiple restarts**: Check logs for authentication failures

#### Automated Secret Management (Infisical)

For enterprise deployments, replace manual Kubernetes Secrets with **Infisical Pro** for centralized secret management with automated rotation.

**Features:**
- 🔄 **Automated rotation**: OpenRouter API (7 days), JWT secrets (90 days), Client secrets (30 days)
- 📊 **90-day audit logs** for SOC2/ISO/IEC 42001 compliance
- 🔐 **RBAC access control** with Machine Identity authentication
- ⚡ **Auto-sync** to Kubernetes every 60 seconds
- 🔁 **Auto-restart** pods when secrets change

**Upgrade Existing Deployment (Preserves All Config):**
```bash
# Get current deployed values to preserve config
helm get values anythingllm -n anything-llm -o yaml > /tmp/current-values.yaml

# Add Infisical config to values file
cat >> /tmp/current-values.yaml << 'EOF'
infisical:
  enabled: true
  projectSlug: "your-project-slug"
  envSlug: "prod"
EOF

# Upgrade with complete values (preserves everything)
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --values /tmp/current-values.yaml \
  --wait --timeout=5m
```

📚 **Complete Setup Guide:** See [docs/INFISICAL_INTEGRATION.md](docs/INFISICAL_INTEGRATION.md) for:
- Infisical project setup and Machine Identity creation
- Kubernetes Operator installation and configuration
- Automated rotation workflows (OpenRouter, JWT, Client secrets)
- Compliance monitoring and compromise detection

### 🔄 Safe Helm Upgrade Process

**CRITICAL: Proper upgrade commands preserve all user data, conversations, and configurations.**

#### **Understanding Helm Upgrade Behavior**

Helm upgrades can behave unexpectedly depending on flags used:

**`--reuse-values` (Reuse Deployed Values):**
- Uses values **currently deployed** in cluster
- Ignores changes in your local `values.yaml`
- Can cause issues if deployed values are incomplete or outdated
- **Use when:** Making targeted changes with `--set` flags only

**`--values` (Use Local Values File):**
- Uses values from your local `values.yaml` file
- Replaces all deployed values with file contents
- Ensures consistency with version-controlled configuration
- **Use when:** Upgrading with updated values.yaml or chart version

**`--reset-values` (Use Chart Defaults):**
- Resets to chart's default values
- **WARNING:** Loses all customizations (domains, resources, etc.)
- **Use when:** Starting fresh or debugging value conflicts

#### **Common Upgrade Scenarios**

**Scenario 1: Upgrade Chart/Application Version**
```bash
# Update Chart.yaml or image tag in values.yaml, then:
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --values=./helm/values.yaml \
  --wait --timeout=10m
```

**Scenario 2: Change Resource Limits**
```bash
# Edit values.yaml resources section, then:
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --values=./helm/values.yaml
```

**Scenario 3: Update Environment Variables**
```bash
# Quick change without editing values.yaml:
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.env.SOME_VAR="new-value"
```

**Scenario 4: Change Domain/Ingress**
```bash
# Update domain without touching other settings:
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set ingress.hosts[0].host=new-domain.com
```

#### **Recommended Upgrade Methods**

**Option 1: Use values.yaml (RECOMMENDED)**
```bash
cd /path/to/anythingllm

# Ensure helm/values.yaml has explicit version
grep "tag:" helm/values.yaml  # Should show: tag: "1.9.1"

# Upgrade with values file
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --values=./helm/values.yaml \
  --wait --timeout=10m

# Verify upgrade
kubectl get deployment anythingllm -n anything-llm -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Option 2: Explicit --set Flags**
```bash
# Set version explicitly on command line
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.image.tag=1.9.1 \
  --set resources.limits.memory=1.5Gi \
  --wait --timeout=10m
```

**Option 3: Fix Deployed Values First**
```bash
# Check current deployed values
helm get values anythingllm -n anything-llm

# If image.tag is missing, fix it:
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.image.tag=1.9.1 \
  --wait --timeout=10m

# Future upgrades can safely use --reuse-values
```

#### **Data Preservation During Upgrades**

**What Gets Preserved:**
- ✅ **PVC Data**: All conversations, documents, vector DB (mounted from `anythingllm-storage`)
- ✅ **Kubernetes Secrets**: API keys, JWT tokens, admin credentials
- ✅ **Configuration**: All Helm values persist across upgrades
- ✅ **Ingress/DNS**: Domain and TLS certificates unchanged

**What Gets Updated:**
- ✅ Container image version
- ✅ Resource limits (CPU/memory)
- ✅ Environment variables
- ✅ Pod configuration

**Rolling Update Process:**
1. New pod created with updated configuration
2. New pod mounts **existing PVC** at `/app/server/storage`
3. Health checks pass on new pod
4. Old pod gracefully terminated
5. **Zero data loss** - same persistent volume, new container

#### **Verify Successful Upgrade**

```bash
# Check Helm revision and status
helm list -n anything-llm
helm history anythingllm -n anything-llm

# Verify pod is running with correct version
kubectl get pods -n anything-llm
kubectl get deployment anythingllm -n anything-llm -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check that PVC is still mounted
kubectl get pvc -n anything-llm
kubectl describe pod -n anything-llm | grep -A 5 "Mounts:"

# Test application access
curl -k https://your-domain.com/api/health
```

#### **Rollback if Needed**

```bash
# View upgrade history
helm history anythingllm -n anything-llm

# Rollback to previous revision
helm rollback anythingllm -n anything-llm

# Rollback to specific revision
helm rollback anythingllm 7 -n anything-llm
```

#### Preserving Configuration During Upgrades

**Problem**: Using `--reuse-values` or `--set` flags can lose configuration if deployed values are incomplete.

**Solution**: Always upgrade with a complete values file that includes all your configuration.

**Export Current Config + Add New Features:**
```bash
# Export current deployed values
helm get values anythingllm -n anything-llm -o yaml > /tmp/production-values.yaml

# Edit file to add new features (e.g., Infisical integration)
# Then upgrade with complete values
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --values /tmp/production-values.yaml \
  --wait --timeout=5m

# Verify all config persisted
helm get values anythingllm -n anything-llm
```

**What Gets Preserved:**
- ✅ LLM provider and model preferences
- ✅ Embedding engine and model selection
- ✅ Timeout settings and configuration
- ✅ Infisical integration settings
- ✅ Ingress domain and TLS config

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
- **Current Version**: 1.9.1 (January 2026)
- **Chart Version**: 2.5.0 (#WeOwnVer: Season 2, Week 5)
- **Versioning System**: [#WeOwnVer](/docs/VERSIONING_WEOWNVER.md) (Season.Week.Day.Version)
- **Image**: `mintplexlabs/anythingllm:1.9.1`
- **Update Strategy**: Rolling updates with zero downtime

#### **Manual Upgrade Commands**

**Option 1: Standard Upgrade (Recommended - Preserves All Settings)**
```bash
# Upgrades to latest Helm chart while keeping all existing configuration
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --wait --timeout=10m
```

**Option 2: Update Community Hub Mode Only**
```bash
# Set to verified/private only (recommended)
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.env.COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED="1" \
  --wait --timeout=10m

# Set to allow all (including unverified - NOT recommended)
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.env.COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED="allow_all" \
  --wait --timeout=10m

# Disable agent skill imports completely
helm upgrade anythingllm ./helm \
  --namespace=anything-llm \
  --reuse-values \
  --set anythingllm.env.COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED=null \
  --wait --timeout=10m
```

**Option 3: Full Reconfiguration**
```bash
# Re-run deployment script for interactive reconfiguration
./deploy.sh
# Select option 2 (Reconfigure AI Models) or option 3 (Toggle Community Hub)
```

**Verify Upgrade**:
```bash
# Check deployment status
kubectl get deployment anythingllm -n anything-llm -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get pods -n anything-llm

# Check Helm status and revision
helm list -n anything-llm

# View current Community Hub mode
helm get values anythingllm -n anything-llm -o json | jq '.anythingllm.env.COMMUNITY_HUB_BUNDLE_DOWNLOADS_ENABLED'
```

**Automatic Helm Cleanup**: Old Helm revisions are automatically cleaned up (keeps last 10 revisions)

#### **Automated Backups** ✅
- **Schedule**: Daily at 2 AM UTC (configurable)
- **Retention**: 30 days (SOC2/ISO/IEC 42001 compliant)
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
- `OPENROUTER_API_KEY`: Unified API key for LLM and Embedding services (Preferred)
- `OPENAI_API_KEY`: Legacy OpenAI provider support (Optional)
- `OPENAI_API_BASE`: Legacy OpenAI provider base URL (Optional)

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
