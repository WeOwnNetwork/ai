# HANDOFF — Open-branch consolidation + M2 argv-secret hardening (continuation)

> Status: **handoff** · Author: ncimino (via Claude Code) · Date: 2026-07-14
> `main` HEAD at handoff: **`77e2bd2`** (PR #86 merged) · Working tree: clean (only untracked `.swp`)
> Scope: a fresh agent can continue from this doc alone. Public repo — this file
> contains **no** real IPs, project UUIDs, or secrets (all such values live only in
> gitignored `terraform.tfvars` / OpenBao / the Perpetuator vault).

---

## 1. Open items / loose ends (act on these)

Split into **agent-buildable** (an AI can do it) and **human-gated** (secrets / live infra / approvals / public actions).

### 1.1 Human-gated

| # | Item | Detail | Where |
|---|---|---|---|
| H1 | **M2 live deploy test** (pre-promotion gate) | The fleet-wide argv→env fix (PR #85) is statically verified only — `copier` isn't installed in the agent env. Render ONE template with `copier` and run the ansible/tofu path against a throwaway droplet; confirm `infisical login`/`tofu init` still authenticate with the creds now in env (not argv). Lowest-risk candidate: any `*-docker` template → a scratch site. | all `*-docker` templates |
| H2 | **Close stale PRs #82 + #83** | Both are OPEN but their content is already in `main` via PR #84 (verified: `deepseek/deepseek-v4-flash` default + `core_plugin_bundle` task present on `main`). Public action, so left for a human: close each with a comment "superseded by #84". Their branches are intentionally kept (see D3). | GitHub PRs [#82](https://github.com/WeOwnNetwork/ai/pull/82), [#83](https://github.com/WeOwnNetwork/ai/pull/83) |
| H3 | **Keycloak D437 admin-lockdown not implemented** | `keycloak-docker/sites/sso.weown.dev/docker/Caddyfile:18` still has a dead `admin.sso.weown.id { … }` vhost that Keycloak rejects under `KC_HOSTNAME_STRICT=true` — it *reads* like an admin lockdown but enforces nothing. Either (a) implement the intended `/admin/*` IP path-ACL on the main vhost (allow-list = the ProtonVPN egress + break-glass IPs, which live ONLY in gitignored tfvars / vault — never commit them), or (b) remove the dead `admin.` vhost (admin is served at `sso.weown.id/admin`). Needs the real IPs → human. | `keycloak-docker/sites/sso.weown.dev/docker/Caddyfile` |
| H4 | **39 Dependabot vulns on default branch** | 17 high / 18 moderate / 4 low — pre-existing dependency CVEs, unrelated to this session's work. Needs a dedicated remediation pass. | `github.com/WeOwnNetwork/ai/security/dependabot` |
| H5 | **Peter (@MOT) offboarded W28 — re-own his merged work** | The keycloak-SSO (PRJ-003), owncloud-oCIS, and smoke-test code is merged, but ownership/custody needs reassigning. Code is fine; this is a people-ops loose end. | vault: `Projects/MOT Offboarding Runbook - 2026-07-06.md` |

### 1.2 Agent-buildable

| # | Item | Detail | Where |
|---|---|---|---|
| A1 | **Finish `supabase-docker` past v0.1 skeleton** | Only `copier.yaml` + `README` + `docs/` + `docker/{compose.prod,Caddyfile}` exist. **Pending (per its README Migration-Status table):** `template/terraform/` (backend.tf.jinja, main.tf, cloud-init.yaml.jinja), Layer-2 `rotate-bootstrap-secret.sh`, `template/ansible/roles/{common,docker,supabase}` task bodies, `scripts/{deploy,backup,restore}`, `.env.example`, `.gitignore`, and a service-deployment ADR. Clone the pattern from `keycloak-docker/`. **BLOCKED on `@CTO` review** before any prod data move (vault: WO-Disc-922 / A463 CTO cut-over review pending). Also two functional gaps from code review: add a `postgres-meta` service for Studio, and GoTrue SMTP env (or `GOTRUE_MAILER_AUTOCONFIRM=true` for dev). | `supabase-docker/` |
| A2 | **Naming reconciliation: INT-P07 vs INT-P08** | The `do-weown-tools` branch labeled the `dev-weown-anythingllm` site **INT-P07**, but the vault consistently uses **INT-P08** for dev.weown.tools. Confirm the correct code and align CHANGELOG/README strings. | `anythingllm-docker/sites/dev-weown-anythingllm/` |
| A3 | **M2 self-check to prevent regressions** | Consider a pre-commit / CI grep guard that fails on `--client-secret=` or `-backend-config="secret_key=` in tracked code, so the argv anti-pattern can't creep back. | `.pre-commit-config.yaml` / `.github/workflows/validation.yml` |

---

## 2. Settled decisions — do NOT reopen

| # | Decision | One-line rationale |
|---|---|---|
| D1 | 29 open branches → **10 integrated, 19 skip+deleted** (PR #84) | Full per-branch review; 19 were already in `e8496d1` / retired / obsolete. |
| D2 | Skip `ldc/add-zeroToHundred-application` + `security-hardening-ssh` | zeroToHundred is app code (not infra); SSH-hardening capability is already covered by `manage-droplets.sh rotate-authorized-keys` + `OPS_AUTHORIZED_KEYS` + cloud-init sshd hardening — verified. |
| D3 | **Keep** the 10 integrated source branches on the remote | Owner's call. They show as perpetually "unmerged" because content landed as fresh commits, not by merging the branches — do NOT try to re-merge them. |
| D4 | Land everything as **one CI-conformant branch → one auto-merged PR** (0 approvals) | `main` ruleset requires a PR (no bypass); this satisfies "autonomous, no review ceremony". |
| D5 | Commits attributed to **ncimino only** — no Claude / co-author trailers | Owner directive. |
| D6 | M2 argv → env-var auth pattern (Infisical `INFISICAL_UNIVERSAL_AUTH_*`; tofu `AWS_*` env, keep `sse_customer_key` on `-backend-config`) | Matches openclaw's already-correct entrypoint; the CLI/S3-backend read these natively. |
| D7 | Preserve latest template versions when integrating stale branches | e.g. kept `main`'s `#78` Minimus fail-loud login rather than a stale branch's revert. |

---

## 3. Completed work (pointers — do not redo)

- **PR #84** (`565ae47`) — 10 branches integrated to `main`, 19 stale + 2 merged-roman branches deleted. Per-branch review edits + public-repo scrubs (real IPs→RFC5737, project UUIDs→placeholders, offboarded emails→`alerts@example.com`), Trivy firewall findings suppressed with canonical `#trivy:ignore`.
- **PR #85** (`9abaf71`) — M2 fleet-wide: 75 files, argv secrets → env-var auth. 57 files now carry `INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET`. 0 remaining argv secrets in tracked code.
- **PR #86** (`87e4ba6`) — restored `+x` on 3 scripts the M2 fix's `perl>tmp && mv` had flipped to 644.
- Reviews + CHANGELOG entries are in-tree (`CHANGELOG.md` `[Unreleased]`). Auto-memory `commit-attribution-ncimino-only` saved.

---

## 4. What a fresh AI cannot infer (repo mechanics + gotchas)

- **`main` ruleset**: PR required (0 approvals, **`bypass_actors: []`** — nobody, incl. admins, can push direct); required status check = **`Validate Branch Name`**; Copilot review + `code_quality` + Trivy run. Land work as: conformant branch → `gh pr create` → wait green → `gh pr merge --merge --delete-branch`.
- **Branch-name regex (CI-enforced)**: `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`. The first description segment needs **≥3 chars** — e.g. `feature/nik-m2-...` FAILS (`m2` is 2). Use `feature/nik-<3+char-word>-...`.
- **Trivy** flags every new DO firewall as CRITICAL `AVD-DIG-0001` (ingress) / `AVD-DIG-0003` (egress). Suppress with an inline `#trivy:ignore:AVD-DIG-000X  # <justification>` above the rule — the canonical pattern used by every existing site/template. Not doing so blocks the merge.
- **Signing**: `commit.gpgsign=true` (ssh). Local commits auto-sign; `git log` shows `sig=U` (valid, unknown validity) for my commits and `sig=E` for GitHub-made merge commits — both are fine, not errors.
- **`copier` is NOT installed** in the agent environment → any "render a template and run it" step is a human gate.
- **`reg.mini.dev` docker login** username is the literal `minimus` (`-u token` → 401). `MINIMUS_TOKEN` from Infisical `/Shared`.
- **Public-repo redaction is absolute**: real IPs → RFC5737 (`203.0.113.x`), Infisical project IDs → `""` (anythingllm/keycloak convention) or zero-UUID `00000000-…` (openclaw convention), emails → `alerts@example.com`. Real values live only in gitignored `terraform.tfvars` + OpenBao + vault.
- **Ephemeral aids** (not committed): the two transform scripts `fix-login-argv.pl` + `fix-tofu-argv.pl` used for M2 live in the session scratchpad; re-derive from the D6 pattern if needed for A3.

---

## 5. Kickoff block (paste to a fresh agent)

```
Read and do: docs/handoff/HANDOFF-branch-consolidation-and-m2.md

Start with §1.2 A1 (finish supabase-docker past v0.1 — but confirm the @CTO
review gate first) OR §1.1 H1 (M2 live deploy test) depending on priority.
Follow §4 for the ruleset/branch-name/Trivy mechanics: work on a CI-conformant
branch, land via one auto-merged PR, commits attributed to ncimino only.
Do NOT re-merge the 10 kept branches (§2 D3). Do NOT commit real IPs/UUIDs (§4).
```
