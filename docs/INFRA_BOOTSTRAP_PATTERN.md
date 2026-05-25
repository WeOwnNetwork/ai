# Infrastructure Bootstrap Pattern

**Status:** Adopted in `s004-deployment/` (proving ground). Migration pending for
other `*-docker` projects — see [Migration Plan](#migration-plan) below.

**Last updated:** 2026-05-25

This document describes the **two-layer deployment pattern** used by WeOwn's
single-droplet Docker-based services (anythingllm, signoz, searxng, keycloak,
wordpress). It addresses two architectural issues that were found during PR #26
and PR #31 code review:

1. **Layer 2 — Bootstrap-secret rotation** — limits the window in which the
   Infisical Machine Identity stored in terraform state / DigitalOcean droplet
   metadata is exploitable.
2. **Path C — Thin cloud-init + Ansible** — separates first-boot bootstrap
   (terraform-owned) from ongoing app-layer config (ansible-owned) so that
   updates to compose, Caddy, scripts, and cron do NOT require destroying
   and recreating the droplet.

---

## Background — the two problems

### Problem 1: Infisical Machine Identity persists in terraform state

`digitalocean_droplet.user_data` is set via `templatefile(cloud-init.yaml, {...})`.
If the rendered cloud-init contains the Machine Identity Client ID + Client
Secret (which it must, to bootstrap Infisical login on first boot), then:

- The fully-rendered `user_data` (with secrets) is persisted in
  `terraform.tfstate` as JSON.
- DigitalOcean stores `user_data` and exposes it via the droplet metadata
  API (`http://169.254.169.254/metadata/v1/user-data`) — readable from any
  process inside the droplet, no auth required.
- The secret is a **bearer credential**: it works from anywhere, not just
  from the droplet, for the lifetime it remains valid in Infisical.
- `sensitive = true` on the terraform variable only hides it from
  `terraform plan` console output. State + metadata still hold cleartext.

### Problem 2: `lifecycle { ignore_changes = [user_data] }` masks updates

DigitalOcean treats `user_data` as immutable after droplet creation. Without
`ignore_changes`, any cloud-init edit triggers droplet destruction + recreation
on the next `tofu apply` — data loss + downtime.

But with `ignore_changes`, cloud-init edits **silently no-op**. A fix in
cloud-init.yaml will never reach an already-provisioned droplet without
explicit `tofu taint` (which still destroys + recreates).

When cloud-init carries non-bootstrap content (compose.yaml, Caddyfile, backup
scripts, cron jobs), every legitimate config change becomes a "destroy the
droplet" decision. This is the trap.

---

## The pattern

### Layer 2 — Bootstrap-secret rotation

**Goal:** the Machine Identity secret persisted in terraform state and DO
metadata is **dead** within minutes of the droplet's first boot.

**Mechanism:**

1. Operator generates a Machine Identity in Infisical with a "v1" Client
   Secret. Puts v1 in `terraform.tfvars`.
2. `tofu apply` renders v1 into `user_data` (via templatefile). It is now in
   state + DO metadata.
3. Cloud-init writes v1 to `/opt/<app>/.infisical-auth.env` (`0600 root`).
4. Cloud-init runs `rotate-bootstrap-secret.sh` ONCE at first boot:
   - Logs into Infisical using v1, captures access token.
   - Decodes the JWT to extract `identityId`.
   - Calls `POST /api/v1/auth/universal-auth/identities/{id}/client-secrets`
     to mint v2.
   - Atomically swaps `.infisical-auth.env` to use v2 (after verifying v2
     authenticates).
   - Calls `POST .../client-secrets/{v1Id}/revoke` to disable v1.
   - Touches `.rotation-complete` (idempotency marker).
5. All subsequent operations (docker compose up, cron backups, ansible deploys)
   use v2. v2 only ever exists on the droplet's filesystem.

**Permissions required on the Machine Identity:**

- Project-level: `Viewer` role on the target project, scoped to the prod env.
- Org-level: ability to manage its own Universal Auth client secrets (varies
  by Infisical role configuration — may require a custom role).

**Failure mode:** if the v2 mint fails (most commonly because the Machine
Identity lacks permission to manage its own credentials), `rotate-bootstrap-secret.sh`
logs the failure clearly to `/var/log/<app>-rotation.log` and exits 0. The
operator must follow the manual rotation runbook in the app's README. The
droplet still functions with v1 — Layer 2 is best-effort, not blocking.

**What Layer 2 does NOT solve:**

- v1 is in terraform state until first boot finishes. A read of state during
  that window (typically <2 minutes from `tofu apply` to rotation) yields a
  working credential. Mitigate by tightly controlling state backend access.
- A future destroy + recreate of the droplet will mint a new v1 (from
  terraform.tfvars) and rotate to a new v2. This is an acceptable steady state
  if the destroy is operator-initiated.

### Path C — Thin cloud-init + Ansible app layer

**Goal:** ongoing config changes (compose, Caddy, scripts, cron) do not require
droplet replacement.

**Cloud-init responsibilities (first-boot only — never edit after droplet exists):**

- Install base packages (curl, gnupg, lsb-release, jq, etc.)
- Install Docker
- Install Infisical CLI (current `artifacts-cli.infisical.com` apt repo)
- Write `/opt/<app>/.infisical-auth.env` with the bootstrap Machine Identity
- Run `rotate-bootstrap-secret.sh` (Layer 2)
- Touch `/opt/<app>/.bootstrap-complete` marker
- Enable unattended-upgrades

**Ansible playbook responsibilities (re-runnable any time):**

- Upload `docker/compose.prod.yaml` → `/opt/<app>/compose.yaml`
- Upload `docker/Caddyfile` → `/opt/<app>/Caddyfile`
- Upload `scripts/backup.sh` → `/opt/<app>/backup.sh`
- Render daily backup cron in `/etc/cron.daily/<app>-backup`
- Install logrotate config for backup log
- Pull container images
- Run `docker compose up -d --remove-orphans` (notify-handlers for force-recreate
  when compose/Caddy/backup files change)
- Wait for app health endpoint

**Workflow:**

```bash
# First-time provision:
cd <app>/terraform
./init.sh                      # configures DO Spaces backend
tofu plan
tofu apply                     # creates droplet; cloud-init bootstraps + rotates

# Application deploy (first time AND every subsequent update):
INFISICAL_PROJECT_ID=<id> ../scripts/deploy.sh root@<droplet-ip>

# After editing compose.yaml / Caddyfile / backup.sh — just re-run deploy.sh.
# No `tofu apply` needed. No droplet downtime.
```

**Boundary rule:** *if a file's content might change during the droplet's
lifetime, it does NOT belong in cloud-init.* If it's strictly install-time
bootstrap, it belongs there. Everything else lives in ansible.

---

## Reference implementation

[`s004-deployment/`](../s004-deployment/) is the canonical Path C +
Layer 2 implementation as of 2026-05-25:

| Layer | File | Responsibility |
|---|---|---|
| Bootstrap | [terraform/templates/cloud-init.yaml](../s004-deployment/terraform/templates/cloud-init.yaml) | Docker, Infisical CLI, `.infisical-auth.env`, rotation |
| Rotation | embedded in cloud-init as `rotate-bootstrap-secret.sh` | Layer 2 mechanism |
| App layer | [ansible/deploy.yml](../s004-deployment/ansible/deploy.yml) | compose + Caddy + backup cron + reconcile |
| Wrapper | [scripts/deploy.sh](../s004-deployment/scripts/deploy.sh) | Thin convenience wrapper around `ansible-playbook` |

---

## Manual rotation runbook (Layer 2 fallback)

If `/var/log/<app>-rotation.log` ends with `ROTATION FAILED:` instead of
`===== Rotation complete =====`, automated rotation didn't work. Most common
cause: the Machine Identity lacks org-level permission to manage its own
client secrets.

**Manual steps:**

1. Confirm the v1 secret on the droplet still works:

   ```bash
   ssh root@<droplet> 'source /opt/<app>/.infisical-auth.env && \
     infisical login --method=universal-auth \
       --clientId="$INFISICAL_CLIENT_ID" \
       --clientSecret="$INFISICAL_CLIENT_SECRET" --silent && echo OK'
   ```

2. In the Infisical UI: **Project → Identities → \<your-bootstrap-identity\>
   → Client Secrets → Create**. Copy the new (v2) secret immediately —
   shown only once.
3. SSH to the droplet and atomically swap the auth file:

   ```bash
   ssh root@<droplet>
   sudo -i
   cd /opt/<app>
   cp .infisical-auth.env .infisical-auth.env.v1.backup
   # Edit .infisical-auth.env, change INFISICAL_CLIENT_SECRET to the v2 value
   nano .infisical-auth.env
   # Verify v2 works:
   source .infisical-auth.env
   infisical login --method=universal-auth \
     --clientId="$INFISICAL_CLIENT_ID" \
     --clientSecret="$INFISICAL_CLIENT_SECRET" --silent && echo "v2 OK"
   # If OK, delete v1 backup:
   rm .infisical-auth.env.v1.backup
   ```

4. In the Infisical UI: **Project → Identities → \<your-bootstrap-identity\>
   → Client Secrets → revoke the v1 secret** (the one shown in
   `terraform.tfvars`).
5. Touch the marker so future cloud-init re-runs don't try to re-rotate:

   ```bash
   ssh root@<droplet> 'touch /opt/<app>/.rotation-complete && chmod 0600 /opt/<app>/.rotation-complete'
   ```

After step 4, the v1 secret in terraform state and DO metadata is dead.

---

## Migration plan

Apply this pattern to the other single-droplet templates in the repo. Each
project has the same shape (terraform/templates/cloud-init.yaml.jinja with
embedded compose + scripts), so the work is similar.

### Migration checklist per project

For each `<app>-docker/` template:

1. **Slim the cloud-init template** (`template/terraform/templates/cloud-init.yaml.jinja`):
   - Remove `write_files:` entries for `compose.yaml`, `Caddyfile`,
     `backup.sh`, `/etc/cron.daily/*` — those move to ansible.
   - Keep: package install, Docker install, Infisical CLI install
     (artifacts-cli apt repo pattern), `.infisical-auth.env` write,
     `rotate-bootstrap-secret.sh` write + run, marker file.
   - Remove `runcmd:` entries that ran `docker compose up`, `docker pull`,
     compose-related — those move to ansible.
   - Keep: `bash /tmp/install-docker.sh`, `bash /tmp/install-infisical.sh`,
     `mkdir /opt/<app>/backups`, `systemctl restart docker`, the
     rotation script invocation, `touch .bootstrap-complete`,
     `dpkg-reconfigure unattended-upgrades`.
2. **Add the Layer 2 rotation script** to the slimmed cloud-init's
   `write_files:` section. Copy from `s004-deployment/terraform/templates/cloud-init.yaml`
   and update paths (`/opt/<app>/.infisical-auth.env`, log path).
3. **Promote `template/ansible/deploy.yml.jinja` to own the full app layer.**
   Move responsibility for compose.yaml + Caddyfile + backup.sh + cron from
   cloud-init into the ansible playbook. The signoz template already has
   most of this — needs additions for backup cron + logrotate.
4. **Update `template/scripts/deploy.sh.jinja`** to be a thin wrapper
   around `ansible-playbook`. Copy `s004-deployment/scripts/deploy.sh` as the
   reference.
5. **Update `template/README.md.jinja`** Quick Start to reflect the new flow:
   `./init.sh` → `tofu apply` → `INFISICAL_PROJECT_ID=… ./scripts/deploy.sh
   root@<ip>`.
6. **Add Layer 2 runbook** to the template README — same content as the
   "Manual rotation runbook" section above, adjusted for the project's paths.

### Project migration status

| Project | Status | Notes |
|---|---|---|
| `s004-deployment/` | **Done** (this PR, 2026-05-25) | Reference implementation. Flat (not a copier template), so the only consumer is this deployment. |
| `signoz-docker/` | Pending | Highest priority — also has the SSH-CIDR + s3-backup-unimplemented + retention-not-wired issues from PR #26 review still partially open. The biggest one is the ZooKeeper anonymous-login note that ships as "accepted risk." |
| `searxng-docker/` | Pending | Similar pattern. `init.sh` already exists (PR #26). |
| `anythingllm-docker/` | Pending | Currently still has `infisical.com/install-cli.sh` (deprecated channel). Adopt the Layer 2 + Path C migration in the same PR that fixes the CLI install. |
| `keycloak-docker/` | Partial — `sites/sso.weown.dev/terraform/` already uses the `init.sh` + backend-config pattern. Needs the cloud-init slim down + ansible promotion. | |
| `wordpress-docker/` | Pending | Recently restructured (PR #32). |

### Sequencing recommendation

1. **Don't bundle the migration into PR #31** — s004-deployment proves the
   pattern; other templates can each adopt it in a focused follow-up PR.
2. **Order by deployment criticality:** anythingllm-docker (live deploys) →
   wordpress-docker (multiple sites) → keycloak-docker (auth tier) →
   signoz-docker (fallback only) → searxng-docker.
3. **Each migration is ~2-4 hours of focused work** plus a `tofu taint` +
   `tofu apply` against any existing droplet to apply the slimmed cloud-init.
   Pre-existing droplets will not auto-adopt the new pattern; they need
   redeployment.

### Migration risks

- **Existing droplets need destroying + recreating** to pick up the slimmed
  cloud-init (because of `ignore_changes = [user_data]` — this is the exact
  problem we are solving for future deploys). Plan downtime windows for
  production services.
- **Ansible becomes a hard dependency** on operator workstations.
  `pipx install --include-deps ansible` works on any platform.
- **The Layer 2 rotation script depends on Infisical's API behavior** which
  may evolve. Pin to the API version that's documented today
  (`/api/v1/auth/universal-auth/...`) and re-test on Infisical version bumps.

### Out of scope for this pattern (future hardening)

The next architectural layer beyond Layer 2 would be **never embedding the
bootstrap secret in cloud-init at all**. Options:

- **HashiCorp Vault response wrapping** — terraform requests a one-time-use
  wrapping token, embeds the wrapping token (not the secret) in user_data,
  cloud-init unwraps to get the real secret. The wrapping token is single-use,
  so even if state leaks the unwrap has already happened or won't work.
- **Cloud-provider identity mediation** — DO droplets have a metadata-derived
  OAuth token; build a small mediator service that exchanges that token for
  the Machine Identity. No bearer secret ever in state.
- **systemd-credentials + TPM** — droplets with TPM hardware (DO offers
  this on newer types) can store secrets in TPM-encrypted form that disk
  access alone cannot decrypt.

These are 1+ week engineering investments and should be planned when this
infrastructure approaches scale where the Layer 2 window (minutes of v1
exposure) becomes unacceptable. Layer 2 is sufficient for the current
deployment scale.

---

## Compliance mapping

| Control | Addressed by |
|---|---|
| NIST CSF 2.0 PR.DS-1 (data-at-rest protection) | Layer 2: bootstrap secret invalidated within minutes; remote state backend with SSE-C encryption. |
| NIST CSF 2.0 PR.AC-4 (least privilege) | Machine Identity scoped to single project, single env, Viewer role. |
| NIST CSF 2.0 PR.IP-3 (configuration change control) | Path C: ansible playbook is the change-control surface; idempotent re-runs; cloud-init is frozen post-bootstrap. |
| CIS Controls v8 4.5 (managed config change) | Same — ansible playbook with version-controlled inputs. |
| CIS Controls v8 5.3 (credential rotation) | Layer 2: automatic rotation of bootstrap secret; manual rotation runbook documented as fallback. |
| ISO/IEC 27001:2022 A.8.24 (cryptographic protection) | DO Spaces backend with SSE-C; secrets at rest only as ciphertext outside their working scope. |
| ISO/IEC 27001:2022 A.8.32 (change management) | Ansible playbook + git-tracked compose/Caddy/scripts. |
