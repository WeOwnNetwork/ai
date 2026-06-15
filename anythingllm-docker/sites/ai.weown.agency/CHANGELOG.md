# int-p01-anythingllm - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — v3.4.5.1 — INT-P01 DOKS → Docker migration site (2026-05-25)

### Added

- **`MIGRATION_RUNBOOK.md`** — phased runbook covering inventory/freeze,
  staging droplet provision (Path C — DO Spaces remote tofu state, slim
  cloud-init, Layer 2 secret rotation), DOKS data extraction, ansible app
  deploy + restore, Jason/Yonks validation, production cutover (DNS swap on
  the dual-hostname droplet — no re-deploy), soak, and rollback. Source
  plan: D383 / Tuleap A174 (`#1238`). Decision record:
  [`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md).
- **`scripts/migrate-from-doks.sh`** — one-shot bridge that `kubectl exec`s
  into the live DOKS pod, streams `/app/server/storage` out as a tarball,
  and wraps it in the exact skinny-backup layout `scripts/restore.sh`
  already understands. Optional `--upload-to-spaces` mirrors to
  `s3://weown-backups/int-p01-anythingllm/` for redundancy.

### Pattern

This site adopts the **Path C + Layer 2 bootstrap pattern** documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md)
(reference implementation: [`sites/s004.ccc.bot/`](../s004.ccc.bot/)).

- Cloud-init handles ONLY first-boot bootstrap (Docker, Infisical CLI,
  Layer 2 bootstrap-secret rotation).
- `ansible/deploy.yml` owns the app layer (compose, Caddyfile, backup
  cron) — re-runnable any time without `tofu taint`.
- Caddyfile is **dual-hostname** (`ai-stage.weown.agency, ai.weown.agency`)
  from first ansible deploy, so production cutover is a single DNS A-record
  swap on the same droplet — no re-deploy.

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
| `project_name` | int-p01-anythingllm |
| `domain` | ai.weown.agency |
| `do_region` | atl1 |
| `droplet_size` | s-2vcpu-4gb-amd |
| `anythingllm_image` | _vestigial_ — runtime image from Infisical `ANYTHINGLLM_IMAGE` (INT-P01 plans `reg.mini.dev/anythingllm:1.7.2`) |
| `caddy_image` | reg.mini.dev/caddy:2 |
| `llm_provider` | openrouter |
| `vector_db` | lancedb |
| `infisical_project_id` |  |
| `infisical_environment` | prod |
| `enable_skinny_backups` | True |
| `backup_remote_storage` | do-spaces |

---

## Migration Notes

This site's reason for existing is the INT-P01 (`ai.weown.agency`) migration
off DOKS — see [`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md) for the
phase-by-phase procedure and [`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md)
for the decision record.
