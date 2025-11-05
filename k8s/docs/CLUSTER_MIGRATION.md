# Migrate Cluster to Larger Node Pool

## Description

Upgrade DigitalOcean Kubernetes cluster from small nodes to larger nodes for better performance and capacity.

**Current Configuration:** s-1vcpu-2gb-amd, 2 nodes, $28/mo  
**Target Configuration:** s-2vcpu-4gb-amd, 2 nodes, $56/mo

**Resource Comparison:**
- **Current**: 2GB RAM per node (4GB total cluster) - fits 1-3 lightweight apps
- **Target**: 4GB RAM per node (8GB total cluster) - fits all 6+ apps with room to grow

**Full Stack Capacity:**
- AnythingLLM (AI embeddings + vector storage)
- Vaultwarden (password management)
- Matomo (analytics + MariaDB)
- n8n (workflow automation)
- WordPress (CMS + MariaDB)
- Nextcloud (file sync + PostgreSQL + Redis)
- Future: Email server, additional services

**When to Use This Migration:**
- ✅ You need 4+ apps from the full stack
- ✅ You want cost-efficient resource distribution ($56/mo vs $42-56/mo for auto-scale)
- ✅ You prefer 2 larger nodes over 3-4 smaller nodes
- ✅ You want optimal pod scheduling and resource allocation

### **Key Features:**
- ✅ **Auto-Discovery**: Automatically detects cluster name and all app namespaces
- ✅ **Modular Commands**: Uses variables instead of hardcoded values
- ✅ **Flexible Configuration**: Works with any namespace/cluster naming scheme
- ✅ **Conditional Execution**: Only migrates apps that are actually deployed
- ✅ **Configuration File**: Saves settings to `migration-config.sh` for reuse

### **How Modular Configuration Works:**

**Traditional Approach (Hardcoded):**
```bash
kubectl patch deployment matomo -n matomo ...
```
Assumes namespace is always "matomo"

**Modular Approach (This Guide):**
```bash
MATOMO_NS=$(kubectl get deployment -A -l app=matomo -o jsonpath='{.items[0].metadata.namespace}')
echo "export MATOMO_NS=\"$MATOMO_NS\"" >> migration-config.sh
kubectl patch deployment matomo -n $MATOMO_NS ...
```
Works with ANY namespace (discovers actual namespace first)

**Benefits:**
- Works with custom namespaces (e.g., `matomo-prod`, `analytics`, `wordpress-site1`)
- Adapts to your cluster's naming conventions automatically
- No manual find-and-replace needed
- Prevents errors from wrong namespace assumptions

---

## Quick Option: Auto-Scale to 3-4 Nodes (No Migration)

**Alternative Approach:** Keep the s-1vcpu-2gb-amd node type, let Kubernetes auto-scaler add nodes as needed.

**Configuration:**
- **Node Type**: s-1vcpu-2gb-amd (same as current)
- **Node Count**: 3-4 nodes (auto-scales based on demand)
- **Cost**: $42-56/mo (3 nodes = $42, 4 nodes = $56)
- **Total Resources**: 6-8GB RAM cluster (vs 8GB RAM with migration)

**When to Use Auto-Scale:**
- ✅ You only need 3-4 apps from the stack (not the full 6+)
- ✅ You want zero migration effort (just deploy and let it scale)
- ✅ You're okay with more nodes but less RAM per node
- ✅ Your workload is variable (scales down to 2 nodes when idle)

**Comparison:**

| Aspect | Auto-Scale (3-4 nodes) | Migration (2 nodes) |
|--------|------------------------|---------------------|
| **Cost** | $42-56/mo | $56/mo |
| **Effort** | Zero (automatic) | 2-3 hours |
| **Nodes** | 3-4 smaller nodes | 2 larger nodes |
| **RAM/Node** | 2GB | 4GB |
| **Best For** | 3-4 apps, variable load | Full stack, stable load |
| **Resource Efficiency** | Less optimal | More optimal |
| **Pod Scheduling** | More fragmentation | Better consolidation |

**Action:** Simply deploy Nextcloud with `./deploy.sh` and let auto-scaler add nodes automatically.

---

## Migration Steps (Full Upgrade)

### 0. Discover Cluster Configuration (5 min)

**CLI Commands:**

**0.1 Get Cluster Name and Identity:**
- [ ] Get cluster name:
  ```bash
  CLUSTER_NAME=$(kubectl config current-context | cut -d'-' -f1)
  echo "Cluster: $CLUSTER_NAME"
  ```

**0.2 Determine Current Node Pool:**
- [ ] Get current node pool name from node labels:
  ```bash
  OLD_POOL=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.doks\.digitalocean\.com/node-pool}')
  echo "Current node pool: $OLD_POOL"
  ```

**0.3 Set New Node Pool Name:**
- [ ] Generate abbreviated new node pool name (shortened to avoid DigitalOcean naming limits):
  ```bash
  CLUSTER_SHORT=$(echo "$CLUSTER_NAME" | cut -c1-8)
  NEW_POOL="${CLUSTER_SHORT}-2vcpu4gb"
  echo "New node pool will be: $NEW_POOL"
  ```
- **Note**: Cluster name is abbreviated to first 8 characters to keep pool name under DigitalOcean's limits

**0.4 Discover Application Namespaces:**
- [ ] Find all app namespaces dynamically:
  ```bash
  echo "=== Discovering Application Namespaces ==="
  
  ANYTHINGLLM_NS=$(kubectl get deployment -A -l app=anythingllm -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$ANYTHINGLLM_NS" ]] && echo "✅ AnythingLLM: $ANYTHINGLLM_NS" || echo "⊘ AnythingLLM: not deployed"
  
  VAULTWARDEN_NS=$(kubectl get deployment -A -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$VAULTWARDEN_NS" ]] && echo "✅ Vaultwarden: $VAULTWARDEN_NS" || echo "⊘ Vaultwarden: not deployed"
  
  MATOMO_NS=$(kubectl get deployment -A -l app=matomo -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$MATOMO_NS" ]] && echo "✅ Matomo: $MATOMO_NS" || echo "⊘ Matomo: not deployed"
  
  N8N_NS=$(kubectl get deployment -A -l app=n8n -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$N8N_NS" ]] && echo "✅ n8n: $N8N_NS" || echo "⊘ n8n: not deployed"
  
  WORDPRESS_NS=$(kubectl get deployment -A -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$WORDPRESS_NS" ]] && echo "✅ WordPress: $WORDPRESS_NS" || echo "⊘ WordPress: not deployed"
  
  NEXTCLOUD_NS=$(kubectl get deployment -A -l app.kubernetes.io/name=nextcloud -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
  [[ -n "$NEXTCLOUD_NS" ]] && echo "✅ Nextcloud: $NEXTCLOUD_NS" || echo "⊘ Nextcloud: not deployed"
  ```
- [ ] Save configuration to file:
  ```bash
  cat > migration-config.sh <<EOF
# Migration Configuration - Generated $(date)
export CLUSTER_NAME="$CLUSTER_NAME"
export OLD_POOL="$OLD_POOL"
export NEW_POOL="$NEW_POOL"
export ANYTHINGLLM_NS="$ANYTHINGLLM_NS"
export VAULTWARDEN_NS="$VAULTWARDEN_NS"
export MATOMO_NS="$MATOMO_NS"
export N8N_NS="$N8N_NS"
export WORDPRESS_NS="$WORDPRESS_NS"
export NEXTCLOUD_NS="$NEXTCLOUD_NS"
EOF
  chmod +x migration-config.sh
  echo "✅ Configuration saved to migration-config.sh"
  ```
- [ ] **IMPORTANT**: Review and edit `migration-config.sh` if any values are incorrect

### 1. Backup All Data and Configuration (30 min)

**CLI Commands:**
- [ ] Create backup directory and load configuration:
  ```bash
  mkdir -p ~/cluster-backup-$(date +%Y%m%d) && cd ~/cluster-backup-$(date +%Y%m%d)
  source ../migration-config.sh
  ```
- [ ] Export all Helm values (using discovered namespaces):
  ```bash
  [[ -n "$ANYTHINGLLM_NS" ]] && helm get values anythingllm -n $ANYTHINGLLM_NS > anythingllm-values.yaml 2>/dev/null
  [[ -n "$VAULTWARDEN_NS" ]] && helm get values vaultwarden -n $VAULTWARDEN_NS > vaultwarden-values.yaml 2>/dev/null
  [[ -n "$MATOMO_NS" ]] && helm get values matomo -n $MATOMO_NS > matomo-values.yaml 2>/dev/null
  [[ -n "$N8N_NS" ]] && helm get values n8n -n $N8N_NS > n8n-values.yaml 2>/dev/null
  [[ -n "$WORDPRESS_NS" ]] && helm get values wordpress -n $WORDPRESS_NS > wordpress-values.yaml 2>/dev/null
  [[ -n "$NEXTCLOUD_NS" ]] && helm get values nextcloud -n $NEXTCLOUD_NS > nextcloud-values.yaml 2>/dev/null
  ls -lh *.yaml
  ```
- [ ] Trigger manual backups (only for deployed apps):
  ```bash
  [[ -n "$VAULTWARDEN_NS" ]] && kubectl create job vaultwarden-pre-migration -n $VAULTWARDEN_NS --from=cronjob/vaultwarden-backup 2>/dev/null || echo "⊘ Vaultwarden backup skipped"
  [[ -n "$MATOMO_NS" ]] && kubectl create job matomo-pre-migration -n $MATOMO_NS --from=cronjob/matomo-backup 2>/dev/null || echo "⊘ Matomo backup skipped"
  [[ -n "$WORDPRESS_NS" ]] && kubectl create job wordpress-pre-migration -n $WORDPRESS_NS --from=cronjob/wordpress-backup 2>/dev/null || echo "⊘ WordPress backup skipped"
  [[ -n "$NEXTCLOUD_NS" ]] && kubectl create job nextcloud-pre-migration -n $NEXTCLOUD_NS --from=cronjob/nextcloud-backup 2>/dev/null || echo "⊘ Nextcloud backup skipped"
  ```
- [ ] Check which backup jobs were created:
  ```bash
  kubectl get jobs -A | grep pre-migration
  ```
- [ ] Wait for each created backup job to complete:
  ```bash
  [[ -n "$VAULTWARDEN_NS" ]] && kubectl wait --for=condition=complete --timeout=600s job/vaultwarden-pre-migration -n $VAULTWARDEN_NS 2>/dev/null || true
  [[ -n "$MATOMO_NS" ]] && kubectl wait --for=condition=complete --timeout=600s job/matomo-pre-migration -n $MATOMO_NS 2>/dev/null || true
  [[ -n "$WORDPRESS_NS" ]] && kubectl wait --for=condition=complete --timeout=600s job/wordpress-pre-migration -n $WORDPRESS_NS 2>/dev/null || true
  [[ -n "$NEXTCLOUD_NS" ]] && kubectl wait --for=condition=complete --timeout=600s job/nextcloud-pre-migration -n $NEXTCLOUD_NS 2>/dev/null || true
  ```
- [ ] Export secrets (encrypted): `kubectl get secrets -A -o yaml > all-secrets-backup.yaml && chmod 600 all-secrets-backup.yaml`
- [ ] Document current state:
  ```bash
  kubectl get nodes > pre-migration-nodes.txt
  kubectl get pods -A -o wide > pre-migration-pods.txt
  kubectl get pvc -A > pre-migration-pvcs.txt
  ```

**DigitalOcean Dashboard:**
- [ ] Navigate to: Volumes → Create Snapshots (for critical volumes with data)
- [ ] Create snapshots named: `pre-migration-YYYY-MM-DD` for each data volume

### 2. Create New Node Pool in DigitalOcean (10 min)

**CLI Commands (Load Config First):**
- [ ] Load migration config:
  ```bash
  cd ~/cluster-backup-$(date +%Y%m%d)
  source ../migration-config.sh
  echo "Creating node pool: $NEW_POOL"
  ```

**DigitalOcean Dashboard:**
- [ ] Navigate to: Kubernetes → [Your Cluster Name] → Node Pools tab
- [ ] Click "Add Node Pool" button
- [ ] Configure:
  - **Plan**: Shared CPU → Basic
  - **Size**: s-2vcpu-4gb-amd ($28/mo per node)
  - **Node Count**: 2
  - **Auto-scaling**: OFF (uncheck)
  - **Name**: Use value from `$NEW_POOL` (e.g., `cluster-name-2vcpu-4gb`)
  - **Tags**: `migration`, `production`
- [ ] Click "Add Node Pool"

**CLI Commands:**
- [ ] Wait for nodes to be Ready: `watch kubectl get nodes` (wait for 2 new nodes, STATUS=Ready, Ctrl+C to exit)
- [ ] Get actual node pool name from DigitalOcean and update config if different:
  ```bash
  ACTUAL_NEW_POOL=$(kubectl get nodes -l doks.digitalocean.com/node-pool-id --no-headers -o custom-columns=POOL:.metadata.labels.doks\\.digitalocean\\.com/node-pool | tail -1)
  echo "Actual new pool name: $ACTUAL_NEW_POOL"
  sed -i '' "s/NEW_POOL=.*/NEW_POOL=\"$ACTUAL_NEW_POOL\"/" ../migration-config.sh
  export NEW_POOL="$ACTUAL_NEW_POOL"
  ```
- [ ] Label new nodes for easy identification:
  ```bash
  kubectl label nodes -l doks.digitalocean.com/node-pool=$NEW_POOL pool=new
  ```
- [ ] Verify labels: `kubectl get nodes --show-labels | grep pool=new`
- [ ] Verify old nodes don't have new label: `kubectl get nodes -l pool!=new`

### 3. Cordon Old Nodes to Prevent New Pod Scheduling (2 min)

**CLI Commands:**
- [ ] Get old node names: `kubectl get nodes -l pool!=new -o name`
- [ ] Cordon all old nodes:
  ```bash
  kubectl cordon $(kubectl get nodes -l pool!=new -o name | tr '\n' ' ')
  ```
- [ ] Verify cordon status: `kubectl get nodes` (old nodes should show SchedulingDisabled)

### 4. Migrate All Applications to New Nodes (60-90 min)

**CLI Commands:**

**4.0 Load Configuration & Verify:**
- [ ] Load migration config (if not already loaded):
  ```bash
  source ~/cluster-backup-$(date +%Y%m%d)/../migration-config.sh
  echo "=== Migration Configuration ==="
  echo "Cluster: $CLUSTER_NAME"
  echo "New Pool: $NEW_POOL"
  echo "AnythingLLM NS: ${ANYTHINGLLM_NS:-not deployed}"
  echo "Vaultwarden NS: ${VAULTWARDEN_NS:-not deployed}"
  echo "Matomo NS: ${MATOMO_NS:-not deployed}"
  echo "n8n NS: ${N8N_NS:-not deployed}"
  echo "WordPress NS: ${WORDPRESS_NS:-not deployed}"
  echo "Nextcloud NS: ${NEXTCLOUD_NS:-not deployed}"
  ```

**4.1 AnythingLLM (if deployed):**
- [ ] Check if deployed: `[[ -n "$ANYTHINGLLM_NS" ]] && echo "✅ Migrate AnythingLLM" || echo "⊘ Skip AnythingLLM"`
- [ ] **If deployed**, patch deployment:
  ```bash
  if [[ -n "$ANYTHINGLLM_NS" ]]; then
    kubectl patch deployment anythingllm -n $ANYTHINGLLM_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $ANYTHINGLLM_NS -l app=anythingllm
    kubectl wait --for=condition=ready pod -l app=anythingllm -n $ANYTHINGLLM_NS --timeout=300s
    kubectl get pods -n $ANYTHINGLLM_NS -o wide
    echo "✅ Test: Open AnythingLLM URL and verify documents accessible"
  fi
  ```

**4.2 Vaultwarden (if deployed):**
- [ ] Check if deployed: `[[ -n "$VAULTWARDEN_NS" ]] && echo "✅ Migrate Vaultwarden" || echo "⊘ Skip Vaultwarden"`
- [ ] **If deployed**, patch deployment:
  ```bash
  if [[ -n "$VAULTWARDEN_NS" ]]; then
    kubectl patch deployment vaultwarden -n $VAULTWARDEN_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $VAULTWARDEN_NS -l app=vaultwarden
    kubectl wait --for=condition=ready pod -l app=vaultwarden -n $VAULTWARDEN_NS --timeout=300s
    kubectl get pods -n $VAULTWARDEN_NS -o wide
    echo "✅ Test: Open Vaultwarden URL, login, access vault items"
  fi
  ```

**4.3 Matomo (if deployed - App + Database):**
- [ ] Check if deployed: `[[ -n "$MATOMO_NS" ]] && echo "✅ Migrate Matomo" || echo "⊘ Skip Matomo"`
- [ ] **If deployed**, patch Matomo app and MariaDB:
  ```bash
  if [[ -n "$MATOMO_NS" ]]; then
    kubectl patch deployment matomo -n $MATOMO_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $MATOMO_NS -l app=matomo
    
    kubectl patch statefulset matomo-mariadb -n $MATOMO_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod matomo-mariadb-0 -n $MATOMO_NS
    
    kubectl get pods -n $MATOMO_NS -w
    kubectl get pods -n $MATOMO_NS -o wide
    echo "✅ Test: Open Matomo URL, check analytics data visible"
  fi
  ```
- **Note**: Press Ctrl+C to exit the watch command when both pods are Running

**4.4 n8n (if deployed):**
- [ ] Check if deployed: `[[ -n "$N8N_NS" ]] && echo "✅ Migrate n8n" || echo "⊘ Skip n8n"`
- [ ] **If deployed**, patch deployment:
  ```bash
  if [[ -n "$N8N_NS" ]]; then
    kubectl patch deployment n8n -n $N8N_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $N8N_NS -l app=n8n
    kubectl wait --for=condition=ready pod -l app=n8n -n $N8N_NS --timeout=300s
    kubectl get pods -n $N8N_NS -o wide
    echo "✅ Test: Open n8n URL, check workflows visible and executable"
  fi
  ```

**4.5 WordPress (if deployed - App + Database):**
- [ ] Check if deployed: `[[ -n "$WORDPRESS_NS" ]] && echo "✅ Migrate WordPress" || echo "⊘ Skip WordPress"`
- [ ] **If deployed**, patch WordPress app and MariaDB:
  ```bash
  if [[ -n "$WORDPRESS_NS" ]]; then
    kubectl patch deployment wordpress -n $WORDPRESS_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $WORDPRESS_NS -l app=wordpress
    
    kubectl patch statefulset wordpress-mariadb -n $WORDPRESS_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod wordpress-mariadb-0 -n $WORDPRESS_NS
    
    kubectl get pods -n $WORDPRESS_NS -w
    kubectl get pods -n $WORDPRESS_NS -o wide
    echo "✅ Test: Open WordPress URL, login to wp-admin, verify site loads"
  fi
  ```
- **Note**: Press Ctrl+C to exit the watch command when both pods are Running

**4.6 Nextcloud (if deployed - App + PostgreSQL + Redis):**
- [ ] Check if deployed: `[[ -n "$NEXTCLOUD_NS" ]] && echo "✅ Migrate Nextcloud" || echo "⊘ Skip Nextcloud"`
- [ ] **If deployed**, patch all Nextcloud components:
  ```bash
  if [[ -n "$NEXTCLOUD_NS" ]]; then
    kubectl patch deployment nextcloud -n $NEXTCLOUD_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $NEXTCLOUD_NS -l app=nextcloud
    
    kubectl patch statefulset nextcloud-postgresql -n $NEXTCLOUD_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod nextcloud-postgresql-0 -n $NEXTCLOUD_NS
    
    kubectl patch deployment nextcloud-redis -n $NEXTCLOUD_NS \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"new"}}}}}'
    kubectl delete pod -n $NEXTCLOUD_NS -l app=redis
    
    kubectl get pods -n $NEXTCLOUD_NS -w
    kubectl get pods -n $NEXTCLOUD_NS -o wide
    echo "✅ Test: Open Nextcloud URL, login, upload/download files"
  fi
  ```
- **Note**: Press Ctrl+C to exit the watch command when all 3 pods are Running

**4.7 System Components (always required):**
- [ ] Migrate cert-manager pods:
  ```bash
  kubectl delete pods -n cert-manager --all
  ```
- [ ] Migrate ingress-nginx controller:
  ```bash
  kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
  ```
- [ ] Wait for cert-manager to be ready:
  ```bash
  kubectl get pods -n cert-manager -w
  ```
- **Note**: Press Ctrl+C when all cert-manager pods are Running
- [ ] Wait for ingress-nginx to be ready:
  ```bash
  kubectl get pods -n ingress-nginx -w
  ```
- **Note**: Press Ctrl+C when ingress-nginx pod is Running
- [ ] Verify all certificates are valid:
  ```bash
  kubectl get certificates -A
  ```
- **Note**: All certificates should show READY=True

### 5. Verify All Systems Operational on New Nodes (20 min)

**CLI Commands:**

**5.1 Pod Distribution Verification:**
- [ ] Verify no app pods remain on old nodes:
  ```bash
  kubectl get pods -A -o wide | grep -E "$(kubectl get nodes -l pool!=new -o jsonpath='{.items[*].metadata.name}' | tr ' ' '|')"
  ```
  Should show ONLY system DaemonSets (cilium, csi-do-node, etc.)
- [ ] Verify all app pods Running: `kubectl get pods -A | grep -v Running | grep -v Completed`
- [ ] Check pod distribution: `kubectl get pods -A -o wide | grep pool=new`

**5.2 Data Integrity and Storage Verification:**
- [ ] Verify all PVCs still bound: `kubectl get pvc -A` (all should show STATUS=Bound)
- [ ] Compare PVC list: `diff pre-migration-pvcs.txt <(kubectl get pvc -A)`
- [ ] Check volume attachments: `kubectl get volumeattachments` (all attached to new nodes)

**5.3 Security and Certificate Verification:**
- [ ] Check certificates valid:
  ```bash
  kubectl get certificates -A
  ```
- **Note**: All should show READY=True, AGE should match pre-migration
- [ ] Test TLS for each domain:
  ```bash
  for domain in vault.example.com matomo.example.com n8n.example.com ai.example.com; do
    echo "Testing $domain..."
    curl -I https://$domain 2>&1 | head -1
  done
  ```
- [ ] Verify NetworkPolicies still exist: `kubectl get networkpolicies -A`
- [ ] Check secrets intact: `kubectl get secrets -A | wc -l` (compare to pre-migration count)
- [ ] Verify RBAC: `kubectl get rolebindings -A | wc -l`

**5.4 Application Functionality Testing (only test deployed apps):**
- [ ] **AnythingLLM**: Access workspace, query document, verify embeddings work
- [ ] **Vaultwarden**: Login, access vault item, create test entry, delete test entry
- [ ] **Matomo**: View dashboard, check visitor data, verify real-time tracking
- [ ] **n8n**: Open workflow, execute test workflow, check execution history
- [ ] **WordPress**: Login to wp-admin, edit/publish post, view site frontend
- [ ] **Nextcloud**: Login, browse files, upload file, download file, share link

**5.5 Resource Usage and Capacity:**
- [ ] Check new node resource allocation:
  ```bash
  kubectl describe nodes -l pool=new | grep -A 5 "Allocated resources:"
  ```
- [ ] Verify reasonable usage (should be <60% CPU, <60% RAM)

**5.6 Backup Jobs and Scheduled Tasks:**
- [ ] Verify backup CronJobs remain scheduled:
  ```bash
  kubectl get cronjobs -A
  ```
- [ ] Check recent backup job completion:
  ```bash
  kubectl get jobs -A | grep backup
  ```

### 6. Monitor Post-Migration for 24-48 Hours

**CLI Commands (run daily):**
- [ ] Day 1 Evening: Check for errors in deployed apps (uses discovered namespaces):
  ```bash
  source ~/cluster-backup-$(date +%Y%m%d)/../migration-config.sh
  [[ -n "$ANYTHINGLLM_NS" ]] && kubectl logs -n $ANYTHINGLLM_NS -l app=anythingllm --tail=50 | grep -i error 2>/dev/null || true
  [[ -n "$VAULTWARDEN_NS" ]] && kubectl logs -n $VAULTWARDEN_NS -l app=vaultwarden --tail=50 | grep -i error 2>/dev/null || true
  [[ -n "$MATOMO_NS" ]] && kubectl logs -n $MATOMO_NS -l app=matomo --tail=50 | grep -i error 2>/dev/null || true
  [[ -n "$N8N_NS" ]] && kubectl logs -n $N8N_NS -l app=n8n --tail=50 | grep -i error 2>/dev/null || true
  [[ -n "$WORDPRESS_NS" ]] && kubectl logs -n $WORDPRESS_NS -l app=wordpress --tail=50 | grep -i error 2>/dev/null || true
  [[ -n "$NEXTCLOUD_NS" ]] && kubectl logs -n $NEXTCLOUD_NS -l app=nextcloud --tail=50 | grep -i error 2>/dev/null || true
  ```
- [ ] Day 1 Evening: Check for pod restarts:
  ```bash
  kubectl get pods -A -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount | grep -v " 0$"
  ```
- [ ] Day 2 Morning: Verify all pods still Running: `kubectl get pods -A | grep -v Running`
- [ ] Day 2 Evening: Check resource trends: `kubectl describe nodes -l pool=new | grep Allocated`
- [ ] Day 2 Evening: Test all app URLs again
- [ ] Day 3 Morning: Final verification - all checks passed, no issues

### 7. Delete Old Node Pool and Cleanup Migration Artifacts (15 min)

**⚠️ CRITICAL: Only proceed after 48 hours with ZERO issues**

**CLI Commands:**
- [ ] Final backup before deletion:
  ```bash
  kubectl get all -A -o yaml > final-state-before-old-pool-deletion.yaml
  ```
- [ ] Drain old nodes (force remaining pods to new nodes):
  ```bash
  kubectl drain $(kubectl get nodes -l pool!=new -o name | tr '\n' ' ') \
    --ignore-daemonsets --delete-emptydir-data --timeout=600s
  ```
- [ ] Verify old nodes fully drained:
  ```bash
  kubectl get pods -A -o wide | grep -E "$(kubectl get nodes -l pool!=new -o jsonpath='{.items[*].metadata.name}' | tr ' ' '|')"
  ```
  Should show ONLY DaemonSets

**DigitalOcean Dashboard:**
- [ ] Navigate to: Kubernetes → [Your Cluster] → Node Pools
- [ ] Locate old node pool (should show nodes as "Drained")
- [ ] Click three-dot menu → "Delete Node Pool"
- [ ] Confirm deletion (type pool name to confirm)
- [ ] Wait for nodes to be removed (~2-3 minutes)

**CLI Verification:**
- [ ] Verify old nodes removed: `kubectl get nodes` (should show only 2 new nodes)
- [ ] Check all pods still Running: `kubectl get pods -A | grep -v Running | grep -v Completed`
- [ ] Verify resource distribution:
  ```bash
  kubectl describe nodes | grep -A 5 "Allocated resources:"
  ```
- **Note**: Should show ~50% usage on each of 2 nodes

**DigitalOcean Billing:**
- [ ] Navigate to: Account → Billing
- [ ] Verify droplet count reduced (should show 2 droplets for cluster)
- [ ] Confirm monthly cost shows ~$56/month

**Cleanup:**
- [ ] Remove migration labels:
  ```bash
  kubectl label nodes --all pool- migration-
  ```
- [ ] Delete manual backup jobs (only those that exist):
  ```bash
  kubectl delete job vaultwarden-pre-migration -n vaultwarden 2>/dev/null || true
  kubectl delete job matomo-pre-migration -n matomo 2>/dev/null || true
  kubectl delete job wordpress-pre-migration -n wordpress 2>/dev/null || true
  kubectl delete job nextcloud-pre-migration -n nextcloud 2>/dev/null || true
  ```
- [ ] Archive migration files:
  ```bash
  cd ~/cluster-backup-$(date +%Y%m%d)
  tar -czf cluster-migration-complete.tar.gz *.yaml *.txt
  ```
- [ ] Update cluster documentation with new node pool configuration

---

## Rollback Plan (If Critical Issues Occur)

**When to Rollback:**
- Data corruption detected
- Multiple apps failing
- Security breach identified
- Performance degradation >50%
- Persistent errors after 2+ hours

**Rollback Steps:**

1. **Stop Migration Immediately - Uncordon old nodes**
   ```bash
   kubectl uncordon $(kubectl get nodes -l pool!=new -o name | tr '\n' ' ')
   ```

2. **Remove Node Selectors from All Deployed Apps** (uses discovered namespaces)
   ```bash
   source ~/cluster-backup-$(date +%Y%m%d)/../migration-config.sh
   
   [[ -n "$ANYTHINGLLM_NS" ]] && kubectl patch deployment anythingllm -n $ANYTHINGLLM_NS --type=json \
     -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   
   [[ -n "$VAULTWARDEN_NS" ]] && kubectl patch deployment vaultwarden -n $VAULTWARDEN_NS --type=json \
     -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   
   if [[ -n "$MATOMO_NS" ]]; then
     kubectl patch deployment matomo -n $MATOMO_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
     kubectl patch statefulset matomo-mariadb -n $MATOMO_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   fi
   
   [[ -n "$N8N_NS" ]] && kubectl patch deployment n8n -n $N8N_NS --type=json \
     -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   
   if [[ -n "$WORDPRESS_NS" ]]; then
     kubectl patch deployment wordpress -n $WORDPRESS_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
     kubectl patch statefulset wordpress-mariadb -n $WORDPRESS_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   fi
   
   if [[ -n "$NEXTCLOUD_NS" ]]; then
     kubectl patch deployment nextcloud -n $NEXTCLOUD_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
     kubectl patch statefulset nextcloud-postgresql -n $NEXTCLOUD_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
     kubectl patch deployment nextcloud-redis -n $NEXTCLOUD_NS --type=json \
       -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
   fi
   ```

3. **Cordon New Nodes**
   ```bash
   kubectl cordon $(kubectl get nodes -l pool=new -o name | tr '\n' ' ')
   ```

4. **Force Pods Back to Old Nodes** (uses discovered namespaces, will reschedule to old nodes)
   ```bash
   [[ -n "$ANYTHINGLLM_NS" ]] && kubectl delete pods -n $ANYTHINGLLM_NS --all 2>/dev/null || true
   [[ -n "$VAULTWARDEN_NS" ]] && kubectl delete pods -n $VAULTWARDEN_NS --all 2>/dev/null || true
   [[ -n "$MATOMO_NS" ]] && kubectl delete pods -n $MATOMO_NS --all 2>/dev/null || true
   [[ -n "$N8N_NS" ]] && kubectl delete pods -n $N8N_NS --all 2>/dev/null || true
   [[ -n "$WORDPRESS_NS" ]] && kubectl delete pods -n $WORDPRESS_NS --all 2>/dev/null || true
   [[ -n "$NEXTCLOUD_NS" ]] && kubectl delete pods -n $NEXTCLOUD_NS --all 2>/dev/null || true
   ```

5. **Verify Apps Running on Old Nodes**
   ```bash
   kubectl get pods -A -o wide | grep -v "pool=new"
   ```

6. **Restore from Backup** (if data corruption detected)
   - Use DigitalOcean volume snapshots created pre-migration
   - Or restore from backup PVCs

7. **Delete New Node Pool**
   - DigitalOcean Dashboard → Kubernetes → Delete new node pool

8. **Investigate Root Cause**
   - Review logs: `kubectl logs -n <namespace> <pod> --previous`
   - Check events: `kubectl get events -A --sort-by='.lastTimestamp'`
   - Document issues before retry

---

## Success Criteria

**Migration Complete When ALL True:**
- ✅ All application pods running on new nodes only
- ✅ Old nodes completely empty (only system DaemonSets remain)
- ✅ All data intact and accessible via browser tests
- ✅ All PVCs bound and attached to new nodes
- ✅ TLS certificates valid and auto-renewing
- ✅ NetworkPolicies still enforced
- ✅ Secrets encrypted and accessible
- ✅ Zero errors in logs for 48+ hours
- ✅ Zero unexpected pod restarts for 48+ hours
- ✅ Backup CronJobs running successfully
- ✅ Resource usage <60% on new nodes
- ✅ Old node pool deleted from DigitalOcean
- ✅ Billing updated to $56/month (2 nodes)
- ✅ Documentation updated with new configuration

---

## Important Notes

**Configuration Management:**
- 📝 **migration-config.sh** is generated in Section 0 and used throughout migration
- 📝 **Review the config file** before proceeding - ensure all variables are correct
- 📝 **Source the config** at the start of each migration session if you pause/resume
- 📝 **Variables adapt to YOUR cluster** - no manual namespace/cluster name updates needed

**Pre-Migration:**
- ✋ **Do NOT start during peak hours** - migrate late night/early morning
- ✋ **Verify all backups complete** before touching production
- ✋ **Test rollback plan mentally** - know the escape route
- ✋ **Have DigitalOcean dashboard open** in separate tab
- ✋ **Complete Section 0 FIRST** - discovery must happen before any migration steps

**During Migration:**
- ⏱️ **One app at a time** - don't rush, verify each before moving to next
- 🔍 **Watch logs continuously** - `kubectl logs -f` while pods migrate
- 📊 **Monitor resource usage** - ensure new nodes aren't overwhelmed
- 🌐 **Test in browser immediately** after each app migration

**Security Critical:**
- 🔒 **Never skip security verification** - NetworkPolicies, certificates, secrets
- 🔒 **Backup files contain secrets** - keep `all-secrets-backup.yaml` encrypted
- 🔒 **Delete backup files after 30 days** - don't leave old credentials around
- 🔒 **Review RBAC after migration** - ensure no permission drift

**Common Issues & Solutions:**
- **Pod stuck Pending**: Check PVC attachment, volume may be locked to old node
  - Solution: Delete pod, wait 30s, check PVC status
- **"Too many restarts"**: Usually app can't connect to database during migration
  - Solution: Migrate database first, then app
- **Certificate errors**: cert-manager may need restart
  - Solution: `kubectl rollout restart deployment cert-manager -n cert-manager`
- **NetworkPolicy blocks**: Pods on new nodes may have different labels
  - Solution: Verify NetworkPolicy selectors include new node labels

**Timeline:**
- **Active hands-on work**: 3-4 hours (can't walk away)
- **Monitoring period**: 48 hours minimum (periodic checks)
- **Total calendar time**: 2-3 days (including soak period)
- **Best schedule**: Start Friday night, monitor Sat/Sun, delete old pool Monday

**Cost Impact:**
- During migration (both pools): ~$70-84/month (temporary, 2-3 days)
- After migration (new pool only): $56/month (permanent)
- Net increase from current: +$14/month (+30%)
- Value: 2x CPU, 2.5x RAM, room for 4-8 more apps
