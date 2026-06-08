# WeOwn.App DOKS Cluster — Inventory (pre-migration)

| Field | Value |
|---|---|
| Date | 2026-06-03 |
| Version | v4.1.1.1 (#WeOwnVer) |
| Status | Adopted as source-of-truth inventory for the W23 cluster migration (`<source_team>` → `<target_team>`). |
| Maintained by | @dilonne |

**Audience:** WeOwn developers and operators executing the W23 DOKS cluster team-move. The migration runbook is `(to be written — W23)` as a follow-up PR. For the broader infrastructure pattern, see [INFRA_BOOTSTRAP_PATTERN.md](./INFRA_BOOTSTRAP_PATTERN.md).

This document captures the live state of the W23 source cluster (referenced as `<CLUSTER_NAME>`) on the `<source_team>` DigitalOcean team as observed on 2026-06-03. It is the input to the W23 migration runbook. Nothing on the source cluster was modified during capture — all commands were read-only.

Real cluster identifiers, node hostnames, LoadBalancer IPs, Spaces buckets, kubeconfig contexts, and PV UUIDs are redacted per repo policy (`.github/copilot-instructions.md` §3.0). The operator-internal runbook (held outside the public repo) carries the resolved values.

---

## 1. Cluster facts

| Property | Value |
|---|---|
| Cluster name | `<CLUSTER_NAME>` |
| Cluster ID | `<CLUSTER_ID>` |
| Region | `atl1` |
| DO team (source) | `<source_team>` |
| Kubernetes version | v1.33.1 (DOKS `1.33.1-do.2`) |
| Auto-upgrade | disabled |
| Node count | 2 |
| Node pool | `<NODE_POOL>` |
| CNI | Cilium with Hubble enabled |
| Default StorageClass | `do-block-storage` (DO Block Storage CSI) |
| Cluster age (default ns) | 313 days |
| Ingress LB external IP | `<INGRESS_LB_IP>` (RFC 5737 example: `203.0.113.10`) |

### 1.1 Node detail

| Node | Status | Age | Version |
|---|---|---|---|
| `<NODE_POOL>-<n1>` | Ready | 89d | v1.33.1 |
| `<NODE_POOL>-<n2>` | Ready | 214d | v1.33.1 |

---

## 2. Workload inventory

### 2.1 Active workloads

> **Disambiguation:** the `anything-llm` namespace below hosts `<AI_LLM_HOSTNAME>`. This is **NOT** INT-P01 / `ai.weown.agency`, which is a separate migration (droplet retirement under [ADR-005](../.github/ADR-005-int-p01-doks-retirement.md), currently on a forensic hold, explicitly out of W23 scope). The two AnythingLLM instances are operationally distinct. The W23 instance was flagged unstable on 2026-05-28; the rebuild is the natural window to land the queued stability fix.

| Workload | Namespace | Type | Replicas | Helm release / chart | Image | Age |
|---|---|---|---|---|---|---|
| Matomo (app) | `matomo` | Deployment | 1/1 | `matomo` / `matomo-2.0.7` (app 5.8.0) | `docker.io/matomo:5.8.0-apache` | 214d |
| MariaDB (matomo DB) | `matomo` | StatefulSet | 1/1 | (same release) | `mariadb:12.0.2` | 214d |
| AnythingLLM | `anything-llm` | Deployment | 1/1 | `anythingllm` / `anythingllm-2.0.0` (app 1.9.0) | `mintplexlabs/anythingllm:1.9.0` | 294d |
| n8n | `n8n` | Deployment | 1/1 | `n8n` / `n8n-2.8.1` (app 2.1.4) | `n8nio/n8n:2.1.4` | 78d |
| Vaultwarden | `vaultwarden` | Deployment | 1/1 | `vaultwarden` / `vaultwarden-1.0.0` (app 1.30.3) | `vaultwarden/server:1.30.3` | 218d |

Each entry above runs a single replica. No horizontal scaling, no PodDisruptionBudgets observed.

### 2.2 Anomalous namespaces

| Namespace | Observation |
|---|---|
| `nextcloud` | Bound PVC `pvc-<REDACTED>` (10 Gi) but no Deployment, StatefulSet, Service, Ingress, or Pods. `kubectl get all -n nextcloud` returns "No resources found." |
| `searxng` | Service `searxng-external` (ClusterIP) and Ingress `<SEARXNG_HOSTNAME>` exist; no Deployment, StatefulSet, or Pods. The Service has zero endpoints — requests return 502/503. |

### 2.3 Addons

| Component | Namespace | Helm-managed? | Source |
|---|---|---|---|
| ingress-nginx | `ingress-nginx` | yes — `ingress-nginx-4.13.1`, app v1.13.1 | upstream chart |
| cert-manager | `cert-manager` | no — raw manifest apply, v1.13.0 | `quay.io/jetstack/cert-manager-*:v1.13.0` |
| CoreDNS | `kube-system` | DOKS-managed | `ghcr.io/digitalocean-packages/coredns:1.12.1` |
| Cilium + Hubble | `kube-system` | DOKS-managed | `ghcr.io/digitalocean-packages/hubble-*` |
| konnectivity-agent | `kube-system` | DOKS-managed | `ghcr.io/digitalocean-packages/kas-network-proxy/proxy-agent:v0.32.0` |
| metrics-server | — | absent on source | — |

---

## 3. Persistent storage

All PVCs use the `do-block-storage` CSI driver (DO Block Storage volumes), `ReadWriteOnce` access mode.

| Namespace | PVC | Capacity | Underlying PV ID |
|---|---|---|---|
| `matomo` | `data-matomo-mariadb-0` | 8 Gi | `pvc-<REDACTED>` |
| `matomo` | `matomo` | 10 Gi | `pvc-<REDACTED>` |
| `matomo` | `matomo-backup` | 20 Gi | `pvc-<REDACTED>` |
| `anything-llm` | `anythingllm-storage` | 20 Gi | `pvc-<REDACTED>` |
| `anything-llm` | `anythingllm-backup` | 10 Gi | `pvc-<REDACTED>` |
| `n8n` | `n8n-data` | 10 Gi | `pvc-<REDACTED>` |
| `n8n` | `n8n-backup` | 5 Gi | `pvc-<REDACTED>` |
| `vaultwarden` | `vaultwarden-data` | 10 Gi | `pvc-<REDACTED>` |
| `vaultwarden` | `vaultwarden-backup` | 20 Gi | `pvc-<REDACTED>` |
| `nextcloud` | `pvc-<REDACTED>` (postgresql-data) | 10 Gi | `pvc-<REDACTED>` |

**Total PVC footprint:** 123 Gi across 10 claims.

---

## 4. Networking

### 4.1 Ingress / DNS map

| Hostname | Workload | Service backend | LB IP |
|---|---|---|---|
| `<MATOMO_HOSTNAME>` | matomo | `matomo:80` | `<INGRESS_LB_IP>` |
| `<AI_LLM_HOSTNAME>` | anything-llm | `anythingllm:80` | `<INGRESS_LB_IP>` |
| `<N8N_HOSTNAME>` | n8n | `n8n:5678` | `<INGRESS_LB_IP>` |
| `<VAULT_HOSTNAME>` | vaultwarden | `vaultwarden:8080` | `<INGRESS_LB_IP>` |
| `<SEARXNG_HOSTNAME>` | (no compute — see §2.2) | `searxng-external:80` (no endpoints) | `<INGRESS_LB_IP>` |

All five ingresses use `IngressClass: nginx` and share the single ingress-nginx controller's LoadBalancer Service.

### 4.2 Services summary

| Service | Namespace | Type | Notes |
|---|---|---|---|
| `ingress-nginx-controller` | `ingress-nginx` | LoadBalancer | external IP `<INGRESS_LB_IP>` |
| `ingress-nginx-controller-admission` | `ingress-nginx` | ClusterIP | webhook admission |
| `matomo` | `matomo` | ClusterIP | app frontend |
| `matomo-mariadb` | `matomo` | ClusterIP | DB port 3306, internal |
| `anythingllm` | `anything-llm` | ClusterIP | |
| `n8n` | `n8n` | ClusterIP | port 5678 |
| `vaultwarden` | `vaultwarden` | ClusterIP | port 8080 |
| `searxng-external` | `searxng` | ClusterIP | no endpoints — workload absent |
| `cert-manager`, `cert-manager-webhook` | `cert-manager` | ClusterIP | |
| `kube-dns`, `cilium-agent`, `hubble-*` | `kube-system` | ClusterIP / Headless | DOKS-managed |

---

## 5. Decisions

All open scope items from the original inventory draft were resolved during the 2026-06-03 review with `@ncimino`. Decisions below shape the migration runbook.

| # | Decision area | Resolution |
|---|---|---|
| 5.1 | **New cluster K8s version** | Pin new control plane at **v1.33.1-do.2** to match source. Override `DOKS_K8S_VERSION` when invoking `cluster-backup/create-tenant-cluster.sh`; the script's default `1.30.5-do.0` is 3 minors behind source and Velero cross-restore will not cleanly carry 1.33 workloads onto a 1.30 API server. Repo note: `cli/lib/do_k8s.sh:89` defaults to 1.33.1 — the two recipes disagree, tracked separately. |
| 5.2 | **Vaultwarden** treatment | Live workload. Pattern B-equivalent — scale-to-0 write-freeze during cutover (password manager; correctness over speed). Active-user confirmation pending. |
| 5.3 | **`nextcloud`** namespace | One-off PVC snapshot to `<SPACES_BUCKET>`, then decommission. Workload is NOT carried forward to the new cluster. |
| 5.4 | **`searxng`** namespace | Drop entirely on the new cluster. SearXNG is deployed separately at the fleet level. |
| 5.5 | **metrics-server** | Installs automatically via `cluster-backup/create-tenant-cluster.sh` on rebuild. No separate install step required. |
| 5.6 | **Cilium + Hubble** continuity | Keep (DOKS default on the new cluster). |
| 5.7 | **cert-manager** version | Fresh install at ≥ v1.16 on the new cluster. Do NOT carry forward source's v1.13.0. |
| 5.8 | **ingress-nginx** image source | Start with upstream `registry.k8s.io/ingress-nginx/controller` to de-risk the move. Swap to a Minimus-hardened equivalent post-soak as a follow-up. |
| 5.9 | **`*-backup` PVCs** | Drop. Replaced going forward by Velero + DO Spaces + skinny-GFS retention (the in-cluster backup PVCs become redundant once the cluster-backup chart is deployed). |

---

## 6. Compliance mapping

| Framework | Control | How this inventory satisfies it |
|---|---|---|
| NIST CSF 2.0 | ID.AM-1 (physical devices and systems within the organization are inventoried) | Cluster, nodes, and node pool captured (§1, §1.1) |
| NIST CSF 2.0 | ID.AM-2 (software platforms and applications within the organization are inventoried) | Helm releases, container images, addon versions (§2) |
| CIS Controls v8 | 1.1 (Establish and maintain detailed enterprise asset inventory) | Workload, PVC, ingress, and service inventory (§2-§4) |
| CIS Controls v8 | 12.4 (Establish and maintain architecture diagrams) | Networking surface (§4.1) and addon topology (§2.3) |

---

## 7. Capture commands (for reproduction)

The data above was captured with read-only `kubectl` and `helm` commands against the source cluster context `<KUBECONFIG_CONTEXT>`.

```bash
# cluster + node facts
kubectl config current-context
kubectl get nodes -o wide

# namespace + workload sweep
kubectl get namespaces
kubectl get deploy,sts,pvc,ingress,svc -A

# anomaly verification
kubectl get all -n nextcloud
kubectl get all -n searxng

# helm release detail
helm list -A

# image refs per workload
kubectl get deploy,sts -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{": "}{range .spec.template.spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'
```

To re-run this inventory against the new cluster post-migration: swap the kubeconfig context to the new cluster's and re-execute. Diffing the outputs should show zero workload deltas (excluding items decommissioned per §5.3 / §5.4 / §5.9) and one infrastructure delta — the LoadBalancer external IP.

---

## 8. Document scope

**In scope:** state observation, workload identification, anomaly flagging, and the decisions captured in §5 that shape runbook authoring.

**Out of scope (covered elsewhere):** migration treatment per workload, phases, Velero install steps, DNS/TTL strategy, freeze windows, rollback procedure. These belong to the migration runbook — `(to be written — W23)` as a follow-up PR (`docs/WEOWN-APP-CLUSTER-RUNBOOK.md`). The W23 bigger-picture rationale lives in the SOW; the cross-cluster Velero mechanic in [cluster-backup/README.md](../cluster-backup/README.md).
