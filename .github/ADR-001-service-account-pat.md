# ADR-001: Ecosystem-Wide GitHub Service Account (`weown-bot`) + Fine-Grained PATs

**Status**: Accepted
**Version**: v3.3.4.1 (#WeOwnVer)
**Date**: 2026-04-23
**Deciders**: `@romandidomizio` (original author, left 2026-05-15) — `@ncimino` (current maintainer)
**Supersedes**: None
**Superseded by**: None

---

## Context

The WeOwn AI infrastructure repository uses an automated Pull Request workflow (`.github/workflows/auto-pr-to-main.yml`) that creates PRs from short-lived working branches (`feature/*`, `fix/*`, `docs/*`, `hotfix/*` — GitHub Flow) to `main`. These PRs must trigger GitHub Copilot's AI code review automatically for compliance and quality gating.

### Technical Constraint

**GitHub Copilot code review is triggered only by PRs authored by a human-type account.** PRs authored by GitHub Apps (`app/<name>[bot]`) are **not** auto-reviewed by Copilot.

### Prior State (before PR #7)

Earlier revisions of the workflow used `ROMAN_PAT` — a Personal Access Token tied to `@romandidomizio` personally. This satisfied the human-type requirement but:

- Created a single point of failure tied to Roman's account
- Conflicted with SOC 2 access control (personal accounts for automated service operations)
- Did not scale to other repositories or organizations
- Presented a severe continuity risk given Roman's scheduled departure 2026-05-15

---

## Decision

**Adopt `weown-bot` as an ecosystem-wide GitHub service account used for all WeOwn automated workflows that require human-type PR authorship.**

Key properties:

1. **One GitHub account** (`weown-bot`) reused across all WeOwn organizations and repositories
2. **Per-repo fine-grained Personal Access Tokens (PATs)** — each repo gets its own PAT scoped only to that repo
3. **Minimum permissions per PAT — workflow-dependent, principle of least privilege**. For this repo the PAT is scoped to `Contents: Read` + `Pull requests: Read/Write` + metadata (auto). `Contents: Read` is sufficient because no workflow in this repo pushes commits via the PAT (developers push from local; workflows only clone and call the PRs API). **Prefer the ephemeral per-run `GITHUB_TOKEN`** (scoped via the workflow's `permissions:` block) for any ops the PAT does not strictly need — e.g., `pat-health-check.yml` uses `GITHUB_TOKEN` with `issues: write` to open rotation reminder issues, so the PAT itself does not need `Issues: Write`. Adding new scopes to the PAT should be treated as a reviewed change (document the rationale in this ADR and the workflows README usage table).
4. **90-day expiration** — enforced by GitHub for fine-grained tokens
5. **Centralized secret management** — all PATs stored in Infisical project `weown-bot GitHub PATs` (see ADR-002)
6. **2FA mandatory** on the `weown-bot` GitHub account (TOTP + recovery codes held by infrastructure team)
7. **Documented stewardship** — primary PAT steward is `@ncimino` (Nik) as of 2026-05-15 (see CODEOWNERS); `@iamwaseem18` and `@mshahid538` are secondary stewards at `@ncimino`'s discretion
8. **No direct commit access** — branch protection rules require PRs; `weown-bot` authors PRs but does not merge to `main`

---

## Alternatives Considered

### Alternative 1: GitHub App

Using a GitHub App would provide:
- ✅ Automatic, short-lived (1-hour) installation tokens
- ✅ Clean bot attribution (no confusion with human activity)
- ✅ Strong audit trail via GitHub Apps event log

But it fails the primary requirement:
- ❌ **GitHub Copilot does not auto-review PRs authored by GitHub Apps** — this is the disqualifier

### Alternative 2: Personal Account (`@romandidomizio`'s PAT, the prior state)

- ❌ Ties automation to a personal account (SOC 2 access control violation)
- ❌ Single point of failure
- ❌ Does not scale across ecosystem
- ❌ Severe continuity risk

### Alternative 3: Short-Lived OIDC-Based Token

Some teams mint short-lived tokens via GitHub OIDC → an external IdP → GitHub. This is elegant but:
- ❌ Requires an external IdP that GitHub trusts
- ❌ More complex to operate and audit
- ❌ Does not avoid the core Copilot "human-type" requirement

---

## Consequences

### Positive

- ✅ **Copilot auto-review works** on every auto-PR
- ✅ **Not tied to any individual** — service continuity preserved through personnel changes
- ✅ **Ecosystem-wide** — one account reused across all WeOwn repos and orgs
- ✅ **Clean audit trail** — all automated PRs clearly attributed to `weown-bot` (not confused with human activity)
- ✅ **Scoped blast radius** — each repo's PAT only grants access to that repo
- ✅ **Compliance-aligned** — satisfies NIST PR.AC (Access Control), CIS 5/6 (Account & Access Mgmt), ISO A.5.15/A.5.16 (Access Control)

### Negative / Tradeoffs

- ⚠️ **Longer-lived PATs** (90 days) vs. GitHub App tokens (1 hour)
  - *Mitigation*: fine-grained scope, Infisical audit logs, multi-layered rotation alerts (see `.github/workflows/README.md` §"Alert Stack")
- ⚠️ **Manual PAT creation** — GitHub does not expose PAT creation via API
  - *Mitigation*: 13-step documented procedure; 3 alert layers fire 14+ days before expiration
- ⚠️ **Human-type account for machine work** may look unusual at first glance
  - *Mitigation*: Account name `weown-bot` makes purpose obvious; CODEOWNERS and ADR clarify ownership

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| PAT leaked | Low | Medium | Fine-grained scope, Infisical audit logs, immediate rotation procedure, branch protection still requires 1 reviewer |
| PAT expires unrotated | Medium | Low | 3-layer alert stack (GitHub email, Infisical reminder, scheduled `pat-health-check.yml`) |
| `weown-bot` account compromised | Low | High | 2FA mandatory, unique email, enterprise-managed, no direct commit access, incident response in `INCIDENT_RESPONSE.md` |
| Stewardship gap post-2026-05-15 | Resolved | — | Transition complete 2026-05-15; `@ncimino` is primary steward per CODEOWNERS; `@iamwaseem18`/`@mshahid538` available at `@ncimino`'s discretion |

---

## Related

- **ADR-002**: Infisical as primary secret store for `WEOWN_BOT_PAT`
- **`.github/SECURITY_ASSESSMENT.md`**: Full threat model for bot + PAT + Infisical Sync
- **`.github/INCIDENT_RESPONSE.md`**: PAT and account compromise runbooks
- **`.github/workflows/README.md`**: Operational procedures (rotation, alerts, transition)
- **`docs/COMPLIANCE_ROADMAP.md`**: Where this decision fits in the multi-phase roadmap

---

## References

- GitHub fine-grained PAT docs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitHub Copilot code review: https://docs.github.com/en/copilot/using-github-copilot/code-review
- NIST CSF 2.0 PR.AC (Access Control): https://www.nist.gov/cyberframework
- CIS Controls v8: Controls 5 (Account Mgmt), 6 (Access Control Mgmt)
- ISO/IEC 27001:2022 Annex A.5.15, A.5.16 (Access Control)
