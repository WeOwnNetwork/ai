# int-s004-anythingllm - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — v4.1.1.1 — INT-S004 rebuild as s004.weown.net (2026-06-02)

### Added

- **New site `sites/s004.weown.net/`** — a fresh AnythingLLM droplet for
  INT-S004 under the new standard FQDN `s004.weown.net`, replacing the
  locked-out `s004.ccc.bot` box. Mirrors the most-hardened sibling
  [`sites/ai.weown.agency/`](../ai.weown.agency/) (INT-P01, PR #36) line-for-line
  modulo names: `project_name=int-s004-anythingllm`, `domain=s004.weown.net`,
  `anythingllm_image=reg.mini.dev/anythingllm:1.7.2` (same pin as the source box —
  no schema migration on restore).
- **`MIGRATION_RUNBOOK.md`** — parallel-build + DNS-cutover recovery runbook:
  provision (Path C — DO Spaces remote tofu state, slim cloud-init, Layer 2
  secret rotation) → DNS → ansible app deploy → restore the off-box
  `s004_storage_<TS>.tar.gz` export → verification gates → soak → decommission
  the old box. The old `s004.ccc.bot` droplet is never modified until after
  soak, so rollback is keeping it untouched + the off-box export as last resort.

### Fixed (root causes of the old s004.ccc.bot failures)

- **Auth lockout (`Cannot create JWT as JWT_SECRET is unset`).** `JWT_SECRET`
  is now present + persistent in the dedicated s004 Infisical project (`prod`),
  set once and never rotated, and the container only ever starts under
  `infisical run`. `docker/compose.prod.yaml` now uses a `${JWT_SECRET:?...}`
  guard so a bare `docker compose up` that bypasses Infisical **refuses to
  start** instead of serving broken auth.
- **No backups.** The canonical `ansible/deploy.yml` installs the daily
  `/etc/cron.daily/int_s004_anythingllm-backup` cron + logrotate, and the
  runbook proves a backup lands in `s3://weown-backups/int-s004-anythingllm/`
  before the old box is decommissioned.

### Decisions

- **Secret-injection model = committed host-side `infisical run`** (what
  `ai.weown.agency` ships). In-container injection (proposed separately as
  ADR-006) is explicitly NOT used here — that out-of-band, uncommitted change
  on the old box is what
  dropped `JWT_SECRET` and caused the lockout.
- **Single-hostname `s004.weown.net`.** A repo-wide audit confirmed nothing
  routes to the legacy `s004.ccc.bot` (only self-references in the retired
  `sites/s004/` and historical prose), and the old box is locked out, so there
  is no legacy traffic to preserve. Re-adding `s004.ccc.bot` later is a
  one-line Caddyfile edit + `./scripts/deploy.sh` (no `tofu taint`).
- **Dedicated s004 Infisical project** + Machine Identity scoped to s004 only
  (least privilege), distinct from INT-P01's `weown-anythingllm`.

### Pattern

Adopts the **Path C + Layer 2 bootstrap pattern** from
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md):
cloud-init handles ONLY first-boot bootstrap (Docker, Infisical CLI, Layer 2
bootstrap-secret rotation); `ansible/deploy.yml` owns the app layer (compose,
Caddyfile, backup cron) — re-runnable any time without `tofu taint`.

---

## Template Parameters Used

| Parameter | Value |
|-----------|-------|
| `project_name` | int-s004-anythingllm |
| `domain` | s004.weown.net |
| `do_region` | atl1 |
| `droplet_size` | s-2vcpu-4gb-amd |
| `anythingllm_image` | reg.mini.dev/anythingllm:1.7.2 |
| `caddy_image` | reg.mini.dev/caddy:2 |
| `llm_provider` | openrouter |
| `vector_db` | lancedb |
| `infisical_environment` | prod |
| `enable_skinny_backups` | true |
| `backup_remote_storage` | do-spaces |

---

## Migration Notes

This site's reason for existing is the INT-S004 recovery: the old
`s004.ccc.bot` droplet became unusable (JWT_SECRET dropped on a container
restart; no backups had ever been configured). See
[`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md) for the phase-by-phase rebuild
and the verification gates that close both failure modes.
