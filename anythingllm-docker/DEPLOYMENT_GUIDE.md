# Deploying a WeOwn AnythingLLM Instance — Operator Guide

**Audience:** WeOwn developers standing up a *new* AnythingLLM instance from the
[`anythingllm-docker`](./) copier template, or operating an existing one.
**Reference deployment:** INT-S004 (`s004.ccc.bot`) — the first instance fully
exercising this flow end-to-end. See [`sites/s004.ccc.bot/`](sites/s004.ccc.bot/).

This guide is the single source of truth for the deploy flow. For the *why*
behind the bootstrap architecture, read
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md).

---

## 1. What you get (the WeOwn stack)

Every instance deployed from this template ships with:

| Capability | How it works |
|---|---|
| **Runtime secret injection** | All app secrets live in Infisical and are fetched at container start via `infisical run -- docker compose up`. **No secrets on disk, ever** — only a Machine Identity is stored on the node. |
| **Path C + Layer 2 bootstrap** | A *thin* cloud-init (Docker + Infisical CLI + a Machine-Identity bootstrap-secret rotation) hands off to an idempotent Ansible app layer. Ongoing changes never require `tofu taint`/droplet rebuild. |
| **Skinny backups** | Daily cron tars the Docker volumes and offloads to DigitalOcean Spaces with grandfather-father-son retention (30 daily / 12 monthly / yearly forever). |
| **Static/reserved IP** | A DO **reserved IP** fronts the droplet, so DNS survives any future droplet rebuild. |
| **Automatic HTTPS** | Caddy obtains + renews a Let's Encrypt cert (TLS-ALPN-01) and reverse-proxies to AnythingLLM over an internal Docker network. |
| **Observability** | A fleet **OTel agent** ships host metrics + Caddy logs to **SigNoz Cloud** (separate deploy — see §9). |
| **Monitoring alerts** | DO CPU/memory/disk monitor alerts to a verified email. |
| **Fail-loud guards** | Compose refuses to start if `JWT_SECRET`, `OPENROUTER_API_KEY`, or `ANYTHINGLLM_IMAGE` aren't injected — so a misconfigured boot fails fast instead of serving broken auth/inference. |
| **Infisical-native OpenTofu** | `terraform/itofu.sh` runs `tofu` with `TF_VAR_*` injected from a separate operator-only Infisical project — no `terraform.tfvars` on disk. |
| **Remote tofu state** | State lives in DO Spaces (S3-compatible) with SSE-C encryption, per-site key. |

---

## 2. Architecture at a glance

```
                       DNS (A record) ─► DO Reserved IP ─► Droplet
                                                              │
  Terraform (itofu.sh, state in DO Spaces) provisions ───────┤
    droplet • reserved IP • firewall • monitor alerts         │
                                                              ▼
  cloud-init (thin): apt(docker, infisical, jq, unzip, awscli-v2)         [Path C]
    └─ writes /opt/<project>/.infisical-auth.env  (bootstrap Machine Identity)
    └─ runcmd: rotate-bootstrap-secret.sh  (Layer 2: mint v2 MI secret, revoke v1)
                                                              │
  ansible (scripts/deploy.sh, every change) ─────────────────┤
    uploads compose.yaml + Caddyfile + backup/restore.sh      │
    installs daily backup cron + logrotate                    │
    syncs team SSH keys (OPS_AUTHORIZED_KEYS)                 │
    `infisical run -- docker compose up -d`  ◄── injects app secrets at runtime
                                                              ▼
                          ┌───────────────── droplet ─────────────────┐
                          │  Caddy :80/:443  ──►  AnythingLLM :3001    │
                          │  (Let's Encrypt)      (internal network)   │
                          └────────────────────────────────────────────┘
  OTel agent (separate fleet deploy) ──► SigNoz Cloud
```

---

## 3. The secrets model (read this first)

We use **two Infisical projects** with very different trust levels. Understanding
this split is the key to the whole flow.

### 3a. `weown-tofu` — operator/infra secrets (per-dev, shared)

- Holds the `TF_VAR_*` **infrastructure** credentials that OpenTofu needs: the
  DigitalOcean API token, DO Spaces keys (state backend), the SSE-C key, the
  droplet's Machine-Identity client id/secret, the app project id, and the
  monitor `alert_email`.
- **Every dev authenticates with their own `infisical login`.** Because all WeOwn
  devs are members of the same Infisical org, the *same* `weown-tofu` project
  secrets are usable across devs — so any authorized dev can run a deployment —
  yet each dev's session is their own identity (auditable, revocable).
- Treat `weown-tofu` as the **per-dev landing zone for deployment tokens**: it
  never touches a droplet. A droplet compromise cannot reach the DO API token,
  because the droplet's Machine Identity can only read the *app* project (3b).
- These are injected as `TF_VAR_*` env vars by `terraform/itofu.sh` (§4), so they
  never land in a `terraform.tfvars` file on disk.

### 3b. The site app project — per-site application secrets

- A **dedicated Infisical project per instance** (least privilege; INT-S004 has
  its own, distinct from INT-P01's). Holds: `JWT_SECRET`, `OPENROUTER_API_KEY`,
  `ADMIN_EMAIL`, `ANYTHINGLLM_IMAGE`, `SPACES_ACCESS_KEY`/`SPACES_SECRET_KEY`
  (backups), `OPS_AUTHORIZED_KEYS` (team SSH).
- These belong to **the project/instance**, not to a dev. The droplet reads them
  at runtime via its **Machine Identity** (a scoped, non-human credential).

### 3c. Machine Identity + runtime injection

- cloud-init writes a **bootstrap** MI client secret to
  `/opt/<project>/.infisical-auth.env`, then **Layer 2** immediately rotates it
  (mints v2, swaps the file, revokes v1) so the secret that briefly lived in
  Terraform state / droplet metadata is invalidated.
- At every `docker compose up`, the deploy does
  `export INFISICAL_TOKEN="$(infisical login --method=universal-auth
  --client-id=… --client-secret=… --plain --silent)"` then
  `infisical run --projectId=<app> --env=prod -- docker compose up -d`.
  Secrets are fetched fresh into the **container environment only** — never
  written to disk. Restart the container and rotated secrets flow in.
  > The `--plain` token capture is required: a universal-auth login does *not*
  > leave a CLI session that a bare `infisical run` reuses; on a headless box it
  > would otherwise drop to an interactive prompt and hang.

### 3d. Image versioning via Infisical (new — in testing)

- The AnythingLLM image ref is **injected from Infisical** as `ANYTHINGLLM_IMAGE`
  (e.g. `reg.mini.dev/<ns>/anythingllm:v1.12.1`). Compose reads
  `image: "${ANYTHINGLLM_IMAGE:?…}"` (fail-loud). This lets you **bump the image
  version by editing one Infisical value + re-running `deploy.sh`** — no repo
  change — and keeps the **private registry namespace out of this public repo**.
- **Status:** proven on AnythingLLM; **Caddy is still pinned** in-repo
  (`reg.mini.dev/caddy:2`) because it's a public-namespace, stable tag. Moving
  Caddy to the same Infisical-injected pattern is a follow-up once the AnythingLLM
  approach has soaked.

---

## 4. tofu state management (DO Spaces backend)

- State is stored in **DigitalOcean Spaces** (S3-compatible) in the
  **`weown-prod-state`** bucket, under a per-site key
  (`<project>/<project>.tfstate`), encrypted with **SSE-C**
  (`TF_VAR_spaces_encryption_key`, an `openssl rand -base64 32` value kept in
  `weown-tofu`).
- The S3 backend block can't read `TF_VAR_*`, so `terraform/init.sh` (and
  `itofu.sh init`) forward the Spaces creds to `-backend-config` at init time.
- **`terraform/itofu.sh`** is the wrapper you use: it runs `tofu` under
  `infisical run` against `weown-tofu` so `TF_VAR_*` are present, and
  `plan` writes a saved `plan.tfplan` that `apply` consumes + deletes
  (so `apply` runs exactly what you reviewed; the plan file is gitignored
  because it contains rendered secrets).

---

## 5. Prerequisites (one-time per dev)

Match the project toolchain — do not improvise package managers:

- **pyenv** with the versions this repo uses: `copier` lives under **3.14.2**,
  `ansible`/`ansible-playbook` under **3.12.12** (`pyenv shell <ver>` to select).
- **OpenTofu** (`tofu`), **Infisical CLI**, **doctl** (authenticated with a DO
  token that has **registry** scope if you'll use DOCR; the deploy token only
  needs Droplet/Reserved-IP/Firewall/Tag/Monitoring).
- `infisical login` (your own account) — grants access to `weown-tofu` + the app
  projects you're authorized for.
- `docker login reg.mini.dev` (Minimus registry; token-as-both) — see §10.
- The shared DO Spaces buckets exist: `weown-prod-state` (tofu state) and
  `weown-prod-backups` (backups), plus a Spaces access key/secret.

---

## 6. Deploy a new instance — step by step

> Throughout: `<project>` is the slug (e.g. `int-s004-anythingllm`), `<domain>`
> the hostname (e.g. `s004.ccc.bot`), `<ip>` the reserved IP.

### 6.1 Render the site from the template

```bash
cd anythingllm-docker
"$(pyenv root)/versions/3.14.2/bin/copier" copy . sites/<domain> \
  --data project_name=<project> \
  --data domain=<domain> \
  --data anythingllm_image=reg.mini.dev/<ns>/anythingllm:<tag> \
  --defaults --trust
```

### 6.2 App Infisical project + bootstrap its secrets (no disk)

1. Create a **dedicated Infisical project** for the instance + a **Machine
   Identity** (Universal Auth) scoped to it. Note the project id + the MI
   client id/secret.
2. Push the app secrets (read with `read -rs`, never to disk/history):

   ```bash
   bash sites/<domain>/scripts/bootstrap-<...>-infisical.sh
   ```

   Sets `JWT_SECRET` (generate once, **never rotate** — rotating logs everyone
   out), `OPENROUTER_API_KEY`, `ADMIN_EMAIL`, **`ANYTHINGLLM_IMAGE`**,
   `SPACES_ACCESS_KEY`/`SPACES_SECRET_KEY`, and `OPS_AUTHORIZED_KEYS` (team SSH
   pubkeys, one per line).

### 6.3 `weown-tofu` infra secrets (`TF_VAR_*`, prod env)

Add (Infisical UI or `infisical secrets set` after login):
`TF_VAR_do_token`, `TF_VAR_ssh_key_fingerprint`, `TF_VAR_spaces_access_key`,
`TF_VAR_spaces_secret_key`, `TF_VAR_spaces_encryption_key`,
`TF_VAR_infisical_client_id`, `TF_VAR_infisical_client_secret`,
`TF_VAR_infisical_project_id` (the **app** project id), and **`TF_VAR_alert_email`**
(a **DO-verified** email — an unverified/placeholder value fails alert creation).

### 6.4 Provision (OpenTofu → droplet, IP, firewall, alerts)

```bash
cd sites/<domain>/terraform
export WEOWN_TOFU_PROJECT_ID=<weown-tofu project id>
./itofu.sh init
./itofu.sh plan      # writes plan.tfplan
./itofu.sh apply     # consumes + deletes the plan
ssh root@<ip> 'tail /var/log/<project_underscored>-rotation.log'   # expect "===== Rotation complete ====="
```

cloud-init takes ~3 min. If rotation shows `ROTATION FAILED`, see
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md).

### 6.5 Deploy the app layer (Ansible)

```bash
cd sites/<domain>
pyenv shell 3.12.12     # ansible lives here
INFISICAL_PROJECT_ID=<app project id> ./scripts/deploy.sh root@<ip>
```

Uploads compose/Caddyfile/backup/restore, installs the daily backup cron +
logrotate, ensures `/var/log/caddy` is writable, syncs team SSH keys, then
`docker compose up -d` under `infisical run`, and waits for `/api/ping`.
**Idempotent — re-run for any compose/Caddy/script change. No terraform.**

### 6.6 Observability (OTel → SigNoz) — see §9

```bash
./scripts/bootstrap-otel-agent.sh --host root@<ip>     # once per host (writes OTel MI creds)
./scripts/deploy-otel-fleet.sh --droplet <project>      # or --tag weown-ai for the whole fleet
```

### 6.7 Validate (don't trust `/api/ping` alone)

`/api/ping` returns 200 even when auth is broken. Verify a **real login**, that
**workspaces/data** are present, a **retrieval query** returns hits, and a
**chat completes** (OpenRouter). For pre-DNS validation, tunnel straight to the
app: `ssh -N -L 3001:127.0.0.1:3001 root@<ip>` then open `http://localhost:3001/`.
> Multi-user instances scope chat history **per user** — an admin sees their own
> chats; use **Settings → Admin → Workspace Chats** to see everyone's.

### 6.8 DNS + reserved IP

Point the `<domain>` **A record at the reserved IP** `<ip>`. Caddy obtains the
Let's Encrypt cert within ~30–60s of propagation (it can't before DNS points
here). Verify: `curl -sSI https://<domain>/api/ping` → `200` with a valid cert.

---

## 7. Skinny backups

- **Daily cron** (`/etc/cron.daily/<project>-backup`) runs `backup.sh` under
  `infisical run`: tars the AnythingLLM storage + Caddy data volumes, compresses,
  and uploads to `s3://weown-prod-backups/<project>/` (DO Spaces).
- **Retention (GFS):** daily 30d, monthly 12mo, yearly forever — applied
  automatically after each upload.
- **Restore:** `./scripts/restore.sh root@<ip> <backup-name>` (name only, e.g.
  `<project>_backup_YYYYMMDD_HHMMSS` — the script auto-fetches from Spaces if the
  tarball isn't local). It stops the container, restores the volume, and restarts.
- **Requires `awscli`** on the droplet for the Spaces upload — cloud-init now
  installs AWS CLI v2 via the official installer (apt's `awscli` is unreliable).

---

## 8. Security & networking

- **Reserved IP** fronts the droplet → DNS is stable across rebuilds.
- **Firewall:** inbound 22/80/443; full outbound.
- **`ssh_source_cidrs`** controls who can reach **port 22**. **Today it defaults
  to `0.0.0.0/0` (open to the internet, key-only auth).** The intended end state
  is to put the fleet **behind Proton VPN**: lock `ssh_source_cidrs` to the
  Proton VPN egress CIDR (and ideally 80/443 management paths too) so SSH is only
  reachable *through the VPN* — s004 sits behind that perimeter. Until that
  rollout, SSH is publicly reachable (key-only); set `TF_VAR_ssh_source_cidrs`
  per-site to tighten it now if your admin IP is stable.
- **Team SSH:** members' public keys live in Infisical `OPS_AUTHORIZED_KEYS`
  (one per line). Ansible writes them to a *separate* `authorized_keys.weown-ops`
  managed file (the DO break-glass key is never touched → no lock-out). Grant/
  revoke = edit the var + re-run `deploy.sh`. A blank/whitespace value is treated
  as "unset" and leaves the file unchanged (never wipes team access).

---

## 9. Observability (SigNoz + OTel)

Observability is a **fleet agent deployed separately** from this template — it's
not in the compose stack. Droplets tagged **`weown-ai`** are targets.

- **Per host, once:** `scripts/bootstrap-otel-agent.sh --host root@<ip>` writes
  the OTel project's Machine-Identity creds to `/opt/otel-agent/.infisical-auth.env`.
- **Deploy/update:** `scripts/deploy-otel-fleet.sh --droplet <project>` (or
  `--tag weown-ai` for all). The agent reads `OTEL_URL` + `OTEL_KEY` from the
  Infisical `otel` project at every `docker compose up` (runtime injection) and
  ships **host metrics + Caddy access logs** (read from the `/var/log/caddy`
  bind mount) to **SigNoz Cloud**. See [`otel-agent/README.md`](../otel-agent/README.md).
- The Caddy file-logging in this template exists specifically so the agent can
  ingest it.

---

## 10. Registry & image strategy (Minimus → DOCR)

- **Today:** images pull from the **Minimus** registry `reg.mini.dev` (hardened
  images). The droplet authenticates with a one-time `docker login reg.mini.dev`
  (token-as-both); the AnythingLLM image ref is injected via Infisical
  (`ANYTHINGLLM_IMAGE`, §3d). Minimus **rotates tags**, so always inject a
  pinned, verified tag — don't rely on `:latest`.
- **Next step — DOCR mirror:** mirror the images we depend on into **DigitalOcean
  Container Registry** to decouple deploy-time from Minimus uptime/tag rotation:

  ```
  docker pull reg.mini.dev/<ns>/anythingllm:<tag>
  docker tag  reg.mini.dev/<ns>/anythingllm:<tag>  registry.digitalocean.com/<reg>/anythingllm:<tag>
  docker push registry.digitalocean.com/<reg>/anythingllm:<tag>
  ```

  Then either make the DOCR repo **public** (zero droplet auth) or give the
  droplet a registry-read DO token. DOCR needs a DO token with **registry**
  scope (the deploy token doesn't have it).
- **⚠️ Open question (legal):** verify the **Minimus license** permits us to
  **store/redistribute** their hardened images in our own registry before
  mirroring. If it doesn't, keep pulling from `reg.mini.dev` at deploy time and
  treat DOCR only as a cache we're licensed to hold. **Do not mirror until this
  is confirmed.**

---

## 11. Operating a live instance

| Change | How |
|---|---|
| compose / Caddyfile / backup.sh | `./scripts/deploy.sh root@<ip>` — no terraform |
| **bump the app image** | edit `ANYTHINGLLM_IMAGE` in the app Infisical project → `./scripts/deploy.sh` (recreates under `infisical run`) |
| any Infisical secret | edit in Infisical → re-run `./scripts/deploy.sh` (recreates the container so the new value is picked up; `docker compose restart` reuses the old env and won't) |
| cloud-init contents | `tofu taint digitalocean_droplet.anythingllm && ./itofu.sh apply` (droplet downtime) |
| add/remove a teammate's SSH | edit `OPS_AUTHORIZED_KEYS` → `./scripts/deploy.sh` |
| ad-hoc compose commands | run under `infisical run` (the fail-loud guards need the injected vars); use plain `docker ps`/`logs` for quick checks |

---

## 12. Reference deployment: INT-S004 (`s004.ccc.bot`)

The first instance to fully exercise this flow — a **rebuild** of the locked-out
old INT-S004 box onto a fresh droplet, same hostname:

- **Parallel build + DNS cutover:** the new droplet was provisioned and validated
  *before* touching DNS; the old box stayed untouched until soak.
- **Restore:** data restored from an off-box `storage` tarball into the new
  volume; AnythingLLM forward-migrated it on boot. Verified 23 workspaces /
  22 threads / 635 chats / 12 users intact.
- **Cutover:** A-record swapped to the reserved IP; Caddy auto-issued the cert.
- **Soak (current):** the **old droplet is shut down but not destroyed** — it's
  the rollback. Decommission only after the soak window passes.
- It also closed the two failures that killed the old box: a `JWT_SECRET` that
  vanished on a non-`infisical run` restart (now fail-loud + always injected),
  and a daily backup cron that was never installed (now standard).

---

## 13. How the team uses these templates

- **One template, many sites.** Render a new `sites/<domain>/` per instance;
  never hand-copy another site.
- **Each dev deploys with their own `infisical login`** but shared `weown-tofu`
  infra secrets — so anyone authorized can deploy, with their own audit trail.
- **App secrets belong to the instance's project**, read by the droplet's
  Machine Identity at runtime — not copied between people or written to disk.
- **State is shared + remote** (DO Spaces, SSE-C) — run `./itofu.sh init` on a
  fresh checkout to pull current state; never keep local-only state for prod.
- **Public repo discipline:** no secrets, no private registry namespaces, no
  private IPs in committed files (use Infisical + RFC 5737 examples).

For the full architecture rationale see
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md); for
WeOwnVer versioning see [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md).
