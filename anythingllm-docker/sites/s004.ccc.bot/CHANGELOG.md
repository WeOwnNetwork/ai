# int-s004-anythingllm - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — v4.1.2.3 — droplet-replacement incident: lifecycle guards + rebuild fixes (2026-06-12)

**Incident**: the Phase-3 resize apply (this runbook, 2026-06-12 ~02:51 UTC)
**destroyed and recreated the droplet** instead of resizing in-place: the
shared weown-tofu `TF_VAR_ssh_key_fingerprint` had changed since the June-2
build, `ssh_keys` is create-time-only, and the plan's
`ssh_keys # forces replacement` marker was missed at the gate. All Docker
volumes died with the box. **Recovered in ≈1 h from the Phase-1 Spaces
backup** (deploy → restore → deploy; data loss = 19 min of chats; user
sessions survived because `JWT_SECRET` is pinned). Full as-run record +
rebuild gotchas table: `RESIZE_RUNBOOK.md` appendix.

### Changed

- **`terraform/main.tf` (+ template) — droplet lifecycle guards**:
  `prevent_destroy = true` (any destroy plan is now a hard error — flip it
  in a reviewed commit to intentionally rebuild) and
  `ignore_changes = [ssh_keys]` (the shared bootstrap-key var becomes a
  create-time-only input; operator key changes can never again arm a fleet
  of silent droplet replacements). Root access post-create is governed by
  `OPS_AUTHORIZED_KEYS`, so ignoring drift costs nothing.
- **`DEPLOYMENT_GUIDE.md` §10** — Minimus registry login corrected:
  username **`minimus`** + token as password ("token-as-both" was wrong,
  401'd on the rebuild); documented that the login is per-droplet state
  that every rebuild must redo before its first deploy, with a token-safe
  stdin command.

### Added

- **`RESIZE_RUNBOOK.md` appendix — as-run record** of the replacement
  incident: root cause, the recovery sequence that worked, and the six
  rebuild gotchas hit on the way (bootstrap-key-only SSH, failed Layer-2
  secret rotation + missing MI permission, Minimus auth, monitor-alert
  404s + `state rm` fix, pyenv/ansible PATH, direct-IP changes).

### Fixed

- **`RESIZE_RUNBOOK.md` Phase 5 bounce test corrected** — it used
  `docker kill <container>` and wrongly expected `restart: unless-stopped`
  to auto-restart it. An operator-initiated `docker kill` is treated as an
  intentional stop, so the restart policy does **not** fire and the
  container stays down — this took s004 offline for 13 h on 2026-06-12
  (`exit 137`, `restarts=0`, clean logs, 6 GiB limit and host RAM both
  fine: not an OOM, a stuck test). Now kills **PID 1 inside** the container
  (`docker exec … kill -9 1`) — an unexpected exit that the policy DOES
  honour, faithfully simulating the kernel OOM — and asserts
  `RestartCount` incremented. Recovery note corrected to plain
  `docker start <container>` (bare `docker compose` fails the
  `${ANYTHINGLLM_IMAGE:?…}` guard unless wrapped in `infisical run`).

---

## [Unreleased] — v4.1.2.2 — OOM stability hardening + droplet resize (2026-06-10)

**Incident**: 2026-06-10 01:00:33 MT — the AnythingLLM container was
memcg-OOM-killed mid agent-RAG chat (4 pinned sources ≈ 19.4k tokens + the
in-process native reranker over 44 docs + LanceDB pushed the node server past
the 2 GiB compose limit; exit 137). Docker auto-restarted in ~9 s, but
`EMBEDDING_ENGINE` fell back to the compose default `native` (the operator's
UI-side switch to `openrouter` was never pinned in Infisical), so every RAG
query failed on a vector-dimension mismatch (384 vs the openrouter-built
LanceDB tables) and agent chats threw OpenRouter `401`, until ~35 min of
manual reconfiguration + a 7.6k-document purge/re-embed. Root-cause analysis:
SigNoz log export, 06:59–07:35 UTC.

### Changed

- **`terraform/variables.tf`** — `droplet_size` `s-2vcpu-4gb-amd` →
  **`s-4vcpu-8gb-amd`**: memory headroom for agent RAG + reranker, and 4 vCPUs
  clears LanceDB's "CPUs ≤ IO core reservations" warning observed all through
  the incident window.
- **`terraform/main.tf`** — explicit **`resize_disk = false`** (provider
  default is `true`): the resize is CPU/RAM-only, keeps the 80 GB disk and
  every Docker volume untouched, and stays reversible (DO disk grows are
  permanent).
- **`docker/compose.prod.yaml`** — AnythingLLM memory limit **2G → 6G**
  (reservation 1G → 2G), sized to the 8 GB droplet (6G app + 256M caddy +
  ~0.5G otel-agent + ~1G OS). The reranker still runs in-process, so reranked
  chats legitimately spike RSS.
- **`docker/compose.prod.yaml`** — **`EMBEDDING_ENGINE` is now fail-loud**
  (`:?`), same pattern as `JWT_SECRET`/`OPENROUTER_API_KEY`/`ANYTHINGLLM_IMAGE`:
  the embedder determines LanceDB vector dimensions, so a silent `:-native`
  fallback after a bounce breaks all retrieval. Compose header now documents
  the rule: **Infisical is the only source of truth for runtime config; UI
  changes do not survive a bounce.**
- **`scripts/bootstrap-s004-infisical.sh`** — now also prompts (plain read,
  non-secret) for `EMBEDDING_ENGINE` / `EMBEDDING_MODEL_PREF` /
  `OPENROUTER_TIMEOUT_MS` with the s004 prod values
  (`openrouter` / `perplexity/pplx-embed-v1-4b` / `10000`), so a fresh
  bootstrap satisfies the new fail-loud guard.

### Added

- **`RESIZE_RUNBOOK.md`** — gated operator runbook: skinny backup → pin
  runtime config in Infisical → `itofu.sh` plan/apply resize (in-place
  update only; STOP on destroy/recreate) → redeploy → **bounce-and-verify
  gate** (`docker kill --signal=KILL`, env-fingerprint sha256 before/after
  must match, real-login + RAG-citation + @agent functional checks) → repair
  of the document that failed to vectorize 5/5 times during the incident
  re-embed (`…/intern_eval_comprehensive_2026-03-18.json`, missing from RAG
  in every workspace) → fleet OOM alert. Includes rollback table + compliance
  mapping (NIST CSF 2.0 PR.IP-3/RC.RP-1/DE.CM-1, CIS v8 4.1/4.2/11.1/11.2/8.11,
  ISO 27001 A.8.9/A.8.13/A.8.16).

### Fixed

- **Recovery idempotency**: a container bounce (OOM kill, `docker kill`,
  droplet reboot) now restores the exact running config from
  Infisical-injected env — no UI re-entry, no API-key re-pasting, no secrets
  on disk.

---

## [Unreleased] — v4.1.1.1 — INT-S004 recovery rebuild (2026-06-02)

### Added

- **This site, re-rendered from the `anythingllm-docker` template** as a fresh
  droplet replacing the locked-out `s004.ccc.bot` box (same hostname). The
  render was validated by diff against the hardened `sites/ai.weown.agency/`
  (INT-P01) — at render time its deployable files matched ai.weown.agency modulo
  names (since hardened further: do_token, weown-prod-* buckets, itofu.sh, team SSH keys).
- **`scripts/bootstrap-s004-infisical.sh`** — prompts (`read -rs`, no disk / no
  history) for the app secrets and pushes them to the dedicated s004 Infisical
  project; generates `JWT_SECRET`; computes the `OPENROUTER_API_…7D_EXP_…` key name.
- **`MIGRATION_RUNBOOK.md`** — recovery runbook: Infisical prep → provision →
  deploy → restore the off-box `s004_storage_<TS>.tar.gz` export → verification
  gates → DNS cutover → soak → decommission. Old box untouched until soak.
- **Team SSH access standard** — ansible writes the team's public keys (from the
  Infisical `OPS_AUTHORIZED_KEYS` var, one per line) to root's
  `authorized_keys.weown-ops` (managed exclusively, alongside the untouched
  break-glass key); grant/revoke = edit the var + `./scripts/deploy.sh` (e.g. on
  termination). Mirrored into the copier template for all future sites.

### Fixed (root causes of the old s004.ccc.bot failures)

- **Auth lockout** (`JWT_SECRET is unset`): `JWT_SECRET` is present + persistent
  in the dedicated s004 Infisical project (set once, never rotate); the container
  only starts under `infisical run`; `docker/compose.prod.yaml` uses a
  `${JWT_SECRET:?…}` guard so a bypass of `infisical run` **fails loud**.
- **No backups**: the ansible deploy installs the daily backup cron + logrotate;
  the runbook proves a backup reaches `s3://weown-prod-backups/int-s004-anythingllm/`
  before decommission.

### Decisions

- **Single-host `s004.ccc.bot`** (same hostname as the box it replaces).
- **Dedicated s004 Infisical project** (least privilege; not INT-P01's `weown-anythingllm`).
- **Committed host-side `infisical run`** (not in-container injection / the ADR-006 proposal).

### Deployed (live, 2026-06-02)

- **Image**: `ANYTHINGLLM_IMAGE` injected from Infisical = **`v1.12.1`** (not the
  render-time `anythingllm_image` value in the parameters table below — compose
  reads `${ANYTHINGLLM_IMAGE:?…}` at runtime). The old box actually ran `:latest`
  (digest `7a2f7157`); restoring its data into v1.12.1 forward-migrated the schema
  cleanly on first boot.
- **Cutover**: DNS `s004.ccc.bot` flipped to the new droplet's reserved IP; HTTPS
  live via Let's Encrypt. Data verified intact (23 workspaces / 12 users / 635
  chats). A backup was proven to `s3://weown-prod-backups/int-s004-anythingllm/`.
  Old box shut down and soaking before decommission.
- **Restore caveat**: AnythingLLM reads its LLM-provider settings (including the
  OpenRouter key) from its **own database**, so the injected `OPENROUTER_API_KEY`
  did not override the restored value — the key had to be re-entered in the UI
  (Settings → AI Providers → LLM Preference → OpenRouter). Use a long-lived key.
- **Observability**: OTel agent shipping host metrics + Caddy logs to SigNoz Cloud
  (shared `otel` project reader Machine Identity; deployed via the fleet scripts).

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
| `anythingllm_image` | _vestigial_ — runtime image comes from Infisical `ANYTHINGLLM_IMAGE` (deployed `v1.12.1`) |
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
