# ai worker hand-off — both lanes (2026-08-05)

Fresh-agent continuation for the standing **two-stream** `ai` worker: **(A) keycloak SSO / Gitea** and **(B) allm / WeOwn.Chat**. Written for the fleet migration. Reasoning transcript is exported at `notes-perpetuator/…/Threads/2026-08-05-ai-5811f513.md`; the record-half of this hand-off is on **PR #143**.

Everything here is what git alone cannot tell you. Completed work is a one-line pointer; only incomplete/ambiguous items get detail.

---

## 0. Environment facts a fresh agent cannot infer

- **Repo `~/projects/ai` is PUBLIC on github.com** — no real secrets/IPs/emails ever. Commits authored by Nik/ncimino only, **no AI co-author trailer**. `main` requires a PR (ruleset); land via a conformant branch (`type/dev-desc`).
- **`~/projects/weown-fleet`** (git remote `WeOwnDev/weown-fleet`) holds the provisioning pipeline. Its commits author as **`Sooth <lagged.chicle.9h@icloud.com>`** — that is Nik's per-repo identity, NOT a mistake. Standing branch: `feature/nik-provision-from-billing`.
- **Commit signing** = Secretive (Secure Enclave). It intermittently returns `agent refused operation` / `communication with agent failed` on FRESH connections; existing SSH masters keep working. Every agent commit needs Nik's key present.
- **SSH to fleet boxes** rides `~/.ssh/sockets/%C` masters (ControlPersist 4h). Ansible was taught to share them (see §A/§B pipeline fixes) — otherwise every deploy dies `agent refused operation`.
- **The auto-mode classifier blocks the agent from**: `gh pr merge --admin`, editing repo rulesets, deploying files onto a live box by hand, and reserved-IP/fund-moving `doctl`/Stripe calls. These are genuinely human-only from an agent seat — do not loop on them, hand them over.

---

## A. KEYCLOAK / SSO lane

### A1. Live state (verified this session)

- **sso droplet: `129.212.240.145`** (ssh alias `sso-keycloak`), domain **sso.weown.id**, realm **`weown-chat`**, Keycloak **26.7.0**.
- It runs the render **`keycloak-docker/sites/sso/`** — project name **`sso-keycloak`**, volumes **`sso_keycloak_*`**, `app_dir=/opt/sso_keycloak`. Infisical project **`117b72e5-c084-44f6-9393-f5252b5ae0a8`** (KeycloakSSO), env prod.
- Realm SMTP **works** — `kc-provision-tenant.sh` sent a real UPDATE_PASSWORD invite this session (chattest customer). So the SMTP-sender path is live, not gated.
- Keycloak clients in the realm: `billing` (OIDC, billing dashboard login), `billing-admin` (service account, flips `subscription_active`), and per-tenant `chat-<slug>` clients created by `kc-provision-tenant.sh`.

### A2. ⚠️ THE LANDMINE (half-fixed, on a branch — finish this first)

The **committed** render `keycloak-docker/sites/sso.weown.dev/` is the WRONG render for the live box: it names volumes `sso_*` (not `sso_keycloak_*`). **Deploying it starts Keycloak on fresh empty volumes → every realm/client/user silently gone behind green healthchecks** (the chat.weown.dev 2026-07-31 class). It was one bootstrap-marker path check away from firing today while shipping the login theme.

**Fix in progress on branch `fix/nik-sso-canonical-render`:**

- `keycloak-docker/sites/sso/` committed as the **canonical** render, with PR #159's `weown` login theme grafted in (theme files + ansible upload task + read-only compose mount at the box's real `/opt/sso_keycloak/theme/weown` path). Playbook syntax-checked, compose YAML-parsed.
- `sites/sso.weown.dev/` **tombstoned**: `RETIRED-DO-NOT-DEPLOY.md` + hard `exit 1` at the top of its `scripts/deploy.sh`.
- `CLAUDE.md` gained the durable rule (render `app_dir` + volume-prefix = identity; verify vs box before deploy; tombstone stale renders).

**INCOMPLETE:** the commit **failed on pre-commit hooks** (yamllint trailing-space in `sites/sso/ansible/inventories/prod.yml`, terraform_fmt on `variables.tf`, markdownlint) — the hooks AUTO-FIXED the files but the commit did not complete. **Next step: `git add -u` the hook-modified files + re-commit** (message already drafted; secrets stay out — `terraform.tfvars` and `.terraform/` are gitignored, only `.example` ships). Then open/refresh the PR.

### A3. PR #159 (branded login theme) — MERGED, NOT YET LIVE

Merged to `main`. The theme is now in the canonical `sites/sso` render but **not deployed to the box and not selected on the realm**. To finish:

1. Deploy `sites/sso` app layer: `cd ~/projects/ai/keycloak-docker/sites/sso && INFISICAL_PROJECT_ID=117b72e5-c084-44f6-9393-f5252b5ae0a8 PYENV_VERSION=3.12.12 ./scripts/deploy.sh root@129.212.240.145` (Nik-run — classifier blocks the agent from deploying to the identity box).
2. Then **select the theme**: Realm `weown-chat` → Realm settings → Themes → Login theme → `weown` (doable via KC admin API with the service-account creds already at the project root — same path `kc-provision-tenant.sh` uses). The theme is inert until selected.

### A4. Template consolidation (DONE)

The ansible/Secretive SSH-master fix (ships `ansible.cfg.jinja` + master-open in `deploy.sh.jinja`) was applied to **all 12 `*-docker` templates** and merged (ai PR #161). keycloak-docker included.

---

## B. ALLM / WeOwn.Chat lane

### B1. Live state

- **Payments P0 is DONE and proven** — billing service live at **billing.weown.dev** (droplet `129.212.240.253`, Infisical project **`bab48ad2-4e8b-41bd-be3b-b634d827113a`** WeOwnBilling). 2-tier affiliate splits compute on PROFIT and transfer via Stripe Connect (verified end-to-end; a double-pay bug from a `@transaction.atomic` rollback was fixed — splits RETURN failures, never raise; `reverse_orphan_transfers` reconciles). ai PR #161 merged.
- **Instances** (WeOwn-Chat Infisical project **`d82fdf29-9fea-4956-89b0-e74a1c6bcd4e`**, folder per `/sites/<slug>`):
  - **chattest** — LIVE. droplet `165.245.130.250` (`/opt/chattest`). SSO fixed this session (its OIDC was never seeded because it predated the wiring — ran `kc-provision-tenant.sh chattest --user nik+chattest@weown.net`, bounced the dashboard; verified `/app/oidc/login` → 302 to sso.weown.id). PR #141's document library deployed + verified here.
  - **demoacme** — droplet `134.199.206.51` (own IP; **reserved IP `129.212.241.214` is DEAD**). Provisioning to the own IP was **in flight at hand-off** (background run) — verify `demoacme.weown.dev` serves and billing Instance flipped to active.
  - **test3** — NOT STARTED. No droplet, no MI, no folder. Needs the full pipeline incl. the manual MI gate.

### B2. ⚠️ DO reserved-IP flakiness (systemic, worked-around not solved)

Newly-created droplets in **atl1** get a reserved IP that routes slowly or **never**, while the droplet's OWN public IP works immediately. Confirmed across 3+ droplets/rebuilds; billing (same region, older) is stable. `render-deploy.sh` now: waits 15 min, reassigns a stuck reserved IP once, and **falls back to the droplet's own IP** (re-pointing DNS) — set `WEOWN_DEPLOY_IP=<own ip>` to force it up front. `allm-bootstrap-admin.sh` always targets the own IP and now trusts its host key first. **Decision B1 pending Nik: drop per-instance reserved IPs entirely** (touches every tenant's terraform).

### B3. The provisioning pipeline & the WORKER (approved, NOT built)

`provision-from-billing.sh` → `provision-instance.sh` → `render-deploy.sh` + `allm-bootstrap-admin.sh` + `kc-provision-tenant.sh`. It is **operator-run, idempotent, with ONE manual gate: Machine-Identity creation** (`provision-instance-mi.sh`, org-level). There is **no continuous worker** — instances sit in billing's "being set up" until an operator runs the pipeline. The billing status page only POLLS (30s meta-refresh + a manual Refresh link); it cannot provision (billing holds no fleet creds, by security design).
**Nik approved building the worker** = a small always-on process that polls billing for pending/failed instances and runs the pipeline with retries. Blockers before it can be automatic:

  1. **Auto-MI** needs a **provisioner Infisical identity** (org-level, Nik's one-time hands) with identity-create rights, creds stored for the worker. (Amends decision A4 "MI creation stays human".)
  2. A **host** (recommend a small dedicated provisioner droplet, isolates fleet creds from billing).

### B4. ⭐ ALLM API-key ownership — context for the ContextVolley unblock

The orchestrator's blocker: on **dev.weown.tools**, `secret/weown/anythingllm` resolves to a user that no longer exists and `ALLM_USER_ID=4` is invalid. **I do NOT have direct context on dev.weown.tools's ALLM user table** — the instances I worked (chattest/demoacme) are *separate per-customer* ALLM deployments, not that central/dev one. BUT the **ownership model this project standardized on is the high-value input:** the ALLM admin + API key must belong to **WeOwn SUPPORT (`support@weown.net`)**, NOT a personal user — see `weown-fleet/scripts/allm-bootstrap-admin.sh` ("the ALLM admin is WEOWN SUPPORT, not the customer; override with `ALLM_ADMIN_USER`"). It mints the Developer API key *after* enabling multi-user, storing `ALLM_ADMIN_API_KEY` in Infisical. **Likely fix for the ContextVolley:** on dev.weown.tools, create/confirm a `support@weown.net` admin, mint a fresh Developer API key as that user, update `secret/weown/anythingllm` + the real `ALLM_USER_ID`, and stop pinning a personal userid. Nik-gated (touches a live secret + a live instance). Verified this session that ALLM's `/api/v1/workspace/<slug>` returns `{workspace:[{documents:[]}]}` (empty workspace still includes `documents:[]`).

### B5. PR #141 (ALLM doc library) — MERGED + DEPLOYED

Merged to main and deployed to chattest (verified: `/api/documents` 401 auth-gated, doc-library UI present, OIDC intact). Includes a second-pass hardening commit (`docsOf` fail-loud verified against live ALLM, atomic lock writes, mutex, body cap, no raw upstream-error echo).

---

## C. Open PRs / branches / worktrees (update semantics)

| Ref | State | Notes |
|---|---|---|
| ai `main` | — | has #161, #159, #141 merged |
| ai branch **`fix/nik-sso-canonical-render`** | commit pending (hook auto-fixes) | A2 — canonical sso render + tombstone + CLAUDE.md rule. Re-add + re-commit, then PR. |
| ai PR **#143** | the coordinating/record PR | issues are DISABLED on this repo → PR comments are the durable surface. Record-half of this hand-off lives here. |
| weown-fleet **`feature/nik-provision-from-billing`** | pushed | provisioning fixes: own-IP fallback, host-key trust ×2, email URL-encode, customer-to-group, `rebuild-instance.sh`, MI argv fix. |
| git worktrees `/private/tmp/pr141`, `/private/tmp/pr159` | throwaway | PR review checkouts; safe to `git worktree remove`. |

## D. Settled decisions — DO NOT REOPEN

- Billing: single product, 2-tier split **on profit**, break-glass admin, own droplet, Connect destination-transfers. Splits **return** failures (never raise inside atomic).
- `sites/sso` canonical; `sites/sso.weown.dev` retired (A2).
- Reserved IPs are the atl1 problem, not the droplets (B2); own-IP fallback is the interim; "drop reserved IPs" is the pending Nik decision.
- Worker approved (B3); MI automation via a provisioner identity (amends "MI stays human").
- ALLM admin/API-key owner = `support@weown.net`, never a personal user (B4).

## E. Human-pending (Nik-gated)

1. Deploy `sites/sso` + select `weown` login theme (A3).
2. Re-commit branch `fix/nik-sso-canonical-render` after hook auto-fixes, open PR (A2).
3. Create the provisioner Infisical identity for auto-MI (B3).
4. Decide: drop per-instance reserved IPs (B2).
5. test3: create MI + provision (B1), or wait for the worker.
6. ContextVolley: fix dev.weown.tools ALLM key ownership (B4).
