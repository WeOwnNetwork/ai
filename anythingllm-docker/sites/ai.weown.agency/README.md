# int-p01-anythingllm (ai.weown.agency) — DOKS → Docker Migration Site

This site is the **target droplet** for the INT-P01 (`ai.weown.agency`)
migration off DOKS, hosting the Calhoun MetaAgent. It is generated from the
[`anythingllm-docker`](../../) copier template and follows the Path C +
Layer 2 pattern documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md)
(reference implementation: [`sites/s004.ccc.bot/`](../s004.ccc.bot/) — live).

> 🚦 **If you are executing the migration, start at the runbook:**
> [`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md). It walks Phases 0–7 and
> the two human validation gates (Jason/Yonks staging soak, CTO production
> cutover approval). The rest of this README documents the steady-state
> deployment shape that the runbook lands on.
>
> 📐 **Decision rationale:**
> [`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md).

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

## Steady-state deployment flow

This site is **already generated** — the Quick-Start "copier copy …" step
that other anythingllm-docker docs describe does not apply here. The
operator steps to land the droplet are:

### 1. Set up Infisical secrets

Before deploying, create the following secrets in your Infisical project:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `OPENROUTER_API_KEY` | Your OpenRouter API key (`sk-or-v1-...`) | Yes |
| `JWT_SECRET` | Random hex string for JWT signing (`openssl rand -hex 32`) — set once, never rotate | Yes |
| `ANYTHINGLLM_IMAGE` | Container image ref (e.g. `reg.mini.dev/<ns>/anythingllm:v1.12.1`) — kept in Infisical, not in git; compose fails loud without it | Yes |
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

### 2. Provision infrastructure (OpenTofu — first-boot bootstrap)

```bash
cd ../int-p01-anythingllm/terraform
# itofu.sh runs tofu under `infisical run` against the operator weown-tofu
# project, injecting TF_VAR_* — no terraform.tfvars on disk. (Local-dev fallback:
# fill terraform.tfvars from the example, then ./init.sh && tofu plan && tofu apply.)
./itofu.sh init && ./itofu.sh plan && ./itofu.sh apply
                 # creates droplet; cloud-init bootstraps Docker + Infisical
                 # CLI + rotates the bootstrap secret (Layer 2)
```

Cloud-init takes ~3 minutes. When `tofu apply` returns, the droplet has
Docker + Infisical CLI installed and the Machine Identity bootstrap secret
has been rotated. **Verify the rotation succeeded:**

```bash
ssh root@<droplet-ip> 'tail /var/log/int_p01_anythingllm-rotation.log'
# Expected last line: "===== Rotation complete ====="
```

If you see `ROTATION FAILED:` instead, follow the manual rotation runbook
in [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md).

### 3. Deploy the application (ansible — app layer + every subsequent update)

```bash
cd ..
INFISICAL_PROJECT_ID=<your-project-id> ./scripts/deploy.sh root@<droplet-ip>
```

This uploads compose.yaml, Caddyfile, backup.sh, installs the daily backup
cron + logrotate, pulls images, runs `docker compose up -d`, and updates
DO droplet tags (skinny-backup + commit-\<sha\>). **Idempotent — re-run any
time you change compose/Caddy/backup files. No terraform needed.**

> ⚠️ **`/api/ping` returns 200 even when auth is broken.** It is an
> unauthenticated liveness probe — a green healthcheck does NOT mean logins
> work. After deploy, verify a real login (and a retrieval query) by hand; do
> not rely on `/api/ping` alone to declare the instance healthy.

### Updating the deployment

| Change | How to apply |
|---|---|
| compose.yaml, Caddyfile, backup.sh, scripts | `./scripts/deploy.sh root@<ip>` — ansible re-uploads + reconciles. No terraform. |
| Container image bump | Edit `ANYTHINGLLM_IMAGE` in Infisical, then `./scripts/deploy.sh root@<ip>`. No repo change, no terraform. |
| Cloud-init contents | Requires `tofu taint digitalocean_droplet.anythingllm && tofu apply`. **Droplet downtime + volume considerations apply.** |
| Infisical project secrets | Edit in Infisical UI, then re-run `./scripts/deploy.sh root@<ip>` — it recreates the container under `infisical run` so the new value is picked up (`docker compose restart` reuses the old env and won't). |
| Machine Identity rotation | See manual runbook in [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md). |

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md)
for the architecture rationale (Path C bootstrap + Layer 2 secret rotation).

## Infisical Security Model

Two Infisical projects, by design (full rationale in
[`../../DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md) §3):

```
weown-tofu (operator project)            this site's app project
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
- **Runtime injection** — secrets are fetched at container start, live in process memory only.
- **To pick up a changed secret, re-run `./scripts/deploy.sh`** — it recreates the container so `infisical run` re-injects. A bare `docker compose restart` reuses the **old** env and will not.

## Backup Strategy

### Skinny Backups (Volume-Based)

Backups run daily via cron and use a **grandfather-father-son** retention policy:

| Backup Type | Retention |
|-------------|-----------|
| Daily | 30 days |
| Monthly (1st of month) | 12 months |
| Yearly (Jan 1st) | Forever |

### Local + Remote Storage

- **Local**: Stored on droplet at `/opt/int_p01_anythingllm/backups/`
- **Remote**: Uploaded to DigitalOcean Spaces for offsite durability

### Manual Backup

```bash
./scripts/backup.sh root@your-droplet-ip
```

The script will prompt to pull the backup to your local machine.

### Restore

```bash
# Restore from local backup on droplet
./scripts/restore.sh root@your-droplet-ip int-p01-anythingllm_backup_20260115_120000

# The restore script will automatically fetch from DO Spaces if the backup
# is not found locally.
```

> **Restore caveat:** AnythingLLM reads its LLM-provider settings (including the
> OpenRouter key) from its **own database**, so on a restored instance the injected
> `OPENROUTER_API_KEY` env var does not override the restored value. If chat returns
> `401 Missing Authentication header`, re-enter the key in **Settings → AI Providers
> → LLM Preference → OpenRouter** in the UI.

## Migration from DOKS

The full Phases-0-through-7 migration plan for moving the live INT-P01
AnythingLLM instance off DOKS lives in
[`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md). Highlights:

- Parallel build + DNS cutover (DOKS untouched until soak completes).
- Caddyfile dual-hostname (`ai-stage.weown.agency, ai.weown.agency`) so the
  cutover is a single DNS A-record swap on the same droplet — no re-deploy,
  no second instance.
- One-shot bridge `scripts/migrate-from-doks.sh` that `kubectl exec`s into
  the DOKS pod, streams `/app/server/storage` out as a tarball, and wraps
  it in the same skinny-backup layout that `scripts/restore.sh` already
  understands — zero new failure modes in the restore path.
- Optional Phase 1.5 local-laptop dry-run round-trips the DOKS backup
  through a throwaway docker container before any cloud infra exists.
- Two human gates: Phase 4 (Jason/Yonks staging soak) and Phase 6 (CTO
  production-cutover approval).

Decision record:
[`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md).

## Secrets Update Process

Edit the secret in Infisical, then redeploy:

```bash
./scripts/deploy.sh root@your-droplet-ip
```

`deploy.sh` **recreates** the container under `infisical run`, so the new value is
injected. A bare `docker compose restart` reuses the old env and will **not** pick
it up. **Never rotate `JWT_SECRET`** (it logs every user out).

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

## Observability

DigitalOcean monitor alerts: CPU > 80%, Memory > 90%, Disk > 85%.

An OTel agent ships host metrics + Caddy logs to **SigNoz Cloud**, deployed by the
fleet scripts (`scripts/bootstrap-otel-agent.sh`, `scripts/deploy-otel-fleet.sh`,
tag `weown-ai`). It authenticates with the shared `otel` Infisical project's
**reader Machine Identity — not this box's app MI** (see
[`../../DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md) §9).

## Support

For issues or questions, open a GitHub issue in the `WeOwnNetwork/ai` repository.
