# supabase-docker

Copier template for self-hosted Supabase deployments on DigitalOcean droplets.

| Field | Value |
|---|---|
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟢 Structurally complete |
| **Effective** | 2026-07-02 (W27 D4) |
| **CCC-ID** | `PLT_2026-W26_2002` (W26 SOW anchor) |
| **Versioning spec** | [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) |

## Status

**Structurally complete (W27 D4, 2026-07-02).** All bootstrap layers landed (Layer 1 DO Spaces state, Layer 2 Infisical rotation, Path C thin cloud-init + ansible app layer). Pop schema migration + `generate-secrets.sh` helper included.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) — S3-compatible backend, SSE-C encryption, private ACL. |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1 from terraform state, mints v2 via Infisical Universal Auth API, atomically swaps the auth file, revokes v1. Fails closed with logs to `/var/log/<project>-rotation.log`. |
| Path C (thin cloud-init + ansible) | **Done** | Cloud-init handles only first-boot bootstrap (Docker + Infisical CLI + Layer 2 rotation). [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) owns compose + Caddyfile + backup script + cron + Pop schema migration apply + `docker compose up`. Ongoing changes don't require `tofu taint`. |
| Infisical CLI install | **Done** | Uses `artifacts-cli.infisical.com` apt repo (NOT legacy `install-cli.sh` which is stuck at v0.38 with broken `infisical run`). |
| Ansible roles | **Done** | `template/ansible/roles/{common,docker,supabase}/` tasks authored. `supabase` role handles Pop schema migration idempotency (skips when `pop` schema already present). |
| Pop schema migration | **Done** | [`template/docker/migrations/001_pop_schema.sql`](template/docker/migrations/001_pop_schema.sql) — pop schema + tenants registry + 6 pop tables + 24 RLS policies + `set_tenant_from_jwt()` PostgREST hook + `pop_admin` bypassrls role. Structural only. |
| Secret generation helper | **Done** | [`template/scripts/generate-secrets.sh.jinja`](template/scripts/generate-secrets.sh.jinja) — mints all 10 Supabase app secrets including HS256-signed `ANON_KEY` and `SERVICE_ROLE_KEY` JWTs. Bash + openssl only. See [Generate Secrets](#generate-secrets) below. |

## Architecture Decision Record

This README + the keycloak-docker pattern serve as the reference for service deployment decisions.

## Overview

This template provides a production-ready self-hosted Supabase deployment with:

- **Supabase Postgres** (15.6 with pgvector + extensions) — persistent database
- **PostgREST** — auto-generated REST API from Postgres schema
- **GoTrue (Auth)** — JWT-based authentication service
- **Realtime** — WebSocket subscriptions to database changes (optional)
- **Studio** — admin UI (optional)
- **Caddy** — Reverse proxy with automatic TLS + path-based dispatch
- **OpenTofu** — Infrastructure as Code (DigitalOcean droplets)
- **Ansible** — Server configuration management
- **Infisical** — Secrets management integration (see [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) §3.10 for the Machine Identity pattern)

## Directory Structure

```text
supabase-docker/
├── copier.yaml                # Copier template configuration
├── README.md                  # This file
├── CHANGELOG.md               # Changelog
├── docs/
│   ├── pop-schema.md          # Pop DB → Supabase schema design
│   └── pop-rls.md             # RLS policy pattern (Approach A — PostgREST hook)
├── sites/                     # Empty — instances generated via `copier copy`
└── template/
    ├── .gitignore             # Rendered project gitignore
    ├── ansible/               # Path C app layer
    │   ├── deploy.yml.jinja   # Idempotent deploy playbook
    │   ├── site.yml.jinja
    │   ├── requirements.yml.jinja
    │   ├── inventories/prod.yml.jinja
    │   └── roles/
    │       ├── common/        # Base server config
    │       ├── docker/        # Docker installation
    │       └── supabase/      # Multi-service health checks + Pop schema seed
    ├── docker/
    │   ├── compose.prod.yaml.jinja   # 6-service stack (Infisical runtime injection)
    │   ├── Caddyfile.jinja           # Path-based routing
    │   ├── .env.example              # Placeholder-only reference
    │   └── migrations/
    │       └── 001_pop_schema.sql    # Pop tables + tenants + RLS
    ├── scripts/
    │   ├── lib.sh.jinja              # Safe site.conf reader
    │   ├── deploy.sh.jinja           # Thin ansible-playbook wrapper
    │   ├── backup.sh.jinja           # pg_dumpall + volume tars + DO Spaces + GFS retention
    │   ├── restore.sh.jinja
    │   └── generate-secrets.sh.jinja # HS256-JWT app secret minter
    └── terraform/
        ├── versions.tf.jinja         # OpenTofu ≥1.7 + DO provider ~2.36
        ├── backend.tf.jinja          # DO Spaces S3-compatible state (weown-tools-state)
        ├── variables.tf.jinja
        ├── outputs.tf.jinja
        ├── monitoring.tf.jinja       # DO CPU/mem/disk alerts
        ├── main.tf.jinja             # Droplet + reserved IP + firewall
        ├── itofu.sh.jinja            # Tofu wrapper: injects TF_VAR_* from weown-supabase-tofu
        ├── site.auto.tfvars.jinja    # Non-sensitive site config (auto-loaded, committed)
        ├── terraform.tfvars.example.jinja  # SENSITIVE placeholders only (workflow 2 reference)
        └── templates/
            └── cloud-init.yaml.jinja # Slim Path C bootstrap + Layer 2 rotation
```

## Prerequisites

Before the first `itofu.sh apply`, three external prerequisites must be in place. Getting any wrong makes the failure mode noisy but recoverable; documenting them here so a re-provision doesn't rediscover them.

**1. DigitalOcean API token custom scopes** — required for `TF_VAR_do_token`:

- **Droplet** (create, read, delete)
- **Reserved IP** (create, read, assign)
- **Firewall** (create, read, update)
- **Tag** (create, read)
- **Monitoring** (create, read) — only if `enable_monitoring = true`
- **SSH Key (read)** — `main.tf` reads the fingerprint via the `digitalocean_ssh_key` data source; without this scope, apply fails with `403 You are missing the required permission ssh_key:read`
- Optional: **Domain** — only if you add the `digitalocean_record` resource for automated A record management

**2. DO Monitoring alert recipient verified** — required for `TF_VAR_alert_email` when `enable_monitoring = true`:

Set the alert email to an address that has been added to DO Monitoring -> Alert Recipients AND clicked the confirmation link. This is separate from being a team member — an unverified team-member email still fails apply with "email is not verified". If in doubt, set `enable_monitoring = false` in `site.auto.tfvars` for a first apply and enable later.

**3. Machine Identity 'manage own client secrets' permission** — required for the Layer 2 bootstrap-secret rotation cloud-init step to succeed:

The Infisical Machine Identity used by the droplet (`TF_VAR_infisical_client_id` / `TF_VAR_infisical_client_secret`) must have the "manage own client secrets" permission (Infisical UI -> Organization Settings -> Access Control -> Machine Identity -> Additional Privileges). Without it, the rotation script in cloud-init succeeds at Layer 1 (v1 auth works) but fails to mint v2 with a 403 on `POST /identities/{id}/client-secrets`. The droplet still boots and app secrets still fetch, but the bootstrap secret is not rotated as intended — v1 remains valid indefinitely.

## Usage

### 1. Create a new deployment from the template

```bash
# Install copier if not already installed (pipx recommended)
pipx install copier

# Render the template into a sibling directory
cd supabase-docker
copier copy . ../supabase-<slug> --data-file answers.yaml
```

### 2. Configure deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: supabase-<slug>
domain: supabase.example.com
do_region: atl1
droplet_size: s-4vcpu-8gb-amd
enable_pgvector: true
enable_studio: true
enable_realtime: true
infisical_project_id: <your-infisical-project-id>
```

### 3. Generate application secrets

Before the first `tofu apply`, mint all Supabase application secrets and load them into Infisical. **Never commit the output.**

```bash
cd ../supabase-<slug>
./scripts/generate-secrets.sh                                  # KEY=VALUE pairs to stdout (default)
./scripts/generate-secrets.sh --infisical-cmds --project-id <id>   # `infisical secrets set` cmds
```

The script generates `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`, `REALTIME_SECRET_KEY_BASE`, and `REALTIME_DB_ENC_KEY`. `ANON_KEY` and `SERVICE_ROLE_KEY` are real HS256 JWTs cryptographically signed against the generated `JWT_SECRET` — GoTrue + PostgREST will verify them at startup.

Also copy `JWT_SECRET` into Infisical as `PGRST_JWT_SECRET` and `GOTRUE_JWT_SECRET` (same value, three var names — Supabase self-host convention).

### 4. Deploy infrastructure — via `itofu.sh` (no infra creds on disk)

Preferred workflow: infra creds live in the `weown-supabase-tofu` Infisical project (paired with `weown-supabase` for app runtime secrets). The `itofu.sh` wrapper runs `tofu` under `infisical run`, so `TF_VAR_*` values are injected as env at plan/apply time. Nothing sensitive touches `terraform.tfvars`.

```bash
cd terraform
export WEOWN_TOFU_PROJECT_ID=<your weown-supabase-tofu Infisical project id>
infisical login                          # one-time; opens browser, writes local session
./itofu.sh init                          # forwards Spaces creds to the S3 backend
./itofu.sh plan                          # writes plan.tfplan (gitignored)
./itofu.sh apply                         # consumes + deletes plan.tfplan
./itofu.sh output -raw reserved_ip       # anything else passes through to `tofu`
```

`itofu.sh apply` provisions the droplet + reserved IP + firewall. Cloud-init runs first-boot bootstrap (Docker, Infisical CLI, Layer 2 bootstrap-secret rotation). Watch `/var/log/cloud-init-output.log` and `/var/log/<project>-rotation.log` on the droplet.

**Required Infisical secrets in `weown-supabase-tofu` (dev env)**:

```
TF_VAR_do_token, TF_VAR_ssh_key_fingerprint,
TF_VAR_spaces_access_key, TF_VAR_spaces_secret_key, TF_VAR_spaces_encryption_key,
TF_VAR_infisical_client_id, TF_VAR_infisical_client_secret,
TF_VAR_infisical_project_id, TF_VAR_infisical_environment,
TF_VAR_alert_email
```

**Fallback (plain `tofu`, no Infisical)**: fill sensitive fields in `terraform.tfvars` directly, run `tofu init/plan/apply`. See `terraform.tfvars.example` for the field list.

### 5. Deploy application

```bash
cd ../scripts
INFISICAL_PROJECT_ID=<id> ./deploy.sh root@<droplet-reserved-ip>
```

Runs the ansible playbook — uploads compose + Caddyfile + backup script, installs daily backup cron, `docker compose up`, applies the Pop schema migration if the `pop` schema is missing.

## Local Development

```bash
cd template/docker
cp .env.example .env.local
# Edit .env.local with your values
docker compose -f compose.prod.yaml up
```

## Secrets Management

<a id="generate-secrets"></a>

All application secrets are managed via Infisical per [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) §3.10 (Machine Identity pattern — only the Machine Identity Client ID + Secret are stored on disk; all other secrets fetched at runtime via `infisical run`).

Required Infisical secrets (all generated by `./scripts/generate-secrets.sh` — see [step 3](#3-generate-application-secrets)):

- `POSTGRES_DB`, `POSTGRES_USER` — non-secret config (defaults: `supabase` / `postgres`); still stored in Infisical because the compose file reads them via `${POSTGRES_DB}` / `${POSTGRES_USER}` at container startup
- `POSTGRES_PASSWORD` — Postgres superuser password
- `JWT_SECRET` — 40-byte HS256 signing secret
- `ANON_KEY` — HS256 JWT signed against `JWT_SECRET`, `role=anon`
- `SERVICE_ROLE_KEY` — HS256 JWT signed against `JWT_SECRET`, `role=service_role`
- `GOTRUE_JWT_SECRET` — same value as `JWT_SECRET` (GoTrue reads this env)
- `PGRST_JWT_SECRET` — same value as `JWT_SECRET` (PostgREST reads this env)
- `REALTIME_SECRET_KEY_BASE` — 64-char Realtime cookie/session signing key
- `REALTIME_DB_ENC_KEY` — 16-char Realtime column encryption key (exact length required by Realtime)
- `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` — Studio basic auth (if `enable_studio: true`)

### JWT verification (why the helper matters)

`ANON_KEY` and `SERVICE_ROLE_KEY` are not random strings — they are real JWTs. GoTrue and PostgREST verify the HS256 signature against `JWT_SECRET` at every request; RLS policies read `role` from the claims. A mistyped payload or wrong algorithm silently breaks auth. The generator script encodes the correct shape once so it doesn't matter what an operator types.

To deploy (Infisical injects secrets at container startup — no `.env` on disk):

```bash
INFISICAL_PROJECT_ID=<id> ./scripts/deploy.sh root@<droplet-ip>
```

## Idempotency

- **OpenTofu**: Re-running `tofu apply` after infrastructure exists will show no changes
- **Ansible**: Re-running playbooks will only make necessary changes
- **Deploy script**: Re-running will only restart services if compose files changed

## Routes (Caddy path-based dispatch)

Behind a single TLS endpoint at `{{ domain }}`:

| Path | Service | Notes |
|---|---|---|
| `/rest/v1/*` | postgrest:3000 | Auto-generated REST API (prefix stripped) |
| `/auth/v1/*` | auth:9999 | GoTrue JWT auth (prefix stripped) |
| `/realtime/v1/*` | realtime:4000 | WebSocket subscriptions (conditional on `enable_realtime`) |
| `/*` (catch-all) | studio:3000 | Admin UI (conditional on `enable_studio`) |

For production hardening (IP lockdown of Studio), see the keycloak-docker admin lockdown pattern at [`keycloak-docker/sites/sso.weown.dev/docker/Caddyfile`](../keycloak-docker/sites/sso.weown.dev/docker/Caddyfile).

## Services to Integrate

This Supabase instance provides persistence + auth + realtime + vector storage for:

- Pop DB schema migration (W26 — primary motivation)
- AnythingLLM vector database centralization (future — replaces local vector DBs across ALLM fleet)
- WeOwn product ladder persistence layer

## Compliance & Review

This repo enforces comprehensive review standards documented in [`.github/copilot-instructions.md`](../.github/copilot-instructions.md), covering NIST CSF, CIS, ISO 27001, SOC 2, and ISO 42001 alignment. PRs against this template will be reviewed against those standards.

Code ownership: see [`.github/CODEOWNERS`](../.github/CODEOWNERS).

## License

See individual component licenses (Supabase: Apache 2.0, PostgreSQL: PostgreSQL License, Caddy: Apache 2.0)
