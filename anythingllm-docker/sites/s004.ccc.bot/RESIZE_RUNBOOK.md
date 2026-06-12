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

> **Ops SSH targets the droplet's DIRECT IP — never `s004.ccc.bot`.**
> The DNS name resolves to the reserved IP, which is the *service*
> address: it deliberately moves between droplets during rebuilds, and
> (observed 2026-06-10) new SSH connections to it can be dropped under
> the constant brute-force load while 80/443 keep flowing — the user-
> facing app was unaffected, but `scp`/`ssh` via the DNS name timed out.
> Resolve the direct IP once and use it for every `root@<droplet-ip>`
> in this runbook:
>
> ```bash
> doctl compute droplet get int-s004-anythingllm \
>   --format PublicIPv4 --no-header
> ```

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

The `anythingllm_storage` tar **is the complete app state**: every chat
and workspace (`anythingllm.db`), all UI-entered settings (the app's
`storage/.env`), LanceDB vectors, uploaded documents, and the encryption
keys. Restoring it returns the app to **exactly** this moment — including
any settings changed in the UI since the last deploy (e.g. Jason's
post-incident configuration work).

**Gate check** (both must pass — this is the rollback point for
everything below):

1. The run prints `Remote backup uploaded successfully`.
2. The backup really contains the chats DB and the UI config — list
   filenames only, values never leave the box:

```bash
ssh root@<droplet-ip> 'set -e; cd /opt/int_s004_anythingllm/backups; \
  B=$(ls -t *.tar.gz | head -1); echo "checking $B:"; \
  tar tzf "$B" | grep -E "anythingllm_storage|compose.yaml|Caddyfile"; \
  mkdir -p /tmp/bkv && tar xzf "$B" -C /tmp/bkv; \
  tar tzf /tmp/bkv/*/anythingllm_storage.tar.gz \
    | grep -cE "anythingllm\.db|^\./\.env|lancedb" ; rm -rf /tmp/bkv'
# expect: storage tar + compose.yaml + Caddyfile listed, then a
# non-zero count proving anythingllm.db / .env / lancedb are inside
```

## Phase 2 — Pin runtime config in Infisical — **GATE 2**

This is the fix for "AnythingLLM does not come back up exactly as it was."
Pin the values the app is **actually running with right now**.

> ⚠️ **The table below is a 2026-06-10 snapshot, not gospel.** Config has
> been changed in the UI since the incident (Jason's post-incident work)
> and UI changes exist nowhere durable. Before setting ANYTHING in
> Infisical: open the AnythingLLM UI (Settings → AI Providers → LLM /
> Embedder / Agent) **and confirm with whoever changed config last** —
> then pin **what is live**, key by key. Pinning a stale value here
> would do to the next bounce exactly what the incident did.

| Infisical key (s004 app project, `prod`) | Value live on 2026-06-10 (verify before pinning) | Why |
|---|---|---|
| `EMBEDDING_ENGINE` | `openrouter` | **Required** — compose now refuses to start without it. Must match the engine that built the current LanceDB vectors. |
| `EMBEDDING_MODEL_PREF` | `perplexity/pplx-embed-v1-4b` | The model the 2026-06-10 re-embed used. Changing it = full re-embed. |
| `OPENROUTER_TIMEOUT_MS` | `10000` | Operator-tuned value; compose fallback is 3000 and silently reverts on bounce if unpinned. |
| `OPENROUTER_MODEL_PREF` | *(check UI)* | Compose fallback is `anthropic/claude-opus-4.5`; if the UI shows a different default LLM, pin it or the next deploy reverts it. |

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

**Downtime expectation — be honest with the team**: a DO size change is a
power-off resize. Expect **~1–3 minutes** of hard downtime in this phase
(plus ~30 s of container recreate in Phase 4). True zero-downtime is not
possible for an in-place resize; the zero-downtime alternative is the
ADR-005 parallel-build pattern (new 8 GB droplet → restore Phase 1 backup
→ DNS cutover), but it is **not recommended here**: any chat written
between backup and cutover would be lost, while the in-place resize never
moves the disk at all — every byte of state stays where it is through the
power cycle. Schedule a quiet window, announce it, and the data-loss risk
is zero rather than "small".

**Rollback guarantee**: `resize_disk = false` keeps the resize reversible
(can downsize back); the volumes are untouched by the resize; and the
Phase 1 backup restores the exact pre-change app state — chats and
UI configuration included — via `restore.sh` if anything goes sideways.

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

> ⚠️ **Kill the PROCESS, not the container.** A real OOM is the *kernel*
> killing the node process — Docker sees an unexpected exit and
> `restart: unless-stopped` fires (auto-restart). `docker kill <container>`
> is operator-initiated, so Docker treats it as an intentional stop and the
> restart policy does NOT fire — the container stays down. (This exact
> mistake took s004 offline for 13 h on 2026-06-12: the old Phase-5 used
> `docker kill` and wrongly expected auto-restart.) Killing PID 1 *inside*
> the container faithfully reproduces an OOM.

```bash
# 1. Fingerprint the running config (hash only — values never leave the box):
ssh root@<droplet-ip> \
  'docker inspect int_s004_anythingllm-anythingllm-1 --format "{{json .Config.Env}}" | sha256sum'

# 2. Simulate the OOM: SIGKILL the node process INSIDE the container, so Docker
#    sees an unexpected exit and the restart policy fires (as it did on 06-10).
ssh root@<droplet-ip> \
  'docker exec int_s004_anythingllm-anythingllm-1 kill -9 1'

# 3. Watch it come back on its own (restart: unless-stopped honours an
#    unexpected death). Give it a moment — RestartCount should increment:
ssh root@<droplet-ip> \
  'sleep 25 && docker inspect int_s004_anythingllm-anythingllm-1 \
     --format "state={{.State.Status}} restarts={{.RestartCount}}"'
# expect: state=running  restarts>=1   (NOT state=exited)

# 4. Re-fingerprint — MUST be byte-identical to step 1:
ssh root@<droplet-ip> \
  'docker inspect int_s004_anythingllm-anythingllm-1 --format "{{json .Config.Env}}" | sha256sum'
```

> If you DO need to test with `docker kill <container>` (or you stopped it
> any other operator-initiated way), it will NOT auto-restart — bring it back
> with **plain docker** (NOT `docker compose`, which fails the
> `${ANYTHINGLLM_IMAGE:?…}` fail-loud guard unless wrapped in `infisical run`):
>
> ```bash
> docker start int_s004_anythingllm-anythingllm-1   # reuses the baked-in env
> ```
>
> General rule on this box: bare `docker compose <cmd>` errors with
> "required variable ANYTHINGLLM_IMAGE is missing a value" because the image
> ref is only injected under `infisical run`. For day-to-day ops use plain
> `docker ps` / `docker logs <name>` / `docker restart <name>`; for anything
> that must re-read compose.yaml, wrap it:
> `infisical run --projectId=<app> --env=prod -- docker compose up -d`.

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

---

## Appendix — As-run record (2026-06-11/12): the resize that became a rebuild

What actually happened when this runbook ran, and what the next operator
should know. Phases 1–2 went to plan. Phase 3 did not.

**The apply DESTROYED the droplet instead of resizing it.** The plan showed
`ssh_keys # forces replacement` (create-time-only attribute): the shared
weown-tofu `TF_VAR_ssh_key_fingerprint` had been changed since the June-2
build (operator key migration), so tofu's only way to honor it was
destroy-and-recreate — taking every Docker volume with it. The gate that
says "STOP on destroy/recreate" exists because of this exact line; it was
missed in the diff wall. **Now structurally fixed**: the droplet resource
carries `prevent_destroy = true` (destroy plans are hard errors) and
`ignore_changes = [ssh_keys]` (shared-var drift is a no-op).

**Recovery that worked** (total ≈ 1 h, data loss = 19 min of chats):

1. Newest Spaces backup identified (Phase-1 discipline = the only copy).
2. Bootstrap var pointed at the recovering operator's DO-registered key;
   one more (harmless — box empty) replacement applied.
3. `deploy.sh` → `restore.sh <newest-backup>` → `deploy.sh` again.
   The second deploy is REQUIRED: restore copies the backup's old
   `compose.yaml` over the new one, and the force-recreate re-injects the
   pinned Infisical env.
4. Sessions survived (`JWT_SECRET` pinned and unchanged); users did not
   even need to log in again.

**Rebuild gotchas hit on the way (in order):**

| Gotcha | Symptom | Fix |
|---|---|---|
| New droplet trusts ONLY the bootstrap key | `Permission denied (publickey)` — OPS keys don't exist until first deploy | SSH with the key matching `TF_VAR_ssh_key_fingerprint`; watch for the Secretive/Touch-ID approval prompt (a missed prompt looks identical to a denial) |
| Layer-2 bootstrap-secret rotation failed | `ROTATION FAILED: v2 client secret create failed` in rotation.log | Non-blocking (v1 secret still valid). Run the README manual-rotation runbook after recovery; grant the MI "manage own client secrets" in Infisical or this recurs every rebuild |
| Minimus registry auth is per-droplet state | deploy fails pulling `reg.mini.dev/caddy:2` with 401 | One-time `docker login reg.mini.dev` — username **`minimus`**, token as password (DEPLOYMENT_GUIDE §10; the old "token-as-both" note was wrong) |
| DO monitor alerts 404 on update | apply errors `PUT …/monitoring/alerts/…: 404` | DO deleted the alerts with their droplet; `./itofu.sh state rm 'digitalocean_monitor_alert.cpu[0]' …memory… …disk…` then re-apply creates fresh ones |
| ansible not on PATH (pyenv) | `pyenv: ansible-galaxy: command not found` | Prefix deploys with `PYENV_VERSION=3.12.12` |
| Direct IP changes on every rebuild | stale `~/.ssh/config` / mux targets | Re-resolve via `doctl compute droplet get int-s004-anythingllm --format PublicIPv4` (Phase 0 rule) |
