# ai worker hand-off — both lanes (2026-08-09)

Fresh-agent continuation for the standing **two-stream** `ai` worker: **(A) keycloak SSO / Gitea** and **(B) allm / WeOwn.Chat**. Supersedes [`HANDOFF-2026-08-05-ai-both-lanes.md`](HANDOFF-2026-08-05-ai-both-lanes.md) — read this one first; the 08-05 doc stays as history and is still correct on the billing/payments detail.

Everything here is what git alone cannot tell you. Completed work is a one-line pointer; only incomplete/ambiguous items get detail. **Issues are DISABLED on this repo — the durable record is the WeOwn vault board** (`Projects/Keycloak-Gitea Rebuild - Open Items Board - 2026-07-18.md`), and the full narrative hand-off lives in the WeOwn vault at `Projects/ai Repo - Thread Hand-offs.md` (engagement custody: WeOwn content does not go in the Perpetuator vault).

---

## 0. State at hand-off

- `main` @ `27a4ba4`. **0 open PRs.** Working tree clean except the untracked items in §A2.
- Merged since the 08-05 doc: **#162** (canonical sso render + tombstone), **#164** (dashboard says "WeOwnChat"), **#165** (Astro landing/purchase page + `weownchat-design` skill).
- Two contributor branches on origin, unmerged: `feature/dilonne-add-supabase-helm` (`1fbeccb`), `feature/dilonne-matomo-dual-host` (`077fa8d`).

## 1. Environment facts a fresh agent cannot infer

- **Repo is PUBLIC on github.com** — no real secrets/private IPs/personal emails, ever. Commits author as Nik/ncimino only, **no AI co-author trailer**. `main` requires a PR.
- **`WEOWN_BOT_PAT` is dead**, so `auto-pr-to-main.yml` fails at checkout on every push — **every PR is opened and merged by hand.** That is how #164/#165 landed.
- Contributor PRs come from forks with `maintainerCanModify: true` — you can push CI fixes directly to the contributor's branch (`gh pr checkout <n>` → commit → push), which is how #165's two lint failures were cleared.
- **Auto-merge is disabled repo-wide** (`gh pr merge --auto` errors). Merge only when checks are already green.
- The auto-mode classifier blocks the agent from deploying to live boxes and from admin merges. Hand those over; don't loop on them.

---

## A. KEYCLOAK / SSO lane

### A1. ⛔ The landmine (defused — keep it that way)

`keycloak-docker/sites/sso.weown.dev/` is the **wrong** render for the live sso droplet: it declares volumes `sso_*` while the box runs `sso_keycloak_*`. **Deploying it brings Keycloak up on fresh empty volumes — every realm, client and user silently gone behind green healthchecks.** The canonical render is `keycloak-docker/sites/sso/` (`app_dir=/opt/sso_keycloak`).

Verified intact at hand-off: `RETIRED-DO-NOT-DEPLOY.md` in the retired render's root + a hard `exit 1` at the top of its `scripts/deploy.sh`. Keycloak/gitea renders have no `.copier-answers.yml` — **patch in place, never re-render.**

### A2. Untracked operator tooling — do not discard

Seven working helper scripts sit untracked in `keycloak-docker/sites/sso/scripts/`: `check-weown-user.sh`, `kc-lock-email-edit.sh`, `kc-set-frontend-url.sh`, `list-weown-users.sh`, `rename-weown-user.sh`, `send-setpassword-email.sh`, `set-weown-user-email.sh`. They predate this session and have never been committed. Decide deliberately — commit them or move them out of the tree — but do not clean them away.

### A3. Open (Nik-gated)

1. **Deploy the `sites/sso` app layer, then select the `weown` login theme.** PR #159 merged and the theme is in the canonical render, but it is **not deployed and not selected** — it is inert until the realm points at it. Realm `weown-chat` → Realm settings → Themes → Login theme → `weown`.
2. **Gitea logout "Invalid redirect uri"** — prepared, unconfirmed: `post.logout.redirect.uris=https://git.weown.tools/*` on the `gitea` client in realm `weown`.
3. Mint the replacement `WEOWN_BOT_PAT` (contents:write + pull-requests:write) → repo Settings → Secrets → Actions.
4. Decommission the old sso droplet + the five powered-off droplets; host hardening runs.

### A4. Gotchas that will burn a live window

- Minimus Keycloak image has **no `bash`** (use `sh`); kcadm lives at `/opt/keycloak/bin/`; every `docker compose exec -T` needs `</dev/null`; `execute-actions-email` needs `-b '["UPDATE_PASSWORD"]'` (the `-s actions=[…]` form 404s).
- **DigitalOcean blocks outbound SMTP on 25/465/587** → SendGrid on **port 2525**. It presents as a timeout with zero firewall evidence.
- Gitea derives the username from the **email local-part at first login** and does not follow a later Keycloak rename. Fix it in Gitea admin — never by changing the email, which is the SSO link key.

---

## B. ALLM / WeOwn.Chat lane

### B1. Instance state

- **chattest** — live and verified (SSO + document library).
- **demoacme** — **down.** Both `demoacme.weown.dev` and the droplet's own IP return `000`. The earlier hand-off recorded "reserved IP dead, own IP works"; that is no longer true, so treat this as a droplet/provisioning failure to diagnose, not just a DNS re-point. The reserved IP remains dead.
- **test3** — not started.

### B2. Contributor branches awaiting action

- `feature/dilonne-matomo-dual-host` — **merge-ready.** A 27-line values override that pins the dual-host ingress so a helm upgrade cannot take `matomo.weown.tools` offline. Clean; no secrets.
- `feature/dilonne-add-supabase-helm` — **needs changes.** Secret hygiene passes (no demo JWTs, no default passwords, terraform `.gitignore` correct) and the templating is sound, but the repo's own hardening checklist is unmet: **no NetworkPolicy** (Postgres reachable cluster-wide, including a bare un-prefixed `db` Service, on a multi-tenant substrate), **no container securityContext** on any of the six stateless services, a floating `caddy: "2"` tag, an unpinned Infisical operator chart, and no probes at all on `meta-deployment`. Also worth resolving in the same pass: the bootstrap Infisical machine-identity credential lands in **local plaintext terraform state** (remote backend deferred), the helm `timeout=600` can be exceeded by the hardening hook's per-table polling, and the hardening job's `2>/dev/null` turns an auth failure into a green "table absent" run.

### B3. Open work

1. **A544 — put the demo chatbot on ocpa.group and rebrand the samples.** Plan (with the mandated pre-flight) is in the WeOwn vault at `Planning/2026W32/Plan - A544 ocpa.group Demo Chatbot - 2026-08-08.md`. **Phase 0 is a hard gate: a verified backup of chat.weown.dev — the `Remote backup verified:` marker plus an actual restore rehearsal — before any content edit.** That box is the one from the 2026-07-31 storage-mount incident and still has no backup cron, so the debt is now on this task's critical path. The target site is not ours to edit; we hand over the embed snippet.
2. **Backup proof is still owed** per box (one verified run + a restore rehearsal). `gitea-git` needs `awscli` installed first — that droplet predates the template package.
3. **ALLM API-key ownership on dev.weown.tools** — create/confirm a support-account admin, mint a fresh Developer API key as that user, and stop pinning a personal user id. The standard: the ALLM admin is **WeOwn support, never a personal user**.
4. Provisioner Infisical identity for automatic machine-identity creation, plus a host for the provisioning worker (approved, not built).

---

## C. Settled — do not reopen

- `sites/sso` is canonical; `sites/sso.weown.dev` is retired (A1).
- Billing: single product, two-tier split **on profit**, Connect destination transfers; splits **return** failures rather than raising inside a transaction.
- The ALLM admin/API-key owner is the WeOwn support account, never a personal user.
- Reserved IPs are the regional problem, not the droplets; "drop per-instance reserved IPs" is still Nik's pending call.

## D. Human-gated queue (nothing here is agent-runnable)

1. Deploy `sites/sso` + select the `weown` login theme.
2. Merge `feature/dilonne-matomo-dual-host`; send Dilonne the supabase review feedback.
3. A544 Phase 0 (backup + restore rehearsal) on chat.weown.dev, then the rebrand.
4. Mint `WEOWN_BOT_PAT`.
5. Decide the repo split (proposal + six open decisions in the WeOwn vault, `Planning/2026W32/Proposal - ai Repo Split - 2026-08-08.md`).
6. Diagnose demoacme; decide on reserved IPs; `test3`.
