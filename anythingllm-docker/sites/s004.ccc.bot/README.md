# int-s004-anythingllm (s004.ccc.bot) — INT-S004 (live)

This is the **live** INT-S004 deployment: a fresh DigitalOcean droplet that
**replaced** the locked-out `s004.ccc.bot` box, **keeping the same hostname**
`s004.ccc.bot`. It was rebuilt from the [`anythingllm-docker`](../../) copier
template (not hand-copied), the data was restored off the old box and validated,
and **DNS was cut over to its reserved IP**; the old box is shut down and soaking
before decommission. It follows the Path C + Layer 2 pattern in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md).

> 📓 **The rebuild is complete.** [`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md)
> is retained as the record of how it was done — Infisical setup (via
> [`scripts/bootstrap-s004-infisical.sh`](scripts/bootstrap-s004-infisical.sh)),
> provisioning, the off-box data restore, the verification gates, the DNS
> cutover, soak, and decommission of the old box. For steady-state operations,
> see [`../../DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md).

## Why this rebuild exists

The old `s004.ccc.bot` failed two ways; this box is built to close both.

- **Auth lockout.** AnythingLLM logged `Cannot create JWT as JWT_SECRET is
  unset` at `makeJWT`. A container restart came back with `JWT_SECRET` empty
  because the container was recreated **without** going through `infisical run`,
  and every login failed. **Fix:** `JWT_SECRET` lives in the dedicated s004
  Infisical project (`prod`) — set once, never rotated — the container only ever
  starts under `infisical run`, and [`docker/compose.prod.yaml`](docker/compose.prod.yaml)
  now **fails loud** (`${JWT_SECRET:?…}`) if the secret is missing instead of
  booting with broken auth.
- **No backups.** The old box never got the canonical ansible deploy, so the
  daily backup cron was never installed and nothing reached DO Spaces.
  **Fix:** the ansible deploy installs `/etc/cron.daily/int_s004_anythingllm-backup`,
  and the runbook proves a backup lands in DO Spaces before decommission.

> ⚠️ `/api/ping` returns **200 even when auth is broken** — it is an
> unauthenticated liveness probe. A green healthcheck does NOT mean logins work.
> Always verify a real login + a retrieval query by hand (runbook Phase 5).

## Key facts

| | |
|---|---|
| `project_name` | `int-s004-anythingllm` → `/opt/int_s004_anythingllm`, volume `int_s004_anythingllm_storage`, cron `int_s004_anythingllm-backup` |
| Hostname | single-host `s004.ccc.bot` (same name as the box it replaces) |
| Secret injection | committed host-side `infisical run` (**not** in-container injection — proposed separately as ADR-006, not adopted here) |
| Infisical project | **dedicated s004 project** (least privilege; distinct from INT-P01's `weown-anythingllm`) |
| Image | `ANYTHINGLLM_IMAGE` injected from Infisical — currently **`v1.12.1`**. The old box actually ran `:latest` (digest `7a2f7157`), so restoring its data into v1.12.1 forward-migrated the schema on first boot (it did not fail). |

## Steady-state deployment flow

This site is **already generated** (re-rendered from the template) — there is no
`copier copy` step. Operator steps (full detail + the data restore in
[`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md)):

### 1. Prep Infisical (dedicated s004 project, prod env)

Create the dedicated s004 Infisical project + a Machine Identity scoped to it,
then run the bootstrap script — it reads each secret with `read -rs` (never to
disk/history) and pushes them to Infisical:

```bash
bash scripts/bootstrap-s004-infisical.sh
```

It sets `JWT_SECRET` (generated, never rotate), `OPENROUTER_API_KEY` (a **fresh,
long-lived** key — the original expired 2026-06-01; avoid short-expiry keys),
`ADMIN_EMAIL`, `ANYTHINGLLM_IMAGE` (the container image ref, e.g.
`reg.mini.dev/<ns>/anythingllm:v1.12.1` — kept in Infisical so the private
registry namespace stays out of this public repo), `SPACES_ACCESS_KEY`,
`SPACES_SECRET_KEY`.

### 2. Provision (OpenTofu — first-boot bootstrap)

```bash
cd terraform
# itofu.sh runs tofu under `infisical run` against the operator weown-tofu
# project, injecting TF_VAR_* — no terraform.tfvars on disk.
./itofu.sh init && ./itofu.sh plan && ./itofu.sh apply
ssh root@<ip> 'tail /var/log/int_s004_anythingllm-rotation.log'   # expect "===== Rotation complete ====="
```

### 3. Deploy the app (ansible — app layer + every subsequent update)

```bash
INFISICAL_PROJECT_ID=<s004-project-id> ./scripts/deploy.sh root@<ip>
```

Uploads compose + Caddyfile + backup.sh, installs the daily backup cron +
logrotate, pulls images, runs `docker compose up -d` **under `infisical run`**,
and tags the droplet. Idempotent — re-run any time compose/Caddy/backup change.

### Updating

| Change | How |
|---|---|
| compose / Caddyfile / backup.sh | `./scripts/deploy.sh root@<ip>` — no terraform |
| image bump | edit `ANYTHINGLLM_IMAGE` in Infisical, then `./scripts/deploy.sh root@<ip>` — no repo change, no terraform |
| cloud-init | `tofu taint digitalocean_droplet.anythingllm && tofu apply` (droplet downtime) |
| Infisical secrets | edit in Infisical UI, then re-run `./scripts/deploy.sh root@<ip>` — it recreates the container under `infisical run` so the new value is picked up (`docker compose restart` reuses the old env and won't). **Never rotate `JWT_SECRET`.** |

## Security

- **No app secrets in git or on disk** — only the Machine Identity reaches the node (Layer 2 rotates even that on first boot)
- **Fail-loud auth** — compose refuses to start if `JWT_SECRET` is not injected
- **TLS** via Caddy (Let's Encrypt); **firewall** 22/80/443; resource limits + security headers

## Observability

DigitalOcean monitor alerts: CPU > 80%, Memory > 90%, Disk > 85%.

An OTel agent ships host metrics + Caddy logs to **SigNoz Cloud**, deployed by the
fleet scripts (`scripts/bootstrap-otel-agent.sh`, `scripts/deploy-otel-fleet.sh`,
tag `weown-ai`). It authenticates with the shared `otel` Infisical project's
**reader Machine Identity — not this box's app MI** (see
[`../../DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md) §9).

> **Restore caveat (learned during this rebuild):** AnythingLLM reads its
> LLM-provider settings — including the OpenRouter API key — from its **own
> database**, so on a restored instance the injected `OPENROUTER_API_KEY` env var
> does not override the restored value. If chat returns `401 Missing
> Authentication header`, re-enter the key in **Settings → AI Providers → LLM
> Preference → OpenRouter** in the UI.
