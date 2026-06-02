# int-s004-anythingllm (s004.weown.net) — INT-S004 Recovery Rebuild

This site is the **fresh rebuild** of INT-S004: it replaces the locked-out
`s004.ccc.bot` droplet with a brand-new droplet under the new standard FQDN
**`s004.weown.net`**. It mirrors the most-hardened sibling site
[`sites/ai.weown.agency/`](../ai.weown.agency/) (INT-P01) and follows the
Path C + Layer 2 pattern documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md).

> 🚦 **If you are executing the rebuild, start at the runbook:**
> [`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md). It walks provisioning, the
> off-box data restore, the verification gates that would have caught both old
> failures, soak, and decommission of the old box. The rest of this README
> documents the steady-state deployment shape the runbook lands on.

## Why this rebuild exists

The old `s004.ccc.bot` failed two ways; this box is built to close both.

- **Auth lockout.** AnythingLLM logged `Cannot create JWT as JWT_SECRET is
  unset` at `makeJWT`. A container restart came back with `JWT_SECRET` empty
  because the secret was not injected, and every login failed. **Fix:**
  `JWT_SECRET` is present **and persistent** in the dedicated s004 Infisical
  project (`prod` env) — set once, never rotated (rotating logs everyone out) —
  and the container only ever starts under `infisical run`. The compose file
  now **fails loud** if `JWT_SECRET` is missing (see
  [`docker/compose.prod.yaml`](docker/compose.prod.yaml)) instead of booting
  with broken auth.
- **No backups.** The old box never got the canonical ansible deploy, so the
  daily backup cron was never installed and nothing reached DO Spaces.
  **Fix:** the ansible Path C deploy installs
  `/etc/cron.daily/int_s004_anythingllm-backup`, and the runbook proves a backup
  actually lands in DO Spaces before the old box is decommissioned.

> ⚠️ `/api/ping` returns **200 even when auth is broken** — it is an
> unauthenticated liveness probe. A green healthcheck does NOT mean logins
> work. Always verify login + a retrieval query by hand (runbook Phase 5); do
> not rely on `/api/ping` alone to declare the instance healthy.

## Key decisions for this site

| Decision | Value | Rationale |
|---|---|---|
| `project_name` | `int-s004-anythingllm` | Mirrors `int-p01-anythingllm`: `/opt/int_s004_anythingllm`, volume `int_s004_anythingllm_storage`, cron `int_s004_anythingllm-backup`, tag `int-s004-anythingllm`. |
| Secret injection | committed host-side `infisical run` | The proven, committed path `ai.weown.agency` ships. **Not** in-container injection (proposed separately as ADR-006; not adopted here) — that out-of-band, uncommitted change is what dropped `JWT_SECRET` on the old box. |
| Hostname | single-host `s004.weown.net` | Verified: nothing in the repo routes to `s004.ccc.bot` (only self-references in the retired `sites/s004/` and historical prose), and the old box is locked out, so there is no legacy traffic to preserve. Escape hatch documented in [`docker/Caddyfile`](docker/Caddyfile). |
| Infisical project | dedicated s004 project | Separate project + Machine Identity scoped to s004 only (least privilege), distinct from INT-P01's `weown-anythingllm`. |
| Image | `reg.mini.dev/anythingllm:1.7.2` | Same pin as the source box, so the restored storage needs no schema migration. |

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
│  │             │  │  • LanceDB vector storage (embedded)│  │
│  │             │  │  • Multi-workspace support          │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                      anythingllmnet                         │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **AnythingLLM AI Assistant** — full-featured RAG platform with document chat
- **OpenRouter Integration** — multi-provider LLM gateway
- **LanceDB** — embedded vector database (zero-config, no separate container)
- **Caddy Reverse Proxy** — automatic TLS via Let's Encrypt
- **Infisical Integration** — runtime secret injection (no secrets on disk)
- **Skinny Backups** — volume-based backups with grandfather-father-son retention
- **DigitalOcean Spaces** — offsite backup storage
- **Idempotent Deployments** — re-running deploy is a no-op if nothing changed

## Steady-state deployment flow

This site is **already generated** (mirrored from `ai.weown.agency`); there is
no `copier copy` step. The operator steps to land the droplet are below — the
full recovery procedure (with the data restore) is in
[`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md).

### 1. Set up Infisical secrets (dedicated s004 project, prod env)

Create the dedicated s004 Infisical project + a Machine Identity scoped to it,
then set these secrets in the `prod` env:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `JWT_SECRET` | `openssl rand -hex 32`. **Set once, never rotate.** | Yes |
| `OPENROUTER_API_KEY` | A **fresh** OpenRouter key (`sk-or-v1-...`); the old one expired 2026-06-01. | Yes |
| `ADMIN_EMAIL` | Admin notification email | Yes |
| `SPACES_ACCESS_KEY` | DO Spaces key for backups | Yes |
| `SPACES_SECRET_KEY` | DO Spaces secret for backups | Yes |
| `OPENROUTER_MODEL_PREF` | Default LLM model | No |
| `OPENROUTER_TIMEOUT_MS` | API timeout in ms (default: `3000`) | No |
| `EMBEDDING_ENGINE` | `native` or `openrouter` (default: `native`) | No |
| `AUTH_TOKEN` / `AUTH_MODE` / `ALLOW_MULTI_WORKSPACE` | Multi-user mode | No |

### 2. Provision infrastructure (terraform — first-boot bootstrap)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: DO token, SSH fingerprint, Spaces keys,
# Machine Identity Client ID + Client Secret, and the dedicated s004
# Infisical project ID.
chmod +x ./init.sh
./init.sh        # configures the DO Spaces state backend with Spaces creds
tofu plan
tofu apply       # creates droplet; cloud-init bootstraps Docker + Infisical
                 # CLI + rotates the bootstrap secret (Layer 2)
```

Cloud-init takes ~3 minutes. **Verify the Layer 2 rotation succeeded:**

```bash
ssh root@<droplet-ip> 'tail /var/log/int_s004_anythingllm-rotation.log'
# Expected last line: "===== Rotation complete ====="
```

If you see `ROTATION FAILED:` instead, follow the manual rotation runbook in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md).

### 3. Deploy the application (ansible — app layer + every subsequent update)

```bash
INFISICAL_PROJECT_ID=<s004-project-id> ./scripts/deploy.sh root@<droplet-ip>
```

This uploads `compose.yaml`, `Caddyfile`, `backup.sh`, installs the daily
backup cron + logrotate, pulls images, runs `docker compose up -d` under
`infisical run`, and updates DO droplet tags (`skinny-backup` + `commit-<sha>`).
**Idempotent — re-run any time you change compose/Caddy/backup files. No
terraform needed.**

### Updating the deployment

| Change | How to apply |
|---|---|
| compose.yaml, Caddyfile, backup.sh, scripts | `./scripts/deploy.sh root@<ip>` — ansible re-uploads + reconciles. No terraform. |
| Container image bump | Edit `terraform/variables.tf` default + `docker/compose.prod.yaml`, then `./scripts/deploy.sh`. `tofu apply` is a no-op (user_data ignored). |
| Cloud-init contents | Requires `tofu taint digitalocean_droplet.anythingllm && tofu apply`. **Droplet downtime + volume considerations apply.** |
| Infisical project secrets | Edit in Infisical UI. `docker compose restart` on the droplet to pick up. **Never rotate `JWT_SECRET`.** |
| Machine Identity rotation | See manual runbook in [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md). |

## Infisical security model

Runtime secret injection — zero application secrets on disk. Only the Infisical
Machine Identity (Client ID + Secret) is stored on the node (and Layer 2
rotates even that on first boot). Secrets are fetched at container start by
`infisical run -- docker compose up` and live in process memory only. See
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md)
for the Path C + Layer 2 rationale.

## Backup strategy

Backups run daily via cron with a **grandfather-father-son** retention policy
(daily 30d / monthly 12mo / yearly forever), stored locally at
`/opt/int_s004_anythingllm/backups/` and uploaded to DigitalOcean Spaces
(`s3://weown-backups/int-s004-anythingllm/`) for offsite durability.

```bash
# Manual backup (prompts to pull a copy locally):
./scripts/backup.sh root@<droplet-ip>
```

## Data import / restore

The **initial** data import for this rebuild is the off-box tarball exported
from the old `s004.ccc.bot` (`s004_storage_<TS>.tar.gz`, whose root is the
contents of `/app/server/storage`). Because that tarball is the raw storage
directory — not the wrapped skinny-backup layout `scripts/restore.sh` expects —
the import is a direct volume extraction documented in
[`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md) Phase 4. `scripts/restore.sh` is
for restoring **subsequent** skinny-backups (the daily cron output, which is in
the layout it understands):

```bash
./scripts/restore.sh root@<droplet-ip> int-s004-anythingllm_backup_<TS>
```

## Security

- **No secrets in git** — `terraform.tfvars` only holds the Machine Identity, not app secrets
- **No secrets on disk** — application secrets live in Infisical and process memory only
- **Fail-loud auth** — compose refuses to start if `JWT_SECRET` is not injected
- **TLS** automatically managed by Caddy (Let's Encrypt)
- **Firewall** restricts inbound to ports 22, 80, 443
- **Resource limits** on all containers; **security headers** enforced by Caddy

## Monitoring

DigitalOcean monitoring alerts are configured for CPU > 80%, Memory > 90%, and
Disk > 85%.

## Support

For issues or questions, open a GitHub issue in the `WeOwnNetwork/ai` repository.
