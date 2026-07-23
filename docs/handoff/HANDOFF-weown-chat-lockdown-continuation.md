# HANDOFF — WeOwn Chat (ALLM product) · lockdown continuation

> **Thread type: `ai-allm` worker** — the WeOwn Chat $1k/mo product. **Scoped APART from the
> keycloak/gitea stream in this same repo** (Rule 25 — see "Cannot infer" below).
> Author: ncimino (via Claude Code) · Date: **2026-07-22** · `main` at merge of PR #121.
> Public repo: contains **no** secrets, real IPs, or customer identities.

## Live state (verified this session, not assumed)

| Fact | Value |
|---|---|
| Product instance | **`weown-chat-sales`** (`INT-P09_WeOwnChat-Sales`) — WeOwn's own **production** sales site |
| URL | `https://chat.weown.dev` — **LIVE** (`/api/ping` → 200; dashboard up, `/app` auth-gated) |
| Registry | `weown-fleet:tenants.yaml` → `status: active`, ring `canary`, 8GB droplet + 50GB encrypted volume |
| Secrets | ONE **`WeOwn-Chat`** initiative project (`d82fdf29-…`), **folder per instance** (`/sites/weown-chat-sales`), droplet MI **path-scoped** to its folder; `OPENROUTER_PROVISIONING_KEY` at project root (operators read it, droplet MIs cannot) |
| Domain plan | `chat.weown.dev` now → swaps to `weown.chat` once Jason acquires it |

## Do-not-reopen (settled)

| Decision | Rationale |
|---|---|
| Customer gets ALLM **`manager`**; WeOwn holds **`admin`** | managed service; customer's only surface is the dashboard at `/app` |
| **End-customer document intake = portal redirect**, never through the bot | Tyler's security-collapse decision; it's what makes v1 shippable (PRD §4) |
| Upload endpoint is for the **practice owner's own grounding docs** | PRD §1/§4 — not an intake channel |
| One secure product, **no tier menu** | Tyler 2026-07-14: "just build the security… don't give people an option" |
| GPG (not `age`) for backup encryption | auditor familiarity; `gnupg` already in cloud-init |
| Fleet: registry + **ephemeral render**, state-per-tenant; **no rendered site dirs in git** | `docs/FLEET_OPERATIONS_DESIGN.md` §6 |
| anythingllm uses the **A405 folder model** (`/infra/shared` + `/infra/sites/$SITE`) | kills stale deploy-specific TF_VARs |

**Completed (pointers — do not redo):** dashboard + Simple-SSO + two-workspace bootstrap (PR #96) · GPG-encrypted backups + ZDR posture (#91) · CIS Phase-A hardening + encrypted data volume (#92) · fleet ops + custody-migration design (#93–#95) · itofu S3-creds fix, closes H1 (#100) · A405 folder-model migration (#102) · `infisical_secret_path` plumbing (#110) + first-deploy bug flush (#111–#113, fleet #5/#6) · fleet pre-flight checks (fleet #8) · **upload lockdown (#121, this session)**.

---

## Open work — in priority order

### 1. Embed domain allowlist — **security hole, do this first**

The public embed is created with an **empty** `allowlist_domains`, so the customer's bot is callable
from *any* website (burns their capped LLM budget, and it's their brand on someone else's page).
"domain-allowlisted" currently exists only as a *comment*.

- Fix in `weown-fleet/scripts/provision-instance.sh` (embed-creation step) — set the allowlist from
  the tenant's `domain` plus a new optional `embed_allowlist_domains` list in `tenants.yaml`.
- Also surface/manage it in the dashboard so a customer adding a second site isn't blocked.
- Verify: an embed call with an `Origin` outside the list must be refused.

### 2. Portal-redirect + disclaimer prompts — **PRD-mandated, currently absent**

Workspaces are created **bare** — zero prompt/portal/disclaimer strings in
`anythingllm-docker/template/scripts/bootstrap-product.sh.jinja`. Tyler's non-negotiables (PRD §3/§4,
demo action **A469**) are encoded nowhere in production:

- "How do I upload my 1099?" → **"please log into your customer portal"** + link (never accept files).
- AI disclaimer; "please don't share private information"; intake-form disclaimer + owner notification.
- Fix: set the workspace system prompt (and `chat_mode`) via the ALLM API at bootstrap, for
  `ws-public` especially. Make the portal URL a per-tenant field.

### 3. Backup verification + restore drill *(needs Spaces access — Nik)*

Cron + GPG client-side encryption are wired, but **no one has verified a real encrypted object
exists in Spaces or that it restores**. Do a real restore-verify on the live box, then schedule a
sampled drill (`FLEET_OPERATIONS_DESIGN.md` §8.5).

### 4. Rotate the MI off the v1 bootstrap secret *(blocked on Nik — see step 1 below)*

The live box still runs on the **v1** Machine-Identity secret, which briefly existed in tofu state /
droplet metadata. Layer-2 rotation (`rotate-bootstrap-secret.sh`) mints v2 + revokes v1, but it
**fails unless the MI has "manage own client secrets"**. Failure marker on-box:
`/opt/<project>/.rotation-failed` and `ROTATION FAILED` in `/var/log/<project>-rotation.log`.
After the grant: re-run rotation and confirm the log ends `===== Rotation complete =====`.

### 5. Sell-surface embeds

Jason's "WeOwn.Chat OPERATIONAL" gate names: `www.F1visa.Net`, `community.F1visa.Net`,
`BurnedOut.xyz`, `www.WeOwn.Chat`. Decide one shared embed vs per-surface embeds (per-surface gives
independent allowlists + analytics), then roll out. Depends on #1.

### 6. Minor: `provision-instance.sh` false health warning

It validates `"$BASE/app/healthz"`, which returns **401 by design** (only root `/healthz` is public),
so a healthy deploy reports a scary warning. Point it at `/healthz` or add a public
`/app/healthz` route.

---

## ⚠️ What a fresh AI CANNOT infer

- **Rule 25 / stream separation.** This repo also hosts the **keycloak/gitea** stream. The ai working
  tree carries *their* uncommitted work: `docs/handoff/HANDOFF-keycloak-gitea-deployment.md` (modified),
  `docs/handoff/HANDOFF-keycloak-gitea-integration.md`, `keycloak-docker/sites/sso/`, `.swp`.
  **Never stage, revert, or "clean" these.** Always `git add` explicit paths and check
  `git diff --cached --name-only` before committing. Branch switches will abort because of them —
  that is expected; do not force it.
- **Infisical landmines (verified live):** `infisical secrets get` **ignores `--projectId`/`--path`
  under user-login auth** (only MI auth honours them) — read via `infisical export` instead.
  UI-created secrets can land **personal-scoped** (invisible to MIs and to `export`). MI project roles
  need **both** *Describe Secret* AND *Read Value*. DO custom tokens need separate `*_action` scopes
  (volume attach = `block_storage_action`).
- **AnythingLLM forces one manual step per instance:** the first admin + Developer API key must be
  created in the UI ([Mintplex #1869](https://github.com/Mintplex-Labs/anything-llm/issues/1869)).
  Everything after that is API-automatable. Multi-user mode has **no email password reset** —
  recovery codes only; operator resets otherwise.
- **The vault's `thread_handoff.md` "🤖 ALLM PRODUCTION CHATBOT" section is STALE** (2026-07-18,
  `int-poc-weownllm` framing, "Infisical project decision"). Superseded by this doc + the
  `weown-chat-initiative-secret-model` memory. Don't act on it.
- **Upload policy knobs** (new): `UPLOAD_ALLOWED_EXT` (default `pdf,md,markdown,txt,csv`) and
  `UPLOAD_MAX_BYTES` (default 25 MB), injected like any other dashboard env.
- **Three regressions came from the 12-PR consolidation (`e8496d1`) that was integrated but never
  deployed** — itofu S3 creds, ssh-key var, folder model. Static checks passed on all three; only a
  live `tofu plan` caught them. **Assume template code is unproven until a real deploy exercises it.**
- **Repo flow:** `main` requires a PR (no bypass); land via conformant branch → `gh workflow run
  auto-pr-to-main.yml --ref <branch>` (a bare push does *not* open the PR) → merge when green.
  `create-pr` showing "fail" is a benign race, not a blocker. Auto-merge is disabled repo-wide.
  Commits are attributed to **ncimino only** (no AI co-author trailers).

---

## 👤 Nik-gated (do these to unblock)

1. **Infisical → `WeOwn-Chat` project → the `weown-chat-sales` droplet Machine Identity → grant
   "manage own client secrets"** → unblocks open-work #4 (rotate off the v1 bootstrap secret).
2. **Stripe keys from Tyler** → unblocks paid signup/billing.
3. **`www.WeOwn.Chat` domain from Jason** → the site moves off `chat.weown.dev`.
4. **Decide embed allowlist domains** (which sell-surfaces are authorised) → unblocks #1 and #5.
5. **Backup verification** — either run the verify/restore yourself or grant Spaces access → #3.

## Kickoff block (paste to a fresh thread)

```
Read and do: docs/handoff/HANDOFF-weown-chat-lockdown-continuation.md

Thread type: ai-allm worker (WeOwn Chat $1k/mo product), scoped APART from the
keycloak/gitea stream in the same repo. Read "What a fresh AI CANNOT infer" FIRST
(Rule 25: never touch the keycloak-stream or uncommitted handoff files in the tree).

Start with open-work #1 (embed domain allowlist — a live security hole: the public
embed currently has an EMPTY allowlist and is callable from any site), then #2
(portal-redirect + disclaimer prompts, PRD-mandated and currently absent).
Surface the Nik-gated items; don't wait on them.

Verify claims against live state before building — chat.weown.dev is production.
```
