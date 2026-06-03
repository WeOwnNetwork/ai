# INT-P01 (AI.WeOwn.Agency) DOKS → Docker Migration Runbook

> **Source plan:** `Engagements/WeOwn/Projects/INT-P01 Migration Plan - DOKS to WeOwnLLM.md` (D383)
> **Decision record:** [`ADR-005`](../../../.github/ADR-005-int-p01-doks-retirement.md) — rationale, compliance mappings, validation gates
> **Owner:** Shahid (SHD) + CTO (Nik) co-review
> **Target window:** Wed **2026-05-27** (adjustable; gated on s004 soak + Jason availability)
> **Image:** injected at runtime via the Infisical `ANYTHINGLLM_IMAGE` secret (compose reads `${ANYTHINGLLM_IMAGE}`). INT-P01 plans to pin `reg.mini.dev/anythingllm:1.7.2` to match its DOKS version, then upgrade after a stable cutover. (The s004.ccc.bot rebuild has since moved to `v1.12.1`, so this is INT-P01's independent choice, not a shared pin.)

---

## What this runbook delivers

A reproducible, **parallel-build + DNS-cutover** migration of INT-P01 off DOKS onto a single DigitalOcean droplet using the `anythingllm-docker` template. The DOKS instance is **never modified** until the post-cutover soak completes, so rollback is a DNS flip.

There are two checkpoints where a human must confirm before proceeding:

1. **Staging soak (Phase 4)** — Jason/Yonks validate the new droplet behind a temporary hostname.
2. **Cutover (Phase 6)** — CTO approves the DNS flip to `ai.weown.agency`.

---

## Prerequisites (verify before starting)

| # | Item | Status check |
|---|---|---|
| 1 | s004.ccc.bot soak complete | A132/#1165 — Jason confirms "working well" |
| 2 | `anythingllm-docker` template SearXNG-ready | A131/#1164 — SearXNG already runs on `searxng.weown.app`; the new droplet just needs outbound HTTPS to it (default firewall allows this) |
| 3 | WeOwnLLM image pullable | `docker pull reg.mini.dev/anythingllm:1.7.2` succeeds with Minimus token (A126) or via DOCR mirror (D341) |
| 4 | DO Spaces credentials in Infisical | `SPACES_ACCESS_KEY` + `SPACES_SECRET_KEY` exist in the `weown-anythingllm` Infisical project, `prod` env |
| 5 | Maintenance window agreed with Jason | Confirm in ♾️ WeOwn.Dev Signal |
| 6 | Local `kubectl` context for DOKS | `kubectl --kubeconfig <path> get pods -A` lists the AnythingLLM workload |
| 7 | DNS TTL pre-lowered | `ai.weown.agency` A record TTL ≤ 300s at least 30 min before cutover |

---

## Files in this directory (Path C — see [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md))

```text
sites/ai.weown.agency/
├── README.md                       # Site overview + steady-state ops
├── CHANGELOG.md                    # Site-level changelog
├── MIGRATION_RUNBOOK.md            # ← this file (one-shot INT-P01 migration)
├── terraform/                      # Layer 1: droplet + DO Spaces state backend
│   ├── backend.tf                  # S3-compat DO Spaces backend (SSE-C)
│   ├── init.sh                     # Reads spaces_* creds → `tofu init -backend-config=`
│   ├── main.tf                     # Droplet, reserved IP, firewall, cloud-init wiring
│   ├── monitoring.tf               # DO monitoring alerts
│   ├── outputs.tf                  # droplet IP + URL outputs
│   ├── variables.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example    # Copy to terraform.tfvars locally (gitignored)
│   └── templates/cloud-init.yaml   # SLIM bootstrap: Docker + Infisical CLI +
│                                   #   Layer 2 bootstrap-secret rotation +
│                                   #   .bootstrap-complete marker. NO compose,
│                                   #   NO Caddyfile, NO backup cron here.
├── ansible/                        # Path C app layer (runs from operator workstation)
│   └── deploy.yml                  # Uploads compose+Caddyfile+backup.sh, installs
│                                   #   cron + logrotate, `docker compose up -d`,
│                                   #   tags droplet with commit-<sha> + skinny-backup,
│                                   #   waits for /api/ping health.
├── docker/                         # Files uploaded by ansible (NOT cloud-init)
│   ├── compose.prod.yaml           # AnythingLLM (pinned to :1.7.2) + Caddy
│   └── Caddyfile                   # Dual-hostname (ai-stage + ai.weown.agency)
└── scripts/                        # Operator entry-points
    ├── deploy.sh                   # Thin ansible-playbook wrapper
    ├── backup.sh                   # Skinny backup — local or remote-via-ssh
    ├── restore.sh                  # Restore a skinny-backup tarball
    └── migrate-from-doks.sh        # ← one-shot: extract DOKS PV → skinny-backup tarball
```

---

## Phase 0 — Inventory & freeze (T-2 days)

**Goal:** capture what's on DOKS so we can verify nothing is missing post-restore.

1. Connect to the DOKS cluster and inventory the AnythingLLM workload:

   ```bash
   export KUBECONFIG=~/.kube/doks-int-p01

   kubectl get ns
   # Note the namespace hosting AnythingLLM (e.g. `anythingllm`, `default`, ...)

   NS=<namespace>
   kubectl -n "$NS" get pods,svc,ingress,pvc
   kubectl -n "$NS" get pod -l app.kubernetes.io/name=anythingllm \
     -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'
   ```

2. Capture the on-disk inventory (workspaces, document counts, sqlite size) so we can diff after restore:

   ```bash
   POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=anythingllm \
     -o jsonpath='{.items[0].metadata.name}')

   kubectl -n "$NS" exec "$POD" -- ls -la /app/server/storage \
     | tee inventory-pre.txt

   kubectl -n "$NS" exec "$POD" -- du -sh /app/server/storage/* \
     | tee -a inventory-pre.txt
   ```

3. Announce a soft content freeze in ♾️ WeOwn.Dev Signal (no new workspaces/documents until cutover).

4. Take a DOKS persistent volume snapshot (defense-in-depth — we won't need it if migration succeeds):

   ```bash
   PVC=$(kubectl -n "$NS" get pvc -o jsonpath='{.items[0].metadata.name}')
   doctl compute volume-action snapshot <volume-id> --snapshot-name "int-p01-pre-migration-$(date +%Y%m%d)"
   ```

---

## Phase 1 — Provision the staging droplet (T-1 day)

**Goal:** bring up the new droplet under the staging hostname `ai-stage.weown.agency` so Jason/Yonks can soak it without affecting production. Because `ai-stage.weown.agency` is on the same parent zone as `ai.weown.agency`, when validation passes we simply re-point the production A record at this same droplet — no re-deploy, no second instance.

1. Set up Terraform vars locally (file is gitignored, never commit):

   ```bash
   cd anythingllm-docker/sites/ai.weown.agency/terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Open `terraform.tfvars` and fill in:
   - `minimus_token` — DigitalOcean API token (Droplet, Reserved IP, Firewall, Tag, Monitoring scopes)
   - `ssh_key_fingerprint` — your SSH key fingerprint from DO Settings → Security
   - `spaces_access_key` / `spaces_secret_key` / `spaces_encryption_key` — DO Spaces credentials for the terraform remote state backend (the SSE-C key is a 32-byte AES-256 key, base64-encoded; mint a fresh one for this site)
   - `infisical_client_id` — Machine Identity for the `weown-anythingllm` Infisical project (read scope)
   - `infisical_client_secret` — the one-time-shown client secret
   - `infisical_project_id` — `weown-anythingllm` project ID
   - `domain` — leave as `ai.weown.agency` (the production URL). The Caddyfile is dual-hostname (`ai-stage.weown.agency, ai.weown.agency`) regardless of this value; `domain` only affects the `tofu output` URL and monitoring alert text. Caddy obtains certs for both names at first request after DNS resolves.
   - Optionally adjust `do_region` if you want the new droplet closer to users / closer to the DOKS source for migration bandwidth

3. Initialize the DO Spaces state backend, plan, apply:

   ```bash
   chmod +x ./init.sh
   ./init.sh        # configures the DO Spaces remote state backend with the
                    # spaces_* credentials from terraform.tfvars (SSE-C
                    # encrypted; see ../docs/INFRA_BOOTSTRAP_PATTERN.md
                    # "Layer 1 — DO Spaces remote state")
   tofu plan        # confirm: 1 droplet + 1 reserved IP + 1 firewall + 1 alert policy
   tofu apply
   DROPLET_IP=$(tofu output -raw droplet_ip)
   echo "Droplet IP: $DROPLET_IP"
   ```

4. Add a DNS A record for the **staging hostname** pointing at the droplet IP:

   ```text
   ai-stage.weown.agency.   60   IN   A   <DROPLET_IP>
   ```

5. Wait for cloud-init to finish (~3 min) and confirm the **Layer 2 bootstrap-secret rotation** succeeded — this matters because the v1 secret in terraform state + DO droplet metadata is dead within minutes of provisioning, replaced by a v2 that only exists in `/opt/int_p01_anythingllm/.infisical-auth.env` on the droplet:

   ```bash
   ssh "root@$DROPLET_IP" 'tail /var/log/int_p01_anythingllm-rotation.log'
   # Expected last line: "===== Rotation complete ====="
   # If you see "ROTATION FAILED:" instead, follow the manual rotation
   # runbook in ../../../docs/INFRA_BOOTSTRAP_PATTERN.md before continuing.
   ```

6. After Phase 3a's ansible deploy completes (next phase), Caddy auto-fetches a Let's Encrypt cert. Verify:

   ```bash
   curl -fv https://ai-stage.weown.agency/  # expect 200 + AnythingLLM login page
   ```

---

## Phase 1.5 — Optional: local laptop dry-run

**Skip this phase if** you're confident enough to validate directly on the staging droplet (Phase 3+). The dry-run is purely a confidence-builder before you spend money on the droplet and before you touch DOKS.

**Goal:** confirm that `migrate-from-doks.sh` + `restore.sh` actually round-trip the DOKS storage into a working AnythingLLM container, without depending on the droplet at all.

1. **Extract DOKS data** (same as Phase 2 — produces `int-p01-anythingllm_backup_<TS>.tar.gz`):

   ```bash
   cd anythingllm-docker/sites/ai.weown.agency/scripts

   ./migrate-from-doks.sh \
     --kubeconfig ~/.kube/doks-int-p01 \
     --namespace anythingllm \
     --selector 'app.kubernetes.io/name=anythingllm' \
     --output-dir ./backups
   ```

2. **Spin up a single-node AnythingLLM locally** with the same image + volume name layout. Use OrbStack / Docker Desktop. Note: `Caddy` is omitted — we'll hit AnythingLLM on `localhost:3001` directly.

   ```bash
   docker network create int_p01_anythingllm_net 2>/dev/null || true
   docker volume create int_p01_anythingllm_storage 2>/dev/null || true

   docker run -d --name int-p01-local \
     --network int_p01_anythingllm_net \
     -p 3001:3001 \
     -v int_p01_anythingllm_storage:/app/server/storage \
     -e SERVER_PORT=3001 \
     -e STORAGE_DIR=/app/server/storage \
     -e DISABLE_TELEMETRY=true \
     -e JWT_SECRET="$(openssl rand -hex 32)" \
     -e ADMIN_EMAIL=admin@example.com \
     reg.mini.dev/anythingllm:1.7.2

   # Wait for healthcheck
   until curl -fs http://localhost:3001/api/ping >/dev/null; do sleep 2; done
   ```

3. **Restore the DOKS backup into the local volume** by hand (laptop has no `restore.sh`/Infisical):

   ```bash
   BACKUP_NAME=int-p01-anythingllm_backup_<TS>  # whichever you produced in step 1
   tar xzf ./backups/${BACKUP_NAME}.tar.gz -C /tmp

   docker stop int-p01-local

   docker run --rm \
     -v int_p01_anythingllm_storage:/data \
     -v /tmp/${BACKUP_NAME}:/backup:ro \
     alpine:3.19 \
     sh -c 'rm -rf /data/* && tar xzf /backup/anythingllm_storage.tar.gz -C /data'

   docker start int-p01-local
   ```

4. **Sanity-check the restored instance** at `http://localhost:3001`:
   - Log in with the DOKS admin account
   - Confirm workspaces are present
   - Browse a workspace's documents — expect the same set as `inventory-pre.txt`
   - Ask a workspace a question that requires retrieval — expect non-empty vector hits (proves LanceDB came over intact)

5. **Tear down** when done — this was a throwaway:

   ```bash
   docker rm -f int-p01-local
   docker volume rm int_p01_anythingllm_storage
   docker network rm int_p01_anythingllm_net
   ```

If the local dry-run passes, proceed to Phase 2 with high confidence. If anything is wrong (missing workspaces, vector search empty), debug here without burning a droplet or coordinating a maintenance window — the failure mode is in the tarball, not in any cloud infrastructure.

---

## Phase 2 — Extract DOKS data with `migrate-from-doks.sh`

**Goal:** capture the live AnythingLLM storage volume from DOKS as a "skinny backup" tarball.

> **Source pod is read-only during this step** — `tar` from a running container is safe but does not freeze writes. Either coordinate a quiet 5-minute window with Jason or accept that any writes during the tar will need to be re-captured during the Phase 5 delta.

```bash
cd anythingllm-docker/sites/ai.weown.agency/scripts

./migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --output-dir ./backups
```

Output: a single file `./backups/int-p01-anythingllm_backup_<TS>.tar.gz` ready for `restore.sh`.

**Sanity-check size:** if the tarball is < 10 MB, something is wrong — AnythingLLM storage for a live instance with workspaces + embeddings is typically 100 MB – several GB. Inspect:

```bash
tar tzf ./backups/int-p01-anythingllm_backup_<TS>.tar.gz | head -20
```

You should see `anythingllm_storage.tar.gz` and `source.txt` inside.

Optionally, also stage the tarball on DO Spaces for redundancy. Use the
zsh-or-bash-compatible `read` form (the zsh `VAR?prompt` syntax is preferred;
bash falls back to `read -rsp`). Both keep the secret out of your shell
history:

```bash
# Pull SPACES_* from Infisical first (do NOT echo them into your shell history)
read -rs "SPACES_ACCESS_KEY?Paste SPACES_ACCESS_KEY: " 2>/dev/null \
  || read -rsp "Paste SPACES_ACCESS_KEY: " SPACES_ACCESS_KEY
echo
read -rs "SPACES_SECRET_KEY?Paste SPACES_SECRET_KEY: " 2>/dev/null \
  || read -rsp "Paste SPACES_SECRET_KEY: " SPACES_SECRET_KEY
echo
export SPACES_ACCESS_KEY SPACES_SECRET_KEY
trap 'unset SPACES_ACCESS_KEY SPACES_SECRET_KEY 2>/dev/null || true' EXIT

./migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --upload-to-spaces
```

---

## Phase 3 — Deploy the app layer + restore onto the staging droplet

**Goal:** stand up the AnythingLLM stack on the new droplet (compose + Caddy),
then swap the DOKS storage on top of the empty data volume.

### 3a. Run the ansible app-layer deploy (Path C)

Cloud-init finished first-boot bootstrap (Docker + Infisical CLI + Layer 2
secret rotation + `.bootstrap-complete` marker). The app layer
(`compose.yaml`, `Caddyfile`, `backup.sh`, daily cron, `docker compose up`)
lives in [`ansible/deploy.yml`](ansible/deploy.yml) — re-runnable any time
compose/Caddyfile changes, no `tofu taint`:

```bash
DROPLET=$(cd ../terraform && tofu output -raw droplet_ip)
INFISICAL_PROJECT_ID=<weown-anythingllm-id> ./scripts/deploy.sh "root@$DROPLET"
```

`deploy.sh` is a thin ansible wrapper. It will:

- assert the droplet completed cloud-init bootstrap (`.bootstrap-complete`)
- upload `compose.yaml`, `Caddyfile`, `backup.sh`
- install the daily backup cron + logrotate
- `docker compose pull` + `docker compose up -d` under `infisical run`
- update DO droplet tags (`commit-<sha>` + `skinny-backup`)
- wait for `https://ai-stage.weown.agency/api/ping` to return 200

At this point the droplet is serving an **empty** AnythingLLM. We're about
to overwrite the storage volume with the DOKS dump.

### 3b. Restore the DOKS tarball onto the running droplet

Use the site's `scripts/restore.sh` from the laptop. The script logs into
Infisical on the droplet (using the `.infisical-auth.env` written by
cloud-init) and re-execs itself there under `infisical run` so the Spaces
creds are injected if the tarball needs to be fetched from S3:

```bash
# If you used --upload-to-spaces in Phase 2, you can skip the scp:
scp ./backups/int-p01-anythingllm_backup_<TS>.tar.gz \
    "root@$DROPLET:/opt/int_p01_anythingllm/backups/"

INFISICAL_PROJECT_ID=<weown-anythingllm-id> \
  ./scripts/restore.sh "root@$DROPLET" int-p01-anythingllm_backup_<TS>
```

The restore stops the `anythingllm` container, wipes `/app/server/storage`,
extracts `anythingllm_storage.tar.gz` from the tarball into the volume, and
restarts AnythingLLM.

### 3c. Verify

```bash
ssh "root@$DROPLET" 'cd /opt/int_p01_anythingllm && docker compose ps'
ssh "root@$DROPLET" 'cd /opt/int_p01_anythingllm && docker compose logs --tail 50 anythingllm'
# expect: "Server listening on port 3001" and no error spam
```

---

## Phase 4 — Staging validation (Jason + Yonks)

**This is the critical "before full production switch-over" checkpoint the plan requires.**

Send the staging URL to Jason + Yonks for hands-on validation against the `verification checklist` in the source plan (§7). Capture each item as PASS/FAIL in the cutover ticket (Tuleap A174/#1238):

- [ ] All workspaces present; document counts match `inventory-pre.txt`
- [ ] Embeddings/vector search returns results (LanceDB intact)
- [ ] Users + roles + API keys functional (multi-user mode)
- [ ] Calhoun MetaAgent loads with skills + MCP servers
- [ ] OpenRouter provider + native tool-calling working
- [ ] **SearXNG web search works for Calhoun (Opus 4.7)** ← the whole point
- [ ] Tavily still available as fallback
- [ ] Caddy TLS valid on the temporary hostname
- [ ] Skinny backups running (check `/var/log/int_p01_anythingllm-backup.log` next morning)
- [ ] Infisical secrets resolving at runtime (`docker compose logs` shows no `${VAR}` literals)
- [ ] Telemetry off (R7)

**Do not proceed to Phase 5 until Jason gives explicit go-ahead.**

---

## Phase 5 — Delta sync (only if Phase 4 took > 24h)

If the staging soak took longer than a few hours, content has likely drifted
on DOKS since Phase 2. Re-run the bridge + restore — same flow as Phase 3b,
just a fresher tarball:

```bash
./scripts/migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --output-dir ./backups
# → produces int-p01-anythingllm_backup_<NEW_TS>.tar.gz

scp ./backups/int-p01-anythingllm_backup_<NEW_TS>.tar.gz \
    "root@$DROPLET:/opt/int_p01_anythingllm/backups/"

INFISICAL_PROJECT_ID=<weown-anythingllm-id> \
  ./scripts/restore.sh "root@$DROPLET" int-p01-anythingllm_backup_<NEW_TS>
```

Re-spot-check Phase 4 items with Jason once more after the delta restore.

---

## Phase 6 — Production cutover (DNS swap, no re-deploy)

**Goal:** point `ai.weown.agency` at the same droplet that's been serving `ai-stage.weown.agency`. The droplet's Caddyfile already lists both names (uploaded by the Phase 3a ansible deploy — see [`docker/Caddyfile`](docker/Caddyfile); cloud-init does NOT manage the Caddyfile under the Path C pattern), so Caddy obtains the cert for `ai.weown.agency` the first time someone hits it after DNS propagates. No re-deploy.

Execute the cutover:

1. **Flip DNS** (TTL was pre-lowered to 60s in the prereqs):

   ```text
   ai.weown.agency.   60   IN   A   <droplet-ip>     # was DOKS ingress IP
   ```

2. **Verify**:

   ```bash
   dig +short ai.weown.agency                # expect droplet IP
   curl -fv https://ai.weown.agency/         # expect 200 + AnythingLLM
   ssh root@$DROPLET 'cd /opt/int_p01_anythingllm && docker compose logs --tail 30 caddy' \
     | grep -i 'certificate obtained'        # confirm fresh cert for ai.weown.agency
   ```

3. **Leave the `ai-stage.weown.agency` DNS record in place** for the soak week so engineers can hit the box directly without depending on the production hostname.

Note: there is no `terraform apply` and no `copier update` step here. The droplet hasn't changed — only the public DNS record pointing at it has.

---

## Phase 7 — Post-cutover soak (T+0 → T+7 days)

1. **Hour 0–48: active monitoring.** Watch DO monitoring alerts, container logs, AnythingLLM error rate. Stay reachable in ♾️ WeOwn.Dev Signal.
2. **Do NOT touch the DOKS instance.** Stop the deployment to free resources but keep all PVs intact:

   ```bash
   kubectl -n "$NS" scale deployment anythingllm --replicas=0
   ```

3. **Day 7 soak complete:** verify with Jason, then run DOKS decommission separately (Tuleap action item; out of scope for this runbook).
4. Update the Instances registry (Tuleap tracker 168) entry for INT-P01:
   - Platform → `droplet (anythingllm-docker)`
   - Image → `reg.mini.dev/anythingllm:1.7.2`
   - IP → new droplet reserved IP
   - DOKS reference removed

---

## Rollback (any phase before DOKS decommission)

DOKS is untouched throughout Phases 0–6. If something breaks at any point:

| At phase | Rollback action |
|---|---|
| 1–4 (staging) | Nothing to roll back — DOKS still serves `ai.weown.agency` |
| 6 (cutover) | Re-point `ai.weown.agency` DNS at the DOKS ingress IP. TTL is 60s so users recover in minutes. |
| 7 (post-cutover, pre-decommission) | Same as above — DOKS deployment scaled to 0 but PVs intact; scale back to 1 and flip DNS. |

After decommission (Day 7+), the DOKS PV snapshot from Phase 0 step 4 is the last-resort restore source.

---

## Open questions to surface back to Jason / CTO before execution

These come from §11 of the source plan and remain unresolved at the time of writing:

1. **Maintenance window** — confirm Wed 2026-05-27 (or alternative).
2. **Vector DB** — current plan assumes LanceDB on DOKS. Confirm with `kubectl exec` into the pod; if it's a different store (Chroma, Pinecone), the storage tarball is incomplete and we need a separate import step.
3. **AnythingLLM version on DOKS** — pin the new droplet to the same major/minor first; upgrade after stable cutover. The image is set via the Infisical `ANYTHINGLLM_IMAGE` secret (compose reads `${ANYTHINGLLM_IMAGE}`); INT-P01 plans `reg.mini.dev/anythingllm:1.7.2`. If DOKS is significantly older, set `ANYTHINGLLM_IMAGE` to a digest matching the DOKS pod.
4. **DOCR mirror (D341) ready?** — if yes, switch `anythingllm_image` to the DOCR mirror so deploy-time isn't gated on Minimus uptime.

> **Image path:** always use `reg.mini.dev/anythingllm:1.7.2` — no `mini_key` segment in the URL. Registry credentials are supplied separately at runtime via the Minimus token stored in Infisical (A126) or by the DOCR mirror's standard `docker login`. Anything that looks like an API key fragment embedded in an image URL is a leak waiting to happen and is not the way auth is wired for this stack.
