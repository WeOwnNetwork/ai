# openclaw-docker

Docker-based OpenClaw deployment template for DigitalOcean droplets.  
This is the **non-Kubernetes** deployment path — ideal for single-node production or when DOKS is overkill.

## Migration status (bootstrap pattern)

> **Reference implementation.** This template is the canonical Path C +
> Layer 2 setup; [`sites/s004/`](sites/s004/) is the rendered output for the
> first deployment, and the other `*-docker` templates should migrate to
> match this shape (see [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md)).

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`template/terraform/init.sh.jinja`](template/terraform/init.sh.jinja). |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1, mints v2 via Infisical API, atomically swaps the auth file, revokes v1. |
| Path C (thin cloud-init + ansible) | **Done** | Cloud-init handles only first-boot bootstrap. [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) owns compose + Caddyfile + backup cron + reconcile. [`template/scripts/deploy.sh.jinja`](template/scripts/deploy.sh.jinja) is a thin `ansible-playbook` wrapper. |
| Infisical CLI install | **Current** — uses `artifacts-cli.infisical.com` apt repo. |
| Auto DO tagging | **Done** | The template's ansible playbook calls `scripts/tag-droplet.sh` to add `skinny-backup` + `commit-<sha>` tags on each deploy. See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) "DO tag taxonomy". |

Rendered sites:

- [`sites/s004/`](sites/s004/) — first OpenClaw deployment (Story 004).

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Caddy     │  │           OpenClaw               │  │
│  │  (Reverse   │  │        (AI Assistant)               │  │
│  │   Proxy)    │  │                                     │  │
│  │ :80, :443   │  │  • RAG document ingestion           │  │
│  │             │  │  • OpenRouter LLM integration       │  │
│  │             │  │  • LanceDB vector storage           │  │
│  │             │  │  • Multi-workspace support          │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                      openclawnet                         │
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

### 1. Install copier

```bash
pip install copier
```

### 2. Create a new deployment

```bash
cd ai/openclaw-docker
copier copy . ../ai-weown-dev --data-file answers.yaml
```

Or use interactive prompts:

```bash
copier copy . ../ai-weown-dev
```

### 3. Configure Infisical secrets

Before deploying infrastructure, create these secrets in your Infisical project:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw API gateway auth token | **Yes** |
| `OPENROUTER_API_KEY` | OpenRouter API key (`sk-or-v1-...`) | **Yes** |
| `SIGNOZ_INGESTION_KEY` | SigNoz Cloud ingestion key for OTel telemetry | **Yes** |
| `MINIMUS_TOKEN` | Minimus registry token for `reg.mini.dev` image pulls | No |
| `PROXY_SERVER` | HTTP proxy for outbound traffic | No |
| `SPACES_ACCESS_KEY` | DO Spaces key for backups | No |
| `SPACES_SECRET_KEY` | DO Spaces secret for backups | No |

### 4. Deploy infrastructure

```bash
cd ../ai-weown-dev/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (only Infisical Machine Identity + DO token)
tofu init
tofu plan
tofu apply
```

### 5. Deploy application

```bash
cd ../scripts
chmod +x deploy.sh
./deploy.sh root@$(tofu output -raw droplet_ip)
```

## Infisical Security Model

This template uses **runtime secret injection** — the gold standard for Docker deployments:

```text
terraform.tfvars ──► droplet ──► cloud-init ──► Infisical Machine Identity
                                                     │
                                                     ▼
                                             Infisical Cloud API
                                                     │
                                                     ▼
                                             Application Secrets
                                             (OPENCLAW_GATEWAY_TOKEN,
                                              OPENROUTER_API_KEY,
                                              SIGNOZ_INGESTION_KEY, etc.)
                                                     │
                                                     ▼
                                      `infisical run -- docker compose up`
                                                     │
                                                     ▼
                                             Container Environment
                                             (secrets in RAM only)
```

**What this achieves:**

- **Zero application secrets on disk** — only the Infisical Machine Identity is stored on the node
- **Runtime injection** — secrets fetched at container start, live in process memory only
- **No rebuilds for rotation** — restart container, new secrets flow in
- **Centralized management** — rotate secrets in Infisical, all droplets pick up changes on next deploy

## Directory Structure

```text
openclaw-docker/
├── copier.yaml                    # Copier template configuration
├── template/                      # Template files (rendered by copier)
│   ├── terraform/
│   │   ├── main.tf.jinja          # Droplet, reserved IP, firewall
│   │   ├── variables.tf.jinja     # Input variables (no app secrets)
│   │   ├── outputs.tf.jinja       # Droplet IP, domain, etc.
│   │   ├── monitoring.tf.jinja    # DO monitoring alerts
│   │   ├── versions.tf            # OpenTofu version constraints
│   │   ├── terraform.tfvars.example
│   │   └── templates/
│   │       └── cloud-init.yaml.jinja  # Bootstrap: Docker, Infisical, compose
│   ├── docker/
│   │   ├── compose.prod.yaml.jinja    # Production stack
│   │   └── Caddyfile.jinja            # Reverse proxy + TLS
│   ├── scripts/
│   │   ├── deploy.sh.jinja            # Deploy / update stack
│   │   ├── backup.sh.jinja            # Skinny volume backup
│   │   └── restore.sh.jinja           # Restore from backup
│   ├── ansible/                       # Future: configuration management
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

Backups run daily via `/etc/cron.daily/openclaw-backup` and are executed **within `infisical run`** so DO Spaces credentials are available from Infisical.

```bash
# Manual backup
./scripts/backup.sh root@your-droplet-ip

# Manual restore
./scripts/restore.sh root@your-droplet-ip openclaw_backup_20260115_120000
```

## Migration from Helm/Kubernetes

If migrating from the existing `ai/openclaw` Helm chart:

### 1. Export data from K8s

```bash
# Scale down to prevent writes
kubectl scale deployment openclaw --replicas=0 -n anything-llm

# Backup PVC contents
kubectl run backup-helper --rm -i --tty \
  --image=alpine:3.19 \
  --overrides='{"spec": {"volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "openclaw-storage"}}]}}' \
  -- tar czf - -C /data . > openclaw-storage-backup.tar.gz
```

### 2. Transfer and restore

```bash
# Copy to new droplet
scp openclaw-storage-backup.tar.gz root@new-droplet:/opt/aiweowndev/backups/

# Restore into Docker volume
ssh root@new-droplet
cd /opt/aiweowndev/backups
docker run --rm \
  -v aiweowndev_storage:/data \
  -v $(pwd):/backup:ro \
  alpine:3.19 \
  tar xzf /backup/openclaw-storage-backup.tar.gz -C /data
```

### 3. Migrate secrets to Infisical

```bash
# Get existing K8s secrets
kubectl get secret openclaw-secrets -n anything-llm -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'

# Add each to Infisical Dashboard → Secrets (same key names)
```

## Security & Compliance

- **NIST CSF 2.0**: PR.DS (data security), PR.AC (access control), DE.CM (monitoring)
- **CIS Controls v8 IG1**: CIS 3.11 (encrypt sensitive data at rest), CIS 4.1 (secure config)
- **ISO 27001-ready**: A.5.17 (authentication info), A.8.24 (use of cryptography)

### Security Features

- No application secrets in git or on disk
- Firewall: 22 (SSH), 80 (HTTP/ACME), 443 (HTTPS/QUIC)
- Automatic security updates via `unattended-upgrades`
- Docker daemon: log rotation, overlay2, json-file logging
- Caddy: automatic TLS, HTTP/3, security headers

## Related Projects

| Project | Runtime | Purpose |
|---------|---------|---------|
| `ai/openclaw` | Kubernetes (Helm) | Original K8s deployment |
| `ai/keycloak-docker` | Docker Compose | SSO / identity provider |
| `ai/wordpress-docker` | Docker Compose | CMS deployments |

## Known Limitations

- **OIDC/SSO**: OpenClaw does not natively support OIDC/OAuth2 login via Keycloak. A token hand-off strategy or reverse-proxy auth may be required for SSO integration. See `ai/keycloak-docker` for our Keycloak deployment.

## License

MIT — See [LICENSE](../LICENSE) in the repository root.

---

## Secret injection pattern

Secrets reach this service at runtime via Infisical. The standard is documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md` → Runtime secret injection](../docs/INFRA_BOOTSTRAP_PATTERN.md#runtime-secret-injection)
and [`.github/ADR-006-in-container-infisical-injection.md`](../.github/ADR-006-in-container-infisical-injection.md):
host-side `infisical run` wrap today (refresh on **redeploy**, not on a bare `docker restart`) →
moving toward **in-container `infisical run`** for bounce-to-refresh, with auto-reload, automatic
rotation, single-use tokens, and a clean K8s/K3s migration. No app secrets on disk or in git
(D247); only the project-scoped Machine Identity lives on the node.
