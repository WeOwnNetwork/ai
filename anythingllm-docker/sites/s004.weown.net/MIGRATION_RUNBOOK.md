# INT-S004 Rebuild → s004.weown.net — Recovery Runbook

> **What:** stand up a fresh AnythingLLM droplet for INT-S004 under the new
> standard FQDN `s004.weown.net`, restore the data exported off the old
> `s004.ccc.bot` box, validate, flip DNS, then decommission the old box.
> **Image:** `reg.mini.dev/anythingllm:1.7.2` (same pin as the source box —
> restored storage needs no schema migration).
> **Pattern:** parallel-build + DNS-cutover. The old `s004.ccc.bot` droplet is
> **never modified** until after the soak, so rollback is keeping it untouched.
> **Owner:** Nik (CTO) + Shahid (SHD).

---

## Why we are rebuilding

The old `s004.ccc.bot` failed two ways; the gates in Phase 5 confirm the new
box closes both:

- **Auth lockout.** AnythingLLM logged `Cannot create JWT as JWT_SECRET is
  unset` at `makeJWT`. A container restart came back with `JWT_SECRET` empty
  because the secret was not injected, and every login failed. The root cause
  was an out-of-band, uncommitted in-container secret-injection change — **not**
  a user-creation action.
- **No backups.** The old box never got the canonical ansible deploy, so the
  daily backup cron was never installed and nothing ever reached DO Spaces.

This rebuild deploys **only from committed IaC** (no hand-edits on the
droplet), keeps `JWT_SECRET` present + persistent in Infisical (set once, never
rotated), starts the container only under `infisical run`, and adds a
`${JWT_SECRET:?...}` compose guard that makes a mis-started container **fail
loud** instead of serving broken auth.

---

## Decisions for this rebuild

| Decision | Value |
|---|---|
| Site folder | `anythingllm-docker/sites/s004.weown.net/` |
| `project_name` | `int-s004-anythingllm` (→ `/opt/int_s004_anythingllm`, volume `int_s004_anythingllm_storage`, cron `int_s004_anythingllm-backup`) |
| Secret injection | committed host-side `infisical run` (NOT in-container injection — proposed separately as ADR-006) |
| Hostname | single-host `s004.weown.net` (see "Hostname decision" below) |
| Infisical project | dedicated s004 project + Machine Identity scoped to s004 only |

### Hostname decision (verified)

`s004.weown.net` is served as the **only** hostname. Before deciding this, the
repo was audited for any dependency on the legacy `s004.ccc.bot`:

- every `s004.ccc.bot` reference is either self-referential to the retired
  `sites/s004/` folder or historical prose (CHANGELOG, ADR-005, the INT-P01
  runbook) — **nothing routes to it** (no integration config, no other host's
  Caddyfile, no DNS-zone file, no instance-registry wiring);
- `s004.weown.net` appears nowhere else yet (brand-new name); and
- the old box is locked out, so there is no live `s004.ccc.bot` traffic to
  preserve.

**Escape hatch:** if an external consumer of `s004.ccc.bot` ever surfaces,
change the `docker/Caddyfile` site line to `s004.weown.net, s004.ccc.bot {`
and re-run `./scripts/deploy.sh`. Caddy fetches the new cert on first request —
no `tofu taint`, no downtime (Path C: the Caddyfile is ansible-owned).

---

## Prerequisites (verify before starting)

| # | Item |
|---|---|
| 1 | **Dedicated s004 Infisical project** created, `prod` env, with `JWT_SECRET` (`openssl rand -hex 32`, set once / never rotate), a **fresh** `OPENROUTER_API_KEY` (old one expired 2026-06-01), `ADMIN_EMAIL`, and `SPACES_ACCESS_KEY` + `SPACES_SECRET_KEY` (required — no offsite backup without them). |
| 2 | **Machine Identity** scoped to that project (Viewer on `prod`); Client ID + one-time Client Secret in hand. |
| 3 | **DigitalOcean API token** (Droplet, Reserved IP, Firewall, Tag, Monitoring scopes) + **DO Spaces** keys for the tofu state backend + a fresh SSE-C key. |
| 4 | **SSH key** registered in DO; you know its fingerprint. |
| 5 | **The off-box export** `s004_storage_<TS>.tar.gz` (root = contents of `/app/server/storage`: `anythingllm.db`, `lancedb/`, `documents/`, …) on your workstation. |
| 6 | **DNS control** for `weown.net` (ability to add an A record with TTL ≤ 300s). |

---

## Files in this directory (Path C — see [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md))

```text
sites/s004.weown.net/
├── README.md                       # Site overview + steady-state ops
├── CHANGELOG.md                    # Site-level changelog
├── MIGRATION_RUNBOOK.md            # ← this file
├── terraform/                      # Layer 1: droplet + DO Spaces state backend
│   ├── backend.tf · init.sh · main.tf · monitoring.tf · outputs.tf
│   ├── variables.tf · versions.tf · terraform.tfvars.example
│   └── templates/cloud-init.yaml   # SLIM bootstrap: Docker + Infisical CLI +
│                                   #   Layer 2 secret rotation + marker. NO
│                                   #   compose, NO Caddyfile, NO cron here.
├── ansible/deploy.yml              # Path C app layer: compose + Caddyfile +
│                                   #   backup.sh + daily cron + logrotate +
│                                   #   `docker compose up -d` + DO tagging.
├── docker/
│   ├── compose.prod.yaml           # AnythingLLM (:1.7.2) + Caddy; JWT_SECRET:? guard
│   └── Caddyfile                   # Single-host s004.weown.net
└── scripts/
    ├── deploy.sh                   # Thin ansible-playbook wrapper
    ├── backup.sh                   # Skinny backup — local or remote-via-ssh
    └── restore.sh                  # Restore a skinny-backup tarball (daily-cron layout)
```

> There is no `migrate-from-doks.sh` here — INT-S004 is not on DOKS. The
> initial data import is the off-box tarball (Phase 4); `restore.sh` is for
> later restores from the daily skinny-backups.

---

## Phase 1 — Provision the droplet (Layer 1)

```bash
cd anythingllm-docker/sites/s004.weown.net/terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in: minimus_token, ssh_key_fingerprint, spaces_access_key/secret_key/
# encryption_key, infisical_client_id, infisical_client_secret, and the
# dedicated s004 infisical_project_id.
chmod +x ./init.sh
./init.sh                       # configures the DO Spaces state backend (SSE-C)
tofu plan                       # expect: 1 droplet + 1 reserved IP + 1 firewall + 3 alerts
tofu apply
DROPLET_IP=$(tofu output -raw droplet_ip)
echo "Droplet IP: $DROPLET_IP"
```

Cloud-init takes ~3 minutes. **Confirm the Layer 2 bootstrap-secret rotation:**

```bash
ssh "root@$DROPLET_IP" 'tail /var/log/int_s004_anythingllm-rotation.log'
# Expected last line: "===== Rotation complete ====="
```

If you see `ROTATION FAILED:`, follow the manual rotation runbook in
[`docs/INFRA_BOOTSTRAP_PATTERN.md`](../../../docs/INFRA_BOOTSTRAP_PATTERN.md)
before continuing (the droplet still works on v1 — rotation is best-effort).

---

## Phase 2 — DNS

Point the new FQDN at the droplet's reserved IP. Because `s004.weown.net` is
brand new, this is go-live, not a cutover — there is no existing traffic.

```text
s004.weown.net.   300   IN   A   <DROPLET_IP>
```

Keep TTL ≤ 300s until after soak so any correction propagates quickly.

---

## Phase 3 — Deploy the app layer (Path C)

```bash
cd ..    # sites/s004.weown.net/
INFISICAL_PROJECT_ID=<s004-project-id> ./scripts/deploy.sh "root@$DROPLET_IP"
```

This uploads `compose.yaml` + `Caddyfile` + `backup.sh`, installs the daily
backup cron + logrotate, pulls images, runs `docker compose up -d` **under
`infisical run`**, tags the droplet (`commit-<sha>` + `skinny-backup`), and
waits for `/api/ping`. At this point the droplet serves an **empty**
AnythingLLM on `s004.weown.net`. Caddy obtains the Let's Encrypt cert on first
HTTPS request after DNS resolves.

---

## Phase 4 — Restore the off-box export

Copy the tarball up, then swap it onto the fresh storage volume. The tarball's
root is the storage directory itself, so we extract it straight into the volume
(this is the raw-storage form — `scripts/restore.sh` is for the wrapped
skinny-backup layout instead).

```bash
scp ./s004_storage_<TS>.tar.gz "root@$DROPLET_IP:/root/restore/"   # mkdir /root/restore first if needed
```

On the droplet (as root):

```bash
# Select the AnythingLLM *app* container precisely. NOTE: a plain
# `grep -i anythingllm` also matches the Caddy container, because both share
# the compose project prefix `int_s004_anythingllm-`. Match the service:
CT=$(docker ps --format '{{.Names}}' | grep -E 'anythingllm-anythingllm-[0-9]+$' | head -1)
echo "app container: $CT"

# Stop/start the container BY NAME (not `docker compose stop`): the new
# JWT_SECRET:? compose guard makes any `docker compose` subcommand fail unless
# it runs under `infisical run`. `docker stop/start <name>` parses no compose
# file, so it is the clean way to bounce the container for a volume swap. A
# restarted container keeps the env injected when it was created.
docker stop "$CT"

docker run --rm \
  -v int_s004_anythingllm_storage:/data \
  -v /root/restore:/backup:ro \
  alpine:3.19 \
  sh -c 'rm -rf /data/* && tar xzf /backup/s004_storage_<TS>.tar.gz -C /data'

docker start "$CT"
```

(Same image `:1.7.2` as the source, so no schema migration is required.)

---

## Phase 5 — Verification gates

These would have caught BOTH old failures. Run from the droplet unless noted.

```bash
# 1. JWT_SECRET is actually injected (the lockout guard):
docker exec "$CT" printenv JWT_SECRET            # → non-empty

# 2. Daily backup cron is installed (the missing-backups fix):
ls -l /etc/cron.daily/int_s004_anythingllm-backup

# 3. No auth/secret errors in the app log. Use `docker logs` (by name), NOT
#    `docker compose logs` — the latter trips the JWT_SECRET:? guard outside
#    `infisical run`. Expect NO output (no lockout, no unsubstituted ${VAR}):
docker logs "$CT" 2>&1 | grep -iE 'jwt_secret is unset|\$\{[A-Z_]+\}' \
  || echo "clean: no JWT-unset / no literal \${VAR}"

# 4. App answers over HTTPS (from anywhere):
curl -fsS https://s004.weown.net/api/ping        # → 200
```

> Reminder: `/api/ping` returns 200 even when auth is broken. The 200 is
> necessary but NOT sufficient — do the manual checks below.

**By hand (log in to `https://s004.weown.net/`):**

- [ ] Log in with a **migrated** account (proves `anythingllm.db` + `JWT_SECRET` work together)
- [ ] Workspaces present; document counts look right
- [ ] A retrieval query returns vector hits (proves `lancedb/` came over intact)
- [ ] OpenRouter answers (fresh `OPENROUTER_API_KEY`) and SearXNG web search works
- [ ] Telemetry off

**Prove backups actually work (before decommission):**

```bash
# From your workstation — runs the droplet's backup.sh under infisical run:
INFISICAL_PROJECT_ID=<s004-project-id> ./scripts/backup.sh "root@$DROPLET_IP"

# Confirm a .tar.gz landed in DO Spaces (the script also prints this command):
#   aws s3 ls s3://weown-backups/int-s004-anythingllm/ \
#     --endpoint-url https://atl1.digitaloceanspaces.com
# Confirm the daily cron file is in place:
ssh "root@$DROPLET_IP" 'ls -l /etc/cron.daily/int_s004_anythingllm-backup'
```

Do not proceed to decommission until a backup object is confirmed in Spaces.

---

## Phase 6 — Soak

Watch DO monitoring alerts, container logs, and the AnythingLLM error rate.
Stay reachable in `♾️ WeOwn.Dev` Signal. Keep TTL low and the old box untouched.

---

## Phase 7 — Decommission the old `s004.ccc.bot`

Only after the soak passes **and** the new box has its own verified DO Spaces
backup (Phase 5). Keep the off-box export `s004_storage_<TS>.tar.gz` as a
last-resort restore source until decommission is fully complete.

Do not leave the live box diverged from git: the deployed compose/Caddy/scripts
must match this branch (they will, since the deploy runs from committed IaC).

---

## Rollback

The old `s004.ccc.bot` droplet is never modified through Phases 1–6, but it is
already locked out, so it is not a working fallback. Rollback therefore means:

| Situation | Action |
|---|---|
| New box fails validation (Phase 5) | Do NOT announce `s004.weown.net` / do NOT decommission. Debug the new box (or rebuild it); the old box and the off-box export are untouched. |
| Problem found during soak | Same — nothing has been torn down. Fix forward on the new box. |
| Catastrophic loss of the new box | Re-provision (Phases 1–3) and re-restore from the off-box export (Phase 4). |

---

## Stakeholder communication

Tell Shahid (plain text, no Tuleap IDs): the old `s004.ccc.bot` is being
retired and rebuilt as the new standard `s004.weown.net`; **do not make changes
on the old box**; the lockout root cause was `JWT_SECRET` not being injected on
a container restart (not a user-creation action); the new box fails fast if the
secret is missing and has working, verified backups.
