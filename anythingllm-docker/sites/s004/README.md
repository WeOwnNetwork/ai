# s004-anythingllm — AnythingLLM (RETIRED)

> ⚠️ **RETIRED — do not deploy.** This is the locked-out old `s004.ccc.bot` box
> (JWT_SECRET was dropped on a container restart; no backups were ever
> configured). It has been superseded by the fresh rebuild at
> [`../s004.ccc.bot/`](../s004.ccc.bot/) (same hostname, re-rendered from the
> hardened template). Kept only as a historical record / for decommission — see
> [`../s004.ccc.bot/MIGRATION_RUNBOOK.md`](../s004.ccc.bot/MIGRATION_RUNBOOK.md).

## What this was

The original Story-004 AnythingLLM deployment: Docker Compose (AnythingLLM +
LanceDB embedded, behind Caddy) on a single DigitalOcean droplet, with Infisical
runtime secret injection.

## Why it was retired

It failed two ways, both fixed by the rebuild at [`../s004.ccc.bot/`](../s004.ccc.bot/):

- **Auth lockout** — `JWT_SECRET` was lost when the container was recreated
  outside `infisical run`, and every login failed. The rebuild adds a fail-loud
  `${JWT_SECRET:?…}` guard so the stack refuses to boot rather than serving
  broken auth, and always starts under `infisical run`.
- **No backups** — the daily backup cron was never installed, so nothing reached
  DO Spaces. The rebuild installs it via the canonical Ansible deploy.

## Current docs

The deployment flow, secrets model, and operations for the **live** box are in:

- [`../../DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md) — the operator guide
- [`../s004.ccc.bot/README.md`](../s004.ccc.bot/README.md) — the live INT-S004 site
- [`../../template/README.md.jinja`](../../template/README.md.jinja) — the template this was rendered from

> The original step-by-step that lived here has been removed so no one follows
> the stale, pre-hardening procedure. Use the links above instead.
