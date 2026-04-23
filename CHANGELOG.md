# WeOwn AI Repository Changelog

This file tracks **repository-level** (infrastructure, workflows, governance, cross-cutting documentation) changes.

Application-specific changes live in per-directory CHANGELOGs. See the index below.

**Format**: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/)
**Versioning**: Per [VERSIONING_WEOWNVER.md](docs/VERSIONING_WEOWNVER.md) — `vSEASON.MONTH.WEEK.ITERATION`

---

## Per-Directory Changelog Index

| Component | Changelog |
|---|---|
| AnythingLLM | [`anythingllm/CHANGELOG.md`](anythingllm/CHANGELOG.md) |
| Matomo | [`matomo/CHANGELOG.md`](matomo/CHANGELOG.md) |
| n8n | [`n8n/CHANGELOG.md`](n8n/CHANGELOG.md) |
| Nextcloud | [`nextcloud/CHANGELOG.md`](nextcloud/CHANGELOG.md) |
| Vaultwarden | [`vaultwarden/CHANGELOG.md`](vaultwarden/CHANGELOG.md) |
| WordPress | [`wordpress/CHANGELOG.md`](wordpress/CHANGELOG.md) |
| WordPress Dev | [`wordpress-dev/docs/CHANGELOG.md`](wordpress-dev/docs/CHANGELOG.md) |

---

## [Unreleased]

Changes in this section will be promoted to a dated release entry on merge to `main`.

---

## [v3.3.4.1] — 2026-04-23

First repository-level CHANGELOG entry (#WeOwnVer `vSEASON.MONTH.WEEK.ITERATION` — Season 3, April, Week 4 of April, Iteration 1). Establishes auto-PR workflow hardening, ecosystem-wide service account, Infisical GitHub Sync, branch naming enforcement, and the initial compliance roadmap.

### Added

- **`weown-bot` ecosystem-wide GitHub service account** with per-repo fine-grained PATs, centralized in Infisical project `weown-bot GitHub PATs` (see [ADR-001](.github/ADR-001-service-account-pat.md))
- **Infisical → GitHub Sync integration** for `WEOWN_BOT_PAT__WEOWNNETWORK_AI` (see [ADR-002](.github/ADR-002-infisical-github-sync.md))
- **New workflows**:
  - [`.github/workflows/pat-health-check.yml`](.github/workflows/pat-health-check.yml) — scheduled weekly PAT health check; opens issue at ≤14 days; hard-fails at ≤3 days
  - [`.github/workflows/branch-name-check.yml`](.github/workflows/branch-name-check.yml) — blocks non-conforming branch names (enforces `<type>/<dev>-<description>` convention)
- **New documents**:
  - [`.github/ADR-001-service-account-pat.md`](.github/ADR-001-service-account-pat.md)
  - [`.github/ADR-002-infisical-github-sync.md`](.github/ADR-002-infisical-github-sync.md)
  - [`.github/SECURITY_ASSESSMENT.md`](.github/SECURITY_ASSESSMENT.md) — threat model, risk register, compliance mapping
  - [`.github/INCIDENT_RESPONSE.md`](.github/INCIDENT_RESPONSE.md) — SEV-1..4 runbooks for PAT/account/Infisical/stewardship scenarios
  - [`.github/CODEOWNERS`](.github/CODEOWNERS) — path-based reviewer assignment with post-2026-05-15 handoff TODOs
  - [`.github/workflows/README.md`](.github/workflows/README.md) — authoritative ops reference (usage table, rotation procedure, alert stack, transition checklist, branch protection, replication steps)
  - [`docs/COMPLIANCE_ROADMAP.md`](docs/COMPLIANCE_ROADMAP.md) — detailed 5-phase compliance roadmap (NIST CSF → CIS → CSA CCM → ISO 27001 → SOC 2 → ISO 42001) with CI/CD integration per phase, success metrics, and forward-looking guardrails
  - [`CONTRIBUTING.md`](CONTRIBUTING.md) — first-time developer onboarding. Covers mandatory SSH-based commit signing (NIST PR.DS-6, SOC 2 CC7.1, ISO 27001 A.8.28, CIS 16.12) with 7-step setup including `gpg.ssh.allowedSignersFile` for local verification and verified-email alignment with GitHub account; the **GitHub Flow** branching model (explicitly named + lifecycle diagram + what we do NOT use + rationale table + branch lifetime expectations); branch naming convention; commit message conventions; full PR workflow with post-merge cleanup; review expectations; expanded troubleshooting (signature-present-vs-absent pre-check, 6-cause diagnostic for `%G?=N`, 2-cause diagnostic for GitHub "Unverified" including committer-email mismatch, retro-sign-and-force-push recipe, ssh-agent/keychain fixes); and compliance cross-references
  - [`CHANGELOG.md`](CHANGELOG.md) — this file
- **PR body enhancements** (in `auto-pr-to-main.yml`):
  - NIST CSF Function-aligned human review checklist (Govern, Identify, Protect, Detect, Respond, Recover)
  - Full commit bodies visible to Copilot for context (`%b` not just `%s`)
  - Author identity (`%an <%ae>`) and date (`%ad`) shown per commit
  - Developer attribution parsed from branch naming convention (`<type>/<dev>-<description>`)
  - Deduplicated contributor list
- **Auto-assignment of 2 reviewers** (`@ncimino` + `@romandidomizio`) via `gh pr edit --add-reviewer`

### Changed

- **`auto-pr-to-main.yml`**: token reference `ROMAN_PAT` → `WEOWN_BOT_PAT`
- **`.github/copilot-instructions.md`**: full rewrite — removed command/test directives (Copilot is static-only), added phase-aware compliance, expanded §3 checklist to cover all six frameworks (NIST CSF 2.0, CIS v8 IG1, CSA CCM v4, ISO/IEC 27001:2022, SOC 2 TSC, ISO/IEC 42001:2023) plus seven ecosystem best-practice blocks (Kubernetes, Docker/Compose, **IaC [OpenTofu for infrastructure + Ansible for software/config]**, Infisical, Observability, GitOps, Security/Supply Chain), added §3.0 explicit PUBLIC-repo precautions (never-commit list, placeholder patterns, git history hazards), moved checklist to top of document, added forward-looking guardrails, ecosystem awareness, anti-pattern reference, and cross-framework review output guidelines. Ansible integration documented throughout: Infisical secrets via `community.hashi_vault` / `infisical run -- ansible-playbook`; idempotency / handlers / vault / inventory best practices; anti-patterns for plaintext secrets, non-idempotent shell, implicit root
- **`.github/CI_CD_WORKFLOWS.md`**: cross-referenced the new workflows README, ADRs, and compliance roadmap; documented `pat-health-check.yml`
- **`docs/VERSIONING_WEOWNVER.md`**: rewritten to the corrected calendar-driven methodology (L-094 REVISED): `vSEASON.MONTH.WEEK.ITERATION`, L-115 ISO-week-offset rule, finalized Season Calendar, Helm/OCI mapping, and calculation cheat sheet
- **`README.md`** (top-level): added "Compliance & Governance" section linking all new docs

### Removed

- **`.github/PAT_MIGRATION_GUIDE.md`** deleted — content was superseded by ADR-001 (rationale), ADR-002 (Infisical sync), CHANGELOG (history), and `.github/workflows/README.md` (authoritative rotation procedure). Retaining the old guide created duplicate-source risk.
- **`maintenance` branch** removed from `auto-pr-to-main.yml` triggers and all documentation. The repository now standardizes on **GitHub Flow**: short-lived `feature/*`, `fix/*`, `docs/*`, `hotfix/*` branches off `main`, merged back via reviewed PRs.

### Security

- Fine-grained PAT replaces broad-scoped tokens: minimally scoped to `Contents: Read` + `Pull requests: R/W` + metadata (auto) on `WeOwnNetwork/ai`. Issue creation in `pat-health-check.yml` intentionally uses the ephemeral per-run `GITHUB_TOKEN` (with workflow-level `issues: write`) rather than expanding the PAT — principle of least privilege (NIST PR.AC-3 / CIS 5.4)
- Secret management centralized in Infisical with 90-day audit logs (SOC 2 evidence)
- Branch naming enforced by `branch-name-check.yml` (blocks non-conforming branches via required status check). Description segment requires 3+ alphanumeric chars before any hyphen suffix (e.g., `feature/ab-a` now rejected). Regex kept in sync with the defense-in-depth guard in `auto-pr-to-main.yml`
- Branch protection to be configured: require 2 approvals + review from Code Owners + signed commits + no bypass (see [`.github/workflows/README.md` §8](.github/workflows/README.md#8-required-branch-protection-settings))
- **Workflow hardening (Copilot review rounds 3–4)**:
  - `pat-health-check.yml` now **fails closed** (`exit 1`) when the `github-authentication-token-expiration` header is missing — previously silently exited 0, which defeated the workflow's safety-net purpose. A missing header indicates token-type misconfiguration (e.g., classic PAT instead of fine-grained) and must surface as a red-X in Actions
  - `pat-health-check.yml` now **fails closed** (`exit 1`) when the header IS present but the timestamp cannot be parsed into an epoch — previously emitted a `::warning::` and silently exited 0, creating a second bypass path that would activate exactly when GitHub changed the header format. Error message includes the offending raw value for forensics (round 4)
  - `pat-health-check.yml` removed unused `ISSUE_LABELS` variable — labels are passed directly to `gh issue create` via three explicit `--label` flags; the unused variable falsely implied a single source of truth (round 4)
  - Temp files in both workflows now route through `$RUNNER_TEMP` (GitHub-runner-scoped, auto-cleaned at job end) instead of the shared `/tmp` — defense in depth beyond the existing `mktemp` + `trap` cleanup pattern
  - `pat-health-check.yml` issue-body links use `${{ github.server_url }}` instead of hardcoded `https://github.com` — portable to GitHub Enterprise Server (matches the `BLOB_BASE` pattern already in `auto-pr-to-main.yml`)
  - `auto-pr-to-main.yml` PR-existence check uses jq `.[0].number // empty` — avoids jq's literal `"null"` string on empty arrays, which would previously cause the script to attempt `gh pr edit null`
  - `docs/VERSIONING_WEOWNVER.md` Helm chart mapping corrected for SemVer precedence: every iteration gets a `-N` prerelease suffix (`3.3.4-1 < 3.3.4-2 < 3.3.4-3 < 3.3.4`), preventing the SemVer-downgrade pitfall where `3.3.4-2` would sort BELOW `3.3.4` in Helm/OCI tooling

### Compliance

- **NIST CSF 2.0** — `Govern`, `Protect (Access Control, Data Security)`, `Detect`, `Respond` functions addressed for auto-PR workflow
- **CIS Controls v8 IG1** — Controls 3, 5, 6, 7, 8, 13, 16, 17 in scope
- **ISO/IEC 27001:2022** — A.5.15 (access control), A.5.37 (documented operating procedures), A.8.2, A.8.24 (cryptographic/secret mgmt), A.8.32 (change mgmt)
- **SOC 2 TSC** — CC6.1–CC6.3 (logical access), CC7.1–CC7.2 (system operations), CC8.1 (change mgmt)

### Transition Note (2026-05-15)

`@romandidomizio` departs 2026-05-15. PAT rotation responsibility transitions to one of Mohammed / Shahid / Dhruv. Full handoff checklist in [`.github/workflows/README.md` §10](.github/workflows/README.md#10-transition-checklist-2026-05-15).

---

## Links

- [Repository README](README.md)
- [Compliance Roadmap](docs/COMPLIANCE_ROADMAP.md)
- [Workflows Documentation](.github/workflows/README.md)
- [Copilot Instructions](.github/copilot-instructions.md)
- [Versioning Standard](docs/VERSIONING_WEOWNVER.md)
