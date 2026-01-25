# Infisical Secret Management & Automated API Key Rotation

🔐 **Enterprise Secrets Management • 🔄 Automated Rotation • 📊 90-Day Audit Logs**

Complete guide for integrating Infisical Pro with AnythingLLM for centralized secret management and automated OpenRouter API key rotation using n8n workflows.

## 📋 Overview

This integration replaces manual Kubernetes secret management with:
- **Centralized secrets** in Infisical Cloud with 90-day audit logs
- **Automated sync** to Kubernetes via Infisical Operator (every 60 seconds)
- **Automated rotation** via n8n workflows:
  - **OpenRouter API Key**: Every 7 days (aggressive security posture)
  - **JWT_SECRET**: Every 90 days (SOC2/ISO42001 recommended)
  - **Machine Identity Client Secret**: Every 30 days (ISO42001 compliance)
- **Compliance-ready** SOC2/ISO42001 audit trails with compromise detection

### Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    INFISICAL + n8n AUTOMATION FLOW                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────┐   │
│   │   n8n       │ ──► │ OpenRouter  │ ──► │    Infisical Cloud      │   │
│   │  Workflow   │     │ Provisioning│     │    (Pro Tier)           │   │
│   │  (Monthly)  │     │    API      │     │                         │   │
│   └─────────────┘     └─────────────┘     │  • 90-day audit logs    │   │
│                                           │  • Secret versioning    │   │
│                                           │  • RBAC permissions     │   │
│                                           └───────────┬─────────────┘   │
│                                                       │                 │
│                                                       ▼                 │
│                                           ┌─────────────────────────┐   │
│                                           │  Infisical K8s Operator │   │
│                                           │  (Syncs every 60s)      │   │
│                                           └───────────┬─────────────┘   │
│                                                       │                 │
│                                                       ▼                 │
│                                           ┌─────────────────────────┐   │
│                                           │   anythingllm-secrets   │   │
│                                           │   (Kubernetes Secret)   │   │
│                                           └───────────┬─────────────┘   │
│                                                       │                 │
│                                                       ▼                 │
│                                           ┌─────────────────────────┐   │
│                                           │    AnythingLLM Pod      │   │
│                                           │  (Auto-restart on sync) │   │
│                                           └─────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## 🔧 Prerequisites

- **Infisical Pro** account (cloud-hosted at app.infisical.com)
- **Kubernetes cluster** with AnythingLLM deployed
- **n8n instance** for workflow automation (optional for manual rotation)
- **OpenRouter account** with Provisioning API access

---

## Phase 1: Infisical Project Setup

### Step 1.1: Create Infisical Project

1. Log in to **https://app.infisical.com**
2. Click **"+ New Project"**
3. Enter project name (e.g., `anythingllm` or `weown-anythingllm`)
4. Note your **Project Slug** from the URL or Settings → General

### Step 1.2: Create Environment

1. Go to **Settings → Environments**
2. Create or verify `prod` environment exists
3. Note the exact **Environment Slug** (e.g., `prod` or `production`)

### Step 1.3: Add Secrets

In the **Secrets** tab with your environment selected, add:

| Key | Description | Example |
|-----|-------------|---------|
| `OPENROUTER_API_KEY` | Your OpenRouter API key | `sk-or-v1-...` |
| `JWT_SECRET` | JWT signing secret | (generate with `openssl rand -hex 32`) |
| `ADMIN_EMAIL` | Admin notification email | `admin@example.com` |

**To retrieve existing values from Kubernetes:**
```bash
# Get JWT_SECRET
kubectl get secret anythingllm-secrets -n anything-llm \
  -o jsonpath='{.data.JWT_SECRET}' | base64 -d

# Get ADMIN_EMAIL
kubectl get secret anythingllm-secrets -n anything-llm \
  -o jsonpath='{.data.ADMIN_EMAIL}' | base64 -d
```

### Step 1.4: Create Machine Identity

1. Go to **Access Control → Machine Identities**
2. Click **"+ Create Identity"**
3. Name: `anythingllm-k8s-operator`
4. Role: **Developer** (read/write access)

### Step 1.5: Configure Universal Auth

1. Click on your Machine Identity
2. Go to **Authentication** tab
3. Click **"+ Add Auth Method"** → **Universal Auth**
4. Configure TTL settings:
   - **Access Token TTL**: `3600` (1 hour) - short-lived for security
   - **Max TTL**: `2592000` (30 days)
5. Click **"Create Client Secret"**
6. **⚠️ SAVE IMMEDIATELY**: Copy both Client ID and Client Secret

**Recommended TTL Settings for SOC2 Compliance:**

| Setting | Value | Reason |
|---------|-------|--------|
| Access Token TTL | 3600 (1 hour) | Short-lived tokens minimize exposure |
| Max TTL | 2592000 (30 days) | Forces periodic re-authentication |
| Client Secret Rotation | 90 days | Manual rotation via n8n workflow |

### Step 1.6: Grant Project Access

1. Go to your project → **Access Control → Machine Identities**
2. Click **"+ Add Identity"**
3. Select `anythingllm-k8s-operator`
4. Role: **Developer**

---

## Phase 2: Kubernetes Integration

### Step 2.1: Install Infisical Operator

```bash
# Add Helm repository
helm repo add infisical-helm-charts \
  'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
helm repo update

# Install operator
helm install infisical-secrets-operator infisical-helm-charts/secrets-operator \
  --namespace infisical-operator \
  --create-namespace

# Verify installation
kubectl get pods -n infisical-operator
```

### Step 2.2: Create Authentication Secret

Store your Machine Identity credentials in Kubernetes:

```bash
kubectl create secret generic infisical-universal-auth \
  --namespace anything-llm \
  --from-literal=clientId="YOUR_CLIENT_ID" \
  --from-literal=clientSecret="YOUR_CLIENT_SECRET"
```

**What this does:**
- Creates a Kubernetes Secret named `infisical-universal-auth`
- Stores credentials the Infisical Operator uses to authenticate
- Credentials reference your Machine Identity from Phase 1

### Step 2.3: Deploy with Infisical Integration

```bash
cd /path/to/anythingllm

helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --set infisical.enabled=true \
  --set infisical.projectSlug="YOUR_PROJECT_SLUG" \
  --set infisical.envSlug="prod" \
  --set ingress.domain="your-domain.com"
```

**Parameters explained:**

| Parameter | Description |
|-----------|-------------|
| `infisical.enabled=true` | Enables InfisicalSecret CRD creation |
| `infisical.projectSlug` | Your Infisical project identifier |
| `infisical.envSlug` | Environment to sync from (e.g., `prod`) |
| `ingress.domain` | Your AnythingLLM domain |

### Step 2.4: Verify Sync

```bash
# Check InfisicalSecret status
kubectl describe infisicalsecret anythingllm-infisical -n anything-llm

# Expected output should show:
# - "Infisical controller has started syncing your secrets"
# - All conditions with Status: True
```

**Troubleshooting sync issues:**

| Error | Cause | Solution |
|-------|-------|----------|
| "Folder with path '/' not found" | Wrong environment slug | Verify `envSlug` matches Infisical exactly |
| "Failed to authenticate" | Invalid credentials | Recreate `infisical-universal-auth` secret |
| "Project not found" | Wrong project slug | Check project slug in Infisical URL |

---

## Phase 3: OpenRouter Provisioning Setup

### Step 3.1: Create Provisioning API Key

1. Go to **https://openrouter.ai/settings/keys**
2. Click **"Create Provisioning Key"** (not a regular API key)
3. Name: `infisical-rotation-key`
4. Copy the key (starts with `sk-or-v1-...`)

### Step 3.2: Store Provisioning Key in Infisical

Add to your Infisical project:

| Key | Value |
|-----|-------|
| `OPENROUTER_PROVISIONING_KEY` | Your provisioning API key |

### Step 3.3: Test Provisioning API

```bash
# Test creating a new key
curl -X POST "https://openrouter.ai/api/v1/keys" \
  -H "Authorization: Bearer YOUR_PROVISIONING_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-rotation-key",
    "limit": 100
  }'

# Response includes the new key and its hash for deletion
```

---

## Phase 4: n8n Workflow Automation

### Step 4.1: Workflow Overview

The n8n workflow performs automated rotation on multiple schedules:

**OpenRouter API Key Rotation (Weekly - Every 7 Days):**
1. **Authenticate** with Infisical API
2. **Get** current OpenRouter API key from Infisical
3. **Create** new OpenRouter API key via Provisioning API
4. **Update** Infisical secret with new key
5. **Wait** for Kubernetes sync (2 minutes)
6. **Delete** old OpenRouter API key
7. **Notify** on success/failure

**JWT_SECRET Rotation (Quarterly - Every 90 Days):**
1. **Authenticate** with Infisical API
2. **Generate** new cryptographically secure JWT secret (32 bytes)
3. **Update** Infisical secret
4. **Wait** for Kubernetes sync and pod restart (5 minutes)
5. **Verify** application health
6. **Notify** on success/failure

**Machine Identity Client Secret Rotation (Monthly - Every 30 Days):**
1. **Authenticate** with Infisical API (using current credentials)
2. **Create** new client secret via Infisical API
3. **Update** Kubernetes secret `infisical-universal-auth`
4. **Wait** for operator to use new credentials (2 minutes)
5. **Revoke** old client secret
6. **Notify** on success/failure

### Step 4.2: Create the Workflow

In your n8n instance, create a new workflow with these nodes:

#### Node 1: Schedule Trigger (OpenRouter - Weekly)
- **Type**: Schedule Trigger
- **Cron**: `0 0 * * 0` (Every Sunday at midnight UTC)
- **Description**: Rotates OpenRouter API key every 7 days

#### Node 2: Get Infisical Access Token
- **Type**: HTTP Request
- **Method**: POST
- **URL**: `https://app.infisical.com/api/v1/auth/universal-auth/login`
- **Body (JSON)**:
```json
{
  "clientId": "{{ $env.INFISICAL_CLIENT_ID }}",
  "clientSecret": "{{ $env.INFISICAL_CLIENT_SECRET }}"
}
```

#### Node 3: Get Current OpenRouter Key
- **Type**: HTTP Request
- **Method**: GET
- **URL**: `https://app.infisical.com/api/v3/secrets/raw/OPENROUTER_API_KEY`
- **Headers**:
  - `Authorization`: `Bearer {{ $json.accessToken }}`
- **Query Parameters**:
  - `workspaceSlug`: `your-project-slug`
  - `environment`: `prod`

#### Node 4: Create New OpenRouter Key
- **Type**: HTTP Request
- **Method**: POST
- **URL**: `https://openrouter.ai/api/v1/keys`
- **Headers**:
  - `Authorization`: `Bearer {{ $env.OPENROUTER_PROVISIONING_KEY }}`
- **Body (JSON)**:
```json
{
  "name": "anythingllm-{{ $now.format('YYYY-MM-DD') }}",
  "limit": null
}
```

#### Node 5: Update Infisical Secret
- **Type**: HTTP Request
- **Method**: PATCH
- **URL**: `https://app.infisical.com/api/v3/secrets/raw/OPENROUTER_API_KEY`
- **Headers**:
  - `Authorization`: `Bearer {{ $node["Get Infisical Access Token"].json.accessToken }}`
- **Body (JSON)**:
```json
{
  "workspaceSlug": "your-project-slug",
  "environment": "prod",
  "secretValue": "{{ $json.key }}"
}
```

#### Node 6: Wait for Sync
- **Type**: Wait
- **Duration**: 2 minutes

#### Node 7: Delete Old OpenRouter Key
- **Type**: HTTP Request
- **Method**: DELETE
- **URL**: `https://openrouter.ai/api/v1/keys/{{ $node["Get Current OpenRouter Key"].json.secret.secretValue | hash }}`
- **Headers**:
  - `Authorization`: `Bearer {{ $env.OPENROUTER_PROVISIONING_KEY }}`

#### Node 8: Success Notification
- **Type**: Slack/Email
- **Message**: `✅ OpenRouter API key rotated successfully for AnythingLLM`

#### Node 9: JWT Secret Rotation (Separate Workflow - Quarterly)
- **Type**: Schedule Trigger
- **Cron**: `0 2 1 */3 *` (1st day of quarter at 2 AM UTC)
- **Generate Secret**:
```javascript
// Function node to generate secure JWT secret
const crypto = require('crypto');
return {
  json: {
    jwtSecret: crypto.randomBytes(32).toString('hex')
  }
};
```
- **Update Infisical**: Same PATCH endpoint as OpenRouter rotation
- **Key Name**: `JWT_SECRET`

#### Node 10: Client Secret Rotation (Separate Workflow - Monthly)
- **Type**: Schedule Trigger  
- **Cron**: `0 3 1 * *` (1st of month at 3 AM UTC)
- **Create Client Secret**: POST to `/api/v1/auth/universal-auth/identities/{id}/client-secrets`
- **Update K8s Secret**: Use Kubernetes HTTP Request or kubectl execution
- **Revoke Old Secret**: DELETE old client secret after successful update

### Step 4.3: Environment Variables

Set these in n8n Settings → Environment Variables:

| Variable | Value |
|----------|-------|
| `INFISICAL_CLIENT_ID` | Your Machine Identity Client ID |
| `INFISICAL_CLIENT_SECRET` | Your Machine Identity Client Secret |
| `OPENROUTER_PROVISIONING_KEY` | Your OpenRouter Provisioning API Key |

### Step 4.4: Add Machine Identity Client Secret Rotation

To also rotate the Infisical Machine Identity credentials (recommended every 90 days):

#### Additional Node: Create New Client Secret
- **Type**: HTTP Request
- **Method**: POST
- **URL**: `https://app.infisical.com/api/v1/auth/universal-auth/identities/YOUR_IDENTITY_ID/client-secrets`
- **Headers**:
  - `Authorization`: `Bearer {{ $node["Get Infisical Access Token"].json.accessToken }}`
- **Body (JSON)**:
```json
{
  "description": "Rotated by n8n - {{ $now.format('YYYY-MM-DD') }}",
  "ttl": "7776000"
}
```

#### Additional Node: Update K8s Secret
- **Type**: Execute Command (requires k8s access)
```bash
kubectl create secret generic infisical-universal-auth \
  --namespace anything-llm \
  --from-literal=clientId="{{ $env.INFISICAL_CLIENT_ID }}" \
  --from-literal=clientSecret="{{ $json.clientSecret }}" \
  --dry-run=client -o yaml | kubectl replace -f -
```

---

## Phase 5: Monitoring & Compliance

### Audit Log Access

Infisical Pro provides 90-day audit logs:

1. Go to your project in Infisical
2. Click **"Audit Logs"** in the sidebar
3. Filter by:
   - **Action**: `secret.read`, `secret.update`
   - **Actor**: Machine Identity or user
   - **Time Range**: Last 90 days

### Detecting Compromised Secrets

**Infisical Built-in Detection:**
- ✅ **Audit logs**: 90-day history of all secret access with IP addresses
- ✅ **Version history**: Track who changed what and when
- ✅ **IP allowlisting**: Restrict access to known infrastructure IPs
- ✅ **Failed authentication alerts**: Monitor for unauthorized access attempts

**OpenRouter Usage Monitoring:**
```bash
# Check API key usage patterns
curl -H "Authorization: Bearer YOUR_PROVISIONING_KEY" \
  https://openrouter.ai/api/v1/keys | jq '.data[] | {name, usage, limit}'

# Alert on unexpected usage spikes
# If daily usage > 2x average, investigate for compromise
```

**JWT Secret Compromise Detection:**
- **Symptom**: Multiple "Invalid token" errors in application logs
- **Symptom**: Users logged out unexpectedly across all sessions
- **Action**: Immediate rotation via n8n workflow (trigger manually)
- **Prevention**: Store JWT_SECRET only in Infisical, never in code/logs

**Machine Identity Compromise Detection:**
- **Symptom**: Infisical audit logs show access from unknown IPs
- **Symptom**: Secrets syncing from unexpected namespaces/clusters
- **Action**: Revoke compromised client secret immediately via Infisical UI
- **Action**: Create new Machine Identity with IP allowlist

**Additional Security Tools:**

| Tool | Purpose | Detection Method | Response Time |
|------|---------|------------------|---------------|
| **GitGuardian** | GitHub repo scanning | Regex + ML for secrets | Real-time |
| **Gitleaks** | Pre-commit scanning | Local git hooks | Pre-commit |
| **OpenRouter Dashboard** | API usage monitoring | Manual review | Daily |
| **Infisical Webhooks** | Secret access alerts | Webhook to Slack/Discord | Real-time |
| **K8s Audit Logs** | Secret read tracking | `kubectl get secret` events | Real-time |

**Automated Compromise Response:**
```yaml
# n8n workflow trigger on suspicious activity
1. Infisical Webhook → Slack alert
2. If confirmed compromise:
   - Trigger immediate rotation workflow
   - Revoke compromised credentials
   - Update IP allowlist
   - Generate incident report
```

### Compliance Checklist

| Requirement | How It's Met | Standard |
|-------------|--------------|----------|
| **Audit Trail** | 90-day logs in Infisical Pro with IP tracking | SOC2/ISO42001 |
| **Secret Rotation** | Automated: OpenRouter (7d), JWT (90d), Client Secret (30d) | SOC2/ISO42001 |
| **Access Control** | RBAC in Infisical + K8s RBAC + IP allowlisting | SOC2 |
| **Encryption at Rest** | AES-256 in Infisical + K8s etcd encryption | ISO42001 |
| **Encryption in Transit** | TLS 1.3 everywhere (API + K8s + Ingress) | SOC2/ISO42001 |
| **Least Privilege** | Machine Identity with project-scoped access only | SOC2 |
| **Compromise Detection** | Audit logs + usage monitoring + automated alerts | SOC2 |
| **Incident Response** | Automated rotation + revocation workflows | ISO42001 |
| **Version Control** | Infisical secret versioning with rollback capability | SOC2 |

---

## 🛠️ Troubleshooting

### InfisicalSecret Not Syncing

```bash
# Check operator logs
kubectl logs -n infisical-operator -l control-plane=controller-manager

# Check InfisicalSecret status
kubectl describe infisicalsecret anythingllm-infisical -n anything-llm
```

### Pod Not Restarting After Secret Change

Verify auto-reload annotation exists:
```bash
kubectl get deployment anythingllm -n anything-llm -o yaml | grep -A 2 annotations
# Should show: secrets.infisical.com/auto-reload: "true"
```

### n8n Workflow Failures

1. Check n8n execution logs
2. Verify environment variables are set
3. Test each HTTP node individually
4. Check Infisical audit logs for authentication failures

---

## 📚 Reference

### Infisical API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/auth/universal-auth/login` | POST | Get access token |
| `/api/v3/secrets/raw/{secretName}` | GET | Read secret |
| `/api/v3/secrets/raw/{secretName}` | PATCH | Update secret |
| `/api/v1/auth/universal-auth/identities/{id}/client-secrets` | POST | Create client secret |

### OpenRouter API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/keys` | POST | Create new API key |
| `/api/v1/keys/{keyHash}` | DELETE | Delete API key |
| `/api/v1/keys` | GET | List all API keys |

### Helm Values Reference

```yaml
infisical:
  enabled: true                              # Enable Infisical integration
  hostAPI: "https://app.infisical.com/api"   # Infisical API endpoint
  resyncInterval: 60                         # Sync interval in seconds
  projectSlug: "your-project-slug"           # Infisical project identifier
  envSlug: "prod"                            # Environment to sync from
  secretsPath: "/"                           # Path within environment
  auth:
    secretName: "infisical-universal-auth"   # K8s secret with credentials
```

---

## 🔗 Related Documentation

- [Infisical Documentation](https://infisical.com/docs)
- [Infisical Kubernetes Operator](https://infisical.com/docs/integrations/platforms/kubernetes)
- [OpenRouter API Reference](https://openrouter.ai/docs)
- [n8n HTTP Request Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.httprequest/)

---

---

## 🔒 Security Rotation Schedule Summary

| Secret Type | Rotation Frequency | SOC2/ISO42001 Requirement | Automation Status |
|-------------|-------------------|---------------------------|-------------------|
| **OpenRouter API Key** | 7 days | Recommended: 90 days | ✅ Automated |
| **JWT_SECRET** | 90 days | Required: 90 days | ✅ Automated |
| **Infisical Client Secret** | 30 days | Required: 30-90 days | ✅ Automated |
| **Admin Passwords** | As needed | Recommended: 90 days | Manual |

**Aggressive Posture Rationale:**
- OpenRouter API key rotation (7 days) exceeds compliance requirements for defense-in-depth
- Minimizes blast radius in case of compromise
- Zero-downtime rotation via automated workflows
- Kubernetes operator handles pod restarts automatically

---

**Last Updated**: January 2026  
**Version**: 2.0.0  
**Maintainer**: WeOwn Development Team
