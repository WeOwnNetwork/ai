# WeOwn.App DOKS Cluster — Migration Runbook (W23)

| Field | Value |
|---|---|
| Date | 2026-06-04 |
| Version | v4.1.1.1 (#WeOwnVer) |
| Status | Draft — pre-execution. Reviewable; do not execute Phase 1 onward until Gate 0 (review + access provisioned) is signed off by `@ncimino`. |
| Maintained by | @dilonne |

**Audience:** WeOwn developers and operators executing the W23 cluster team-move (`<source_team>` → `<target_team>`). For the inventory of the source cluster being migrated, see [WEOWN-APP-CLUSTER-INVENTORY.md](./WEOWN-APP-CLUSTER-INVENTORY.md). For the broader infrastructure pattern referenced throughout, see [INFRA_BOOTSTRAP_PATTERN.md](./INFRA_BOOTSTRAP_PATTERN.md). For the Velero + Restic chart mechanic this runbook drives, see [cluster-backup/README.md](../cluster-backup/README.md). For the parallel-build + DNS-cutover pattern this runbook adopts, see [ADR-005](../.github/ADR-005-int-p01-doks-retirement.md).

This document is the operator's step-by-step recipe for migrating the W23 source cluster (referenced as `<CLUSTER_NAME>` in the inventory) into the target team. Real cluster identifiers, node hostnames, LoadBalancer IPs, Spaces buckets, kubeconfig contexts, and PV UUIDs are redacted per repo policy (`.github/copilot-instructions.md` §3.0). The operator-internal companion to this runbook holds the resolved values.

The migration is non-destructive on the source side until Gate 2 sign-off. Rollback at every phase prior to DNS cutover is a single command against the new cluster. Rollback after DNS cutover is a single DNS A-record swap back to the source LB.

---

## 1. Approach (summary)

Parallel build + DNS cutover, modelled on [ADR-005](../.github/ADR-005-int-p01-doks-retirement.md). The W23 differences from INT-P01 are: (a) target is a fresh DOKS cluster, not a droplet; (b) data migration uses Velero + Restic cross-cluster restore via shared DO Spaces, not a one-shot `kubectl exec` bridge.

1. Stand up a new DOKS cluster on `<target_team>`, K8s pinned to v1.33.1-do.2 to match source (per inventory §5.1).
2. Install addons (ingress-nginx + cert-manager + metrics-server via `cluster-backup/create-tenant-cluster.sh` recipe, with explicit overrides documented in this runbook).
3. Install Velero + Restic via `cluster-backup/deploy.sh` on **both** clusters, both pointing at the shared `<SPACES_BUCKET>` (cross-team access via the same access key).
4. Take backups from the source; restore into the target on temp/staging hostnames; validate per workload (Gate 1).
5. Deploy OTel collector to the target shipping to SigNoz Cloud `ingest.us2.signoz.cloud` (Friday work, kept in this runbook so the new cluster is observable before cutover).
6. Lower DNS TTLs 48 h ahead of cutover (Phase 7).
7. Cut over non-matomo workloads first (anything-llm with the queued stability fix, n8n). Final delta restore + DNS A-record swap per host.
8. Cut over matomo last in a frozen window using Pattern B (scale to 0, `mysqldump --single-transaction`, restore, scale up, swap DNS). Vaultwarden also uses Pattern B-equivalent (scale to 0, file copy, restart) (Gate 2).
9. Soak the source cluster stopped-but-intact for 7 days as instant rollback.
10. Decommission source cluster after soak completes cleanly.

The two anomalous namespaces (`nextcloud`, `searxng`) and the four `*-backup` PVCs are NOT carried forward, per inventory §5. Nextcloud's PVC is snapshotted to Spaces once for archival before its source-side decommission.

---

## 2. Prerequisites (Gate 0)

Do not start Phase 1 until **every** item below is checked off. If any item is missing, surface in WeOwn.Dev Signal and pause.

### 2.1 Access

- [ ] DO API token for `<source_team>` (read scope), wired into `doctl auth init --context <source_ctx>`.
- [ ] DO API token for `<target_team>` (full scope), wired into `doctl auth init --context <target_ctx>`.
- [ ] Source cluster kubeconfig pulled and merged into `~/.kube/config` (or `KUBECONFIG=` pointed at it). Verified by `kubectl --context <SOURCE_KUBECONFIG_CONTEXT> get nodes`.
- [ ] GitHub write access to `WeOwnNetwork/ai` (verified by the inventory PR submission).
- [ ] Proton Pass `[@PLT]` shared vault contains:
  - DO Spaces access key + secret for the shared `<SPACES_BUCKET>` (used by Velero on both clusters).
  - Infisical Machine Identity for OTel reader (project `otel`, env `dev`) — needed for Phase 6.
  - OpenRouter team API key (not used by this runbook directly; needed for app-layer reconciliation).
- [ ] Infisical CLI access (`infisical login`) verified.
- [ ] SigNoz Cloud account access (org us2) verified — needed Phase 6.
- [ ] SSH access to any operator-internal bastion (if required by VPN/Proton-VPN posture once that lands; not blocking W23 today).

### 2.2 Tooling on the operator workstation

```bash
kubectl version --client  # ≥ 1.33
doctl version             # any recent
helm version              # ≥ 3.12
velero version --client-only   # 1.18+
infisical --version       # any recent
mysql --version           # client only; for Matomo Pattern B
mysqldump --version       # client only; for Matomo Pattern B
yq --version              # for kubeconfig merge/edit
jq --version              # for command-pipelines
```

If any of the above is missing, install via `brew install <tool>` (macOS) before proceeding.

### 2.3 Repo state

- [ ] Latest `main` pulled.
- [ ] Inventory PR ([#41]) merged or accepted-and-pending — runbook references it.
- [ ] This runbook branch (`docs/dilonne-w23-cluster-runbook`) up to date.

### 2.4 Sign-off

- [ ] `@ncimino` has reviewed this runbook and confirmed proceed to Phase 1.
- [ ] Maintenance window for cutover (Phase 8) agreed with `@ncimino` (low-traffic window, default Sat low-traffic per SOW; can slip to early W24 if Phase 4–7 run tight).

---

## 3. Phase 1 — Provision the target cluster

**Goal:** A fresh DOKS cluster on `<target_team>` matching the source's K8s version + region, with addons installed.

**Duration estimate:** 30–45 minutes (cluster provisioning + addon install).

**Rollback for this phase:** `doctl kubernetes cluster delete <NEW_CLUSTER_NAME>` (no production traffic touched yet).

### 3.1 Cluster create

⚠️ **Do not run `cluster-backup/create-tenant-cluster.sh` as a black box.** Per inventory §5.1, its default `DOKS_K8S_VERSION=1.30.5-do.0` is three minors behind source (`1.33.1-do.2`) and Velero cross-restore will not cleanly carry 1.33 workloads onto a 1.30 API server. Override the version, and use only the cluster-create + addon-install portions of the script's logic; the script's later "deploy standard apps" section provisions fresh AnythingLLM / Vaultwarden which would overwrite migrated state.

Direct `doctl` invocation, matching the source's node size + count:

```bash
doctl auth switch --context <target_ctx>

doctl kubernetes cluster create <NEW_CLUSTER_NAME> \
  --region atl1 \
  --version 1.33.1-do.2 \
  --node-pool "name=<NEW_NODE_POOL>;size=<SAME_AS_SOURCE_SIZE>;count=2;auto-scale=false" \
  --wait
```

Resolve `<SAME_AS_SOURCE_SIZE>` by inspecting the source pool first:

```bash
doctl auth switch --context <source_ctx>
doctl kubernetes cluster node-pool list <CLUSTER_NAME>
# note the `size` column; use the same value on the target.
```

### 3.2 Pull and isolate the new kubeconfig

```bash
doctl auth switch --context <target_ctx>
doctl kubernetes cluster kubeconfig save <NEW_CLUSTER_NAME>
kubectl config rename-context $(kubectl config current-context) <TARGET_KUBECONFIG_CONTEXT>
kubectl --context <TARGET_KUBECONFIG_CONTEXT> get nodes   # expect 2 Ready nodes
```

### 3.3 Install addons

Per inventory §5.5, `cluster-backup/create-tenant-cluster.sh` installs ingress-nginx + cert-manager + metrics-server. Use only the addon-install steps from that script with pinned versions per §5.7 and §5.8:

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> apply -f \
  "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/cloud/deploy.yaml"
kubectl --context <TARGET_KUBECONFIG_CONTEXT> wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

kubectl --context <TARGET_KUBECONFIG_CONTEXT> apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml"
kubectl --context <TARGET_KUBECONFIG_CONTEXT> wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=cert-manager --timeout=300s

kubectl --context <TARGET_KUBECONFIG_CONTEXT> apply -f \
  "https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml"
```

Per inventory §5.7, cert-manager is `v1.16.2` (latest stable in that line) — explicitly NOT carrying forward source's v1.13.0. Per §5.8, ingress-nginx image is `registry.k8s.io/ingress-nginx/controller` (upstream) for the initial cutover; swap to a Minimus-hardened equivalent post-soak.

### 3.4 Verification

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> get pods -A
# Expect: ingress-nginx-controller Ready, cert-manager (3 pods) Ready, metrics-server Ready.

kubectl --context <TARGET_KUBECONFIG_CONTEXT> get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Expect: an IP (the new LB). Record as <NEW_INGRESS_LB_IP>; will be referenced through Phase 7 and Phase 8.
```

Wait until the LB IP is allocated before proceeding. DO provisioning typically takes 2–5 minutes.

---

## 4. Phase 2 — Install Velero on both clusters

**Goal:** Both source and target clusters running the `cluster-backup` Helm chart, pointed at the same `<SPACES_BUCKET>` so the target can read backups taken on the source.

**Duration estimate:** 20 minutes.

**Rollback for this phase:** `helm uninstall cluster-backup -n velero` on either side. No production impact.

### 4.1 Install on the source cluster

```bash
kubectl config use-context <SOURCE_KUBECONFIG_CONTEXT>

cd <repo>/cluster-backup
chmod +x deploy.sh
./deploy.sh   # interactive — answer:
              # Tenant: <source_tenant_label>
              # Cluster: <CLUSTER_NAME>
              # Environment: prod
              # S3 bucket: <SPACES_BUCKET>
              # S3 region: atl1   (or whichever the Spaces bucket lives in)
              # S3 endpoint: https://<REGION>.digitaloceanspaces.com
              # S3 access key + secret: from Pass vault
```

Verify:

```bash
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> get pods -n velero
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> get backupstoragelocation -n velero
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup-location get -n velero
# Expect: PHASE = Available
```

### 4.2 Install on the target cluster

```bash
kubectl config use-context <TARGET_KUBECONFIG_CONTEXT>

# Same deploy.sh, same S3 inputs, different tenant label:
./deploy.sh   # Tenant: <target_tenant_label>; Cluster: <NEW_CLUSTER_NAME>; everything else same.
```

Verify the target can see backups the source will produce:

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> get pods -n velero
velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> backup-location get -n velero
# Expect: PHASE = Available; both clusters now share the same BackupStorageLocation.
```

---

## 5. Phase 3 — Dry-run backup + restore

**Goal:** Prove the Velero mechanic works end-to-end against the source's actual workloads, restored into the target's staging namespaces, before doing anything destructive.

**Duration estimate:** 30–60 minutes per workload.

**Rollback for this phase:** delete the staging namespaces and the dry-run backup on the target. No source impact.

### 5.1 Take dry-run backups on the source

One backup per workload, namespace-scoped:

```bash
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-dryrun-matomo \
  --include-namespaces matomo \
  --default-volumes-to-fs-backup \
  --ttl 168h

velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-dryrun-anythingllm \
  --include-namespaces anything-llm \
  --default-volumes-to-fs-backup \
  --ttl 168h

velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-dryrun-n8n \
  --include-namespaces n8n \
  --default-volumes-to-fs-backup \
  --ttl 168h

velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-dryrun-vaultwarden \
  --include-namespaces vaultwarden \
  --default-volumes-to-fs-backup \
  --ttl 168h
```

Wait for each to land "Completed":

```bash
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup describe w23-dryrun-matomo --details
# Phase: Completed
# Persistent Volume Restores: should list all matomo PVCs
```

Inspect logs if any backup shows "PartiallyFailed":

```bash
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup logs w23-dryrun-matomo
```

### 5.2 Restore into staging namespaces on the target

Use namespace mapping to isolate the dry-run from any future production namespaces on the target:

```bash
velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-dryrun-matomo-restore \
  --from-backup w23-dryrun-matomo \
  --namespace-mappings matomo:matomo-staging

velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-dryrun-anythingllm-restore \
  --from-backup w23-dryrun-anythingllm \
  --namespace-mappings anything-llm:anything-llm-staging

velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-dryrun-n8n-restore \
  --from-backup w23-dryrun-n8n \
  --namespace-mappings n8n:n8n-staging

velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-dryrun-vaultwarden-restore \
  --from-backup w23-dryrun-vaultwarden \
  --namespace-mappings vaultwarden:vaultwarden-staging
```

Verify each restore lands "Completed" and pods come up:

```bash
velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore describe w23-dryrun-matomo-restore --details

kubectl --context <TARGET_KUBECONFIG_CONTEXT> get pods -n matomo-staging
kubectl --context <TARGET_KUBECONFIG_CONTEXT> get pvc -n matomo-staging
```

### 5.3 Per-workload smoke tests (Gate 1)

For each restored workload, port-forward into the target pod (without DNS) and verify:

**Matomo + MariaDB** (most important — the data integrity proof point):

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> port-forward -n matomo-staging svc/matomo 8080:80
# Open http://localhost:8080 → log in → verify dashboard renders
# Spot-check: pick a known existing site and confirm visit history loads.

kubectl --context <TARGET_KUBECONFIG_CONTEXT> exec -n matomo-staging matomo-mariadb-0 -- \
  mysql -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM matomo.matomo_log_visit;"
# Compare against source:
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> exec -n matomo matomo-mariadb-0 -- \
  mysql -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM matomo.matomo_log_visit;"
# Within ±0.1% delta (some inflight rows acceptable on the source's running counter).
```

**AnythingLLM** (verify workspaces + chats load):

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> port-forward -n anything-llm-staging svc/anythingllm 3001:80
# Open http://localhost:3001 → log in → all workspaces present.
```

**n8n** (verify workflows visible):

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> port-forward -n n8n-staging svc/n8n 5678:5678
# Open http://localhost:5678 → log in → workflows list non-empty.
```

**Vaultwarden** (verify item count matches source — but do NOT decrypt; clients re-decrypt with master passwords):

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> exec -n vaultwarden-staging deploy/vaultwarden -- \
  sqlite3 /data/db.sqlite3 "SELECT COUNT(*) FROM ciphers;"
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> exec -n vaultwarden deploy/vaultwarden -- \
  sqlite3 /data/db.sqlite3 "SELECT COUNT(*) FROM ciphers;"
# Exact match expected (dry-run is a point-in-time copy).
```

### 5.4 Gate 1 sign-off

Before proceeding to Phase 4, capture the smoke-test results in the PR description or a Gate 1 comment on this runbook PR. `@ncimino` signs off Gate 1.

Tear down the staging namespaces after sign-off so the target cluster is clean for the real restore:

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> delete namespace matomo-staging anything-llm-staging n8n-staging vaultwarden-staging
```

The dry-run backups in `<SPACES_BUCKET>` are retained for 168 h (7 d) per the `--ttl` flag, useful for rollback comparisons.

---

## 6. Phase 4 — Real restore on temp hostnames (pre-cutover)

**Goal:** Restore each workload into its production namespace on the target, exposed via a sibling staging hostname so it can be smoke-tested with real cert-manager TLS before DNS cutover.

**Duration estimate:** 60–90 minutes.

**Rollback for this phase:** delete the restored namespaces on the target. Source unchanged.

### 6.1 Take fresh backups on the source (closer to cutover = less drift)

Same commands as §5.1 with name suffix `-pre-cutover` and a 72 h TTL.

### 6.2 Restore into production namespaces on the target

Restore into the same namespace names (no `:-staging` mapping this time). Per inventory §5.9, the `*-backup` PVCs are **excluded** from the restore — they're not carried forward.

```bash
velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-restore-matomo \
  --from-backup w23-precutover-matomo \
  --exclude-resources persistentvolumeclaims.matomo-backup

# Repeat for anything-llm, n8n, vaultwarden — exclude their respective *-backup PVCs.
```

### 6.3 Patch ingresses to add the staging hostname (dual-hostname trick)

For each workload, edit its restored Ingress to include BOTH the production hostname AND a sibling staging hostname under the same `tls:` block. cert-manager will issue both certs at first request, so production cutover later is a DNS-only operation (no last-minute Let's Encrypt issuance).

Per inventory §4.1, the production hostnames are stored as placeholders. Staging hostnames mirror them with a `-staging` suffix on the leftmost label.

Example for matomo (apply the same pattern to anything-llm, n8n, vaultwarden):

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> patch ingress matomo -n matomo --type=json -p='[
  {"op":"replace","path":"/spec/tls/0/hosts","value":["<MATOMO_HOSTNAME>","<MATOMO_STAGING_HOSTNAME>"]},
  {"op":"add","path":"/spec/rules/-","value":{"host":"<MATOMO_STAGING_HOSTNAME>","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"matomo","port":{"number":80}}}}]}}}
]'
```

Wait for cert-manager to issue:

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> get certificate -n matomo
kubectl --context <TARGET_KUBECONFIG_CONTEXT> describe certificate -n matomo
# Wait for: Status: Ready: True
```

### 6.4 Point staging hostnames at the new LB

For each `<WORKLOAD_STAGING_HOSTNAME>`, create or update a DNS A-record pointing at `<NEW_INGRESS_LB_IP>` from Phase 3.4. (Production hostnames remain pointed at the source LB throughout this phase.)

### 6.5 Real-hostname smoke tests

Same per-workload checks as §5.3 but against the staging hostnames over real HTTPS:

```bash
curl -sSI "https://<MATOMO_STAGING_HOSTNAME>/" | head -5
curl -sSI "https://<AI_LLM_STAGING_HOSTNAME>/api/ping"
# etc.
```

For matomo specifically, log in via browser and confirm the dashboard renders without errors.

---

## 7. Phase 5 — Deploy OTel collector → SigNoz Cloud

**Goal:** New cluster ships telemetry to SigNoz Cloud before going live, so the cutover itself is observable.

**Duration estimate:** 30–45 minutes.

**Rollback for this phase:** `helm uninstall otel-collector -n observability` and `kubectl delete namespace observability`. Pre-cutover, no production impact.

This phase implements the K8s equivalent of [`otel-agent/README.md`](../otel-agent/README.md)'s droplet pattern.

### 7.1 Pre-create the K8s Secret with OTel reader MI credentials

From Pass vault, retrieve the shared OTel reader MI credentials (`INFISICAL_OTEL_PROJECT_ID`, `INFISICAL_OTEL_CLIENT_ID`, `INFISICAL_OTEL_CLIENT_SECRET`). Then fetch the SigNoz endpoint + token from Infisical:

```bash
export INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id=$INFISICAL_OTEL_CLIENT_ID \
  --client-secret=$INFISICAL_OTEL_CLIENT_SECRET \
  --plain --silent)"

OTEL_URL=$(infisical secrets get OTEL_URL --projectId=$INFISICAL_OTEL_PROJECT_ID --env=dev --plain)
OTEL_KEY=$(infisical secrets get OTEL_KEY --projectId=$INFISICAL_OTEL_PROJECT_ID --env=dev --plain)

# Confirm the URL has the https:// scheme (per otel-agent/README.md gotcha).
echo "$OTEL_URL" | grep -E '^https://' || OTEL_URL="https://${OTEL_URL}"

kubectl --context <TARGET_KUBECONFIG_CONTEXT> create namespace observability
kubectl --context <TARGET_KUBECONFIG_CONTEXT> create secret generic otel-signoz-auth -n observability \
  --from-literal=OTEL_URL="$OTEL_URL" \
  --from-literal=OTEL_KEY="$OTEL_KEY"
```

### 7.2 Install the OTel collector Helm chart

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm --kube-context <TARGET_KUBECONFIG_CONTEXT> install otel-collector \
  open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values otel-values.yaml
```

`otel-values.yaml` skeleton (full file maintained in an operator-internal companion to keep the public repo clean of cluster specifics):

```yaml
mode: daemonset
image:
  repository: otel/opentelemetry-collector-contrib
  tag: "0.114.0"
extraEnvs:
  - name: OTEL_URL
    valueFrom: { secretKeyRef: { name: otel-signoz-auth, key: OTEL_URL } }
  - name: OTEL_KEY
    valueFrom: { secretKeyRef: { name: otel-signoz-auth, key: OTEL_KEY } }
config:
  receivers:
    k8s_cluster: { auth_type: serviceAccount }
    kubeletstats: { auth_type: serviceAccount, collection_interval: 30s, endpoint: ${env:K8S_NODE_NAME}:10250, insecure_skip_verify: true }
    hostmetrics: { collection_interval: 30s, scrapers: { cpu: {}, memory: {}, disk: {}, network: {}, filesystem: {}, load: {} } }
    filelog: { include: [/var/log/pods/*/*/*.log], start_at: end, operators: [{ type: container }] }
  processors:
    memory_limiter: { check_interval: 1s, limit_percentage: 80, spike_limit_percentage: 25 }
    k8sattributes:
      auth_type: serviceAccount
      passthrough: false
      extract: { metadata: [k8s.pod.name, k8s.pod.uid, k8s.deployment.name, k8s.namespace.name, k8s.node.name] }
    batch: { send_batch_size: 1024, timeout: 10s }
  exporters:
    otlphttp/signoz:
      endpoint: ${env:OTEL_URL}
      headers: { signoz-access-token: ${env:OTEL_KEY} }
      compression: gzip
  service:
    pipelines:
      metrics: { receivers: [k8s_cluster, kubeletstats, hostmetrics], processors: [memory_limiter, k8sattributes, batch], exporters: [otlphttp/signoz] }
      logs:    { receivers: [filelog], processors: [memory_limiter, k8sattributes, batch], exporters: [otlphttp/signoz] }
resources:
  limits: { memory: 256Mi }
  requests: { memory: 128Mi }
```

### 7.3 Verify telemetry is flowing

```bash
kubectl --context <TARGET_KUBECONFIG_CONTEXT> logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=50 -f
# Look for batch-export messages, no auth errors.
```

In SigNoz Cloud UI:

- Infrastructure → Hosts → filter `k8s.cluster.name=<NEW_CLUSTER_NAME>` → metrics appear within 60 s.
- Logs Explorer → filter `k8s.namespace.name=matomo` → pod logs flowing.

---

## 8. Phase 6 — DNS TTL preparation

**Goal:** Lower TTLs on every cutover hostname 48 h before Phase 7 starts, so propagation (and rollback propagation) is bounded by ~60 s.

**Duration estimate:** 5 minutes work; 48 h wall-clock wait.

**Rollback for this phase:** raise TTL back to original. No traffic impact.

### 8.1 Lower TTL

For each cutover hostname (production, not staging), edit the A-record TTL from its current value (commonly 3600 s = 1 h) to **60 s**:

- `<MATOMO_HOSTNAME>`
- `<AI_LLM_HOSTNAME>`
- `<N8N_HOSTNAME>`
- `<VAULT_HOSTNAME>`

(`<SEARXNG_HOSTNAME>` is being dropped per inventory §5.4 — its DNS A-record can be removed at decommission time, not migrated.)

### 8.2 Wait for the lower TTL to propagate

Current TTL = 3600 s, so 1 h after the change the new 60 s TTL is observed everywhere. Confirm:

```bash
for h in <MATOMO_HOSTNAME> <AI_LLM_HOSTNAME> <N8N_HOSTNAME> <VAULT_HOSTNAME>; do
  for resolver in 1.1.1.1 8.8.8.8 9.9.9.9; do
    echo -n "$h @$resolver: "
    dig +noall +answer @$resolver "$h" | awk '{print $2}'
  done
done
# Expect: 60 (or lower) from all resolvers before proceeding.
```

---

## 9. Phase 7 — Cutover non-matomo workloads

**Goal:** Move `anything-llm`, `n8n`, and `vaultwarden` from source to target via DNS cutover, in order of risk (low → high). Matomo is handled separately in Phase 8 with a freeze window.

**Duration estimate:** 15–30 minutes per workload + monitoring soak between.

**Rollback for this phase:** revert the DNS A-record to the source LB IP. Propagation is bounded by 60 s. Source workload still serving as before.

### 9.1 Order

1. `anything-llm` first — lowest care, has the queued stability fix that lands during the rebuild (inventory §2.1 disambiguation note).
2. `n8n` second.
3. `vaultwarden` last (non-matomo) — uses Pattern B-equivalent. See §9.3.

### 9.2 Per-workload cutover steps (Pattern A — anything-llm, n8n)

For each workload:

1. **Final delta backup on the source** (catches anything written since Phase 6 backup):

   ```bash
   velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-final-<workload> \
     --include-namespaces <workload> \
     --default-volumes-to-fs-backup --ttl 168h
   ```

2. **Final restore on the target** (delta over the Phase 6 restore):

   ```bash
   velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-final-<workload>-restore \
     --from-backup w23-final-<workload> \
     --exclude-resources persistentvolumeclaims.<workload>-backup \
     --existing-resource-policy=update
   ```

3. **Verify the workload comes up healthy on the target**:

   ```bash
   kubectl --context <TARGET_KUBECONFIG_CONTEXT> rollout status deploy/<workload> -n <workload>
   curl -sSI "https://<WORKLOAD_STAGING_HOSTNAME>/" | head -5
   ```

4. **Flip DNS A-record**: `<WORKLOAD_HOSTNAME>` → `<NEW_INGRESS_LB_IP>`.
5. **Monitor for 5 minutes**:

   ```bash
   kubectl --context <TARGET_KUBECONFIG_CONTEXT> logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 -f
   # New cluster receiving traffic for the cutover hostname.

   kubectl --context <SOURCE_KUBECONFIG_CONTEXT> logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 -f
   # Old cluster traffic draining for that hostname.
   ```

6. **Confirm SigNoz** shows new request traffic on the new cluster for the cutover hostname.

Wait 30 minutes between each workload's cutover. If anything regresses, rollback (revert DNS, propagation in 60 s) and stop.

### 9.3 Vaultwarden Pattern B-equivalent

Vaultwarden uses sqlite, not MariaDB, but per inventory §5.2 it's still treated as a write-freeze workload because it's a password manager and consistency matters.

```bash
# 1. Freeze writes on the source.
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> scale deploy/vaultwarden -n vaultwarden --replicas=0

# 2. Final backup on the source (post-freeze, so sqlite is consistent).
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-final-vaultwarden \
  --include-namespaces vaultwarden \
  --default-volumes-to-fs-backup --ttl 168h

# 3. Restore + verify on the target.
velero --kubecontext <TARGET_KUBECONFIG_CONTEXT> restore create w23-final-vaultwarden-restore \
  --from-backup w23-final-vaultwarden \
  --exclude-resources persistentvolumeclaims.vaultwarden-backup \
  --existing-resource-policy=update
kubectl --context <TARGET_KUBECONFIG_CONTEXT> rollout status deploy/vaultwarden -n vaultwarden

# 4. Smoke test on staging hostname (browser login + cipher count parity).

# 5. Flip DNS A-record: <VAULT_HOSTNAME> → <NEW_INGRESS_LB_IP>.

# 6. Source vaultwarden stays scaled to 0. Do NOT scale back up on the source — clients are now writing to the target.
```

---

## 10. Phase 8 — Matomo cutover (Gate 2)

**Goal:** Migrate matomo + MariaDB with zero data loss. This is the highest-care step in the entire runbook.

**Duration estimate:** 30–60 minutes inside a frozen window.

**Rollback for this phase:** revert DNS A-record to source LB IP. Source matomo unchanged (it was scaled to 0 during the freeze; scale back to 1 to resume on the source).

### 10.1 Pre-flight (Gate 2)

- [ ] `@ncimino` has signed off Phase 7 completion and matomo cutover go-ahead.
- [ ] Maintenance window agreed (low-traffic time, default Sat).
- [ ] Phase 7 cutover hostnames stable in SigNoz, no error-rate regression.
- [ ] Pass vault contains MariaDB root password (or it's retrievable via `infisical run` from the app project).

### 10.2 Pattern B — scale-to-0 + `mysqldump --single-transaction`

```bash
SOURCE=<SOURCE_KUBECONFIG_CONTEXT>
TARGET=<TARGET_KUBECONFIG_CONTEXT>

# T-15 min — freeze app writes on the source (MariaDB stays running, just no inflight app writes).
kubectl --context $SOURCE scale deploy/matomo -n matomo --replicas=0
kubectl --context $SOURCE wait deploy/matomo -n matomo --for=delete --timeout=60s || \
  kubectl --context $SOURCE wait pods -n matomo -l app=matomo --for=delete --timeout=60s

# T-12 min — take a consistent mysqldump from the still-running mariadb-0 pod.
kubectl --context $SOURCE exec -n matomo matomo-mariadb-0 -- sh -c \
  'mysqldump --single-transaction --routines --triggers --all-databases -uroot -p"$MARIADB_ROOT_PASSWORD" > /tmp/final.sql'
kubectl --context $SOURCE cp matomo/matomo-mariadb-0:/tmp/final.sql ./matomo-final-$(date +%Y%m%d-%H%M%S).sql

# T-8 min — verify dump integrity (size > expected baseline, parseable).
ls -lh matomo-final-*.sql
head -5 matomo-final-*.sql
tail -5 matomo-final-*.sql

# T-6 min — copy the dump into the target's mariadb-0 pod and restore.
DUMP=./matomo-final-$(date +%Y%m%d-%H%M%S).sql   # or the actual filename you just wrote
kubectl --context $TARGET cp "$DUMP" matomo/matomo-mariadb-0:/tmp/final.sql
kubectl --context $TARGET exec -n matomo matomo-mariadb-0 -- sh -c \
  'mysql -uroot -p"$MARIADB_ROOT_PASSWORD" < /tmp/final.sql'

# T-3 min — smoke test on staging hostname.
curl -sSI "https://<MATOMO_STAGING_HOSTNAME>/" | head -5
# Open <MATOMO_STAGING_HOSTNAME> in browser → log in → dashboard renders → row count parity:
kubectl --context $TARGET exec -n matomo matomo-mariadb-0 -- \
  mysql -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM matomo.matomo_log_visit;"
# Compare against source pre-freeze count (recorded in §5.3 smoke tests).

# T-1 min — scale target matomo Deployment back to 1 (resume serving on new cluster).
kubectl --context $TARGET scale deploy/matomo -n matomo --replicas=1
kubectl --context $TARGET rollout status deploy/matomo -n matomo

# T-0 — flip DNS A-record: <MATOMO_HOSTNAME> → <NEW_INGRESS_LB_IP>.

# T+1 min — verify DNS propagation.
for resolver in 1.1.1.1 8.8.8.8 9.9.9.9; do
  echo -n "@$resolver: "
  dig +short @$resolver <MATOMO_HOSTNAME>
done

# T+5 min — monitor ingress traffic.
kubectl --context $TARGET logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 -f
# Expect: GET <MATOMO_HOSTNAME>/... lines starting.

# T+15 min — browser smoke test against production hostname.

# T+1 h — confirm source ingress no longer receiving traffic for <MATOMO_HOSTNAME>.
kubectl --context $SOURCE logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 | grep -c "<MATOMO_HOSTNAME>"
# Expect: near-zero.
```

### 10.3 Matomo rollback (if needed within Phase 8)

```bash
# 1. Flip DNS A-record back to source LB IP. Propagation ~60 s.
# 2. Source matomo Deployment was scaled to 0 — scale back up:
kubectl --context $SOURCE scale deploy/matomo -n matomo --replicas=1
# 3. The dump file is retained locally + the Velero backup of matomo is also available. No data loss.
```

---

## 11. Phase 9 — Soak

**Goal:** Verify the cutover is stable for ≥7 days before decommissioning the source cluster.

**Duration estimate:** 7 days wall-clock.

**Rollback during soak:** DNS revert per affected hostname; source cluster is stopped-but-intact for the entire soak window.

### 11.1 Stop the source cluster's serving capacity

```bash
# Scale each migrated workload's source-side Deployment / StatefulSet to 0.
# Do NOT delete the namespaces — preserve the data PVCs.
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> scale deploy/matomo -n matomo --replicas=0
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> scale statefulset/matomo-mariadb -n matomo --replicas=0
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> scale deploy/anythingllm -n anything-llm --replicas=0
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> scale deploy/n8n -n n8n --replicas=0
# vaultwarden already at 0 from §9.3.
```

The source ingress-nginx controller stays running — if a rollback flip happens, traffic needs to land somewhere that can scale back up.

### 11.2 Snapshot nextcloud PVC and decommission its namespace (per inventory §5.3)

```bash
# Take a Velero backup of just the nextcloud PVC (data archival, not for re-deployment).
velero --kubecontext <SOURCE_KUBECONFIG_CONTEXT> backup create w23-nextcloud-archive \
  --include-namespaces nextcloud \
  --default-volumes-to-fs-backup \
  --ttl 8760h   # 1 year retention for archival
# Verify completion, then:
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> delete namespace nextcloud
```

### 11.3 Drop searxng namespace on the source (per inventory §5.4)

```bash
kubectl --context <SOURCE_KUBECONFIG_CONTEXT> delete namespace searxng
# Also remove the <SEARXNG_HOSTNAME> DNS A-record at this point.
```

### 11.4 Monitor target health daily

- SigNoz dashboards: error rate, latency, request rate per workload.
- Compare against the baseline captured in Phase 5.3.
- Investigate any deviation > 2x baseline before continuing the soak.

---

## 12. Phase 10 — Decommission source cluster

**Goal:** Permanently remove the source cluster after a clean 7-day soak.

**Duration estimate:** 10 minutes.

**Rollback:** none. This is irreversible. Only proceed with `@ncimino` final sign-off.

### 12.1 Sign-off

- [ ] 7-day soak completed clean.
- [ ] No regressions in SigNoz.
- [ ] All Phase 7 + Phase 8 cutover hostnames stable.
- [ ] Velero backups in `<SPACES_BUCKET>` retained per the existing GFS policy.
- [ ] `@ncimino` final sign-off.

### 12.2 Delete

```bash
doctl --context <source_ctx> kubernetes cluster delete <CLUSTER_NAME>
# Confirm prompt.
```

DO Block Storage volumes attached to the deleted cluster are released. Velero backup tarballs in `<SPACES_BUCKET>` remain available per the bucket's retention policy.

### 12.3 Update inventory

Re-run the inventory capture commands from [WEOWN-APP-CLUSTER-INVENTORY.md §7](./WEOWN-APP-CLUSTER-INVENTORY.md) against the new cluster context and bump the inventory file with the post-migration snapshot, status changed to "Post-migration; source cluster decommissioned <DATE>".

---

## 13. Rollback summary (all phases)

| Phase | Failure mode | Rollback action |
|---|---|---|
| 1 | Cluster fails to provision | `doctl kubernetes cluster delete <NEW_CLUSTER_NAME>`; re-run Phase 1. Source untouched. |
| 2 | Velero install errors | `helm uninstall cluster-backup -n velero` on the affected cluster; re-run with corrected inputs. |
| 3 | Dry-run restore fails | Delete staging namespaces on target; review Velero logs; fix; re-run. Source untouched. |
| 4 | Real restore fails | Delete the affected production namespace on target; re-run from §6.2. Source untouched. |
| 5 | OTel not shipping | `helm uninstall otel-collector -n observability`; verify Pass vault values; re-run Phase 5. No production impact. |
| 6 | TTL not propagating | Raise TTL back to original; investigate DNS provider; retry. |
| 7 | Non-matomo cutover regresses | Flip DNS A-record back to source LB IP (~60 s propagation). Source workload still running. |
| 8 | Matomo cutover regresses | Flip DNS back to source LB IP; scale source matomo Deployment to 1. Dump file + Velero backup both retained. |
| 9 | Soak reveals regression | DNS revert per affected hostname; scale source workload back to 1; investigate. |
| 10 | Decommission errors | None. Do not proceed without sign-off. |

---

## 14. Compliance mapping

| Framework | Control | How this runbook satisfies it |
|---|---|---|
| NIST CSF 2.0 | PR.IP-3 (configuration change control) | Two-gate human approval (Gate 1 + Gate 2); fully documented phases; no production change without sign-off |
| NIST CSF 2.0 | RC.RP-1 (recovery plan executed) | §13 rollback table covers every phase explicitly |
| NIST CSF 2.0 | DE.CM-1 (continuous monitoring) | Phase 5 OTel → SigNoz before cutover; baseline + post-cutover comparison |
| CIS Controls v8 | 11.1 (Establish and maintain a data recovery process) | Velero backups + Pattern B database dumps + 7-day soak with rollback |
| CIS Controls v8 | 12.4 (Maintain network architecture diagrams) | Hostname/LB/ingress topology documented (cross-ref inventory §4) |
| ISO 27001:2022 | A.5.30 (ICT readiness for business continuity) | Rollback procedures verified in Phase 3 dry-run before any production exposure |
| ISO 27001:2022 | A.8.13 (information backup) | Velero + DO Spaces + GFS retention wired before cutover |

---

## 15. Document scope

**In scope:** target cluster provisioning, addon installation, Velero install on both clusters, dry-run validation (Gate 1), per-workload cutover sequence, matomo Pattern B with freeze window (Gate 2), 7-day soak, source decommission.

**Out of scope (covered elsewhere):**

- Source cluster state observation → [WEOWN-APP-CLUSTER-INVENTORY.md](./WEOWN-APP-CLUSTER-INVENTORY.md)
- Bootstrap architecture pattern (Path C + Layer 2) → [INFRA_BOOTSTRAP_PATTERN.md](./INFRA_BOOTSTRAP_PATTERN.md)
- Velero + Restic Helm chart internals → [cluster-backup/README.md](../cluster-backup/README.md)
- INT-P01 / `ai.weown.agency` retirement → [ADR-005](../.github/ADR-005-int-p01-doks-retirement.md) (separate workstream, forensic hold)
- Real values for all `<PLACEHOLDER>` identifiers → operator-internal companion (held outside the public repo)
