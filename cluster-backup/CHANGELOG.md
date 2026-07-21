# cluster-backup — Changelog

All notable changes to this Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-22

### Added

- Initial release of `cluster-backup` Helm chart.
- Velero v1.12.2 server Deployment with metrics on port 8085 and a paired
  `ClusterIP` Service so the included ServiceMonitor and the `kubectl
  port-forward` workflow documented in `NOTES.txt` both have a Service to
  target.
- Restic / node-agent DaemonSet for filesystem-level PVC backup. Mounts only
  the kubelet pod-volume root (`/var/lib/kubelet/pods`); the prior host-root
  (`/`) mount has been removed.
- `BackupStorageLocation`, `VolumeSnapshotLocation`, and three default
  `Schedule` CRs (daily / weekly / monthly) plus per-app schedules for
  anythingllm / wordpress / vaultwarden / n8n.
- Cluster-scoped RBAC for both Velero and Restic, scoped to the resource
  verbs each controller actually issues against the API server.
- Zero-trust NetworkPolicy: ingress from `ingress-nginx`, `monitoring`, and
  same-namespace metrics scraping only; egress to kube-system DNS, external
  S3-compatible storage (excluding RFC1918 / link-local / loopback), and the
  Kubernetes API server only.
- ServiceMonitor for Prometheus, with metric/label relabelings preserved
  from the original implementation.
- Three shell helpers — `deploy.sh`, `verify.sh`, `test-local.sh`,
  `create-tenant-cluster.sh` — for guided installation, post-install
  verification, local end-to-end testing on minikube/kind via MinIO, and DO
  tenant-cluster bootstrap.

### Security

- ServiceAccount `automountServiceAccountToken` is `true` for both Velero
  and Restic (they need in-cluster API access). The previous `false` value
  would have prevented backup/restore controllers from functioning.
- Pod Security Context applies `runAsNonRoot`, `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and the
  `RuntimeDefault` seccomp profile (Velero server). The Restic DaemonSet
  retains a `SYS_ADMIN` capability add — required for restic's pod-volume
  mount operations — and is therefore operationally bounded to clusters
  whose Pod Security Standard for the `velero` namespace is `baseline` or
  looser (not `restricted`). Tighten in a follow-up if your environment
  requires `restricted`.
- S3 credentials are deliberately NOT rendered by the chart. `deploy.sh`
  prompts interactively (`read -rs` for the secret key) and writes the
  Secret via `kubectl create secret … --dry-run=client | kubectl apply -f -`
  using `mktemp` for the on-disk staging file with a `trap … EXIT` cleanup
  so the credential never lives at a predictable path.
- `helm` is no longer told to install the upstream `vmware-tanzu/velero`
  subchart as a dependency. Both stacks would render Velero workloads and
  collide; this chart provides its own templates exclusively.

### Notes for operators

- Run `deploy.sh` (or otherwise create the
  `<release>-cluster-backup-cloud-credentials` Secret in the `velero`
  namespace) BEFORE the `BackupStorageLocation` and
  `VolumeSnapshotLocation` will reach `Available` phase. The chart
  intentionally does not render this Secret.
- Use the Velero CLI for all CR mutations
  (`velero backup create`, `velero restore create`, `velero schedule get`).
  `kubectl create backup …` is not a valid kubectl subcommand.
