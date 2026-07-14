# claw-weown-dev - OpenClaw AI Assistant Deployment

Production-ready OpenClaw deployment using Docker Compose on DigitalOcean droplets.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Caddy     │  │           OpenClaw               │  │
│  │  (Reverse   │  │        (AI Assistant)               │  │
│  │   Proxy)    │  │                                     │  │
│  │ :80, :443   │  │  • RAG document ingestion           │  │
│  │             │  │  • OpenRouter LLM integration       │  │
│  │             │  │  • LanceDB vector storage (embedded)│  │
│  │             │  │  • Multi-workspace support          │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                      openclawnet                         │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **OpenClaw AI Assistant** - Full-featured RAG platform with document chat
- **OpenRouter Integration** - Multi-provider LLM gateway (Anthropic, OpenAI, Mistral, etc.)
- **LanceDB** - Embedded vector database (zero-config, no separate container needed)
- **Caddy Reverse Proxy** - Automatic TLS via Let's Encrypt
- **Infisical Integration** - Runtime secret injection (no secrets on disk)
- **Skinny Backups** - Volume-based backups with grandfather-father-son retention
- **DigitalOcean Spaces** - Offsite backup storage
- **Idempotent Deployments** - Re-running deploy scripts is a no-op if nothing changed

## Prerequisites

- DigitalOcean account with API token
- SSH key for droplet access
- Domain configured with DNS A record pointing to droplet IP
- Infisical account with Machine Identity configured

## Quick Start

### 1. Create a new deployment from template

```bash
# Install copier if not already installed
pip install copier

# Create a new OpenClaw deployment
cd openclaw-docker
copier copy . ../openclaw-ai --data-file answers.yaml
```

### 2. Configure your deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: openclaw-ai
domain: ai.weown.dev
do_region: atl1
droplet_size: s-2vcpu-4gb-amd
infisical_project_id: your-project-id
```

### 3. Set up Infisical secrets

Before deploying, create the following secrets in your Infisical project:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw API gateway authentication token | Yes |
| `OPENROUTER_API_KEY` | OpenRouter API key (`sk-or-v1-...`) for LLM inference | Yes |
| `SIGNOZ_INGESTION_KEY` | SigNoz Cloud ingestion key for OTel telemetry | Yes |
| `MINIMUS_TOKEN` | Minimus registry token for `reg.mini.dev` image pulls | No |
| `PROXY_SERVER` | HTTP proxy URL for outbound traffic | No |
| `SPACES_ACCESS_KEY` | DO Spaces key for backups | No |
| `SPACES_SECRET_KEY` | DO Spaces secret for backups | No |

### 4. Provision infrastructure (terraform — first-boot bootstrap)

```bash
cd ../claw-weown-dev/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: DO token, SSH fingerprint, Spaces keys,
# Machine Identity Client ID + Client Secret, Infisical project ID.
chmod +x ./init.sh
./init.sh        # configures the DO Spaces state backend with Spaces creds
tofu plan
tofu apply       # creates droplet; cloud-init bootstraps Docker + Infisical
                 # CLI + rotates the bootstrap secret (Layer 2)
```

Cloud-init takes ~3 minutes. When `tofu apply` returns, the droplet has
Docker + Infisical CLI installed and the Machine Identity bootstrap secret
has been rotated. **Verify the rotation succeeded:**

```bash
ssh root@<droplet-ip> 'tail /var/log/claw_weown_dev-rotation.log'
# Expected last line: "===== Rotation complete ====="
```

If you see `ROTATION FAILED:` instead, follow the manual rotation runbook
in [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md).

### 5. Deploy the application (ansible — app layer + every subsequent update)

```bash
cd ..
INFISICAL_PROJECT_ID=<your-project-id> ./scripts/deploy.sh root@<droplet-ip>
```

This uploads compose.yaml, Caddyfile, backup.sh, installs the daily backup
cron + logrotate, pulls images, runs `docker compose up -d`, and updates
DO droplet tags (skinny-backup + commit-\<sha\>). **Idempotent — re-run any
time you change compose/Caddy/backup files. No terraform needed.**

### Updating the deployment

| Change | How to apply |
|---|---|
| compose.yaml, Caddyfile, backup.sh, scripts | `./scripts/deploy.sh root@<ip>` — ansible re-uploads + reconciles. No terraform. |
| Container image bump (terraform var) | Edit `terraform/variables.tf` default + `docker/compose.prod.yaml`. `tofu apply` is a no-op (user_data ignored). Run `./scripts/deploy.sh` to redeploy. |
| Cloud-init contents | Requires `tofu taint digitalocean_droplet.openclaw && tofu apply`. **Droplet downtime + volume considerations apply.** |
| Infisical project secrets | Edit in Infisical UI. `docker compose restart` on the droplet to pick up. |
| Machine Identity rotation | See manual runbook in [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md). |

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md)
for the architecture rationale (Path C bootstrap + Layer 2 secret rotation).

## Infisical Security Model

This template uses **runtime secret injection** — the gold standard for Docker deployments:

```
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
- **Runtime injection** — secrets are fetched at container start, live in process memory only
- **No container rebuilds for rotation** — restart the container, new secrets flow in
- **Automatic sync** — Infisical CLI checks for updated secrets on every deploy

## Backup Strategy

### Skinny Backups (Volume-Based)

Backups run daily via cron and use a **grandfather-father-son** retention policy:

| Backup Type | Retention |
|-------------|-----------|
| Daily | 30 days |
| Monthly (1st of month) | 12 months |
| Yearly (Jan 1st) | Forever |

### Local + Remote Storage

- **Local**: Stored on droplet at `/opt/claw_weown_dev/backups/`
- **Remote**: Uploaded to DigitalOcean Spaces for offsite durability

### Manual Backup

```bash
./scripts/backup.sh root@your-droplet-ip
```

The script will prompt to pull the backup to your local machine.

### Restore

```bash
# Restore from local backup on droplet
./scripts/restore.sh root@your-droplet-ip claw-weown-dev_backup_20260115_120000

# The restore script will automatically fetch from DO Spaces if the backup
# is not found locally.
```

## Migration from Helm/Kubernetes

If you're migrating from the existing `ai/openclaw` Helm-based deployment:

### Data Migration

1. **Export data from Kubernetes**:

   ```bash
   # Scale down to prevent writes
   kubectl scale deployment openclaw --replicas=0 -n anything-llm

   # Create a backup tarball of the storage PVC
   kubectl run backup-helper --rm -i --tty \
     --image=alpine:3.19 \
     --overrides='{"spec": {"volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "openclaw-storage"}}]}}' \
     -- tar czf - -C /data . > openclaw-storage-backup.tar.gz
   ```

2. **Transfer to new droplet**:

   ```bash
   scp openclaw-storage-backup.tar.gz root@new-droplet-ip:/opt/claw_weown_dev/backups/
   ssh root@new-droplet-ip
   cd /opt/claw_weown_dev/backups
   tar xzf openclaw-storage-backup.tar.gz
   ```

3. **Restore into Docker volume**:

   ```bash
   docker run --rm \
     -v claw_weown_dev_storage:/data \
     -v /opt/claw_weown_dev/backups:/backup:ro \
     alpine:3.19 \
     tar xzf /backup/openclaw-storage-backup.tar.gz -C /data
   ```

### Secret Migration

Move secrets from Kubernetes to Infisical:

```bash
# Get existing secrets from K8s
kubectl get secret openclaw-secrets -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'

# Add each to Infisical Dashboard → Secrets
# OpenClaw needs: OPENCLAW_GATEWAY_TOKEN, OPENROUTER_API_KEY, SIGNOZ_INGESTION_KEY
```

## Secrets Update Process

To update secrets without rebuilding:

```bash
# Update the secret in Infisical Dashboard, then redeploy
./scripts/deploy.sh root@your-droplet-ip
```

The deploy script restarts containers, which triggers a fresh `infisical run` and picks up the latest secrets.

## Idempotency

Both OpenTofu and deployment scripts are idempotent:

- **OpenTofu**: Re-running `tofu apply` after infrastructure exists will show no changes
- **Deploy script**: Re-running will only restart services if compose files changed
- **Infisical login**: Safe to run multiple times (cached token)

## Security

- **No secrets in git** — terraform.tfvars only contains Machine Identity, not app secrets
- **No secrets on disk** — application secrets live in Infisical and process memory only
- **TLS automatically managed** by Caddy (Let's Encrypt)
- **Firewall** restricts access to ports 80, 443, 22
- **Resource limits** on all containers
- **Security headers** enforced by Caddy

## Monitoring

DigitalOcean monitoring alerts are configured for:

- CPU usage > 80%
- Memory usage > 90%
- Disk usage > 85%

## Support

For issues or questions, open a GitHub issue in the `WeOwnNetwork/ai` repository.
