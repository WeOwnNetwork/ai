# Helm Value Management & Safe Upgrade Strategies

**Version**: 2.5.0  
**Last Updated**: January 26, 2026  
**Applies To**: WordPress, Matomo, AnythingLLM, n8n, Vaultwarden, Nextcloud

---

## 🚨 Critical Warning

**NEVER use `--reset-values` with stateful applications!** This regenerates ALL values including passwords, breaking database connections and losing all configuration.

---

## Understanding Helm Value Precedence

### `--reuse-values` (✅ Recommended for Stateful Apps)

```bash
helm upgrade myapp ./chart --reuse-values
```

**Behavior:**
- Keeps ALL existing values from previous deployment
- Only adds NEW values introduced in chart updates
- Preserves passwords, domains, secrets, and all configuration

**Use Cases:**
- ✅ WordPress, Matomo, AnythingLLM (any app with databases)
- ✅ When you want to change 1-2 specific values
- ✅ Production upgrades where safety is critical

**Advantages:**
- Zero risk of password regeneration
- Database connections remain intact
- Configuration persists across upgrades

**Disadvantages:**
- May miss important chart default changes
- Requires explicit `--set` flags for new values

**Example:**
```bash
# Safe upgrade with single value change
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.openRouterKey="new-key-value"

# Safe upgrade with multiple changes
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.openRouterKey="new-key" \
  --set anythingllm.jwtSecret="new-jwt" \
  --set ingress.domain="newdomain.com"
```

---

### `--reset-values` (❌ Dangerous for Stateful Apps)

```bash
helm upgrade myapp ./chart --reset-values
```

**Behavior:**
- ❌ **DISCARDS ALL existing values**
- Regenerates everything from chart defaults
- Creates NEW random passwords for placeholders

**Use Cases:**
- Only for complete redeployment
- Only for stateless applications with no persistent data
- When you explicitly want to wipe configuration

**Dangers:**
- ⚠️ **Database connection failures** - MariaDB has old password, app gets new password
- ⚠️ **Lost configuration** - domains, emails, API keys all regenerated
- ⚠️ **Downtime** - requires manual secret patching to recover

**The Incident (WordPress application version 3.2.5):**
```
1. Deployed WordPress → Password: WUOgATZwjcTICvkoBhoO7cd3W
2. Upgraded with --reset-values → NEW password generated
3. MariaDB PVC still has OLD password (persistent data)
4. WordPress tries to connect with NEW password → Access denied
5. Site shows: "Error establishing a database connection"
```

**Never Use With:**
- WordPress, Matomo, AnythingLLM, Nextcloud (databases)
- n8n, Vaultwarden (persistent storage)
- Any app with StatefulSets or PVCs

---

### `--values` (Merge Strategy)

```bash
helm upgrade myapp ./chart --values custom-values.yaml
```

**Behavior:**
- Merges your values file with chart defaults
- Chart defaults take precedence for unspecified values
- Predictable, version-controlled configuration

**Use Cases:**
- When you maintain a complete values file
- GitOps workflows with values in version control
- Multi-environment deployments (staging, production)

**Advantages:**
- Version-controlled configuration
- Repeatable deployments
- Easy to review changes (git diff)

**Disadvantages:**
- Must keep values file in sync with chart updates
- Requires maintaining separate values file per deployment

**Example:**
```bash
# Extract current values
helm get values anythingllm -n anything-llm > anythingllm-values.yaml

# Modify the file
vim anythingllm-values.yaml

# Apply changes
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --values anythingllm-values.yaml
```

---

### Best Practice: Extract → Modify → Apply

**Recommended workflow for safe upgrades:**

```bash
# 0. Create a secure temporary file and ensure it is cleaned up
if ! VALUES_FILE="$(mktemp /tmp/anythingllm-values.XXXXXX.yaml)"; then
  echo "Error: Failed to create temporary values file" >&2
  exit 1
fi
trap 'rm -f "$VALUES_FILE"' EXIT

# 1. Extract current values
helm get values anythingllm -n anything-llm > "$VALUES_FILE"

# 2. Review and modify
cat "$VALUES_FILE"
# Edit only what you need to change, e.g.:
#   "${EDITOR:-nano}" "$VALUES_FILE"

# 3. Apply with layered approach
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --values "$VALUES_FILE"
```

**Why this works:**
- `--reuse-values` preserves all existing values
- `--values` overlays your specific changes
- Zero risk of losing critical configuration

---

## Live Deployment Value Updates

### Method 1: Helm Upgrade with `--set` (✅ Recommended)

```bash
# Single value change
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.openRouterKey="new-key-value"

# Multiple values
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.openRouterKey="sk-or-v1-xxx" \
  --set anythingllm.jwtSecret="$(openssl rand -hex 32)" \
  --set ingress.domain="newdomain.com"
```

**Advantages:**
- ✅ **Persistent** - Changes saved in Helm release
- ✅ **Survives pod restarts** and cluster maintenance
- ✅ **Audit trail** in Helm history
- ✅ **Rollback capable** with `helm rollback`

**Disadvantages:**
- Requires helm command access
- Values visible in shell history (use temp files for secrets)

---

### Method 2: kubectl patch Secret (⚠️ Temporary)

```bash
# Base64 encode your new value
NEW_VALUE=$(echo -n "new-api-key" | base64)

# Patch the secret
kubectl patch secret anythingllm-secrets \
  -n anything-llm \
  --type='json' \
  -p='[{"op":"replace","path":"/data/OPENROUTER_API_KEY","value":"'$NEW_VALUE'"}]'

# Restart pods to pick up change
kubectl rollout restart deployment anythingllm -n anything-llm
```

**Advantages:**
- ✅ **Fast** - Immediate change without helm upgrade
- ✅ **No helm required** - Works with kubectl only

**Disadvantages:**
- ❌ **NOT persistent** - Next helm upgrade overwrites
- ❌ **Manual pod restart** required
- ❌ **No audit trail** in Helm history
- ❌ **Not recommended for production**

---

### Method 3: AnythingLLM UI (❌ Not Persistent)

**Location:** AnythingLLM UI → Settings → LLM Preferences → API Keys

**Problems:**
- ❌ Changes stored in SQLite database, NOT Kubernetes secrets
- ❌ **Lost on pod restart** unless using persistent volume
- ❌ **Not synchronized** with Helm values
- ❌ **Not recommended** for production

**When to use:**
- Testing API keys before committing to Helm
- Temporary configuration changes
- Non-production environments

---

### Method 4: GUI Tools (Lens, Portainer, k9s)

#### Lens Desktop (Best GUI Option)

```bash
# Install from: https://k8slens.dev

# Workflow:
1. Connect to cluster
2. Navigate: Workloads → Secrets → anythingllm-secrets
3. Click "Edit" → Modify values
4. Navigate: Workloads → Deployments → anythingllm
5. Click "Restart" to apply changes
```

**Advantages:**
- ✅ **User-friendly GUI** for Kubernetes management
- ✅ **Real-time validation** of YAML/JSON
- ✅ **Visual diff** of changes

**Disadvantages:**
- ❌ **Still not persistent** - Helm will overwrite on next upgrade
- ❌ Desktop application required

#### Portainer (Web UI)

**Location:** Already deployed in monitoring stack

```bash
# Workflow:
1. Navigate to: https://portainer.{CLUSTER_DOMAIN}
2. Go to: Kubernetes → Secrets → anythingllm-secrets
3. Click "Edit" → Modify values
4. Go to: Kubernetes → Deployments → anythingllm
5. Click "Redeploy" to apply changes
```

**Same persistence limitations as Lens**

---

### Method 5: Deploy Script Integration (✅ Best for Production)

**New deploy.sh function:**

```bash
# Usage: ./deploy.sh
# Select existing deployment → Option 7: Update Configuration Values

modify_live_deployment() {
    echo "=========================================="
    echo "  Secure Configuration Update"
    echo "=========================================="
    
    # Create secure temporary file
    VALUES_FILE="$(mktemp)"
    if [[ -z "$VALUES_FILE" || ! -e "$VALUES_FILE" ]]; then
        echo "Error: Failed to create temporary values file." >&2
        exit 1
    fi
    
    # Extract current values
    helm get values anythingllm -n anything-llm > "$VALUES_FILE"
    
    echo "Current configuration extracted"
    echo ""
    echo "Update Method:"
    echo "1) Quick Update (--reuse-values + --set specific values)"
    echo "2) Full Values File Update (--values with complete config)"
    echo ""
    
    read -p "Select method [1]: " method
    method=${method:-1}
    
    if [[ "$method" == "1" ]]; then
        echo ""
        echo "What would you like to modify?"
        echo "1) OpenRouter API Key"
        echo "2) JWT Secret (generates new secure token)"
        echo "3) Admin Email"
        echo "4) Domain"
        echo "5) Multiple values (interactive)"
        
        read -p "Select option: " choice
        
        # Set up consolidated trap for all temporary files
        SECRET_VALUES=$(mktemp)
        trap 'rm -f "$SECRET_VALUES"' EXIT

        case $choice in
            1)
                read -sp "Enter new OpenRouter API Key: " new_key
                echo
                # Use secure temp file to avoid exposing secrets in process arguments
                cat > "$SECRET_VALUES" <<EOF
anythingllm:
  openRouterKey: "$new_key"
EOF
                helm upgrade anythingllm ./helm \
                  --namespace anything-llm \
                  --reuse-values \
                  --values "$SECRET_VALUES"
                ;;
            2)
                echo "Generating new JWT secret..."
                new_jwt=$(openssl rand -hex 32)
                # Use secure temp file to avoid exposing secrets in process arguments
                cat > "$SECRET_VALUES" <<EOF
anythingllm:
  jwtSecret: "$new_jwt"
EOF
                helm upgrade anythingllm ./helm \
                  --namespace anything-llm \
                  --reuse-values \
                  --values "$SECRET_VALUES"
                echo "✅ New JWT Secret generated and applied"
                ;;
            # ... more options
        esac
    else
        # Open values file in editor
        ${EDITOR:-nano} "$VALUES_FILE"

        # Apply full values file
        helm upgrade anythingllm ./helm \
          --namespace anything-llm \
          --reuse-values \
          --values "$VALUES_FILE"
        
        # Cleanup handled by function exit or caller trap
    fi
    
    echo "✅ Configuration updated. Pods restarting..."
}
```

---

## Comparison Matrix

| Method | Persistent | GUI | Fast | Prod-Safe | Audit Trail |
|--------|-----------|-----|------|-----------|-------------|
| **helm upgrade --reuse-values --set** | ✅ | ❌ | ⚠️ | ✅ | ✅ |
| **helm upgrade --values** | ✅ | ❌ | ⚠️ | ✅ | ✅ |
| **kubectl patch secret** | ❌ | ❌ | ✅ | ❌ | ❌ |
| **AnythingLLM UI** | ❌ | ✅ | ✅ | ❌ | ❌ |
| **Lens/Portainer GUI** | ❌ | ✅ | ✅ | ❌ | ❌ |
| **Deploy script function** | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Common Scenarios

### Scenario 1: Update API Key Only

```bash
# Recommended: Helm upgrade with --reuse-values
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.openRouterKey="sk-or-v1-new-key"
```

### Scenario 2: Rotate JWT Secret

```bash
# Generate new secret
NEW_JWT=$(openssl rand -hex 32)

# Apply with Helm
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set anythingllm.jwtSecret="$NEW_JWT"

# Note: All users will be logged out (expected behavior)
```

### Scenario 3: Change Domain

```bash
# Update domain and regenerate TLS certificate
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --set ingress.domain="newdomain.com"

# Update DNS A record to point to cluster external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Scenario 4: Upgrade Chart Version

```bash
# Extract current values first into a secure temporary file
BACKUP_FILE="$(mktemp "${TMPDIR:-/tmp}/anythingllm-backup-XXXXXX.yaml")"
helm get values anythingllm -n anything-llm > "$BACKUP_FILE"
echo "Backup saved to: $BACKUP_FILE"

# Upgrade chart with reused values
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values

# If something breaks, rollback
helm rollback anythingllm -n anything-llm
```

### Scenario 5: Bulk Configuration Changes

```bash
# Create a secure temporary file for current values
TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "$TMP_VALUES_FILE"' EXIT

# Extract current values
helm get values anythingllm -n anything-llm > "${TMP_VALUES_FILE}"

# Edit multiple values
"${EDITOR:-vim}" "${TMP_VALUES_FILE}"

# Apply all changes at once
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --values "${TMP_VALUES_FILE}"

# Cleanup handled by trap EXIT
```

---

## Troubleshooting

### Issue: "Error establishing database connection" after upgrade

**Cause:** Used `--reset-values` which regenerated passwords

**Solution:**
```bash
# Get old password from Helm history
helm get values anythingllm -n anything-llm --revision 5 | grep mariadbPassword

# Encode password separately to avoid exposure
OLD_PASSWORD_BASE64=$(echo -n "OLD_PASSWORD" | base64)

# Patch secret with correct password (use the base64-encoded value)
kubectl patch secret anythingllm-secrets \
  -n anything-llm \
  --type='json' \
  -p='[{"op":"replace","path":"/data/MARIADB_PASSWORD","value":"'"$OLD_PASSWORD_BASE64"'"}]'

# Restart pods
kubectl rollout restart deployment anythingllm -n anything-llm
```

### Issue: Changes not persisting after pod restart

**Cause:** Changes made via kubectl or application UI, not Helm

**Solution:** Always use `helm upgrade` with `--reuse-values` or `--values`

### Issue: Can't remember what values were used

```bash
# View current values
helm get values anythingllm -n anything-llm

# View all values (including defaults)
helm get values anythingllm -n anything-llm --all

# View values from specific revision
helm get values anythingllm -n anything-llm --revision 3
```

---

## Security Best Practices

### Never Expose Secrets in Shell History

```bash
# ❌ BAD: Secret visible in shell history
helm upgrade app ./chart --set password="MySecret123"

# ✅ GOOD: Use temporary file
AUTH_FILE="$(mktemp)"
trap 'rm -f "$AUTH_FILE"' EXIT

# Single quotes prevent variable expansion - this is literal text
cat > "$AUTH_FILE" << 'EOF'
password: MySecret123
apiKey: sk-xxx
EOF

helm upgrade app ./chart --reuse-values --values "$AUTH_FILE"

# Cleanup handled by trap EXIT
```

### Use Secure Secret Generation

```bash
# Generate cryptographically secure secrets
openssl rand -hex 32  # JWT secrets
openssl rand -base64 32  # API tokens
pwgen -s 32 1  # Passwords (if pwgen installed)
```

### Audit Helm Changes

```bash
# View Helm history
helm history anythingllm -n anything-llm

# View specific revision details
helm get values anythingllm -n anything-llm --revision 10

# Compare two revisions
diff <(helm get values app -n ns --revision 1) \
     <(helm get values app -n ns --revision 2)
```

---

## Related Documentation

- [`VERSIONING_WEOWNVER.md`](./VERSIONING_WEOWNVER.md) - WeOwn versioning system
- [`/anythingllm/README.md`](../anythingllm/README.md) - AnythingLLM deployment guide
- [`/anythingllm/docs/INFISICAL_INTEGRATION.md`](../anythingllm/docs/INFISICAL_INTEGRATION.md) - Automated secret rotation

---

## Quick Reference

### Safe Upgrade Commands

```bash
# Standard upgrade (safe for all apps)
helm upgrade APP ./helm --namespace NS --reuse-values

# Upgrade with single value change
helm upgrade APP ./helm --namespace NS --reuse-values --set key=value

# Upgrade with multiple changes
helm upgrade APP ./helm --namespace NS --reuse-values \
  --set key1=value1 \
  --set key2=value2

# Upgrade with values file (using a secure temporary file)
VALUES_FILE="$(mktemp)"
helm get values APP -n NS > "$VALUES_FILE"
# Edit "$VALUES_FILE"
helm upgrade APP ./helm --namespace NS --reuse-values --values "$VALUES_FILE"
rm -f "$VALUES_FILE"

# Rollback if needed
helm rollback APP -n NS
```

### Emergency Recovery

```bash
# If deployment is broken after upgrade:
1. Check what changed: helm diff revision APP 1 2 -n NS
2. View old values: helm get values APP -n NS --revision 1
3. Rollback: helm rollback APP -n NS
4. Verify: kubectl get pods -n NS
```

---

## Enterprise Secrets Management

### 🔐 **Best Practice: External Secret Managers**

**Recommended Approach**: Use **Infisical Kubernetes Operator** or **HashiCorp Vault** instead of raw Kubernetes secrets for production deployments.

#### **Why External Secret Managers?**

**Security Benefits:**
- ✅ Centralized secret rotation without pod restarts
- ✅ Audit trails for secret access
- ✅ Automatic secret sync across clusters
- ✅ Reduced manual intervention
- ✅ Enterprise compliance (SOC2/ISO42001)
- ✅ Secret versioning and rollback

**vs. Native Kubernetes Secrets:**
- ❌ Manual rotation requires pod restarts
- ❌ Limited audit capabilities
- ❌ No cross-cluster sync
- ❌ Secrets visible in etcd (even if encrypted)
- ❌ Process listing exposure with `--set` flags

#### **Infisical Kubernetes Operator Setup**

```bash
# 1. Install Infisical Operator
helm repo add infisical https://infisical.github.io/helm-charts
helm install infisical-secrets-operator infisical/secrets-operator -n infisical --create-namespace

# 2. Create InfisicalSecret resource
cat <<EOF | kubectl apply -f -
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: anythingllm-secrets
  namespace: anything-llm
spec:
  hostAPI: https://app.infisical.com/api
  resyncInterval: 60
  authentication:
    serviceToken:
      serviceTokenSecretReference:
        secretName: infisical-service-token
        secretNamespace: infisical
  managedSecretReference:
    secretName: anythingllm-secrets
    secretType: Opaque
EOF

# 3. Secrets auto-sync from Infisical → Kubernetes every 60 seconds
# 4. Update secrets in Infisical dashboard, no pod restarts needed
```

#### **Secure Kubernetes Secrets (Alternative)**

If external secret managers aren't available, follow these practices:

**1. Never Use `--set` for Secrets:**
```bash
# ❌ WRONG - Exposed in process listings
helm upgrade app ./helm --set app.apiKey="sk-secret-key"

# ✅ CORRECT - Use secure temp file
SECRET_VALUES=$(mktemp)
trap 'rm -f "$SECRET_VALUES"' EXIT
cat > "$SECRET_VALUES" <<EOF
app:
  apiKey: "sk-secret-key"
EOF
helm upgrade app ./helm --values "$SECRET_VALUES"
rm -f "$SECRET_VALUES"
```

**2. Enable etcd Encryption at Rest:**
```yaml
# /etc/kubernetes/manifests/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

**3. Restrict Secret Access with RBAC:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: anything-llm
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["anythingllm-secrets"]
  verbs: ["get"]
```

**4. Rotate Secrets Every 90 Days:**
```bash
# Use secure temp file method from above
# Track rotation dates in compliance documentation
```

**5. Audit Secret Access:**
```bash
# Enable Kubernetes audit logging
kubectl logs -n kube-system kube-apiserver-* | grep "secrets/anythingllm-secrets"
```

#### **Migration Path: Kubernetes Secrets → Infisical**

```bash
# 1. Export existing secrets to secure temporary file
# WARNING: This backup contains sensitive data in plain text
BACKUP_FILE="$(mktemp "${TMPDIR:-/tmp}/k8s-secrets-backup-XXXXXX.json")"
kubectl get secret anythingllm-secrets -n anything-llm -o json > "$BACKUP_FILE"
echo "⚠️  SECURITY WARNING: Backup file $BACKUP_FILE contains secrets in plain text"
echo "   Delete immediately after migration or encrypt with: gpg -c $BACKUP_FILE"

# 2. Import to Infisical via CLI or dashboard
infisical secrets set OPENROUTER_API_KEY="$(kubectl get secret anythingllm-secrets -n anything-llm -o jsonpath='{.data.OPENROUTER_API_KEY}' | base64 -d)"

# 3. Deploy InfisicalSecret resource (shown above)

# 4. Verify sync
kubectl get secret anythingllm-secrets -n anything-llm -o yaml

# 5. Securely delete manual backup
rm -f "$BACKUP_FILE"
echo "✅ Backup file deleted"
```

**Status**: Infisical integration planned for WeOwn cohort deployments. Current deployments use encrypted Kubernetes secrets with RBAC restrictions.

---

**Remember:** Always use `--reuse-values` for stateful applications. Never use `--reset-values` in production unless you explicitly want to wipe configuration.
