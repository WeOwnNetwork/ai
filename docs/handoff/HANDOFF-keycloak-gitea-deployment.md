# HANDOFF — Keycloak + Gitea on the WeOwn `ai` stack (local-first → Infisical/DO)

---

## 🔄 PIVOT 2026-07-17 (afternoon) — REBUILD approved, re-own path superseded

Jason (@GTM, Signal): **complete Keycloak rebuild approved** — nothing was ever
connected to MOT's instance, and both Jason and Nik are locked out (Caddy admin
ACL = Jason's ProtonVPN dedicated-server IP + one break-glass IP only; SSH has
no standing ingress by MOT's design). Note the OIDC endpoint itself still
answers 200 — the box isn't dead, just sealed; rebuild is the owner's call.
**Priorities**: 1) **Gitea → `git.weown.tools` (P0)**, 2) Fathom.AI SSO,
3) Matomo → `matomo.weown.tools` (migrate off weown.app). Fresh deployment with
NSA/ISO-style ansible host hardening (DevSec pattern from anythingllm-docker).
The §"Keycloak re-own" items below are superseded except: tfstate hygiene and
the MOT backdoor sweep concerns transfer to decommissioning the old `sso`
droplet after cutover. Vault: `Journal/2026W29/Signal - Jason - 2026-07-17.md`.

## ⏰ STATUS NOTE FOR NIK — overnight run 2026-07-17 (read this first)

**TL;DR: tonight's success criterion is MET.** Gitea SSO-logs-in through Keycloak
end-to-end on localhost; the new `gitea-docker` template is built, verified, and
up as **PR #98** (`feature/nik-gitea-docker`) with **all 15 CI checks green**
(CodeQL, Trivy, lint, compliance, branch-name). Merging is yours — see item 1
below.

### ✅ Done tonight

1. **MOT recon (§3)** — *re-own Keycloak, build Gitea fresh* confirmed:
   - `sso.weown.id` is LIVE (OIDC discovery HTTP 200) on droplet `sso`; the
     committed site is genuinely ADR-006/Path-C-shaped. **No Gitea exists
     anywhere** (repo, droplets, runbook).
   - Re-own gaps found: `sites/sso.weown.dev/site.conf` has an **EMPTY
     `INFISICAL_PROJECT_ID`** (deploy/backup scripts non-functional as
     committed); terraform backend is **local with NO tfstate in the repo**
     (droplet unmanaged by IaC — `backend.tf.remote` for
     `weown-prod-state/sso/sso.tfstate` is ready but unactivated); the
     **`admin.sso.weown.id` vhost is still open** (D437/A387 never executed,
     assignee offboarded); the runbook's **MOT backdoor sweep** (extra
     admins/clients/service accounts) is still unchecked; dir is named
     `.dev` but serves `.id`.
2. **`gitea-docker/` copier template** (new, committed) — cloned from
   keycloak-docker, full stack preserved (ADR-006 injection, Path C, Layer-2
   rotation, skinny backups, monitoring). Gitea specifics: OIDC-only login,
   `gitea_ssh_port` (2222) firewall rule w/ inline Trivy suppression,
   `INSTALL_LOCK=true`, `/api/healthz` checks, **no admin vhost**. Verified:
   copier renders, `tofu validate`, YAML + `bash -n` all clean.
3. **Local end-to-end SSO PROVEN**: local KC 24 (`:8081`, realm `weown`,
   confidential client `gitea`, scopes `openid email profile offline_access`)
   - rendered gitea-local (`:3000`) → full OIDC dance → user auto-registered
   (active) → authenticated session. Stacks still running in Docker
   (`kc-local-*`, `gitea-local-*`; scratch dir has the renders + throwaway
   `.env`s — nothing secret, nothing committed).
4. **PR #98** open via `gh workflow run auto-pr-to-main.yml`.

### 🧪 Landmines found (encoded into the template already)

- Gitea env-only config needs `GITEA__security__INSTALL_LOCK=true` or every
  `gitea admin` command dies with "not installed".
- The `localhost:host-gateway` extra_hosts trick does NOT work (built-in
  `127.0.0.1 localhost` wins) — local issuer must be a host both browser and
  container resolve identically (used the Mac's LAN IP).
- Keycloak realms default `sslRequired=external` → non-localhost HTTP
  discovery gets 403 "HTTPS required" (local-only issue; prod is HTTPS).
- Keycloak 24 kcadm PUT to `default-client-scopes` 404s; leaving
  `offline_access` optional + requesting it in Gitea's `--scopes` works.

### 👤 Morning gate (needs you — in order)

1. **Merge PR #98** (already all-green): `gh pr merge 98 --merge --delete-branch`.
2. **Keycloak re-own** (before adding the prod `gitea` client): fill
   `INFISICAL_PROJECT_ID` in `sites/sso.weown.dev/site.conf`; migrate tfstate
   to the remote backend + `tofu import` the `sso` droplet/IP/firewall; run
   the MOT backdoor sweep; D437 admin-vhost lockdown (real IPs); optionally
   rename the site dir to `sso.weown.id`.
3. **Gitea prod flip (§5)**: Infisical project + Machine Identity for
   `git.weown.*` (confirm domain w/ Jason); real secrets (`POSTGRES_*`,
   `GITEA__database__*`, `GITEA__security__SECRET_KEY`/`INTERNAL_TOKEN`,
   `GITEA__oauth2__JWT_SECRET`, `MINIMUS_TOKEN`); copier render into
   `gitea-docker/sites/<domain>/`; `weown-tofu` droplet + DNS; create the
   prod `gitea` client in the `weown` (or chosen) realm on sso.weown.id and
   run the README's auth-source bootstrap.
4. Local cleanup when done testing:
   `docker compose -p kc-local down -v` + `docker compose -p gitea-local down -v`.

---

> Status: **handoff** · Author: ncimino (via Claude Code) · Date: 2026-07-15
> `main` HEAD at handoff: **`50d298c`** (PR #96 — customer dashboard) · Working tree clean (only untracked `.swp`)
> Public repo — this file carries **no** secrets, real IPs, or project UUIDs.
> Scope: a fresh agent continues from this doc alone. Companion (chatbot product,
> out of scope here): [`docs/FLEET_OPERATIONS_DESIGN.md`](../FLEET_OPERATIONS_DESIGN.md),
> [`docs/CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md).

---

## 0. The mission + the operating conditions (read first)

**Goal:** stand up **Keycloak** (SSO/IdP) and **Gitea** (self-hosted git) on the
WeOwn `ai` stack, applying the same principles as the Perpetuator internal
platform but using **Infisical** (WeOwn's secret store) instead of OpenBao —
i.e. the existing `keycloak-docker` copier + ADR-006 in-container Infisical
injection pattern. **Gitea authenticates via Keycloak (OIDC).** Both are WeOwn
*internal* infrastructure (Jason approved "Gitea + Keycloak in writing" — vault
D452, 2026-07-13), deployed to WeOwn's DO account on the same `weown-tofu` +
per-site-Infisical model as `anythingllm-docker`.

**Operating conditions Nik set (he is asleep — drive autonomously):**

1. **Drive as far as you can tonight without him**, using **local Docker
   containers** to connect Keycloak ↔ Gitea and get OIDC login working
   end-to-end on localhost.
2. **The Infisical + DigitalOcean flip is the MORNING gate** — needs Nik for
   real secrets (Infisical Machine Identity, `MINIMUS_TOKEN`) and DO. Do NOT
   attempt live DO/Infisical deploys tonight.
3. **Better: find MOT's (Peter's) existing Keycloak/Gitea instances and verify
   them** rather than rebuild — see §3. If found + healthy, the job shifts from
   "build" to "re-own + align to the template."
4. **"Check things before you get yourself stuck"** — verify each precondition
   (this doc's §2 already did the big ones) before committing to a path.
5. Keep working around blockers autonomously until Nik is back in the morning.
6. **Never read live secret files** (`gitea/.env`, `ansible/vault.yml`,
   `*/.infisical-auth.env`) — regenerate throwaway values for local.

---

## 1. Do-not-reopen decisions (settled)

| # | Decision | Rationale |
|---|---|---|
| K1 | Deploy on the **existing `ai/keycloak-docker` copier template** (not a fresh design) | Mature; one live-ish site `sites/sso.weown.dev/`; already encodes ADR-006 Infisical injection + Path C + Layer 2 |
| K2 | **Local containers first, Infisical/DO in the morning** | Nik's condition; local uses `compose.local.yaml` + a throwaway `.env` (no Infisical, public images) |
| K3 | **Gitea = new `gitea-docker` copier template, cloned from `keycloak-docker/`** | Per repo `CLAUDE.md` "clone keycloak-docker as the reference for new services". No gitea template exists in `ai` yet. |
| K4 | Config reference for Gitea = **`~/projects/mcp/infra/ansible/roles/gitea/`** (canonical internal) + **`~/projects/gitea/`** (standalone, has the Keycloak-SSO note) | Working, proven configs to lift from |
| K5 | Gitea SSO through Keycloak via **OIDC** (OpenID Connect auth source), auto-register on, registration otherwise disabled | Standard; forces all Gitea logins through Keycloak |
| K6 | Public images for LOCAL only (`quay.io/keycloak/keycloak:24.0`, `gitea/gitea`, `postgres:16`, `caddy:2`); prod uses `reg.mini.dev/*` via `MINIMUS_TOKEN` | Avoids the private-registry login locally |

## 2. Verified preconditions (already checked tonight — don't re-verify)

- ✅ **Docker** works: v29.1.3, compose v2.40.3 (containers already running).
- ✅ **copier** works at `/Users/nik/.pyenv/versions/3.14.2/bin/copier` (9.14.3).
  The `copier` shim on PATH is broken — **use the full path**.
- ✅ **`keycloak-docker` renders clean** and has full local-test support:
  `template/docker/compose.local.yaml.jinja` (plain `${VAR}` interpolation, no
  Infisical) + `Caddyfile.local` (`localhost { reverse_proxy keycloak:8080 }`).
- ⚠️ **Port conflict:** `rp-be-postgres-1` already holds host **`:5432`**. Local
  keycloak/gitea Postgres MUST remap (e.g. `55432`, `55433`). Keycloak default
  `:8080`, Gitea `:3000` — check those too before `up`.
- ⚠️ **keycloak `compose.local.yaml` has NO `command:`** — the KC image needs
  one; add `command: ["start-dev"]` via a local override (correct for local:
  no hostname/TLS strictness).
- Local env vars keycloak `compose.local` wants: `DB_NAME, DB_USER, DB_PASSWORD,
  DB_ROOT_PASSWORD, KEYCLOAK_IMAGE, KEYCLOAK_ADMIN_USERNAME,
  KEYCLOAK_ADMIN_PASSWORD, CADDY_IMAGE, DOMAIN`.

## 3. MOT (Peter, @MOT, offboarded W28) — find + verify before rebuilding

Per the ai repo's prior handoff **H5** and the vault **`Projects/MOT Offboarding
Runbook - 2026-07-06.md`**: Peter delivered **Keycloak-SSO (PRJ-003)**,
owncloud-oCIS, and smoke-test code — **merged**, but **custody/ownership needs
reassigning**. `ai/keycloak-docker/sites/sso.weown.dev/` exists and (per the
earlier M2 handoff) was migrated to Path-C serving **`sso.weown.id`**.

**Tasks (do these read-only first):**

- [ ] Read the MOT Offboarding Runbook + `sites/sso.weown.dev/` (site.conf,
      README, CHANGELOG) to establish what's actually deployed and where.
- [ ] Check whether an Infisical project + a live DO droplet already exist for
      Keycloak (don't read secrets — check existence via `sites/sso.weown.dev/`
      config pointers + `doctl compute droplet list --tag weown-ai` if authed).
- [ ] Determine if any **Gitea** was ever deployed by MOT (agent research
      pending — see note below). If none: build fresh per §4.
- [ ] **D437 open item** (from the M2 handoff): `sites/sso.weown.dev/docker/
      Caddyfile` has a dead `admin.sso.weown.id { … }` vhost Keycloak rejects
      under `KC_HOSTNAME_STRICT=true` — either implement the `/admin/*` IP
      path-ACL or remove the dead vhost. Needs real IPs → a Nik/morning item.

> *MOT-specifics research agent was still running at handoff; fold its findings
> in when available. The above is from H5 + the M2 handoff + this session's recon.*

## 4. Tonight's build plan (local, no secrets, no DO)

### 4a. Keycloak up locally

1. Render to a scratch dir (NOT committed):
   `"/Users/nik/.pyenv/versions/3.14.2/bin/copier" copy ~/projects/ai/keycloak-docker <tmp> --data project_name=kc-local --data domain=localhost --data keycloak_image=quay.io/keycloak/keycloak:24.0 --data caddy_image=caddy:2 --data postgres_version=16 --data keycloak_db_name=keycloak --data infisical_project_id="" --defaults --trust`
2. In `<tmp>/docker/`: write a throwaway `.env` (the 9 vars in §2) + a
   `docker-compose.override.yml` remapping ports (`db 55432:5432`,
   `keycloak 8081:8080`) and adding `command: ["start-dev"]` to keycloak.
3. `docker compose --env-file .env -f compose.local.yaml -f docker-compose.override.yml up -d db keycloak`
   (skip `caddy` locally — hit KC directly on `http://localhost:8081`).
4. Verify: `curl -sf http://localhost:8081/health/ready`; admin console
   `http://localhost:8081/admin` (admin / the `.env` password).

### 4b. Realm + Gitea OIDC client (automate via kcadm.sh)

Keycloak starts EMPTY (no realm import in the template). Bootstrap via
`docker exec … /opt/keycloak/bin/kcadm.sh` (lift the command sequence from
`~/projects/mcp/infra/ansible/roles/keycloak_client/tasks/main.yml`):

- Create realm `weown` (or `master` for local test).
- Create confidential client `gitea`: `publicClient=false`,
  `standardFlowEnabled=true`, redirect URI
  **`http://localhost:3000/user/oauth2/Keycloak/callback`** (the `Keycloak`
  segment MUST match the Gitea auth-source name, case-sensitive), web origins `+`.
- **Client scopes MUST include `offline_access`** (+ `openid email profile`) —
  without a refresh token Gitea sets new SSO users `prohibit_login=true`. `email`
  scope is mandatory or auto-register fails "missing fields: email".
- Grab the client secret (Credentials tab / `kcadm.sh … client-secret`).

### 4c. Gitea up locally + wire the auth source

1. **Create `ai/gitea-docker/`** by cloning the `keycloak-docker/` copier skeleton
   (copier.yaml, template/{docker,ansible,scripts,terraform}), swapping Keycloak
   specifics for Gitea's (config from `~/projects/mcp/infra/ansible/roles/gitea/
   templates/`). Gitea service: `gitea/gitea:<pin>`, its own Postgres (`gitea`
   DB), env `GITEA__database__*` (HOST=`db:5432`, NAME/USER/PASSWD),
   `GITEA__server__ROOT_URL`, `GITEA__service__DISABLE_REGISTRATION=true`,
   `GITEA__oauth2_client__ENABLE_AUTO_REGISTRATION=true`,
   `oauth2_client__USERNAME=email`, `oauth2_client__ACCOUNT_LINKING=auto`.
   `SECRET_KEY`/`INTERNAL_TOKEN`/`oauth2 JWT_SECRET` auto-generate on first run
   (not blocking locally). Also make a `compose.local.yaml` (public image, `.env`).
2. **localhost issuer gotcha (the #1 time-sink):** the Gitea *container* and the
   *browser* must resolve the **same** issuer URL. Put both stacks on one docker
   network OR give the Gitea container `extra_hosts: ["localhost:host-gateway"]`
   so `http://localhost:8081/realms/<realm>/.well-known/openid-configuration`
   resolves identically in-container and in-browser. Plan this up front.
3. Add the auth source (headless):
   `docker exec <gitea> gitea admin auth add-oauth --name Keycloak --provider openidConnect --key gitea --secret <secret> --auto-discover-url http://localhost:8081/realms/<realm>/.well-known/openid-configuration --scopes "email profile"`
4. **Verify end-to-end:** browser → `http://localhost:3000` → "Sign in with
   Keycloak" → Keycloak login → redirected back, auto-registered, logged into
   Gitea. That is tonight's success criterion.
5. Commit progressively on a branch `feature/nik-gitea-docker` (the new template
   is real, committable work; the local render/.env stay uncommitted — scratch).
   Follow §4-mechanics of the repo (below).

## 5. Morning gate (needs Nik — do NOT attempt tonight)

1. **Infisical**: create per-site projects (keycloak, gitea) + Machine Identities;
   push the real secrets (DB creds, `KEYCLOAK_ADMIN_*`, `GITEA__*` secrets,
   `MINIMUS_TOKEN`). Flip local `.env` → `infisical run` (ADR-006 entrypoint).
2. **`reg.mini.dev`** private images (needs `MINIMUS_TOKEN`).
3. **DO**: `weown-tofu` provisioning (droplet, reserved IP, firewall, DO Spaces
   state/backups), DNS. Target domains: `sso.weown.id` (live) + a `git.weown.*`
   (confirm with Nik/Jason).
4. **Verify MOT's live instances** with Nik (his DO access) and decide re-own
   vs rebuild.
5. D437 admin-lockdown (real IPs).

## 6. Repo mechanics (a fresh AI cannot infer these)

- **`main` ruleset**: PR required (0 approvals, `bypass_actors: []`); required
  check = **`Validate Branch Name`**; Copilot + CodeQL + Trivy run. **CodeQL and
  Trivy WILL block on real findings** (CodeQL caught a `js/insufficient-password-hash`
  in PR #96 this session — real gate). Land as: conformant branch → push →
  `gh workflow run auto-pr-to-main.yml --ref <branch>` (a bare push does NOT
  open the PR — the workflow only *updates* an existing one; you must dispatch
  it) → wait green → `gh pr merge --merge --delete-branch`.
- **Branch-name regex**: `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`
  — first desc segment ≥3 chars.
- **Commits attributed to `ncimino` only** — no AI/co-author trailers.
- **Trivy** flags new DO firewalls CRITICAL `AVD-DIG-0001/0003`; suppress with
  inline `#trivy:ignore:AVD-DIG-000X  # <justification>`.
- **markdownlint** pre-commit **auto-fixes and then aborts the commit** — if a
  commit "fails" on markdownlint with "files were modified", just `git add` +
  re-commit (the fix is already applied).
- **pre-commit `detect-private-key`** false-positives on the literal string
  `BEGIN … PRIVATE KEY` even in prompts/comments — reword, don't `--no-verify`.
- Public-repo redaction absolute: no real IPs (RFC5737), no project UUIDs, no
  customer names.

## 7. Kickoff block (paste to a fresh agent)

```
Read and do: docs/handoff/HANDOFF-keycloak-gitea-deployment.md

Nik is asleep — drive autonomously as far as you can WITHOUT him, per §0's
operating conditions. Tonight = LOCAL Docker only: get Keycloak + Gitea running
locally and Gitea SSO-logging-in through Keycloak end-to-end (§4). The
Infisical + DigitalOcean flip is the MORNING gate (§5) — do NOT attempt it.
First, §3: look for MOT's (Peter's) existing Keycloak/Gitea instances and verify
rather than blindly rebuild. Check every precondition before committing to a
path (§2 already did the big ones: docker✓, copier at the pyenv full-path✓,
keycloak compose.local✓, :5432 port conflict, KC needs start-dev). Build the new
gitea-docker template by cloning keycloak-docker (§4c); commit real template work
on feature/nik-gitea-docker via §6 mechanics (ncimino-only, dispatch auto-pr,
CodeQL/Trivy gate). Never read live secret files; use throwaway local values.
Keep working around blockers until Nik is back in the morning; leave a status
note at the top of this file for him.
```
