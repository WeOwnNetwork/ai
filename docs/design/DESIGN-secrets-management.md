# Secrets Management — capability

**Status:** draft · **Owner:** Nik · **Source:** *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §2–§4

The end-to-end capability for fleet secrets: a self-hosted **store** (OpenBao), a locked
**governance** model (naming + least-privilege), a **register** that says which secret belongs to
what, and a per-instance **migration recipe** off the cost-heavy parts of Infisical. No secret value
ever enters an agent context.

Builds on [DESIGN — reusable OpenBao deploy + secret-store POC](../DESIGN-openbao-reusable-deploy-and-secret-store-poc.md).

## The four parts and their requirements docs

| Part | What it is | Requirements |
| --- | --- | --- |
| **Governance** (prerequisite) | Path scheme `weown/<tier>/<scope>/<service>/<key>`, four policy templates, one AppRole per instance-service, deny-by-default | [secrets-governance](../requirements/REQUIREMENTS-secrets-governance.md) |
| **Store** | Reusable ansible role that stamps OpenBao onto any box in ≤ 15 min; idempotent, fails closed, asserts the real contract | [openbao-deploy](../requirements/REQUIREMENTS-openbao-deploy.md) |
| **Register** | One row per secret path: agency/platform/instance/service → OpenBao path; zero orphans; live before wave 1 | [secrets-register](../requirements/REQUIREMENTS-secrets-register.md) |
| **Migration** | Partial, staged, rollback-first; waves cost-first; cutover per instance via `SECRET_BACKEND`; rollback = flip the variable | [infisical-migration](../requirements/REQUIREMENTS-infisical-migration.md) |

## Principles (each traceable to an incident or rule)

1. **Deny-by-default; scope = the blast radius.** A compromised agency instance reads its own
   secrets and nothing else.
2. **Path leaf ≡ identity name ≡ register row.** One name across store, identity, and register —
   this is what makes orphans visible.
3. **No secret value in any agent context, ever.** Blind pipelines; store-to-store copies.
4. **No shared human super-credential.** Human access is OIDC against the WeOwn SSO (individually
   attributable); break-glass is a Shamir quorum — never a shared password-manager row.
5. **Registry-first.** The register row exists (`building`) before the secret does.

## The seam (what makes everything per-instance)

Every container already starts through one wrapper (ADR-006). The store-agnostic seam dispatches
that wrapper on `SECRET_BACKEND`:

```text
entrypoint-secrets.sh          # dispatches on SECRET_BACKEND
  ├── infisical  → infisical run -- "$@"     (today, unchanged)
  ├── openbao    → bao agent / exec wrapper
  └── sops       → decrypt to env, then exec
```

With it unset or `infisical`, behaviour is identical to today. It turns "migrate the fleet" into
"flip a per-instance variable and redeploy" — and the same flip back is the rollback. The seam
**gates wave 1** of the migration.

## What stays in Infisical (the "partial" boundary)

| Stays (for now) | Why |
| --- | --- |
| Human/dev workflow (CLI login, dashboard browsing) | Its UX is what OpenBao doesn't replace cheaply; seats are not the cost driver |
| `infra/shared` tofu variables | Low count, dev-facing, moves last (or stays on a free tier) |
| Anything on an unmigrated instance | Migration is per-instance via the seam; no half-migrated instances |

Dropping Infisical entirely is deliberately deferred until the machine-identity overage is gone.

## Unseal custody (a human decision, not an engineering ticket)

- Recommendation: **Shamir 3-of-5**, shares held by five named humans across WeOwn and the
  contractor side, each in that person's **individual** password manager — never a shared vault.
- No cloud auto-unseal at this stage (it reintroduces the vendor dependency self-hosting avoids);
  production uses a self-hosted transit unseal vault instead (see the Wave-0 implementation repo).
- Alert on sealed state; a written unseal runbook; **quarterly drill** (seal → quorum unseals →
  write/read round-trip → logged).
- Cliff-aware: 3-of-5 across both parties means no single person's absence bricks the store.

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Restructured to WeOwn doc conventions: dropped internal taxonomy frontmatter + trace sections, renamed off `CAP-`/`RP-` prefixes | Nik |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
