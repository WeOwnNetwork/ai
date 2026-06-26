# Changelog

All notable changes to `supabase-docker` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to WeOwn versioning conventions per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) (`#WeOwnVer` = `vSEASON.MONTH.WEEK.ITERATION`).

| Field | Value |
|---|---|
| **Document** | `supabase-docker/CHANGELOG.md` |
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟡 DRAFT |
| **Effective** | 2026-06-26 |
| **Related** | [Repo-level CHANGELOG](../CHANGELOG.md) |

## [Unreleased]

### Pending

- `template/terraform/` — main.tf.jinja, backend.tf.jinja, monitoring.tf.jinja, outputs.tf.jinja, variables.tf.jinja, versions.tf, terraform.tfvars.example.jinja
- `template/terraform/templates/cloud-init.yaml.jinja` — droplet bootstrap with embedded compose body
- `template/scripts/` — deploy.sh.jinja, backup.sh.jinja, restore.sh.jinja
- `template/ansible/` — playbooks and role task files (directories scaffolded, content pending)
- `template/docker/.env.example` — placeholder env file referencing required Infisical secrets
- `template/.gitignore`, `template/README.md.jinja`, `template/CHANGELOG.md.jinja`

## [v4.1.4.1] — 2026-06-26

### Added

- Initial template scaffold mirroring [`keycloak-docker/`](../keycloak-docker/) structure
- `copier.yaml` with full variable set:
  - Project identity (project_name, domain)
  - DigitalOcean infrastructure (region, droplet_size — bumped default to `s-4vcpu-8gb-amd` for Supabase memory requirements)
  - Container images for 6 services (postgres, postgrest, gotrue, realtime, studio, caddy)
  - Supabase feature toggles (enable_pgvector, enable_studio, enable_realtime)
  - Infisical secrets management (Machine Identity client_id/secret/project_id/environment)
  - Skinny backup configuration
  - DigitalOcean monitoring alerts
- `template/docker/compose.prod.yaml.jinja`:
  - 6-service stack: db (Supabase Postgres with pgvector) + postgrest + auth + realtime + studio + caddy
  - All services have restart policy, healthchecks, resource limits per WeOwn hardening checklist
  - Conditional Jinja blocks for `enable_realtime` and `enable_studio`
  - Infisical runtime injection pattern (`${VAR}` for all secrets, no values on disk)
  - Volume names use `{{ project_name | replace('-', '_') }}_<name>` convention
  - Single bridge network with project-scoped name
- `template/docker/Caddyfile.jinja`:
  - Path-based dispatch behind single TLS endpoint
  - `/rest/v1/*` → postgrest, `/auth/v1/*` → auth, `/realtime/v1/*` → realtime, `/*` → studio
  - WebSocket upgrade headers on realtime block
  - Hardening hook left as comment for future Studio IP lockdown

### Security

- All application secrets sourced from Infisical at runtime via `infisical run` — no secrets on disk
- Only Infisical Machine Identity (Client ID + Secret) stored in `terraform.tfvars`
- No `.env` files with real secret values committed (only `.env.example` with placeholders)
- All services run with explicit resource limits + healthchecks per WeOwn hardening checklist
- Single bridge network with explicit naming (no default Docker bridge usage)

### Notes

- Pattern mirrors [`keycloak-docker/`](../keycloak-docker/) exactly per WeOwn copier template convention (see [`CLAUDE.md`](../CLAUDE.md))
- `template/terraform/` and `template/scripts/` deferred to follow-up — will mostly be mechanical copy from `keycloak-docker` with project-specific swaps
- `template/terraform/templates/cloud-init.yaml.jinja` will embed the compose body per existing pattern; the "slim cloud-init" follow-up flagged for later iteration
- Anchored to W26 SOW `PLT_2026-W26_2002` (Pop DB → Supabase + RLS substrate)

[Unreleased]: https://github.com/WeOwnNetwork/ai/compare/supabase-docker-v4.1.4.1...HEAD
[v4.1.4.1]: https://github.com/WeOwnNetwork/ai/releases/tag/supabase-docker-v4.1.4.1
