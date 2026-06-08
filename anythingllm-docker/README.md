# anythingllm-docker

Docker-based AnythingLLM deployment template for DigitalOcean droplets.  
This is the **non-Kubernetes** deployment path — ideal for single-node production or when DOKS is overkill.

> 📘 **Deploying a new instance? Start with the [Deployment Guide](DEPLOYMENT_GUIDE.md)** —
> the step-by-step operator flow + the full secrets/state/backup/observability model.

## Pattern status (Path C + Layer 2)

> **Canonical reference.** This template is the WeOwn Path C + Layer 2 setup,
> and the rest of the `*-docker` fleet has been migrated to match it (see the
> repo CHANGELOG). The live reference deployment is
> [`sites/s004.ccc.bot/`](sites/s004.ccc.bot/) (INT-S004).

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + migration checklist. This template's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`template/terraform/init.sh.jinja`](template/terraform/init.sh.jinja) — SSE-C, `weown-prod-state` bucket. |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1, mints v2 via Infisical API, atomically swaps the auth file, revokes v1. |
| Path C (thin cloud-init + ansible) | **Done** | Cloud-init handles only first-boot bootstrap. [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) owns compose + Caddyfile + backup cron + reconcile. [`template/scripts/deploy.sh.jinja`](template/scripts/deploy.sh.jinja) is a thin `ansible-playbook` wrapper. |
| Infisical-native tofu (`itofu.sh`) | **Done** | [`template/terraform/itofu.sh.jinja`](template/terraform/itofu.sh.jinja) runs `tofu` under `infisical run` against the operator `weown-tofu` project, injecting `TF_VAR_*` — no `terraform.tfvars` on disk. |
| Runtime image pin (`ANYTHINGLLM_IMAGE`) | **Done** | The compose image ref is injected from Infisical at runtime, so the private registry namespace stays out of this public repo and bumps need no repo change. |
| Auto DO tagging | **Done** | The template's ansible playbook calls `scripts/tag-droplet.sh` to add `skinny-backup` + `commit-<sha>` tags on each deploy. See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) "DO tag taxonomy". |

Rendered sites (full registry in [`sites/README.md`](sites/README.md)):

- [`sites/s004.ccc.bot/`](sites/s004.ccc.bot/) — **INT-S004, live** (the reference deployment).
- [`sites/ai.weown.agency/`](sites/ai.weown.agency/) — INT-P01, DOKS → Docker migration in flight.
- [`sites/s004/`](sites/s004/) — ⚠️ retired (the original locked-out box; do not deploy).

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Caddy     │  │           AnythingLLM               │  │
│  │  (Reverse   │  │        (AI Assistant)               │  │
│  │   Proxy)    │  │                                     │  │
│  │ :80, :443   │  │  • RAG document ingestion           │  │
│  │             │  │  • OpenRouter LLM integration       │  │
│  │             │  │  • LanceDB vector storage           │  │
│  │             │  │  • Multi-workspace support          │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                      anythingllmnet                         │
└─────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Docker Compose** (not K8s) — simpler ops, lower cost, no cluster management
- **LanceDB embedded** — zero-config vector DB, no separate container
- **Infisical runtime injection** — application secrets never touch disk
- **Caddy** — automatic TLS via Let's Encrypt, HTTP/3, security headers
- **Skinny backups** — volume-based backups with grandfather-father-son retention

## Prerequisites

- [DigitalOcean](https://m.do.co/c/2d7b0b6d4d0d) account with API token
- SSH key uploaded to DigitalOcean (Account → Security → SSH Keys)
- Domain with DNS A record pointing to the droplet IP
- [Infisical](https://infisical.com) account with a Machine Identity

## Quick Start

> The full operator flow — the two-project Infisical secrets model, OpenTofu
> state, backups, observability — is in **[`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md)**.
> This Quick Start only covers rendering a new site from the template.

### 1. Install copier

```bash
pip install copier
```

### 2. Render a new site

Sites live under [`sites/<domain>/`](sites/) — one directory per deployment:

```bash
cd anythingllm-docker
copier copy . sites/<domain> \
  --data project_name=<short-slug> \
  --data domain=<domain> \
  --defaults --trust
```

The generated site already includes `ansible/`, `terraform/` (with `backend.tf`,
`init.sh`, `itofu.sh`), `docker/`, and `scripts/` — Path C + Layer 2 by default.
The container image is **not** a render-time value; it is injected at runtime from
Infisical (`ANYTHINGLLM_IMAGE`).

### 3. Deploy

Follow [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md). In brief: push the app secrets
to the site's Infisical project, set the `TF_VAR_*` infra creds in the operator
`weown-tofu` project, provision with `terraform/itofu.sh` (no `terraform.tfvars`
on disk), then `./site.sh deploy`.

The `site.sh` wrapper auto-detects the droplet IP from tofu output and reads
`INFISICAL_PROJECT_ID` from `site.conf`, so you don't need to pass env vars or
look up the IP manually.

**Alternative:** You can still use the scripts directly:

```bash
./scripts/deploy.sh root@<ip>
```

#### Required app secrets (Infisical)

| Secret Key | Required | Notes |
|---|---|---|
| `JWT_SECRET` | **Yes** | `openssl rand -hex 32` — set once, never rotate |
| `OPENROUTER_API_KEY` | **Yes** | OpenRouter key (`sk-or-v1-...`) |
| `ANYTHINGLLM_IMAGE` | **Yes** | Image ref (e.g. `reg.mini.dev/<ns>/anythingllm:v1.12.1`) — kept in Infisical, not in git |
| `ADMIN_EMAIL` | **Yes** | Admin notification email |
| `SPACES_ACCESS_KEY` / `SPACES_SECRET_KEY` | **Yes** | DO Spaces creds for backups |
| `OPS_AUTHORIZED_KEYS` | No | Team SSH public keys (one per line) |

## Infisical Security Model

Two Infisical projects, by design (full rationale in
[`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) §3):

```text
weown-tofu (operator project)            site app project (per deployment)
  └─ TF_VAR_* infra creds                  └─ OPENROUTER_API_KEY, JWT_SECRET,
       │  injected by itofu.sh                  ANYTHINGLLM_IMAGE, ADMIN_EMAIL, …
       ▼                                            │ read at runtime by the
   tofu provisions the droplet                      ▼ droplet's Machine Identity
                                       `infisical run -- docker compose up`
                                                     │
                                                     ▼
                                             Container environment
                                             (secrets in RAM only)
```

**What this achieves:**

- **Zero application secrets on disk** — only the Machine Identity reaches the node (Layer 2 rotates even that on first boot); infra creds are injected as `TF_VAR_*` by `itofu.sh`, never written to `terraform.tfvars`.
- **Runtime injection** — secrets fetched at container start, live in process memory only.
- **To pick up a changed secret, re-run `./scripts/deploy.sh`** — it recreates the container so `infisical run` re-injects. A bare `docker compose restart` reuses the **old** env and will not.
- **Centralized management** — edit a secret in Infisical; the next deploy picks it up.

## Directory Structure

```text
anythingllm-docker/
├── copier.yaml                    # Copier template configuration
├── template/                      # Template files (rendered by copier)
│   ├── terraform/                     # Layer 1 — provisioning
│   │   ├── main.tf.jinja              # Droplet, reserved IP, firewall
│   │   ├── variables.tf.jinja         # Input variables (no app secrets)
│   │   ├── outputs.tf.jinja           # Droplet IP, domain, etc.
│   │   ├── monitoring.tf.jinja        # DO monitoring alerts
│   │   ├── versions.tf                # OpenTofu version constraints
│   │   ├── backend.tf.jinja           # DO Spaces remote state (SSE-C)
│   │   ├── init.sh.jinja              # tofu init w/ Spaces backend-config
│   │   ├── itofu.sh.jinja             # tofu under `infisical run` (weown-tofu, TF_VAR_*)
│   │   ├── terraform.tfvars.example.jinja  # local-dev fallback only
│   │   └── templates/
│   │       └── cloud-init.yaml.jinja  # SLIM first-boot bootstrap + Layer 2 rotation
│   ├── docker/
│   │   ├── compose.prod.yaml.jinja    # Production stack (image from Infisical)
│   │   └── Caddyfile.jinja            # Reverse proxy + TLS
│   ├── ansible/
│   │   └── deploy.yml.jinja           # Path C app layer — compose/Caddy/backup reconcile
│   ├── scripts/
│   │   ├── deploy.sh.jinja            # Ansible wrapper (app layer + every update)
│   │   ├── backup.sh.jinja            # Skinny volume backup
│   │   └── restore.sh.jinja           # Restore from backup
│   ├── .gitignore
│   ├── README.md.jinja
│   └── CHANGELOG.md.jinja
└── README.md                    # This file
```

## Backup Strategy

### Grandfather-Father-Son Retention

| Backup Type | Retention |
|-------------|-----------|
| Daily | 30 days |
| Monthly (1st of month) | 12 months |
| Yearly (Jan 1st) | Forever |

### Execution

Backups run daily via `/etc/cron.daily/anythingllm-backup` and are executed **within `infisical run`** so DO Spaces credentials are available from Infisical.

```bash
# Manual backup
./scripts/backup.sh root@your-droplet-ip

# Manual restore
./scripts/restore.sh root@your-droplet-ip anythingllm_backup_20260115_120000
```

## Migration from Helm/Kubernetes

The live INT-P01 (`ai.weown.agency`) DOKS → Docker migration is **automated** by
`sites/ai.weown.agency/scripts/migrate-from-doks.sh` — it `kubectl exec`s into the
pod, streams `/app/server/storage` out as a tarball, and wraps it in the same
skinny-backup layout `restore.sh` already understands (see that site's
[`MIGRATION_RUNBOOK.md`](sites/ai.weown.agency/MIGRATION_RUNBOOK.md) and
[`ADR-005`](../.github/ADR-005-int-p01-doks-retirement.md)). The manual steps
below are a generic fallback for migrating some other Helm instance by hand
(`aiweowndev` is just an example project name):

### 1. Export data from K8s

```bash
# Scale down to prevent writes
kubectl scale deployment anythingllm --replicas=0 -n anything-llm

# Backup PVC contents
kubectl run backup-helper --rm -i --tty \
  --image=alpine:3.19 \
  --overrides='{"spec": {"volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "anythingllm-storage"}}]}}' \
  -- tar czf - -C /data . > anythingllm-storage-backup.tar.gz
```

### 2. Transfer and restore

```bash
# Copy to new droplet
scp anythingllm-storage-backup.tar.gz root@new-droplet:/opt/aiweowndev/backups/

# Restore into Docker volume
ssh root@new-droplet
cd /opt/aiweowndev/backups
docker run --rm \
  -v aiweowndev_storage:/data \
  -v $(pwd):/backup:ro \
  alpine:3.19 \
  tar xzf /backup/anythingllm-storage-backup.tar.gz -C /data
```

### 3. Migrate secrets to Infisical

```bash
# Get existing K8s secrets
kubectl get secret anythingllm-secrets -n anything-llm -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'

# Add each to Infisical Dashboard → Secrets (same key names)
```

## Security & Compliance

- **NIST CSF 2.0**: PR.DS (data security), PR.AC (access control), DE.CM (monitoring)
- **CIS Controls v8 IG1**: CIS 3.11 (encrypt sensitive data at rest), CIS 4.1 (secure config)
- **ISO 27001-ready**: A.5.17 (authentication info), A.8.24 (use of cryptography)

### Security Features

- No application secrets in git or on disk; runtime injection only
- Fail-loud compose guards — the stack refuses to boot without `JWT_SECRET`, `OPENROUTER_API_KEY`, or `ANYTHINGLLM_IMAGE`
- App port bound to `127.0.0.1` — only Caddy (80/443) is internet-facing; reserved static IP
- Firewall: 22 (SSH), 80 (HTTP/ACME), 443 (HTTPS/QUIC)
- Automatic security updates via `unattended-upgrades`
- Docker daemon: log rotation, overlay2, json-file logging
- Caddy: automatic TLS, HTTP/3, security headers

### Infisical Outage Procedures

If Infisical Cloud becomes unavailable, deployments and backups will fail. See [INFISICAL_OUTAGE_RUNBOOK.md](../docs/INFISICAL_OUTAGE_RUNBOOK.md) for emergency procedures including:

- Manual deployment without Infisical
- Local-only backup creation
- Emergency restore procedures
- Recovery steps when Infisical comes back online

## Observability

Each droplet runs an OTel collector agent that ships host metrics + Caddy access
logs to **SigNoz Cloud**. It is deployed separately by the fleet scripts
([`scripts/bootstrap-otel-agent.sh`](../scripts/bootstrap-otel-agent.sh),
[`scripts/deploy-otel-fleet.sh`](../scripts/deploy-otel-fleet.sh), tag `weown-ai`)
and reads its endpoint/key from the shared `otel` Infisical project via that
project's reader Machine Identity — distinct from each box's app Machine Identity.
See [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) §9.

## Related Projects

| Project | Runtime | Purpose |
|---------|---------|---------|
| `ai/anythingllm` | Kubernetes (Helm) | Original K8s deployment — being retired (INT-P01, [ADR-005](../.github/ADR-005-int-p01-doks-retirement.md)) |
| `ai/keycloak-docker` | Docker Compose | SSO / identity provider |
| `ai/wordpress-docker` | Docker Compose | CMS deployments |

## Known Limitations

- **OIDC/SSO**: AnythingLLM does not natively support OIDC/OAuth2 login via Keycloak. A token hand-off strategy or reverse-proxy auth may be required for SSO integration. See `ai/keycloak-docker` for our Keycloak deployment.

## License

MIT — See [LICENSE](../LICENSE) in the repository root.
