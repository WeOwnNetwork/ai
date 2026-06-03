# INT-S004 Recovery Rebuild → s004.ccc.bot — Runbook

> **What:** stand up a fresh AnythingLLM droplet for INT-S004, restore the data
> exported off the old box, validate, flip DNS, then decommission the old box —
> **keeping the same hostname `s004.ccc.bot`**.
> **Image:** `reg.mini.dev/anythingllm:1.7.2` (same pin as the source box → no
> schema migration on restore).
> **Pattern:** parallel-build + DNS-cutover. The old box is **never modified**
> until after soak.
> **Owner:** Nik (CTO) + Shahid (SHD).

This site is **re-rendered from the `anythingllm-docker` copier template** and
validated against the hardened `sites/ai.weown.agency/` (INT-P01); the
deployable files are byte-identical modulo names.

---

## Why we are rebuilding

- **Auth lockout:** AnythingLLM logged `Cannot create JWT as JWT_SECRET is
  unset`; a container restart came back with `JWT_SECRET` empty because it was
  recreated **without** `infisical run`. The `${JWT_SECRET:?…}` guard in
  `docker/compose.prod.yaml` now makes that fail loud instead of serving broken
  auth.
- **No backups:** the old box never got the canonical ansible deploy, so the
  daily backup cron was never installed. The ansible deploy here installs it,
  and Phase 5 proves a backup reaches DO Spaces before decommission.

Deploy **only from committed IaC** (no hand-edits on the droplet — that is what
produced the `docker-anythingllm-1`, run-by-hand container that broke).

---

## Hostname & cutover model (important — read this)

The new box uses the **same** hostname `s004.ccc.bot` as the box it replaces, so
this is an in-place replacement, not a new FQDN. Consequence for validation:

- While DNS `s004.ccc.bot` still points at the **old** box, the **new** box's
  Caddy **cannot** obtain a Let's Encrypt cert for `s004.ccc.bot` (the ACME
  challenge resolves to the old box). So **pre-cutover validation is done over
  an SSH tunnel to the app port** (`:3001`), not over public HTTPS.
- **Cutover = flip the `s004.ccc.bot` A-record** from the old box's IP to the
  new droplet's reserved IP. Only then does Caddy fetch the cert; validate HTTPS
  immediately after.
- **Rollback = flip the A-record back to the old box.** Caveat: the old box is
  locked out, so it is a weak fallback — the real safety is that the new box was
  validated over the tunnel *before* cutover, and the off-box export is retained.

---

## Prerequisites

| # | Item |
|---|---|
| 1 | **Dedicated s004 Infisical project** + a Machine Identity scoped to it (Viewer on `prod`); Client ID + one-time Client Secret in hand. |
| 2 | App secrets set via `scripts/bootstrap-s004-infisical.sh` (Phase 0). |
| 3 | **DO API token** (Droplet, Reserved IP, Firewall, Tag, Monitoring) + **DO Spaces** keys for the tofu state backend + a fresh SSE-C key. The shared **`weown-prod-state` Spaces bucket must already exist in the `atl1` region** — it is NOT auto-created (`tofu init` errors `NoSuchBucket` if missing). If it lives in another region, update `endpoint` in `terraform/backend.tf` to that region. |
| 4 | **SSH key** in DO; you know its fingerprint. |
| 5 | **The off-box export** `s004_storage_<TS>.tar.gz` (root = contents of `/app/server/storage`). |
| 6 | **DNS control** for `ccc.bot` (ability to flip the `s004.ccc.bot` A-record; pre-lower its TTL to ≤300s ~30 min ahead). |

---

## Phase 0 — Infisical app secrets (no disk)

```bash
cd anythingllm-docker/sites/s004.ccc.bot
bash scripts/bootstrap-s004-infisical.sh
```

Reads each secret with `read -rs` (never to disk/history) and pushes to the
dedicated s004 project (`prod`): generated `JWT_SECRET` (set once, **never
rotate**), a **fresh** `OPENROUTER_API_KEY` named
`OPENROUTER_API_ANYTHINGLLM_INT-S004_7D_EXP_<creation+7d>` (the old key expired
2026-06-01), `ADMIN_EMAIL`, `SPACES_ACCESS_KEY`, `SPACES_SECRET_KEY`, and the
team `OPS_AUTHORIZED_KEYS` (public SSH keys for root access, one per line).

---

## Phase 1 — Provision (terraform, no `terraform.tfvars` on disk)

### 1a. One-time: the shared Spaces buckets + Spaces keys

DO Spaces is **S3-compatible** — the `aws` CLI works against it via `--endpoint-url`.
The **Spaces keys** are an access-key/secret pair you generate at **DO console →
API → Spaces Keys** (a *different* page from Personal Access Tokens — they are NOT
the `do_token`). `tofu init` uses them to read/write remote state.

The whole AnythingLLM fleet shares two buckets (skip if they already exist):

| Bucket | Purpose | Per-instance scoping |
|---|---|---|
| `weown-prod-state` | tofu remote state | state key path `int-s004-anythingllm/…tfstate` + per-site SSE-C key |
| `weown-prod-backups` | skinny backups | object prefix `int-s004-anythingllm/` |

Create both in `atl1` (console: **Spaces Object Storage → Create**, region Atlanta;
or CLI with **valid Spaces keys**):

```bash
for b in weown-prod-state weown-prod-backups; do
  AWS_ACCESS_KEY_ID=<spaces-access-key> AWS_SECRET_ACCESS_KEY=<spaces-secret> \
    aws s3 mb "s3://$b" --endpoint-url https://atl1.digitaloceanspaces.com
done
```

> `InvalidAccessKeyId` means the Spaces **access key** is wrong (most often the
> `do_token` pasted by mistake) — regenerate at **API → Spaces Keys**. The same
> valid Spaces keys are what you feed `SP_A`/`SP_S` below.

### 1b. Set up the `weown-tofu` Infisical project (one-time, operator-only)

Infra provisioning secrets live in a SEPARATE Infisical project — **not** the
s004 app project — so neither the public repo nor the droplet (whose Machine
Identity reads only the app project) ever sees the DO API token / Spaces keys.
Create a project `weown-tofu`; in its `prod` env add these named **exactly**
`TF_VAR_*` (Infisical UI, or `infisical secrets set` after `infisical login`):

| Secret | Value |
|---|---|
| `TF_VAR_do_token` | DigitalOcean API token |
| `TF_VAR_ssh_key_fingerprint` | your DO SSH key fingerprint |
| `TF_VAR_spaces_access_key` / `TF_VAR_spaces_secret_key` | DO Spaces keys (state backend) |
| `TF_VAR_spaces_encryption_key` | SSE-C key (`openssl rand -base64 32`) |
| `TF_VAR_infisical_client_id` / `TF_VAR_infisical_client_secret` | the s004 droplet's Machine Identity |
| `TF_VAR_infisical_project_id` | the s004 **app** project id (`8420b42e-…`) |

No Machine Identity is needed for `weown-tofu` — operators authenticate with
their own `infisical login`.

### 1c. Provision (Infisical-native — nothing on disk)

`./itofu.sh` runs tofu under `infisical run` against `weown-tofu`, so tofu reads
the `TF_VAR_*` automatically (and `init` forwards the Spaces creds to the S3
backend):

```bash
cd terraform
infisical login                              # operator account; once per session
export WEOWN_TOFU_PROJECT_ID=<weown-tofu project id>
./itofu.sh init       # tofu init w/ DO Spaces backend (SSE-C)
./itofu.sh plan       # expect: 1 droplet + 1 reserved IP + 1 firewall + 3 alerts
./itofu.sh apply
DROPLET_IP=$(./itofu.sh output -raw droplet_ip); echo "new droplet: $DROPLET_IP"
ssh "root@$DROPLET_IP" 'tail /var/log/int_s004_anythingllm-rotation.log'   # → "===== Rotation complete ====="
```

`plan` saves to `plan.tfplan` (gitignored) and `apply` applies **exactly** that
saved plan, then deletes it (plan files hold sensitive values in plaintext) — so
what you reviewed is what runs; no re-plan, no drift, no `yes` prompt.

> **Fallback (local tfvars):** `cp terraform.tfvars.example terraform.tfvars`,
> fill it, then `./init.sh && tofu plan && tofu apply`. The tfvars is gitignored
> (never committed) but sits on local disk — the `itofu.sh` path above avoids
> even that, so prefer it.

---

## Phase 2 — Deploy the app layer (Path C)

```bash
INFISICAL_PROJECT_ID="$TF_VAR_infisical_project_id" ./scripts/deploy.sh "root@$DROPLET_IP"
```

Uploads compose + Caddyfile + backup.sh, installs the daily backup cron +
logrotate, pulls images, runs `docker compose up -d` **under `infisical run`**,
tags the droplet, waits for `/api/ping`. The box now serves an **empty**
AnythingLLM (no public cert yet — DNS still points at the old box).

**Team SSH access** is applied in this same deploy: ansible writes the team's
public keys (from the Infisical `OPS_AUTHORIZED_KEYS` var, one per line) to
`/root/.ssh/authorized_keys.weown-ops` (managed exclusively), alongside the
untouched break-glass key. Set `OPS_AUTHORIZED_KEYS` in Infisical first (the
Phase 0 script prompts for it, or paste in the UI). To **add/revoke** access
later (e.g. on termination), edit `OPS_AUTHORIZED_KEYS` + re-run `./scripts/deploy.sh`.
**Keep a break-glass `root` session open the first time** in case sshd needs a fix.

---

## Phase 3 — Restore the off-box export

**Step 0 (non-negotiable): inspect the tarball layout first.**

```bash
tar tzf s004_storage_<TS>.tar.gz | head -20
```

- Root = `anythingllm.db`, `lancedb/`, `documents/` → extract straight in (below).
- Nested under `app/server/storage/` → add `--strip-components=3`.

```bash
mkdir -p /root/restore   # then from your laptop: scp s004_storage_<TS>.tar.gz root@$DROPLET_IP:/root/restore/

# On the droplet (select the APP container precisely — a plain `grep anythingllm`
# also matches Caddy, which shares the compose project prefix):
CT=$(docker ps --format '{{.Names}}' | grep -E 'anythingllm-anythingllm-[0-9]+$' | head -1); echo "$CT"

# Stop/start BY NAME — `docker compose stop` would trip the JWT_SECRET:? guard
# outside `infisical run`. A restarted container keeps its injected env.
docker stop "$CT"
docker run --rm -v int_s004_anythingllm_storage:/data -v /root/restore:/backup:ro alpine:3.19 \
  sh -c 'rm -rf /data/* && tar xzf /backup/s004_storage_<TS>.tar.gz -C /data'   # (+ --strip-components=N if nested)
docker start "$CT"
```

---

## Phase 4 — Validate the new box (pre-cutover, over an SSH tunnel)

DNS still points at the old box, so validate the app directly on `:3001`:

```bash
# From your laptop:
ssh -N -L 3001:127.0.0.1:3001 "root@$DROPLET_IP" &   # tunnel; Ctrl-C / kill when done
```

| # | Gate | Check | Pass |
|---|---|---|---|
| 1 | Secret injected | `ssh root@$DROPLET_IP "docker exec $CT printenv JWT_SECRET"` | non-empty |
| 2 | No lockout | `ssh root@$DROPLET_IP "docker logs $CT 2>&1 \| grep -i 'jwt_secret is unset'"` | empty |
| 3 | No literal vars | `ssh root@$DROPLET_IP "docker logs $CT 2>&1 \| grep -E '\$\{[A-Z_]+\}'"` | empty |
| 4 | App up | `curl -fsS http://localhost:3001/api/ping` (through the tunnel) | 200 |
| 5 | **Login** | open `http://localhost:3001/` → log in with a **migrated** account | succeeds |
| 6 | Data | workspaces present; counts look right | matches old box |
| 7 | Vectors | run a retrieval query | returns hits (LanceDB intact) |
| 8 | LLM | a chat completes | OpenRouter (fresh key) answers |

> `/api/ping` returns 200 even when auth is broken — gate 4 is necessary, not
> sufficient. Gates 5–7 are the real proof. Login works with **any** stable
> `JWT_SECRET` (it signs the session issued *after* password auth) — the new
> box's secret need not match the old box's.

Prove backups before you cut over:

```bash
INFISICAL_PROJECT_ID="$TF_VAR_infisical_project_id" ./scripts/backup.sh "root@$DROPLET_IP"
ssh "root@$DROPLET_IP" 'ls -l /etc/cron.daily/int_s004_anythingllm-backup'
# confirm a .tar.gz now exists in s3://weown-prod-backups/int-s004-anythingllm/
```

---

## Phase 5 — Cutover (DNS) + post-cutover validation

1. **Flip the `s004.ccc.bot` A-record** from the old box's IP to `$DROPLET_IP` (TTL was pre-lowered).
2. Caddy now obtains the Let's Encrypt cert on first request. Verify HTTPS:

```bash
dig +short s004.ccc.bot                 # → $DROPLET_IP
curl -fv https://s004.ccc.bot/api/ping  # → 200 with a valid cert
ssh root@$DROPLET_IP "docker logs \$CT_caddy 2>&1 | grep -i 'certificate obtained'"
```

3. Re-run gates 5–7 over `https://s004.ccc.bot/`.

---

## Phase 6 — Soak, then decommission

- Soak: watch DO alerts, container logs, error rate. Keep TTL low; old box untouched.
- **Decommission the old box only after** soak passes **and** the new box has its
  own verified DO Spaces backup. Keep the off-box export as last-resort until then.
- Do not leave the live box diverged from git (it won't be — it's deployed from
  this committed IaC).

---

## Rollback

| Situation | Action |
|---|---|
| New box fails Phase 4 | Don't cut over. Debug/rebuild the new box; old box + export untouched. |
| Problem during soak (post-cutover) | Flip the `s004.ccc.bot` A-record back to the old box (weak fallback — it's locked out) and re-investigate; nothing torn down. |
| Catastrophic loss of new box | Re-provision (Phases 1–2) and re-restore from the off-box export (Phase 3). |

---

## Stakeholder note (Shahid, plain text — no Tuleap IDs)

Old `s004.ccc.bot` is being rebuilt fresh on a new droplet (same hostname); please
don't change the old box. Root cause was `JWT_SECRET` not injected on a container
restart (the box was recreated without `infisical run`) — not a user-creation
action. The new box fails fast if the secret is missing and has working backups.
