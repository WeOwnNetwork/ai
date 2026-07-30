# Changelog

All notable changes to `supabase-docker` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to WeOwn versioning conventions per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) (`#WeOwnVer` = `vSEASON.MONTH.WEEK.ITERATION`).

| Field | Value |
|---|---|
| **Document** | `supabase-docker/CHANGELOG.md` |
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟢 Current |
| **Effective** | 2026-06-26 |
| **Related** | [Repo-level CHANGELOG](../CHANGELOG.md) |

## [Unreleased]

### Fixed (W27 D5, 2026-07-03 — surfaced during first live deploy of supabase-dev)

- `template/ansible/deploy.yml.jinja` — five infisical-run tasks (Optional docker login, Start compose stack, Check Pop schema, Apply Pop schema migrations, Reconcile docker compose handler) rewritten to use `INFISICAL_TOKEN=$(timeout 30 infisical login … --plain --silent)` + `export INFISICAL_TOKEN` + `timeout <N> infisical run …`. Original pattern hung indefinitely when the CLI hit an interactive prompt code path.
- `template/ansible/deploy.yml.jinja` — Apply/Check Pop schema tasks now wrap `docker compose exec` in `bash -c '…'` inside `infisical run` so `$POSTGRES_PASSWORD` resolves in the injected child env, not the outer `set -u` shell (was failing with unbound-variable).
- `template/ansible/deploy.yml.jinja` — Check-Pop-schema task rewritten to drop the `bash -c` wrap and the `-e PGPASSWORD` flag entirely: psql inside the container uses peer auth on the local UNIX socket (postgres OS user -> postgres DB role, no password needed), and `< /dev/null` closes stdin so `docker compose exec -T` can't SIGSTOP on a TTY-read race with ansible's non-interactive SSH session. First live re-provision surfaced this: the earlier bash-c-wrapped variant with embedded single-quoted SQL wedged docker-compose in state `Tl` under `timeout 60`, blocking the deploy for 40+ min before manual kill. Simpler SQL (schema-only check) is now the fast-path; the migration file's own IF NOT EXISTS + duplicate_object guards make a false-negative retry safe.
- `template/ansible/deploy.yml.jinja` — Wait-for-PostgREST-health and Wait-for-GoTrue-health probes now hit `https://{{ domain }}/…` with `follow_redirects: safe` instead of `http://127.0.0.1/…`. Caddy 308-redirects HTTP to HTTPS, and 127.0.0.1 trips TLS SNI validation; matching what a real client sees is both correct and end-to-end proof the whole stack is up.
- `template/ansible/deploy.yml.jinja` — "Install daily backup cron" task updated to use the same `timeout 30` + `--plain` + `INFISICAL_TOKEN` export pattern as the deploy tasks. Original `infisical login --silent` in the cron wrapper would wedge at 3 AM on the first daily fire (same hang class that blocked the deploy today), and cron would eat stdout so the failure would only surface as missing backups.
- `template/scripts/backup.sh.jinja` — remote-mode SSH wrapper (`./backup.sh root@host` operator path) refactored to the same token-capture pattern for the same reason.
- `template/terraform/templates/cloud-init.yaml.jinja` — dropped the `mkdir /var/log/caddy` + `chmod 0777` runcmd entries; dead code since Caddy now logs to stderr (no host bind mount). Comment preserved so anyone re-adding file logging knows to re-add these lines.
- `template/ansible/deploy.yml.jinja` — Optional docker login gated behind `use_minimus_registry: true` (default false); previously hung on greenfield sites without `MINIMUS_TOKEN` set.
- `template/docker/compose.prod.yaml.jinja` — added `API_EXTERNAL_URL: https://{{ domain }}/auth/v1` to the auth service. GoTrue v2.x exits fatal with "required key API_EXTERNAL_URL missing value" without it.
- `template/docker/Caddyfile.jinja` — removed empty `tls { }` block (invalid Caddyfile syntax); switched `log { output file /var/log/caddy/… }` to `output stderr` (caddy container can't create host log dirs).
- `template/docker/migrations/001_pop_schema.sql` — moved `tenants` table from `public.tenants` to `pop.tenants`. Supabase Realtime pre-creates its own `public.tenants` at startup with columns (`external_id`, `jwt_secret`, `max_concurrent_users`), silently no-op'ing our `CREATE TABLE IF NOT EXISTS`. All FK references updated.
- `template/terraform/templates/cloud-init.yaml.jinja` — replaced the apt `awscli` package (dropped from Ubuntu 24.04 noble) with an AWS CLI v2 install script (official installer, arch-aware) hooked into runcmd. Prior renders fail with "Unable to locate package awscli".
- `copier.yaml` — bumped `studio_image` default to `supabase/studio:2026.06.29-sha-20290c7`. The 2024-vintage default (`20240805-1abf2d5`) was pruned from Docker Hub; new copies would fail `docker pull` with "manifest unknown".
- `template/terraform/variables.tf.jinja` — `do_token` description now lists `SSH Key (read)` as a required custom scope (main.tf reads SSH fingerprint via `digitalocean_ssh_key` data source; apply fails 403 without it).

### Added (W27 D5, 2026-07-03)

- `template/terraform/site.auto.tfvars.jinja` — new non-sensitive site config file, auto-loaded by tofu, committed to git. Splits domain/region/images/toggles/backup/monitoring-thresholds away from `terraform.tfvars.example` (which is now sensitive-placeholders-only). Prevents the earlier bug where placeholder values baked into `terraform.tfvars` overrode `TF_VAR_*` env injection from `itofu.sh`.
- `template/.gitignore` — exception for `terraform/site.auto.tfvars` (allow-committed alongside the existing `terraform.tfvars.example` exception).
- `README.md` — new **Prerequisites** section documenting three external gotchas hit during first live provision: DO API token custom scopes (incl. SSH Key read), DO Monitoring alert-recipient email verification (separate from team membership), and Infisical Machine Identity `manage own client secrets` permission required for Layer 2 rotation.

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
