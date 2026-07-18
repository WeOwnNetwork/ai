# AnythingLLM Production Operations Runbook

> Status: draft · 2026-07-17 · Owner: ncimino
> Scope: day-2 operations for the live AnythingLLM droplets. Deploy mechanics
> live in [`anythingllm-docker/DEPLOYMENT_GUIDE.md`](../../anythingllm-docker/DEPLOYMENT_GUIDE.md);
> customer lifecycle detail in [`CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md).
> Public repo: no secrets, no IPs, no Infisical project UUIDs — reference form only.

## 1. Fleet map

| Site dir (`anythingllm-docker/sites/`) | Domain | Droplet / project name | Notes |
|---|---|---|---|
| `s004.ccc.bot/` | s004.ccc.bot | `int-s004-anythingllm` | Live reference deployment. **Host-side `infisical run` variant** (pre-ADR-006) |
| `dev-weown-anythingllm/` | do.weown.tools | `dev-weown-anythingllm-anythingllm` | INT-P07, WeOwnLLM build |
| `ai.weown.agency/` | ai.weown.agency | `int-p01-anythingllm` | DOKS→Docker migration in flight (ADR-005) |
| `s004/` | — | — | **RETIRED tombstone — never deploy** |

The `anythingllm` doctl tag is BROADER than this map — as of 2026-07-18 it
covers 12 droplets, including customer instances (`weownllm-f1visa`,
`weownllm-burnedout`, `ads-ptoken-agency-anythingllm-atl1`), shared/experimental
boxes (`prime-weown-dev`, `pop-weown-tools`, `meta-qwen-weown-tools`,
`Paperless-ngx-DocsWeOwnTools`), and **powered-off** droplets
(`s004-ccc-bot-…` — the pre-resize s004 box, `ceo-weown-team-…`,
`lite-ocpa-group-…`). Enumerate live state before any tag-wide operation:

```bash
doctl compute droplet list --tag-name anythingllm --format Name,Status --no-header
```

Tag-wide `manage-droplets.sh exec/deploy` hits ALL active tagged boxes — do not
assume the tag equals the three template-managed sites above. Off droplets are
suspend-state or superseded hardware; confirm owner intent before deleting.

**SSH always targets the droplet's DIRECT IP, never the DNS name** — DNS points
at the reserved IP (a service address that can move between droplets):

```bash
doctl compute droplet get <droplet-name> --format PublicIPv4 --no-header
```

## 2. Where credentials live (reference only)

- **`weown-tofu` Infisical project** — operator `TF_VAR_*` infra creds
  (per-dev `infisical login`; never reaches droplets).
- **Per-site Infisical app project** — `JWT_SECRET`, `OPENROUTER_API_KEY`,
  `ANYTHINGLLM_IMAGE`, `ADMIN_EMAIL`, `SPACES_ACCESS_KEY/SECRET_KEY`,
  `OPS_AUTHORIZED_KEYS`, `BACKUP_GPG_PUBLIC_KEY`, dashboard secrets. Project ID
  (non-secret) is committed in the site's `site.conf`.
- **Droplet Machine Identity** — `/opt/<project_underscored>/.infisical-auth.env`
  (root 0600); the bootstrap secret is Layer-2 rotated at first boot — verify
  `/var/log/<project_underscored>-rotation.log` ends `===== Rotation complete =====`.
- **Operator store** — `OPENROUTER_PROVISIONING_KEY`,
  `BACKUP_GPG_PRIVATE_KEY_<project>` (backup decryption; never on droplets).

Never print secret values into a terminal/agent context — see `AGENTS.md`.

## 3. Health checks

```bash
curl -sSI https://<domain>/api/ping          # 200 = app up (TLS + proxy path)
./scripts/manage-droplets.sh status anythingllm   # docker ps + uptime, whole tag
```

- `/api/ping` returns 200 **even when auth/config is broken** — real validation
  is: log in, workspaces list, retrieval hit, one chat completion.
- Container healthcheck: `curl -f http://localhost:3001/api/ping` (30s interval).
- Dashboard (product sites): `https://<domain>/app/` → `/healthz` on :3000.
- memcg OOM kills are invisible to DO host alerts — the SigNoz log alert
  ("Fleet: container memcg OOM kill", `scripts/create-signoz-oom-alert.sh`)
  pages on the kernel `Memory cgroup out of memory` line.

## 4. Restart / bounce

```bash
ssh root@<droplet-ip>
cd /opt/<project_underscored>
docker compose restart anythingllm
```

- ADR-006 sites: restart **re-fetches secrets** from Infisical
  (bounce-to-refresh). The s004 host-side variant instead needs the committed
  deploy path (`infisical run -- docker compose up -d`) to pick up new values.
- To *test* the restart policy, kill **PID 1 inside the container**
  (`docker exec <c> kill -9 1`) — `docker kill` is operator-initiated and
  `restart: unless-stopped` will NOT fire (this exact mistake caused a 13-hour
  s004 outage, 2026-06-12).
- After any bounce, compare
  `docker inspect --format '{{json .Config.Env}}' <c> | sha256sum` pre/post —
  the 2026-06-10 s004 incident was a restart silently reverting
  `EMBEDDING_ENGINE` to the compose default. **Pin all runtime config in
  Infisical; never rely on UI-only settings.** Changing `EMBEDDING_ENGINE`
  invalidates every LanceDB vector.

## 5. Upgrade

1. Edit `ANYTHINGLLM_IMAGE` in the site's Infisical project (pin a tag —
   Minimus rotates them; fresh droplets need a one-time
   `docker login reg.mini.dev` before first pull).
2. `cd anythingllm-docker/sites/<domain> && ./scripts/deploy.sh root@<droplet-ip>`
   (idempotent; recreates the container).
3. Validate per §3 (real login + chat, not just `/api/ping`).

Cloud-init/infra changes go through the site's `terraform/` (`./itofu.sh plan/apply`;
state in DO Spaces `weown-prod-state`, SSE-C). `tofu taint` of the droplet =
downtime — schedule it.

## 6. Backup posture

- **Daily cron** per droplet (`/etc/cron.daily/<project_underscored>-backup`,
  log `/var/log/<project>-backup.log`). Manual: `./scripts/backup.sh root@<droplet-ip>`.
- Contents: the `anythingllm_storage` volume (SQLite DB, `storage/.env` UI
  settings, LanceDB vectors, uploads, encryption keys) + Caddy volumes + config.
- Offload: `s3://weown-prod-backups/<project>/` (canonical bucket); GFS
  retention 30 daily / 12 monthly / yearly.
- Customer instances: tarball is **GPG-encrypted client-side** (per-customer
  key; public key on site, private key operator-only) and app data sits on a
  dedicated encrypted DO block-storage volume.
- Restore: `./scripts/restore.sh root@<droplet-ip> <backup-name>` (name only,
  no paths/URLs; auto-fetches from Spaces; runs under `infisical run`).
- Infisical down? Running containers keep working; deploys/backups/rotation
  break — follow [`INFISICAL_OUTAGE_RUNBOOK.md`](../INFISICAL_OUTAGE_RUNBOOK.md).

## 7. Customer-instance lifecycle (concierge SaaS)

Full detail: [`CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md).

1. **Provision** — render site from `anythingllm-docker`, `./itofu.sh apply`
   (or `scripts/deploy-new-site.sh --template anythingllm-docker`, which also
   creates the Infisical project + MI; note it does NOT push
   `OPENROUTER_API_KEY`/`ANYTHINGLLM_IMAGE` — add those manually).
2. **LLM key** — `scripts/provision-openrouter-key.sh --customer <slug>
   --project-id <site-project> --limit-usd <cap>`: per-customer, budget-capped,
   monthly reset, written straight into the site project (ZDR-only routing).
3. **Deploy + product bootstrap** — `./scripts/deploy.sh`, then
   `./scripts/bootstrap-product.sh --base https://<domain> --project-id <id>`
   (creates `ws-public`/`ws-private`, embed widget, dashboard secrets), then
   redeploy. Customer touches only the dashboard (`/app/`); WeOwn keeps the
   `admin` role + SSH.
4. **Operate** — §3–§6 above.
5. **Suspend / deprovision** — final backup → power off (keep reserved IP +
   Infisical project) for suspend; destroy via `./itofu.sh`, revoke the
   customer's OpenRouter key, delete the Infisical project/MI for exit. Final
   backup retained 60 days.

## 8. Observability

- OTel agent per host (`scripts/bootstrap-otel-agent.sh` once, then
  `scripts/deploy-otel-fleet.sh --tag weown-ai`) → SigNoz Cloud (host metrics +
  Caddy access logs).
- DO monitoring alerts (CPU/mem/disk) from each site's `monitoring.tf`.
- Sizing rule of thumb: leave ~2 GB for OS+Caddy+OTel — 4 GB droplet → 2G
  container limit, 8 GB → 6G, 16 GB → 12G. s004 history says agent-RAG needs
  the 8 GB tier.
