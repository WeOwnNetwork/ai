# INT-P01 (AI.WeOwn.Agency) DOKS → Docker Migration Runbook

> **Source plan:** `Engagements/WeOwn/Projects/INT-P01 Migration Plan - DOKS to WeOwnLLM.md` (D383)
> **Owner:** Shahid (SHD) + CTO (Nik) co-review
> **Target window:** Wed **2026-05-27** (adjustable; gated on s004 soak + Jason availability)
> **Image:** `reg.mini.dev/anythingllm:latest` (WeOwnLLM hardened — confirmed working on s004.ccc.bot 2026-05-21)

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
| 3 | WeOwnLLM image pullable | `docker pull reg.mini.dev/anythingllm:latest` succeeds with Minimus token (A126) or via DOCR mirror (D341) |
| 4 | DO Spaces credentials in Infisical | `SPACES_ACCESS_KEY` + `SPACES_SECRET_KEY` exist in the `weown-anythingllm` Infisical project, `prod` env |
| 5 | Maintenance window agreed with Jason | Confirm in ♾️ WeOwn.Dev Signal |
| 6 | Local `kubectl` context for DOKS | `kubectl --kubeconfig <path> get pods -A` lists the AnythingLLM workload |
| 7 | DNS TTL pre-lowered | `ai.weown.agency` A record TTL ≤ 300s at least 30 min before cutover |

---

## Files in this directory (generated from `anythingllm-docker` template)

```text
sites/ai.weown.agency/
├── README.md                       # Template-rendered overview
├── CHANGELOG.md                    # Template-rendered changelog
├── MIGRATION_RUNBOOK.md            # ← this file
├── terraform/
│   ├── main.tf                     # Droplet, reserved IP, firewall
│   ├── monitoring.tf               # DO monitoring alerts
│   ├── outputs.tf
│   ├── variables.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example    # Copy to terraform.tfvars locally (gitignored)
│   └── templates/cloud-init.yaml
├── docker/
│   ├── compose.prod.yaml           # AnythingLLM + Caddy
│   └── Caddyfile                   # Reverse proxy + TLS
└── scripts/
    ├── deploy.sh                   # Push compose/Caddyfile + restart stack
    ├── backup.sh                   # Skinny backup (already running on the new droplet)
    ├── restore.sh                  # Unpack a skinny-backup tarball onto the new droplet
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

**Goal:** bring up the new droplet under a **temporary hostname** so Jason/Yonks can soak it without affecting `ai.weown.agency`.

1. Set up Terraform vars locally (file is gitignored, never commit):

   ```bash
   cd anythingllm-docker/sites/ai.weown.agency/terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Open `terraform.tfvars` and fill in:
   - `minimus_token` — DigitalOcean API token (Droplet, Reserved IP, Firewall, Tag, Monitoring scopes)
   - `ssh_key_fingerprint` — your SSH key fingerprint from DO Settings → Security
   - `infisical_client_id` — Machine Identity for the `weown-anythingllm` Infisical project (read scope)
   - `infisical_client_secret` — the one-time-shown client secret
   - `infisical_project_id` — `weown-anythingllm` project ID
   - **`domain`** — set to a **temporary** hostname for staging, e.g. `int-p01-new.ccc.bot` (matches the source plan's Phase 1 hostname)
   - Optionally adjust `do_region` if you want the new droplet closer to users / closer to the DOKS source for migration bandwidth

3. Apply:

   ```bash
   tofu init
   tofu plan       # confirm: 1 droplet + 1 reserved IP + 1 firewall + 1 alert policy
   tofu apply
   tofu output -raw droplet_ip
   ```

4. Add a DNS A record for the **temporary hostname** pointing at the droplet IP, e.g.:

   ```text
   int-p01-new.ccc.bot.   60   IN   A   <droplet-ip>
   ```

   Caddy will request a Let's Encrypt cert automatically on first start. Verify:

   ```bash
   curl -fv https://int-p01-new.ccc.bot/  # expect 200 + AnythingLLM login page
   ```

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

Output: a single file `./backups/int-p01_backup_<TS>.tar.gz` ready for `restore.sh`.

**Sanity-check size:** if the tarball is < 10 MB, something is wrong — AnythingLLM storage for a live instance with workspaces + embeddings is typically 100 MB – several GB. Inspect:

```bash
tar tzf ./backups/int-p01_backup_<TS>.tar.gz | head -20
```

You should see `anythingllm_storage.tar.gz` and `source.txt` inside.

Optionally, also stage the tarball on DO Spaces for redundancy:

```bash
# Pull SPACES_* from Infisical first (do NOT echo them into your shell history)
read -rs "SPACES_ACCESS_KEY?Paste SPACES_ACCESS_KEY: "; echo
read -rs "SPACES_SECRET_KEY?Paste SPACES_SECRET_KEY: "; echo
trap 'unset SPACES_ACCESS_KEY SPACES_SECRET_KEY' EXIT

./migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --upload-to-spaces
```

---

## Phase 3 — Restore onto the staging droplet

**Goal:** load the DOKS storage into the new droplet's `int_p01_storage` Docker volume.

1. Copy the tarball to the droplet (or rely on `restore.sh`'s built-in DO Spaces fetch if you used `--upload-to-spaces` above):

   ```bash
   DROPLET=$(cd ../terraform && tofu output -raw droplet_ip)
   scp ./backups/int-p01_backup_<TS>.tar.gz root@$DROPLET:/opt/intp01/backups/
   ```

2. Trigger the restore on the droplet, wrapped in `infisical run` so the Spaces creds (if needed) are injected:

   ```bash
   ssh root@$DROPLET 'cd /opt/intp01 && \
     infisical run --projectId=<weown-anythingllm-id> --env=prod -- \
     ./restore.sh int-p01_backup_<TS>'
   ```

   `restore.sh` will:
   - stop the `anythingllm` container
   - wipe `/app/server/storage` inside the volume
   - extract `anythingllm_storage.tar.gz` into the volume
   - restart `anythingllm`

3. Verify the container is healthy:

   ```bash
   ssh root@$DROPLET 'cd /opt/intp01 && docker compose ps'
   ssh root@$DROPLET 'cd /opt/intp01 && docker compose logs --tail 50 anythingllm'
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
- [ ] Skinny backups running (check `/var/log/intp01-backup.log` next morning)
- [ ] Infisical secrets resolving at runtime (`docker compose logs` shows no `${VAR}` literals)
- [ ] Telemetry off (R7)

**Do not proceed to Phase 5 until Jason gives explicit go-ahead.**

---

## Phase 5 — Delta sync (only if Phase 4 took > 24h)

If the staging soak took longer than a few hours, content has likely drifted on DOKS since Phase 2. Re-run the bridge:

```bash
./migrate-from-doks.sh \
  --kubeconfig ~/.kube/doks-int-p01 \
  --namespace anythingllm \
  --selector 'app.kubernetes.io/name=anythingllm' \
  --output-dir ./backups
# → produces int-p01_backup_<NEW_TS>.tar.gz

scp ./backups/int-p01_backup_<NEW_TS>.tar.gz root@$DROPLET:/opt/intp01/backups/

ssh root@$DROPLET 'cd /opt/intp01 && \
  infisical run --projectId=<id> --env=prod -- \
  ./restore.sh int-p01_backup_<NEW_TS>'
```

Re-spot-check Phase 4 items with Jason once more after the delta restore.

---

## Phase 6 — Production cutover

**Goal:** flip `ai.weown.agency` DNS to the new droplet and re-issue TLS.

1. Edit `terraform/terraform.tfvars` and change:

   ```hcl
   domain = "ai.weown.agency"   # was "int-p01-new.ccc.bot"
   ```

2. Re-deploy the Caddyfile + compose (Terraform doesn't need re-apply for this; cloud-init only runs once):

   ```bash
   # Regenerate the Caddyfile/compose locally with the new domain
   cd ../../..  # back to repo root
   /Users/nik/.pyenv/versions/3.14.2/bin/copier update anythingllm-docker/sites/ai.weown.agency \
     --data-file /tmp/int-p01-copier-answers.yaml \
     --data domain=ai.weown.agency \
     --defaults --trust

   cd anythingllm-docker/sites/ai.weown.agency/scripts
   ./deploy.sh root@$DROPLET
   ```

   `deploy.sh` uploads the new `Caddyfile` + `compose.yaml` and runs `docker compose up -d` under `infisical run` — Caddy will auto-fetch a new cert for `ai.weown.agency`.

3. Flip DNS:

   ```text
   ai.weown.agency.   60   IN   A   <droplet-ip>     # was DOKS ingress IP
   ```

4. Verify:

   ```bash
   dig +short ai.weown.agency                # expect droplet IP
   curl -fv https://ai.weown.agency/         # expect 200 + AnythingLLM
   ssh root@$DROPLET 'cd /opt/intp01 && docker compose logs --tail 30 caddy' \
     | grep -i 'certificate obtained'        # confirm fresh cert
   ```

5. **Leave the temporary hostname (`int-p01-new.ccc.bot`) DNS record in place** for the soak week so engineers can still reach the box directly without going through the production CNAME.

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
   - Image → `reg.mini.dev/anythingllm:latest`
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
3. **AnythingLLM version on DOKS** — pin the new droplet to the same major/minor first; upgrade after stable cutover. Current default in `compose.prod.yaml` is whatever `reg.mini.dev/anythingllm:latest` resolves to; if DOKS is significantly older, replace `latest` with a digest matching the DOKS pod.
4. **Registry pull path** — `reg.mini.dev/anythingllm:latest` vs `reg.mini.dev/mini_key/anythingllm:latest`. s004 used the simpler path successfully; the D381 doc references the longer one. Verify before `tofu apply` and adjust `anythingllm_image` in `terraform.tfvars` if needed.
5. **DOCR mirror (D341) ready?** — if yes, switch `anythingllm_image` to the DOCR mirror so deploy-time isn't gated on Minimus uptime.
