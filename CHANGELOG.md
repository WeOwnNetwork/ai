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

## [v3.3.4.2] — 2026-04-23

Second #WeOwnVer iteration in the same week, following PR #7 (v3.3.4.1) merge. Ships documentation sync for the `main` branch ruleset (configured on the same day as the merge), a new ADR capturing ruleset decisions + compliance mappings, an inline contributors table + enforcement-posture matrix in `CONTRIBUTING.md` §4, and a small doc correction surfaced during workflow testing.

### Added

- **`.github/ADR-003-main-branch-ruleset.md`** — new ADR documenting the 12 rules enabled on the `main` ruleset (configured 2026-04-23), mapped to SOC 2 (CC6.1, CC6.3, CC7.1, CC7.2, CC8.1), ISO/IEC 27001:2022 (A.5.15, A.5.28, A.5.37, A.8.13, A.8.24, A.8.29, A.8.32), ISO/IEC 42001:2023 (A.6.2.7, A.6.2.8, A.7.2, A.8.3, A.9.3, A.9.4), NIST CSF 2.0 (PR.AC-4, PR.DS-6, PR.IP-1, PR.IP-3, DE.CM-1, DE.CM-7, DE.CM-8), and CIS Controls v8 (3.11, 11.2, 11.3, 16.1, 16.9, 16.11, 16.12, 18.3). Also documents rules intentionally NOT enabled (linear history, code scanning results, signed tags — latter two tracked as future items), rationale for empty bypass list under SOC 2 CC6.3, and a "Dev Attribution Enforcement Posture" section comparing three options (A=strict regex allowlist, B=reviewer-enforced convention [chosen], C=hybrid warning layer) with explicit numeric upgrade triggers (e.g., "escalate to Option C if team >15 or >10% of merged PRs use non-table handles in a quarter").
- **Platform-sourced developer attribution in `auto-pr-to-main.yml` step 6** — the workflow reads `${{ github.triggering_actor || github.actor }}` to attribute PRs, producing `**Triggered by:** @<real-github-username>` in the PR body. Zero maintenance: no case-statement mapping to keep in sync, no onboarding / offboarding workflow edits required, no risk of stale mappings drifting from `CONTRIBUTING.md`. The `<dev>` segment in branch names is preserved for human-readable naming only. Resolves 4 of 6 Copilot round-1 review comments on PR #13 that flagged `@<short-handle>` as potential misattribution. (An intermediate iteration added a case-statement mapping; subsequent iteration replaced it with `github.actor` for correctness-by-default.)

### Changed

- **`.github/workflows/README.md` §8.1** rewritten to reflect the as-configured ruleset (12 enabled rules with compliance column) instead of an aspirational recommendation list. Removes `pat-health-check.yml` from "required status checks" (it is `schedule:` triggered, cannot be a PR-time gate). Clarifies that "Require code quality results at warning and higher" is satisfied by **CodeQL Default Setup** (distinct from "Require code scanning results" which requires SARIF via a different API). Adds explicit note on why linear history is intentionally NOT enabled and how "Restrict who can push" is effectively covered by "Require a PR" + empty bypass list.
- **`CONTRIBUTING.md` §4 Branch Naming** — (a) removed the false-invalid example `feature/add-thing` (which actually DOES pass the regex: `add` = 2+ char `<dev>`, `thing` = 3+ char description) and replaced with genuinely invalid examples (`feature/ab-a`, `feature/roman--double-hyphen`, `random/roman-test`); (b) added a "Convention beyond the regex" note clarifying that `<dev>` is a human-readable short handle (typically first name / alias), not used for PR attribution — attribution is sourced from `github.actor` directly; (c) added a "Known contributor handles" table with GitHub handles + branch `<dev>` segments only (extended context such as legal names, tenure, and roles lives in internal onboarding docs, not this public repo); Nik's branch `<dev>` segment changed from `ncimino` to `nik` (shorter, matches first-name convention); placeholder TODO handles replaced with real ones (`@iamwaseem18`, `@mshahid538`); `@YonksTEAM` added as executive stakeholder reference; (d) added an "Enforcement posture" mini-matrix summarizing the three options documented in detail in ADR-003 so contributors understand why convention-not-mechanical is the current choice and what would trigger a change. Self-contained — no separate file.
- **`.github/workflows/README.md` header** — version bumped from `v3.3.4.1` to `v3.3.4.2` per #WeOwnVer pre-merge iteration policy (this is the second merge-event iteration in the same ISO week).
- **`.github/CODEOWNERS`** — replaced placeholder handles `@mohammed-TODO` / `@shahid-TODO` / `@dhruv-TODO` with confirmed real GitHub handles `@iamwaseem18` / `@mshahid538` / `@dhruvmalik007` (active per-path rules unchanged — still `@ncimino @romandidomizio` until 2026-05-15 handoff decisions are finalized). Added `@YonksTEAM` as an executive stakeholder reference in the header (not a path reviewer — avoids notification noise). Header PII minimization: legal names, tenure descriptors, and recovery-credential custody details removed from the public header; extended operational context lives in internal onboarding / security docs.
- **Branch naming example sync** — updated example branch `fix/ncimino-...` → `fix/nik-...` across `.github/workflows/branch-name-check.yml` (error-message output), `.github/workflows/README.md` §3, and root `README.md` §"Branch Strategy" to match Nik's confirmed branch `<dev>` segment in `CONTRIBUTING.md` §4. `auto-pr-to-main.yml` reviewer assignment remains `--add-reviewer ncimino,romandidomizio` — Nik's GitHub handle `@ncimino` is unchanged; only his `<dev>` branch segment changed from `ncimino` to `nik`.
- **`.github/workflows/README.md` §9 + §10** — Reviewer Rotation Procedure step 2 and Transition Checklist row 4 updated to reflect that placeholder-handle replacement is complete (`~~strikethrough~~ + ✅`), leaving only the per-path specialist-assignment decision as pending. Keeps the transition checklist an accurate audit artifact of what's done vs. still open.
- **`.github/INCIDENT_RESPONSE.md` Scenario 6** — Stewardship Gap response steps 2 and 3 updated to reference real GitHub handles (`@iamwaseem18` / `@mshahid538` / `@dhruvmalik007`) instead of `@<name>-TODO` placeholders. Incident playbook accuracy matters for SEV-4 on-call response — no ambiguity about who to page.
- **`CONTRIBUTING.md` §4** now explicitly documents the branch-name-vs-PR-body identifier split: `<dev>` is a human-readable short handle; PR `**Triggered by:**` attribution uses `github.actor` automatically. Added a blockquote callout table for quick reference. Resolves a user-facing ambiguity flagged in Copilot round-1 review of PR #13.
- **`.github/workflows/README.md` §3 Parsing Rules** simplified from 5 steps (including a handle-to-username mapping step) down to 3 steps (regex validation + direct `github.actor` attribution). Added a "Branch name vs. PR body—two different identifiers (by design)" subsection with a clarity table.
- **`.github/workflows/README.md` §9 Reviewer Rotation Procedure** — stripped contributor legal name in the "placeholder-handle replacement complete" note; kept only the GitHub handles (PII minimization in public runbook, addressing Copilot round-2 review feedback).
- **`.github/CODEOWNERS` PII minimization** — header re-written to remove contributor legal names, tenure descriptors, intern status, executive titles, and recovery-credential custody details. Kept only GitHub handles + minimal functional-area descriptors (IaC, Docker, Agentic AI). Reduces social-engineering surface area on a public repo, addressing Copilot round-2 review feedback.

### Fixed

- **`.github/ADR-003-main-branch-ruleset.md` stale path reference** — "Not enabled → Require signed tags" bullet previously pointed to `.pr7-handoff-checklist` (a local-only, gitignored file that does not exist in the repo tree). Replaced with `/CHANGELOG.md` + `docs/VERSIONING_WEOWNVER.md`, both of which are in-repo tracking locations. Resolves 1 of 6 Copilot review comments on PR #13.
- **`.github/ADR-003-main-branch-ruleset.md` date arithmetic** — "Next scheduled review" incorrectly read `2026-07-23`. 2026-04-23 + 90 calendar days = 2026-07-22 (April 30-23=7 remaining days in April, May=31, June=30 → 7+31+30=68 days, 90-68=22 → July 22). Corrected to `2026-07-22` and clarified "90 calendar days" to remove math ambiguity. Resolves 1 of 6 Copilot review comments on PR #13 about date inconsistency.

### Security / Compliance

- **SOC 2 CC6.3 evidence-ready**: §8.1 table maps each of the 12 enabled rules to specific SOC 2 Trust Services Criteria. Auditors can cross-reference the GitHub ruleset config with this table for one-shot coverage proof.
- **ISO 27001 A.5.15 + A.5.37**: path-reviewer binding (CODEOWNERS #3) + change-of-state reset (stale approval dismissal #2) documented and enforced.
- **ISO 42001 AI governance**: rule #10 (auto-request Copilot review) now mapped to Annex A.6.2.7 (AI-aware technical controls) and A.6.2.8 (review + approval of AI-generated output).
- **`WEOWN_BOT_PAT` rotation audit note** — the fine-grained PAT scoped to `WeOwnNetwork/ai` was regenerated on 2026-04-23 during this PR's cycle to restore the `auto-pr-to-main.yml` workflow (prior PAT was invalidated; `PAT Health Check` workflow run `24870414632` confirmed the post-rotation PAT authenticated as `weown-bot` with 89 days to next expiration on 2026-07-22). New PAT is 89-day fine-grained, single-repo scope, stored via Infisical → GitHub Secret sync. The rotation event itself is an auditable control (no sensitive credential material recorded here).

### Meta

- **Testing evidence**: all three workflows validated via a 42-case solo regression matrix (branch-name regex coverage, defense-in-depth parity, developer attribution extraction, jq fallback behavior, YAML parse) — see `.pr7-test-workspace/solo-tests.sh` (local-only, not committed).
- **Version cadence**: this PR is the second merge-event in Season 3, April Week 4. Next merge in this ISO week would be `v3.3.4.3`; next ISO week starts at `v3.3.5.1`. See `docs/VERSIONING_WEOWNVER.md` for the full cadence rules.

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
- **Workflow hardening (Copilot review rounds 3–5)**:
  - `pat-health-check.yml` now **fails closed** (`exit 1`) when the `github-authentication-token-expiration` header is missing — previously silently exited 0, which defeated the workflow's safety-net purpose. A missing header indicates token-type misconfiguration (e.g., classic PAT instead of fine-grained) and must surface as a red-X in Actions
  - `pat-health-check.yml` now **fails closed** (`exit 1`) when the header IS present but the timestamp cannot be parsed into an epoch — previously emitted a `::warning::` and silently exited 0, creating a second bypass path that would activate exactly when GitHub changed the header format. Error message includes the offending raw value for forensics (round 4)
  - `pat-health-check.yml` separates `gh api /user` exit-code check from header-grep so a transient API/network failure (previously swallowed by `2>/dev/null | grep ... || true`) is not misclassified as a PAT-configuration issue. Three distinct red-X paths now exist with targeted error messages: (1) API call itself failed, (2) call succeeded but header absent, (3) header present but unparseable. Stderr of the failing `gh api` is surfaced in the Actions log (round 5)
  - `branch-name-check.yml` sets `permissions: {}` — the workflow makes no API calls and does not check out the repo (only reads `github.head_ref` / `github.ref` context and runs a local grep), so the ephemeral `GITHUB_TOKEN` is stripped of every permission (round 5)
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
