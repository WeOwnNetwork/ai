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

**The Incident (WordPress v3.2.5):**
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
# 1. Extract current values
helm get values anythingllm -n anything-llm > /tmp/current-values.yaml

# 2. Review and modify
cat /tmp/current-values.yaml
# Edit only what you need to change

# 3. Apply with layered approach
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --values /tmp/current-values.yaml
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
    
    # Extract current values
    helm get values anythingllm -n anything-llm > /tmp/current-values.yaml
    
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
        
        case $choice in
            1)
                read -sp "Enter new OpenRouter API Key: " new_key
                echo
                helm upgrade anythingllm ./helm \
                  --namespace anything-llm \
                  --reuse-values \
                  --set anythingllm.openRouterKey="$new_key"
                ;;
            2)
                echo "Generating new JWT secret..."
                new_jwt=$(openssl rand -hex 32)
                helm upgrade anythingllm ./helm \
                  --namespace anything-llm \
                  --reuse-values \
                  --set anythingllm.jwtSecret="$new_jwt"
                echo "✅ New JWT Secret generated and applied"
                ;;
            # ... more options
        esac
    else
        # Open values file in editor
        ${EDITOR:-nano} /tmp/current-values.yaml
        
        # Apply full values file
        helm upgrade anythingllm ./helm \
          --namespace anything-llm \
          --reuse-values \
          --values /tmp/current-values.yaml
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
# Extract current values first
helm get values anythingllm -n anything-llm > /tmp/anythingllm-backup.yaml

# Upgrade chart with reused values
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values

# If something breaks, rollback
helm rollback anythingllm -n anything-llm
```

### Scenario 5: Bulk Configuration Changes

```bash
# Extract current values
helm get values anythingllm -n anything-llm > /tmp/current.yaml

# Edit multiple values
vim /tmp/current.yaml

# Apply all changes at once
helm upgrade anythingllm ./helm \
  --namespace anything-llm \
  --reuse-values \
  --values /tmp/current.yaml
```

---

## Troubleshooting

### Issue: "Error establishing database connection" after upgrade

**Cause:** Used `--reset-values` which regenerated passwords

**Solution:**
```bash
# Get old password from Helm history
helm get values anythingllm -n anything-llm --revision 5 | grep mariadbPassword

# Patch secret with correct password
kubectl patch secret anythingllm-secrets \
  -n anything-llm \
  --type='json' \
  -p='[{"op":"replace","path":"/data/MARIADB_PASSWORD","value":"'$(echo -n "OLD_PASSWORD" | base64)'"}]'

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
cat > "$AUTH_FILE" << 'EOF'
password: MySecret123
apiKey: sk-xxx
EOF

helm upgrade app ./chart --reuse-values --values "$AUTH_FILE"
rm -f "$AUTH_FILE"
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

# Upgrade with values file
helm get values APP -n NS > /tmp/values.yaml
# Edit /tmp/values.yaml
helm upgrade APP ./helm --namespace NS --reuse-values --values /tmp/values.yaml

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

**Remember:** Always use `--reuse-values` for stateful applications. Never use `--reset-values` in production unless you explicitly want to wipe configuration.
