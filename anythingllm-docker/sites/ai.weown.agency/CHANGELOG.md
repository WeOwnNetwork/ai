# int-p01 - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — INT-P01 DOKS → Docker migration

### Added

- **`MIGRATION_RUNBOOK.md`** — phased runbook covering inventory/freeze, staging
  droplet provision, DOKS data extraction, restore, Jason/Yonks validation,
  production cutover, soak, and rollback. Source plan reference: D383 / Tuleap
  A174 (#1238).
- **`scripts/migrate-from-doks.sh`** — one-shot bridge that `kubectl exec`s into
  the live DOKS pod, streams `/app/server/storage` out as a tarball, and wraps
  it in the same layout `scripts/restore.sh` already understands. Optional
  `--upload-to-spaces` mirrors the artifact to `s3://weown-backups/int-p01/`.
- Generated from `anythingllm-docker` copier template at branch
  `feature/nik-int-p01-doks-to-docker-migration` — `project_name=int-p01`,
  `domain=ai.weown.agency`, `anythingllm_image=reg.mini.dev/anythingllm:latest`
  (WeOwnLLM hardened, per D381; confirmed working on s004.ccc.bot 2026-05-21).

### Migration approach (summary)

Parallel build + DNS cutover. DOKS is never modified during the migration —
rollback is a DNS flip until decommission (T+7 days post-cutover).

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
| `project_name` | int-p01 |
| `domain` | ai.weown.agency |
| `do_region` | atl1 |
| `droplet_size` | s-2vcpu-4gb-amd |
| `anythingllm_image` | reg.mini.dev/anythingllm:latest |
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
