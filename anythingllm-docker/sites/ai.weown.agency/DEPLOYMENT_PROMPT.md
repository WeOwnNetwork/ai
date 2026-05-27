# INT-P01 Deployment Prompt — IDE / Agent Guide

> **What this is**: a self-contained brief for the IDE agent (Cursor / Claude Code / etc.)
> that will execute the INT-P01 DOKS → Docker migration. The agent should read this
> BEFORE touching any files and refer back to it throughout. Companion docs:
>
> - [`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md) — decision of record + validation gates
> - [`MIGRATION_RUNBOOK.md`](MIGRATION_RUNBOOK.md) — phase-by-phase procedure (authoritative)
> - [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md) — Layer 1 / Layer 2 / Path C
> - [`.github/copilot-instructions.md`](../../../.github/copilot-instructions.md) — repo policy

---

## Your job

Execute the INT-P01 (`ai.weown.agency`) DOKS → Docker migration end-to-end. The plan, ADR, and rendered site already exist on `main` — your job is the operational execution: local test, staging droplet, Jason review, production DNS cutover, DOKS decommission. **Do not modify the DOKS source environment until production cutover succeeds.**

This is a high-stakes migration of a live single-tenant instance (Calhoun MetaAgent). The pattern is **parallel build + DNS cutover** — rollback at any point before decommission is a single DNS A-record edit.

---

## STEP 0 — Sync the working tree (do this FIRST, before reading anything else)

The artifacts you'll need ALL live on `origin/main` post-PR #36. If you opened this file from a stale checkout, the rest of the files may appear "missing" — they're not, you're just behind. Force-sync now:

```bash
git fetch origin
git checkout main
git pull --ff-only origin main

# Verify the artifacts exist locally:
ls .github/ADR-005-int-p01-doks-retirement.md \
   docs/INFRA_BOOTSTRAP_PATTERN.md \
   anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md \
   anythingllm-docker/sites/ai.weown.agency/scripts/migrate-from-doks.sh \
   anythingllm-docker/sites/ai.weown.agency/terraform/init.sh \
   anythingllm-docker/sites/ai.weown.agency/docker/compose.local.yaml \
   anythingllm-docker/sites/s004/README.md
# All 7 should exist. If any are missing, you are NOT on the latest main —
# do not proceed; fix your checkout first.
```

Then open the deployment branch for your work:

```bash
git checkout -b feature/<dev>-int-p01-deploy   # replace <dev> with your lowercase handle
```

---

## Before touching any files — read these in order

1. **`.github/ADR-005-int-p01-doks-retirement.md`** — the architectural decision, why, validation gates
2. **`anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md`** — phase-by-phase procedure (authoritative; this prompt extends it with a local-test phase before Phase 1)
3. **`docs/INFRA_BOOTSTRAP_PATTERN.md`** — Layer 1 (DO Spaces tfstate) + Layer 2 (Infisical Machine Identity rotation on first boot) + Path C (slim cloud-init + ansible app layer)
4. **`.github/copilot-instructions.md`** — repo policy: branch naming, secret handling, immutable image tags (§3.7), Compose hardening (§3.8), no committed IPs (§3.6)
5. **`anythingllm-docker/sites/s004/`** — canonical reference site (already deployed); mirror its structure
6. **`anythingllm-docker/sites/ai.weown.agency/`** — your target site (already rendered from the template; do NOT re-render unless changing copier inputs)

**Summarize back to me what you understand about: the dual-hostname Caddy pattern, the Layer 2 rotation flow, the migrate-from-doks.sh bridge script's output format, and the two human validation gates. Do NOT touch any file until I confirm your summary is right.**

---

## Deployment constants (use exactly these values)

| Variable | Value | Source |
|---|---|---|
| `project_name` | `int-p01-anythingllm` | already baked into rendered site |
| `domain` | `ai.weown.agency` (production) | already in Caddyfile |
| `staging_domain` | `ai-stage.weown.agency` | already in Caddyfile (dual-host) |
| `anythingllm_image` | `reg.mini.dev/anythingllm:1.7.2` | D381 (WeOwnLLM hardened); verified on s004.ccc.bot |
| `caddy_image` | `reg.mini.dev/caddy:2` | repo standard |
| `do_region` | `atl1` | repo default |
| `droplet_size` | `s-2vcpu-4gb-amd` | matches s004 |
| Infisical project | `weown-anythingllm` | confirm with operator (Nik) before Phase 0 |
| Infisical env | `prod` | for the migrated droplet; `dev` may be used for local |
| Backup bucket | `weown-backups/int-p01-anythingllm/` | DO Spaces, atl1 |
| Source DOKS namespace | `anythingllm` (verify; ask operator) | DOKS cluster `WeOwnNetwork/ai` cluster |
| Source DOKS selector | `app.kubernetes.io/name=anythingllm` (verify) | DOKS resource label |

If any value above is uncertain, **stop and ask the operator**. Do not guess.

---

## Required local tools

```bash
# Confirm these are installed before Phase 0
copier --version          # >= 9.0
tofu version              # OpenTofu >= 1.5
docker --version          # >= 24.0 with compose v2
kubectl version --client  # for DOKS extraction
ansible --version         # >= 2.15 (with community.docker collection)
infisical --version       # >= 0.39 (artifacts-cli, NOT legacy install-cli.sh)
doctl version             # for DO tag operations
gh --version              # for PR + workflow ops
aws --version             # for DO Spaces (s3-compatible)
jq --version              # for JSON wrangling
```

Operator-supplied credentials (must exist before starting):

- `~/.kube/doks-int-p01` — kubeconfig for the source DOKS cluster
- Infisical Machine Identity (Client ID + Client Secret) for `weown-anythingllm` project
- DO API token with scopes: Droplet R/W, Reserved IP R/W, Firewall R/W, Tag R/W, Monitoring R
- SSH key fingerprint in the DO account
- DO Spaces access/secret keys + SSE-C encryption key (32-byte AES-256, base64)
- SearXNG endpoint URL (likely `https://searxng.weown.app`) — verify reachable

---

## Phases — extended runbook

The authoritative procedure is `MIGRATION_RUNBOOK.md`. This prompt **inserts a Phase 1.5 (local-laptop validation)** between extracting the source backup (Phase 1) and provisioning the staging droplet (Phase 2).

### Phase 0 — Pre-flight (≤ 30 min)

- [ ] Open a new branch: `feature/nik-int-p01-deploy` (or `feature/<dev>-int-p01-deploy` if not Nik). Branch must match `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`.
- [ ] Open a draft PR immediately (via `gh workflow run auto-pr-to-main.yml --ref <branch>`) so progress is visible. Title: `feat(int-p01): execute DOKS → Docker migration for ai.weown.agency`.
- [ ] Add a `POST_DEPLOY_NOTES.md` to the site dir and commit empty — you'll fill it in as you go.
- [ ] Verify all secrets above are reachable. If Infisical project `weown-anythingllm` is missing any of the secrets (`OPENROUTER_API_KEY`, `JWT_SECRET`, `ADMIN_EMAIL`, `MINIMUS_TOKEN`, `SPACES_ACCESS_KEY`, `SPACES_SECRET_KEY`, `SEARXNG_BASE_URL`), populate them BEFORE Phase 1. Confirm with operator.
- [ ] Verify DNS for `ai-stage.weown.agency` is currently unassigned (will point to staging droplet at end of Phase 2).
- [ ] Verify DOKS source pod is healthy: `kubectl --kubeconfig ~/.kube/doks-int-p01 -n anythingllm get pods` shows a Running pod.

### Phase 1 — Extract source backup from DOKS (≤ 15 min)

Run the bridge script with no destructive changes to DOKS:

```bash
cd anythingllm-docker/sites/ai.weown.agency

./scripts/migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --storage-path /app/server/storage \
  --output-dir ./backups \
  --upload-to-spaces        # only if SPACES_ACCESS_KEY/SPACES_SECRET_KEY in env
```

This produces `./backups/int-p01-anythingllm_backup_<TS>.tar.gz` AND (if `--upload-to-spaces`) puts it in `s3://weown-backups/int-p01-anythingllm/`. The DOKS pod is **untouched**; only read via `kubectl exec | tar`.

**Verify the tarball:**

```bash
tar tzf ./backups/int-p01-anythingllm_backup_<TS>.tar.gz | head
# Should show:
#   int-p01-anythingllm_backup_<TS>/
#   int-p01-anythingllm_backup_<TS>/anythingllm_storage.tar.gz
#   int-p01-anythingllm_backup_<TS>/source.txt
```

### Phase 1.5 — LOCAL-LAPTOP validation (new — ≤ 60 min)

**Goal**: confirm the backup restores cleanly and the AnythingLLM application boots with the migrated data — on the operator's laptop, before paying for a droplet — using `compose.local.yaml` (HTTP-only, no Caddy TLS, no Layer 2 rotation, no Infisical Machine Identity dance).

1. **Bring up the local stack** (the rendered site already includes a `docker/compose.local.yaml`):

   ```bash
   cd anythingllm-docker/sites/ai.weown.agency/docker

   # Local-only env file — populate from Infisical so secrets stay off disk
   infisical run --projectId=<weown-anythingllm-id> --env=dev -- docker compose -f compose.local.yaml up -d
   ```

   If `compose.local.yaml` is missing from the rendered site for any reason, render it on-the-fly from the template:

   ```bash
   copier copy --force ../../../anythingllm-docker /tmp/local-render --data-file <answers.yaml> --defaults --trust --vcs-ref=HEAD
   cp /tmp/local-render/docker/compose.local.yaml docker/compose.local.yaml
   ```

2. **Restore the DOKS-extracted backup into the local volumes**:

   ```bash
   # restore.sh local mode reads project_name from itself
   ./scripts/restore.sh local int-p01-anythingllm_backup_<TS>
   ```

3. **Validate** (UI accessible at `http://localhost:3001`):
   - [ ] AnythingLLM login screen renders
   - [ ] Sign in with the credentials from the DOKS instance
   - [ ] Workspace list matches DOKS (count + names)
   - [ ] Open the **Calhoun** workspace
   - [ ] Send a test chat — **verify SearXNG web search works** (this was the bug that motivated the migration; if it fails locally too, debug now, not on a paid droplet)
   - [ ] Upload a small test document, verify it embeds
   - [ ] Query a pre-existing document, verify retrieval works
4. **Capture findings in `POST_DEPLOY_NOTES.md`**: any errors, warnings, missing data, perf differences vs DOKS.
5. **Tear down**:

   ```bash
   docker compose -f compose.local.yaml down -v   # -v wipes local volumes
   ```

**Gate**: if any of the validation checkboxes fail, stop here and escalate to operator. Do NOT provision the staging droplet until local-test passes.

### Phase 2 — Provision staging droplet (≤ 30 min)

Follow `MIGRATION_RUNBOOK.md` Phase 1-2 ("Provision the new droplet"). Summary:

```bash
cd anythingllm-docker/sites/ai.weown.agency/terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: real values for Infisical Machine Identity (v1 bootstrap secret),
# DO API token, SSH fingerprint, DO Spaces creds, SSE-C key. DO NOT commit terraform.tfvars.

./init.sh           # bridges DO Spaces backend creds from tfvars to `tofu init -backend-config`
tofu plan -out=int-p01.tfplan
tofu apply int-p01.tfplan
```

Wait for cloud-init to finish (~3 min) then **verify Layer 2 rotation succeeded**:

```bash
DROPLET=$(tofu output -raw droplet_ip)
ssh root@$DROPLET 'tail -50 /var/log/int-p01-anythingllm-rotation.log'
# Expect: "===== Rotation complete ====="
# If "ROTATION FAILED": follow the manual runbook in MIGRATION_RUNBOOK.md before proceeding
```

Then assign DNS for the staging subdomain to the reserved IP:

```bash
RESERVED_IP=$(tofu output -raw reserved_ip)

# Set ai-stage.weown.agency A record → $RESERVED_IP via DO API or web UI
# Wait for propagation (typically < 2 min for DO-hosted zones):
dig +short ai-stage.weown.agency
# Should return $RESERVED_IP
```

Caddy will issue the TLS cert automatically for `ai-stage.weown.agency` on first request (it's already in the same Caddyfile block as `ai.weown.agency`, but only `ai-stage` has a DNS record at this point).

### Phase 3 — Deploy app layer + restore on staging (≤ 20 min)

```bash
cd anythingllm-docker/sites/ai.weown.agency/scripts

INFISICAL_PROJECT_ID=<weown-anythingllm-id> ./deploy.sh root@$DROPLET
# This runs ansible-playbook which uploads compose.yaml, Caddyfile, backup.sh, restore.sh
# and starts the stack under `infisical run`. Watch for "Wait for AnythingLLM health" PASS.

# Then restore the backup
INFISICAL_PROJECT_ID=<weown-anythingllm-id> ./restore.sh root@$DROPLET int-p01-anythingllm_backup_<TS>
# restore.sh on the operator side wraps the droplet's restore.sh in `infisical run`,
# which fetches SPACES_ACCESS_KEY/SECRET so the tarball can be pulled from DO Spaces
# if it isn't already on the droplet from Phase 1's --upload-to-spaces.
```

Smoke-test on the staging URL:

```bash
curl -sf https://ai-stage.weown.agency/api/ping
# Expect: {"online":true,"version":"..."}
```

### Phase 4 — Jason + Yonks staging soak (gate 1 — HUMAN VALIDATION REQUIRED)

**Hand off to operator. Do NOT proceed without written sign-off in the PR.**

Operator (Nik) sends Jason + Yonks the staging URL `https://ai-stage.weown.agency` with the verification checklist (§7 of source plan D383). Critical gate item: **SearXNG web search must work** — that's the bug that motivated the migration.

Soak window: minimum 24 hours of dual-running with no production traffic on the staging URL. Real validation is Jason/Yonks driving real conversations through the Calhoun MetaAgent and confirming behavior matches DOKS.

**Update `POST_DEPLOY_NOTES.md`** with anything Jason flags. If anything is broken, fix on staging (do NOT touch DOKS), re-run Phase 3 deploy, retry validation.

### Phase 5 — Production DNS cutover (gate 2 — CTO APPROVAL REQUIRED)

**Hand off to operator (Nik) for the maintenance window. Do NOT initiate without written approval.**

Sequence:

1. Operator coordinates a brief maintenance window (10–15 min).
2. Operator switches DNS A-record for `ai.weown.agency` from the DOKS LoadBalancer IP to the droplet's reserved IP.
3. Wait for propagation: `dig +short ai.weown.agency` returns the droplet IP.
4. Caddy on the droplet already has the cert for `ai.weown.agency` (dual-hostname block; it was issued at Phase 2 time alongside `ai-stage`).
5. Smoke-test: `curl -sf https://ai.weown.agency/api/ping`.
6. **DOKS pod is left running** — do not stop or scale it. It is the rollback safety net.

**Rollback** (if anything goes wrong in the cutover window): switch DNS A-record back to the DOKS LoadBalancer. Cutover and rollback are both single DNS edits.

### Phase 6 — 7-day soak + DOKS decommission

After 7 days of clean production traffic on the droplet:

1. Operator runs `kubectl --kubeconfig ~/.kube/doks-int-p01 -n anythingllm scale deployment anythingllm --replicas=0` (NOT delete — keep manifest as rollback option).
2. After another 7 days with no rollback needed: `kubectl delete namespace anythingllm` + delete the DO LoadBalancer + delete the DOKS cluster if it was INT-P01-only.
3. Move ADR-005 from `Proposed` → `Accepted` (edit `.github/ADR-005-int-p01-doks-retirement.md` line 3).
4. Close Tuleap A174 / `#1238`.
5. Update `anythingllm/CHANGELOG.md` (the K8s deployment changelog) with the retirement note.

---

## Validation gates summary

| Gate | Phase | Validator | Required for | Pass criterion |
|---|---|---|---|---|
| **G0** | 1.5 (local) | Self (agent) | Provisioning droplet | All local validation checkboxes pass; SearXNG works locally |
| **G1** | 4 (staging soak) | Jason + Yonks | Production DNS cutover | Written PR comment "PASS — staging looks good"; SearXNG works on `ai-stage` |
| **G2** | 5 (cutover) | `@ncimino` (CTO) | Cutover execution | Maintenance window agreed; staging validated; rollback procedure rehearsed |
| **G3** | 6 (decom) | `@ncimino` (CTO) | DOKS namespace deletion | 7 days clean production traffic on droplet; no rollback events |

---

## What NOT to do

- ❌ **Do not modify the DOKS pod** during any phase up to Phase 5 — read-only `kubectl exec` only
- ❌ **Do not commit real secrets, droplet IPs, or VPC IPs** to git — see `.github/copilot-instructions.md` §3.6
- ❌ **Do not use `:latest` image tags** — §3.7; pin to `reg.mini.dev/anythingllm:1.7.2`
- ❌ **Do not skip Phase 1.5** (local test) — provisioning a droplet costs $$ and time; catch issues on the laptop first
- ❌ **Do not skip the staging soak** — Jason+Yonks must drive real conversations before cutover
- ❌ **Do not decom DOKS before the 7-day post-cutover soak** — it's the rollback safety net
- ❌ **Do not bypass branch protection** — every PR must have a non-author codeowner approval OR admin-merge with explicit reason

---

## Output expected at the end

1. A merged PR `feature/<dev>-int-p01-deploy` → `main` with:
   - `POST_DEPLOY_NOTES.md` (added by you) capturing: each phase's actual duration, issues hit, deltas vs runbook, validation evidence
   - Optionally any one-off operator scripts you wrote
   - **No** changes to the existing rendered site files (those are the contract; if you find a bug there, open a separate PR for the template fix)
2. A production droplet running at `ai.weown.agency` with:
   - DO tag `weown-ai`, `anythingllm`, `int-p01`, `commit-<sha>`, `skinny-backup` (auto-tagged by ansible)
   - Daily backups landing in `s3://weown-backups/int-p01-anythingllm/`
   - SigNoz Cloud telemetry flowing (via `bootstrap-otel-agent.sh` if not already deployed)
3. DOKS namespace `anythingllm` deleted; cluster decom if INT-P01-only
4. ADR-005 status: `Accepted`
5. Tuleap A174 / `#1238` closed

---

## When you get stuck

Read first, ask second:

1. **The runbook** (`MIGRATION_RUNBOOK.md`) — phase-by-phase procedure with exact commands
2. **The s004 site** (`anythingllm-docker/sites/s004/`) — what a working deployment of the same template looks like
3. **The OTel runbook** (`otel-agent/README.md`) — for telemetry setup
4. **`.github/workflows/README.md` §11** — troubleshooting CI / branch protection

Then ping the operator (Nik) with:

- Current phase + step
- What you tried
- Exact error message
- Hypothesis if you have one

Operator's expected response time: minutes for cutover-blocking issues, hours otherwise.

---

## Confirmation prompt (paste this back to operator before starting)

```
I have read:
- ADR-005-int-p01-doks-retirement.md
- anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md
- anythingllm-docker/sites/ai.weown.agency/DEPLOYMENT_PROMPT.md (this file)
- docs/INFRA_BOOTSTRAP_PATTERN.md
- .github/copilot-instructions.md
- anythingllm-docker/sites/s004/ (canonical reference)

I understand:
1. The pattern is parallel build + DNS cutover; DOKS is never modified before Phase 5
2. There are two human gates (G1: Jason+Yonks staging; G2: CTO production cutover) plus G0 (my local validation)
3. The new Phase 1.5 inserts a local-laptop validation BEFORE provisioning the staging droplet
4. Rollback at any point before Phase 6 decom is a single DNS A-record edit
5. SearXNG must work — that's the bug that motivated the migration and the staging gate's critical item
6. Image is pinned to reg.mini.dev/anythingllm:1.7.2 (NOT :latest)
7. No real secrets, droplet IPs, or VPC IPs ever get committed

I have the required local tools and operator-supplied credentials.

Ready to start Phase 0. Confirm to proceed.
```

If the operator does not confirm, **wait**. Do not proceed.
