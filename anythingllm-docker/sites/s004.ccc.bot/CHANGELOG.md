# int-s004-anythingllm - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — v4.1.1.1 — INT-S004 recovery rebuild (2026-06-02)

### Added

- **This site, re-rendered from the `anythingllm-docker` template** as a fresh
  droplet replacing the locked-out `s004.ccc.bot` box (same hostname). The
  render was validated by diff against the hardened `sites/ai.weown.agency/`
  (INT-P01) — deployable files are byte-identical modulo names.
- **`scripts/bootstrap-s004-infisical.sh`** — prompts (`read -rs`, no disk / no
  history) for the app secrets and pushes them to the dedicated s004 Infisical
  project; generates `JWT_SECRET`; computes the `OPENROUTER_API_…7D_EXP_…` key name.
- **`MIGRATION_RUNBOOK.md`** — recovery runbook: Infisical prep → provision →
  deploy → restore the off-box `s004_storage_<TS>.tar.gz` export → verification
  gates → DNS cutover → soak → decommission. Old box untouched until soak.

### Fixed (root causes of the old s004.ccc.bot failures)

- **Auth lockout** (`JWT_SECRET is unset`): `JWT_SECRET` is present + persistent
  in the dedicated s004 Infisical project (set once, never rotate); the container
  only starts under `infisical run`; `docker/compose.prod.yaml` uses a
  `${JWT_SECRET:?…}` guard so a bypass of `infisical run` **fails loud**.
- **No backups**: the ansible deploy installs the daily backup cron + logrotate;
  the runbook proves a backup reaches `s3://weown-backups/int-s004-anythingllm/`
  before decommission.

### Decisions

- **Single-host `s004.ccc.bot`** (same hostname as the box it replaces).
- **Dedicated s004 Infisical project** (least privilege; not INT-P01's `weown-anythingllm`).
- **Committed host-side `infisical run`** (not in-container injection / the ADR-006 proposal).

---

## [v3.3.4.1] — 2026-04-23

### Added

- Initial anythingllm-docker copier template for DigitalOcean droplet deployments
- Docker Compose stack: AnythingLLM (LanceDB embedded) + Caddy reverse proxy
- Infisical runtime secret injection — zero application secrets on disk
  - `infisical run` fetches OPENROUTER_API_KEY, JWT_SECRET, ADMIN_EMAIL at container startup
  - Infisical Machine Identity (Client ID + Secret) is the only credential in terraform.tfvars
- Skinny backup system with grandfather-father-son retention policy
  - Daily backups retained for 30 days
  - Monthly backups (1st of month) retained for 12 months
  - Yearly backups (Jan 1st) kept forever
- DigitalOcean Spaces remote backup upload via `aws s3` CLI
- Idempotent deploy script (`scripts/deploy.sh`) using Infisical runtime injection
- Backup (`scripts/backup.sh`) and restore (`scripts/restore.sh`) scripts
  - Restore supports automatic fetch from DO Spaces if backup not found locally
- Terraform/OpenTofu infrastructure: droplet, reserved IP, firewall, monitoring alerts
  - CPU, memory, and disk utilization alerts via DigitalOcean monitoring
- Cloud-init bootstrap with Docker, Infisical CLI, unattended-upgrades
- Security hardening: firewall (22, 80, 443), Docker daemon config (log rotation, overlay2)
- Caddy automatic TLS with Let's Encrypt + security headers

### Security

- No application secrets committed to git or written to droplet disk
- All sensitive configuration sourced from Infisical Cloud at runtime
- Backup encryption at rest via DO Spaces SSE
- Docker volumes for persistent storage (no bind mounts for app data)

### Compliance

- NIST CSF 2.0: PR.DS (data security), PR.AC (access control), DE.CM (monitoring)
- CIS Controls v8 IG1: CIS 3.11 (encrypt sensitive data at rest), CIS 4.1 (secure config)
- ISO 27001-ready: A.5.17 (authentication info), A.8.24 (use of cryptography)

---

## Template Parameters Used

| Parameter | Value |
|-----------|-------|
| `project_name` | int-s004-anythingllm |
| `domain` | s004.ccc.bot |
| `do_region` | atl1 |
| `droplet_size` | s-2vcpu-4gb-amd |
| `anythingllm_image` | reg.mini.dev/anythingllm:1.7.2 |
| `caddy_image` | reg.mini.dev/caddy:2 |
| `llm_provider` | openrouter |
| `vector_db` | lancedb |
| `infisical_project_id` |  |
| `infisical_environment` | prod |
| `enable_skinny_backups` | True |
| `backup_remote_storage` | do-spaces |

---

## Migration Notes

If migrating from the Kubernetes Helm deployment in `ai/anythingllm/`:

1. **Data**: Export the PVC contents as a tarball and restore into the Docker volume
2. **Secrets**: Move from Kubernetes secrets (`anythingllm-secrets`) to Infisical project
3. **Ingress**: Replace NGINX Ingress + cert-manager with Caddy (automatic TLS)
4. **Backups**: Replace Kubernetes CronJob with cron.daily + `infisical run` wrapper

See `README.md` for detailed migration procedures.
