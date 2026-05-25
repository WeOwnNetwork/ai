# s004-anythingllm - AnythingLLM AI Assistant Deployment

Production-ready AnythingLLM deployment using Docker Compose on DigitalOcean droplets.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Caddy     │  │           AnythingLLM               │  │
│  │  (Reverse   │  │        (AI Assistant)               │  │
│  │   Proxy)    │  │                                     │  │
│  │ :80, :443   │  │  • RAG document ingestion           │  │
│  │             │  │  • OpenRouter LLM integration       │  │
│  │             │  │  • LanceDB vector storage (embedded)│  │
│  │             │  │  • Multi-workspace support          │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                      anythingllmnet                         │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **AnythingLLM AI Assistant** - Full-featured RAG platform with document chat
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

## Deployment model — Path C (thin cloud-init + Ansible app layer)

This deployment uses the **two-layer bootstrap pattern** documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md).
Read that document first if you're new to the pattern.

- **Cloud-init** (`terraform/templates/cloud-init.yaml`) handles first-boot
  bootstrap only: Docker, Infisical CLI, the Machine Identity auth file, and
  the Layer 2 bootstrap-secret rotation. Edits to it require destroying and
  recreating the droplet (because `lifecycle { ignore_changes = [user_data] }`).
- **Ansible playbook** (`ansible/deploy.yml`) owns everything else: compose,
  Caddyfile, backup script, cron, and `docker compose up`. Re-runnable any
  time without touching terraform.

## Quick Start

### 1. Set up Infisical secrets

Create the following secrets in your Infisical project:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `OPENROUTER_API_KEY` | Your OpenRouter API key (`sk-or-v1-...`) | Yes |
| `JWT_SECRET` | Random hex string for JWT signing (`openssl rand -hex 32`) | Yes |
| `ADMIN_EMAIL` | Admin notification email | Yes |
| `OPENROUTER_MODEL_PREF` | Default LLM model (e.g., `anthropic/claude-opus-4.5`) | No |
| `OPENROUTER_TIMEOUT_MS` | API timeout in ms (default: `3000`) | No |
| `EMBEDDING_ENGINE` | `native` or `openrouter` (default: `native`) | No |
| `EMBEDDING_MODEL_PREF` | Specific embedding model ID | No |
| `AUTH_TOKEN` | Auth token for multi-user mode | No |
| `AUTH_MODE` | Authentication mode | No |
| `ALLOW_MULTI_WORKSPACE` | Enable multi-workspace (`true`/`false`) | No |
| `SPACES_ACCESS_KEY` | DO Spaces key for backups | No |
| `SPACES_SECRET_KEY` | DO Spaces secret for backups | No |

Then create a **Machine Identity** for the droplet to use:

1. Infisical Dashboard → Organization → **Machine Identities** → Create.
2. Auth method: **Universal Auth**.
3. Add it to your project with **Viewer** role on the **prod** env.
4. Generate a Client Secret (shown once — copy immediately).
5. **Important for Layer 2 rotation:** at the org level, grant this identity
   permission to manage its own Universal Auth client secrets. If your
   Infisical org doesn't support this, automated rotation will fail and
   the manual rotation runbook (below) applies instead.

### 2. Provision infrastructure (terraform)

```bash
cd s004-deployment/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: DO token, SSH fingerprint, Spaces keys,
# Machine Identity client ID + client secret, project ID.
./init.sh        # configures S3 backend with Spaces credentials (one-time)
tofu plan
tofu apply       # creates droplet; cloud-init bootstraps + rotates
```

Cloud-init takes ~3 minutes. When `tofu apply` returns, the droplet is up
and the Layer 2 rotation has run.

**Verify Layer 2 rotation succeeded:**

```bash
ssh root@<droplet-ip> 'tail /var/log/s004anythingllm-rotation.log'
# Expected last line: "===== Rotation complete ====="
```

If you see `ROTATION FAILED:` instead, follow the
[Manual bootstrap-secret rotation runbook](#manual-bootstrap-secret-rotation-runbook)
below.

### 3. Deploy the application (ansible)

```bash
cd ../scripts
INFISICAL_PROJECT_ID=<your-project-id> ./deploy.sh root@<droplet-ip>
```

This uploads compose.yaml, Caddyfile, backup.sh, installs the daily backup
cron, pulls images, and runs `docker compose up -d`. Idempotent — re-run any
time you change those files.

### 4. Verify

```bash
curl -I https://<your-domain>/      # 200 or 301 from Caddy
ssh root@<droplet-ip> 'docker compose -f /opt/s004anythingllm/compose.yaml ps'
```

## Updating the deployment

| Change | How to apply |
|---|---|
| compose.yaml, Caddyfile, backup.sh, scripts | `./scripts/deploy.sh root@<ip>` — ansible re-uploads + reconciles. No terraform. |
| Container image bump (terraform var) | Edit `terraform/variables.tf` default + `docker/compose.prod.yaml`. `tofu apply` is a no-op (user_data ignored). Run `./scripts/deploy.sh` to redeploy. |
| Cloud-init contents | Requires `tofu taint digitalocean_droplet.anythingllm && tofu apply`. **Droplet downtime + volume considerations apply.** |
| Infisical project secrets (OPENROUTER_API_KEY etc.) | Edit in Infisical UI. `docker compose restart` on the droplet to pick up. |
| Machine Identity rotation | See manual runbook below. |

## Manual bootstrap-secret rotation runbook

If `/var/log/s004anythingllm-rotation.log` shows automated rotation failed
(or for routine rotation later):

1. Confirm the current secret on the droplet still works:

   ```bash
   ssh root@<droplet> 'source /opt/s004anythingllm/.infisical-auth.env && \
     infisical login --method=universal-auth \
       --clientId="$INFISICAL_CLIENT_ID" \
       --clientSecret="$INFISICAL_CLIENT_SECRET" --silent && echo OK'
   ```

2. In the Infisical UI: **Project → Identities → \<your-bootstrap-identity\>
   → Client Secrets → Create**. Copy the new secret immediately.
3. SSH to the droplet, atomically swap the auth file:

   ```bash
   ssh root@<droplet>
   sudo -i
   cd /opt/s004anythingllm
   cp .infisical-auth.env .infisical-auth.env.backup
   # Edit .infisical-auth.env, update INFISICAL_CLIENT_SECRET to the new value
   nano .infisical-auth.env
   # Verify new secret works:
   source .infisical-auth.env
   infisical login --method=universal-auth \
     --clientId="$INFISICAL_CLIENT_ID" \
     --clientSecret="$INFISICAL_CLIENT_SECRET" --silent && echo OK
   rm .infisical-auth.env.backup
   touch .rotation-complete  # marker so cloud-init re-runs don't try again
   chmod 0600 .rotation-complete
   ```

4. In the Infisical UI: **revoke the old client secret** (the one that was
   in `terraform.tfvars` before this rotation).

After step 4, the v1 secret in terraform state and DO metadata is dead.

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
                                              (OPENROUTER_API_KEY,
                                               JWT_SECRET, etc.)
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

- **Local**: Stored on droplet at `/opt/s004-anythingllm/backups/`
- **Remote**: Uploaded to DigitalOcean Spaces for offsite durability

### Manual Backup

```bash
./scripts/backup.sh root@your-droplet-ip
```

The script will prompt to pull the backup to your local machine.

### Restore

```bash
# Restore from local backup on droplet
./scripts/restore.sh root@your-droplet-ip anythingllm-ai_backup_20260115_120000

# The restore script will automatically fetch from DO Spaces if the backup
# is not found locally.
```

## Migration from Helm/Kubernetes

If you're migrating from the existing `ai/anythingllm` Helm-based deployment:

### Data Migration

1. **Export data from Kubernetes**:

   ```bash
   # Scale down to prevent writes
   kubectl scale deployment anythingllm --replicas=0 -n anything-llm

   # Create a backup tarball of the storage PVC
   kubectl run backup-helper --rm -i --tty \
     --image=alpine:3.19 \
     --overrides='{"spec": {"volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "anythingllm-storage"}}]}}' \
     -- tar czf - -C /data . > anythingllm-storage-backup.tar.gz
   ```

2. **Transfer to new droplet**:

   ```bash
   scp anythingllm-storage-backup.tar.gz root@new-droplet-ip:/opt/s004-anythingllm/backups/
   ssh root@new-droplet-ip
   cd /opt/s004-anythingllm/backups
   tar xzf anythingllm-storage-backup.tar.gz
   ```

3. **Restore into Docker volume**:

   ```bash
   docker run --rm \
     -v s004_anythingllm_storage:/data \
     -v /opt/s004-anythingllm/backups:/backup:ro \
     alpine:3.19 \
     tar xzf /backup/anythingllm-storage-backup.tar.gz -C /data
   ```

### Secret Migration

Move secrets from Kubernetes to Infisical:

```bash
# Get existing secrets from K8s
kubectl get secret anythingllm-secrets -n anything-llm -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'

# Add each to Infisical Dashboard → Secrets
# Key names remain the same: OPENROUTER_API_KEY, JWT_SECRET, ADMIN_EMAIL
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
