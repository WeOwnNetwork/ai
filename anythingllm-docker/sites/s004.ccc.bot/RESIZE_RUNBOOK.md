# INT-S004 Resize & Bounce-Proof Recovery Runbook

**Trigger**: 2026-06-10 01:00:33 MT — the AnythingLLM container was
memcg-OOM-killed mid agent-RAG chat (2 GiB compose limit hit; kernel killed
the node server, exit 137). Docker auto-restarted it in ~9 s, **but the app
did not come back as it was**: `EMBEDDING_ENGINE` fell back to the compose
default (`native`) because the operator's earlier UI-side switch to
`openrouter` was never pinned in Infisical. Every RAG query then failed with
`No vector column found to match with the query vector dimension: 384`, and
agent chats threw OpenRouter `401 Missing Authentication header`, until ~35
minutes of manual re-configuration and a full purge + re-embed.

**This runbook** (a) upsizes the droplet 4 GB → 8 GB and the container limit
2G → 6G, (b) pins ALL runtime config in Infisical so any future bounce
restores the app **identically** with **no secrets on disk**, and (c) proves
both with a kill-and-verify gate.

**Versioning**: #WeOwnVer v4.1.2.2 · **Repo changes paired with this runbook**:
`terraform/variables.tf` (`s-4vcpu-8gb-amd`), `terraform/main.tf`
(`resize_disk = false`), `docker/compose.prod.yaml` (6G limit,
`EMBEDDING_ENGINE` fail-loud), `scripts/bootstrap-s004-infisical.sh`
(embedding-config prompts), repo-root `scripts/create-signoz-oom-alert.sh`.

**Redaction (§3.0)**: `<droplet-ip>`, `<s004-app-project-id>`, and
`<weown-tofu-project-id>` are placeholders — resolve them from `./itofu.sh
output`, the Infisical dashboard, and your operator notes. Never commit
resolved values.

---

## Invariants (apply to every phase)

- **No secrets on disk, in argv, in shell history, or in an AI agent's
  context.** Secrets move via `read -rs` → env → `infisical run` only.
- **Infisical is the single source of truth for runtime config.** UI-side
  settings changes do not survive a bounce and are forbidden as the primary
  change mechanism — change Infisical, then redeploy.
- **#OnlyHumanApproves**: each GATE below needs a human green-light before
  the next phase.

---

## Phase 0 — Preflight (read-only)

```bash
cd anythingllm-docker/sites/s004.ccc.bot/terraform

# Current droplet state + IP (no secrets in output):
export WEOWN_TOFU_PROJECT_ID=<weown-tofu-project-id>
./itofu.sh output                      # note droplet_ip / reserved IP
doctl compute droplet get int-s004-anythingllm --format Name,Memory,VCPUs,Disk,Region,Status

# Target size must exist in atl1:
doctl compute size list | grep s-4vcpu-8gb-amd

# App currently healthy?
curl -fsS https://s004.ccc.bot/api/ping && echo OK
```

If `s-4vcpu-8gb-amd` is unavailable in `atl1`, pick the nearest premium-AMD
8 GB slug `doctl` offers and change `droplet_size` in
`terraform/variables.tf` to match before Phase 3.

## Phase 1 — Backup current state — **GATE 1**

Run the existing skinny backup (volume tars → DO Spaces, GFS retention).
Remote mode SSHes in and uses the droplet's own Machine Identity — no
local secrets needed beyond your SSH key:

```bash
cd anythingllm-docker/sites/s004.ccc.bot
INFISICAL_PROJECT_ID=<s004-app-project-id> ./scripts/backup.sh root@<droplet-ip>
# Answer the "Pull backup to local machine?" prompt as you prefer.
```

**Gate check**: the run must print `Remote backup uploaded successfully`.
This is the rollback point for everything below.

## Phase 2 — Pin runtime config in Infisical — **GATE 2**

This is the fix for "AnythingLLM does not come back up exactly as it was."
Pin the values the app is **actually running with right now** (they were
set UI-side during the 2026-06-10 remediation and exist nowhere durable):

| Infisical key (s004 app project, `prod`) | Value | Why |
|---|---|---|
| `EMBEDDING_ENGINE` | `openrouter` | **Required** — compose now refuses to start without it. Must match the engine that built the current LanceDB vectors. |
| `EMBEDDING_MODEL_PREF` | `perplexity/pplx-embed-v1-4b` | The model the 2026-06-10 re-embed used. Changing it = full re-embed. |
| `OPENROUTER_TIMEOUT_MS` | `10000` | Operator-tuned value; compose fallback is 3000 and silently reverts on bounce if unpinned. |

These are **non-secret config** values — setting them via CLI argv is fine
(the argv ban is for secrets):

```bash
infisical secrets set EMBEDDING_ENGINE=openrouter \
  --projectId=<s004-app-project-id> --env=prod
infisical secrets set EMBEDDING_MODEL_PREF=perplexity/pplx-embed-v1-4b \
  --projectId=<s004-app-project-id> --env=prod
infisical secrets set OPENROUTER_TIMEOUT_MS=10000 \
  --projectId=<s004-app-project-id> --env=prod
```

Then confirm the full required set exists (names only — never print values):

```bash
infisical secrets --projectId=<s004-app-project-id> --env=prod --plain 2>/dev/null \
  | awk '{print $1}' | sort
# Must include: ADMIN_EMAIL ANYTHINGLLM_IMAGE EMBEDDING_ENGINE
#               EMBEDDING_MODEL_PREF JWT_SECRET OPENROUTER_API_KEY
#               OPENROUTER_TIMEOUT_MS SPACES_ACCESS_KEY SPACES_SECRET_KEY
```

> If the OpenRouter key is due for rotation (7-day-expiry naming scheme),
> rotate it NOW via `bash scripts/bootstrap-s004-infisical.sh` (mint the new
> key before revoking the old; the script reads it with `read -rs`).

**Gate check**: before setting anything, verify in the AnythingLLM UI
(Settings → AI Providers → Embedder) that prod really is
`openrouter` + `pplx-embed-v1-4b`. If it differs, pin **what the UI shows**
— the vectors on disk were built with it.

## Phase 3 — Resize the droplet — **GATE 3**

The repo already carries `droplet_size = "s-4vcpu-8gb-amd"` and
`resize_disk = false` (CPU/RAM-only: disk stays 80 GB, filesystem and every
Docker volume untouched, and the resize stays reversible).

```bash
cd anythingllm-docker/sites/s004.ccc.bot/terraform
export WEOWN_TOFU_PROJECT_ID=<weown-tofu-project-id>
./itofu.sh init        # only if this checkout hasn't been init'd
./itofu.sh plan
```

**Gate check — read the plan before applying**:

- `digitalocean_droplet.anythingllm` must show **`~ update in-place`** with
  `size: "s-2vcpu-4gb-amd" -> "s-4vcpu-8gb-amd"` (+ `resize_disk = false`).
- It must **NOT** show `-/+ destroy and then create replacement`. If it
  does, STOP — something else drifted; investigate before touching prod.
- Reserved IP and firewall: no changes.

```bash
./itofu.sh apply       # consumes the saved plan, then deletes it
```

Expect **~1–3 minutes of downtime** (power-off → resize → power-on). The
reserved IP and DNS do not change. Verify:

```bash
doctl compute droplet get int-s004-anythingllm --format Memory,VCPUs,Disk
# expect: 8192  4  80   (disk intentionally unchanged)
ssh root@<droplet-ip> 'uptime && docker ps --format "{{.Names}}\t{{.Status}}"'
# both containers should be up (restart: unless-stopped survives the reboot)
```

## Phase 4 — Deploy the new app layer

Ships the 6G-limit compose and force-recreates the stack under
`infisical run` — this is also what picks up the Phase 2 Infisical values:

```bash
cd anythingllm-docker/sites/s004.ccc.bot
INFISICAL_PROJECT_ID=<s004-app-project-id> ./scripts/deploy.sh root@<droplet-ip>
```

The new `EMBEDDING_ENGINE` fail-loud guard doubles as a check: if Phase 2
was skipped, compose refuses to start and the deploy fails here, loudly,
instead of booting a silently-misconfigured app.

Verify the limit landed:

```bash
ssh root@<droplet-ip> \
  'docker inspect int_s004_anythingllm-anythingllm-1 --format "{{.HostConfig.Memory}}"'
# expect: 6442450944   (6 GiB)
```

## Phase 5 — Bounce-and-verify (idempotent recovery proof) — **GATE 4**

Prove the thing the incident disproved: a hard kill comes back **identical**.

```bash
# 1. Fingerprint the running config (hash only — values never leave the box):
ssh root@<droplet-ip> \
  'docker inspect int_s004_anythingllm-anythingllm-1 --format "{{json .Config.Env}}" | sha256sum'

# 2. Simulate the OOM kill (same signal the kernel sends):
ssh root@<droplet-ip> 'docker kill --signal=KILL int_s004_anythingllm-anythingllm-1'

# 3. Watch it come back on its own (restart: unless-stopped):
ssh root@<droplet-ip> 'sleep 20 && docker ps --format "{{.Names}}\t{{.Status}}"'

# 4. Re-fingerprint — MUST be byte-identical to step 1:
ssh root@<droplet-ip> \
  'docker inspect int_s004_anythingllm-anythingllm-1 --format "{{json .Config.Env}}" | sha256sum'
```

Then the functional gate (a green `/api/ping` is NOT enough — it returns 200
even with broken auth):

- [ ] Real login works (`JWT_SECRET` unchanged, sessions intact).
- [ ] Settings → Embedder still shows `openrouter` / `pplx-embed-v1-4b`.
- [ ] A RAG chat in `tools-deepseek-pro` returns **citations** (no
      dimension-mismatch errors in `docker logs`).
- [ ] An **@agent** chat streams a reply — watch
      `docker logs -f` for `[AIbitat] Provider error: 401`. The 401 appeared
      twice post-incident before settings were re-saved; if it recurs with
      env config pinned, capture the log line and open an upstream issue —
      do NOT fix it by UI-only changes.
- [ ] `docker stats --no-stream` during a reranked agent chat: RSS spikes
      but stays well under 6 GiB.

## Phase 6 — Repair incident data damage

One document failed to vectorize **5/5 times** during the 2026-06-10
re-embed and is silently missing from RAG in every workspace
(`ccc-gtm-deepseek`, `tools-deepseek-pro`, `vsa-claude`, `vsa-mimo`,
`vsa-qwen`):

```text
_PROJECTS_/PRJ-020-intern-eval-workflow/data-migration-popdb/intern_eval_comprehensive_2026-03-18.json
```

It chunks to 66 pieces and the OpenRouter embedder rejected the batch every
time. Fix in the **source repo** (`CCCbotNet/fedarch`), not the UI: split
the JSON into ≤ ~25-chunk parts (or convert the data tables to Markdown),
then re-sync the GitHub connector and confirm via embed-progress + a query
that should cite it. Also review whether all 4 pinned sources (~19.4k
tokens prepended to **every** chat in those workspaces) are still
intentional — pinned bulk is what made the reranker spike fatal.

## Phase 7 — Turn on the missing pager

DO droplet alerts (CPU/mem/disk, `monitoring.tf`) cannot see memcg kills —
host RAM was healthy throughout the incident. Create the fleet-wide SigNoz
log alert on the kernel's kill line:

```bash
export SIGNOZ_BASE_URL="https://<workspace>.<region>.signoz.cloud"
read -rs "SIGNOZ_API_KEY?Paste SigNoz API key: " && export SIGNOZ_API_KEY && echo
./scripts/create-signoz-oom-alert.sh     # repo root
```

Confirm in SigNoz: Alerts → "Fleet: container memcg OOM kill" exists and
routes to a channel a human actually watches at 1 AM.

## Rollback

| Failure point | Rollback |
|---|---|
| Plan shows destroy/recreate (Phase 3) | Do not apply. Investigate drift (`./itofu.sh plan` diff) first. |
| Resize fails / box unhealthy | `resize_disk = false` keeps the disk intact: revert `droplet_size` in `variables.tf`, `./itofu.sh plan && apply` to downsize back. |
| App data damaged (should not happen — volumes untouched) | `INFISICAL_PROJECT_ID=<s004-app-project-id> ./scripts/restore.sh root@<droplet-ip> <backup-name-from-phase-1>` |
| Config wrong after deploy | Fix the value **in Infisical**, re-run `./scripts/deploy.sh` (a bare `docker compose restart` reuses old env by design). |

## Compliance mapping

| Control | Mapping |
|---|---|
| NIST CSF 2.0 | PR.IP-3 (config change control via Infisical-pinned env), RC.RP-1 (tested recovery, Phase 5 gate), DE.CM-1 (Phase 7 memcg-kill alert closes the host-metrics blind spot) |
| CIS Controls v8 | 4.1/4.2 (secure configuration process for the stack), 11.1/11.2 (backup before change, Phase 1), 8.11 (log-based alerting) |
| ISO/IEC 27001:2022 | A.8.9 (configuration management), A.8.13 (information backup), A.8.16 (monitoring activities) |
