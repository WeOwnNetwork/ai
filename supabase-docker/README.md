# supabase-docker

Copier template for self-hosted Supabase deployments on DigitalOcean droplets.

| Field | Value |
|---|---|
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟡 DRAFT — initial scaffold |
| **Effective** | 2026-06-26 (W26 D5) |
| **CCC-ID** | `PLT_2026-W26_2002` (W26 SOW anchor) |
| **Versioning spec** | [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) |

## Status

**Initial scaffold (W26 D5, 2026-06-26).** Skeleton in place for review with `@CTO` before any prod data move. Several layers still pending — see Migration Status below.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Pending** | `template/terraform/backend.tf.jinja` not yet authored. Reference: [`keycloak-docker/template/terraform/backend.tf.jinja`](../keycloak-docker/template/terraform/backend.tf.jinja) and the working pattern in [`keycloak-docker/sites/sso.weown.dev/terraform/`](../keycloak-docker/sites/sso.weown.dev/terraform/). |
| Layer 2 (bootstrap-secret rotation) | **Pending** | No `rotate-bootstrap-secret.sh` yet. Reference: [`anythingllm-docker/sites/s004.ccc.bot/terraform/templates/cloud-init.yaml`](../anythingllm-docker/sites/s004.ccc.bot/terraform/templates/cloud-init.yaml). |
| Path C (thin cloud-init + ansible) | **Pending** | `template/terraform/templates/cloud-init.yaml.jinja` not yet authored. Plan to follow `keycloak-docker`'s current pattern (embedded compose body) for v0.1, then slim cloud-init in a follow-up. |
| Infisical CLI install | **Pending** | Use artifacts-cli apt repo (NOT legacy `install-cli.sh`). |
| Ansible roles | **Pending** | `template/ansible/roles/{common,docker,supabase}/` directories scaffolded but tasks not yet authored. |

## Architecture Decision Record

**ADR pending** — service deployment ADR for self-hosted Supabase to be authored alongside `template/terraform/` work. Until then, this README + the keycloak-docker pattern serve as the de facto reference for review.

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
├── sites/                     # Empty for now — instances generated via `copier copy`
└── template/
    ├── ansible/               # Ansible playbooks and roles (scaffolded)
    │   ├── inventories/
    │   └── roles/
    │       ├── common/        # Base server config
    │       ├── docker/        # Docker installation
    │       └── supabase/      # Supabase-specific config
    ├── docker/
    │   ├── compose.prod.yaml.jinja   # 6-service stack (Infisical runtime injection)
    │   └── Caddyfile.jinja           # Path-based routing
    ├── scripts/               # Deploy, backup, restore scripts (pending)
    └── terraform/             # OpenTofu infrastructure (pending)
        └── templates/         # cloud-init (pending)
```

## Usage

### Create a new deployment

```bash
# Install copier if not already installed
pip install copier

# Create a new Supabase deployment
cd supabase-docker
copier copy . ../sites/example.com --data-file answers.yaml
```

### Configure deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: supabase-example
domain: example.com
do_region: nyc3
droplet_size: s-4vcpu-8gb-amd
enable_pgvector: true
enable_studio: true
enable_realtime: true
infisical_project_id: your-infisical-project-id
```

### Deploy infrastructure (once `template/terraform/` is complete)

```bash
cd ../sites/example.com/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu plan
tofu apply
```

### Deploy application (once `template/scripts/` is complete)

```bash
cd ../scripts
chmod +x deploy.sh
./deploy.sh root@your-droplet-ip
```

## Local Development

```bash
cd template/docker
cp .env.example .env.local
# Edit .env.local with your values
docker compose -f compose.prod.yaml up
```

## Secrets Management

All application secrets are managed via Infisical per [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) §3.10 (Machine Identity pattern — only the Machine Identity Client ID + Secret are stored on disk; all other secrets fetched at runtime via `infisical run`).

Required Infisical secrets:

- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`
- `GOTRUE_JWT_SECRET` (often same as `JWT_SECRET`)
- `PGRST_JWT_SECRET` (often same as `JWT_SECRET`)
- `REALTIME_SECRET_KEY_BASE` (64+ char random string)
- `REALTIME_DB_ENC_KEY` (32 char random string)
- `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` (Studio basic auth, if exposed)

To deploy with secrets injected at runtime:

```bash
infisical run -- ./scripts/deploy.sh root@your-droplet-ip
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
