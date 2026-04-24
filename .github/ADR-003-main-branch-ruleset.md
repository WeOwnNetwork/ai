# ADR-003: `main` Branch Ruleset — Enabled Rules and Compliance Mappings

**Status**: Accepted
**Version**: v3.3.4.2 (#WeOwnVer)
**Date**: 2026-04-23
**Deciders**: `@romandidomizio`, `@ncimino`
**Supersedes**: None
**Superseded by**: None
**Related**:
- [`ADR-001`](ADR-001-service-account-pat.md) — service account + PAT posture
- [`ADR-002`](ADR-002-infisical-github-sync.md) — Infisical secret synchronization
- [`.github/workflows/README.md` §8.1](workflows/README.md#81-branch-ruleset-on-main-configured-2026-04-23) — authoritative ruleset reference
- [`.github/CODEOWNERS`](CODEOWNERS) — path-based reviewer enforcement

---

## Context

The `WeOwnNetwork/ai` repository stores the infrastructure-as-code and operational runbooks for the WeOwn agentic platform. Changes to `main` have production implications (deployments are gated on the files in this repo). SOC 2 Type II, ISO/IEC 27001:2022, ISO/IEC 42001:2023, and CIS Controls v8 all require enforced change-management controls for production-affecting branches.

Prior to this ADR, `main` was protected only by the legacy Branch Protection UI with a 1-reviewer requirement and no required status checks. This posture did not satisfy:

- **SOC 2 CC8.1** (formal change management with reviewer segregation of duties)
- **SOC 2 CC6.3** (logical access controls for privileged write operations)
- **ISO 27001 A.5.15** (access control policy)
- **ISO 27001 A.8.24** (use of cryptography — signed commits)
- **CIS 16.9** (separation of duties for code changes)
- **NIST CSF 2.0 PR.AC-4** (access permissions + authorizations managed by least privilege + separation of duties)

---

## Decision

**Adopt a GitHub Ruleset targeting `main` that enforces 12 rules** (configured 2026-04-23 via repo Settings → Rules → Rulesets).

### Platform choice: Rulesets over legacy Branch Protection

- Rulesets support granular rule composition, explicit bypass lists, and org-wide reuse. Branch Protection Rules are deprecated for new configurations.
- Only Rulesets expose:
  - Per-rule enforcement control (vs. all-or-nothing BPR)
  - Distinct "bypass" semantics (empty list = no one bypasses)
  - "Require code quality results" (works with the Code Quality API + CodeQL)
  - "Require approval of the most recent reviewable push" (closes race conditions)

### Target and enforcement

- **Target**: `refs/heads/main` only
- **Enforcement status**: Active
- **Bypass list**: empty (no roles, no teams, no individuals)
- **Precedence over BPR**: the repo has no Branch Protection Rule on `main`; the Ruleset is the sole enforcement mechanism

### Enabled rules

| # | Rule | SOC 2 | ISO 27001 | ISO 42001 | NIST CSF 2.0 | CIS v8 | Rationale |
|---|---|---|---|---|---|---|---|
| 1 | Require PR with 2 reviewers | CC6.3, CC8.1 | A.5.15, A.5.37 | A.6.2.8 | PR.AC-4, PR.IP-3 | 16.9, 16.11 | Segregation of duties; no solo merges |
| 2 | Dismiss stale approvals on new push | CC8.1 | A.5.37 | A.9.4 | PR.IP-1 | 16.11 | Prevents approve-then-amend bypass |
| 3 | Require review from Code Owners | CC6.3 | A.5.15 | A.6.2.8 | PR.AC-4 | 16.9 | Path-specific expertise enforced |
| 4 | Require approval of most recent reviewable push | CC8.1 | A.5.37 | A.9.4 | PR.IP-1 | 16.11 | Closes race: approve PR → sneak bad commit → merge |
| 5 | Require conversation resolution before merging | CC8.1 | A.5.37 | A.6.2.7 | PR.IP-1, DE.CM | 16.11 | All Copilot / reviewer comments addressed or explicitly deferred |
| 6 | Require signed commits | CC6.1 | A.8.24 | A.7.2 | PR.DS-6 | 3.11 | Cryptographic authorship guarantee |
| 7 | Require status checks to pass | CC7.1, CC7.2 | A.5.37 | A.9.3 | DE.CM-1, DE.CM-7 | 18.3 | Automated gating via workflows |
| 7a | &nbsp;&nbsp;Required check: `Validate Branch Name` | CC7.1 | A.5.37 | — | DE.CM-7 | — | Enforces branch naming regex at PR time |
| 8 | Require branches up to date before merging | CC7.2 | A.5.37 | A.9.3 | DE.CM-1 | — | Tests against latest `main`, prevents stale-merge surprises |
| 9 | Require code quality results at warning and higher | CC7.1 | A.8.29 | A.9.3 | DE.CM-8 | 16.1, 16.12 | Satisfied by CodeQL Default Setup (see below) |
| 10 | Auto-request Copilot review | — | A.5.37 | A.6.2.7 | DE.CM-8 | 16.11 | AI-assisted review depth; ISO 42001 AI-aware control |
| 11 | Restrict deletions | CC7.1 | A.5.37, A.8.13 | A.8.3 | PR.IP-1 | 11.2 | Prevents accidental/malicious branch deletion |
| 12 | Block force pushes | CC7.1 | A.5.28, A.8.32 | A.8.3 | PR.IP-1 | 11.3 | Preserves audit trail immutability |

### Not enabled (intentional)

- **Require linear history** — Team allows merge commits for context preservation. Squash-merges via the PR UI are the default merge style; merge commits are preserved only when a reviewer explicitly chooses "Create a merge commit" (rare).
- **Separate "Restrict who can push"** rule — Not exposed as a standalone toggle in the new Rulesets UI. Effectively covered by "Require a pull request" (#1 above) + empty bypass list: no role can push directly to `main` without going through a PR.
- **Require code scanning results** — Distinct from #9 above. This rule requires SARIF via the Code Scanning API (CodeQL's Advanced Setup output). We use Code Quality results instead because CodeQL Default Setup outputs to the Code Quality API rather than the Code Scanning API. If we migrate to CodeQL Advanced Setup, we should re-evaluate adding this rule.
- **Require signed tags** — Not yet enabled. Should be added when we start using tags for release marking (track via `/CHANGELOG.md` and `docs/VERSIONING_WEOWNVER.md`).

### Code quality signal: CodeQL Default Setup

Rule #9 requires something to produce code quality signals. This is satisfied by **CodeQL Default Setup**, configured 2026-04-21 at Settings → Code security → Code scanning → CodeQL analysis → Default setup.

Configuration (from `gh api /repos/WeOwnNetwork/ai/code-scanning/default-setup`):

```json
{
  "state": "configured",
  "languages": ["actions", "javascript", "javascript-typescript", "python", "typescript"],
  "query_suite": "default",
  "threat_model": "remote",
  "schedule": "weekly",
  "runner_type": "standard"
}
```

Runs on: push to default branch, every PR, weekly schedule. GitHub hosts the CodeQL workflow implicitly (no `.github/workflows/codeql.yml` in this repo).

### Rationale for empty bypass list

Under SOC 2 CC6.3 and ISO 27001 A.5.15, reviewers and approvers must be subject to the same controls as contributors. The mechanical implementation of "Include administrators" (from the legacy BPR UI) is "bypass list = empty" in Rulesets.

**Org-owner ruleset edits** are a separate concern — these are captured in the organization audit log (retention per GitHub Enterprise plan). If an org owner modifies the ruleset, the audit trail shows who, what, and when. This satisfies SOC 2 CC7.1 (audit trail for privileged operations) provided:

1. The org audit log retention is ≥ 90 days (check Settings → Audit log → Retention)
2. At least one non-bypassed owner exists so single-person rule modification is not possible without an audit record
3. The ruleset edit itself triggers notification to other owners (GitHub emails org owners on ruleset changes by default)

---

## Consequences

### Positive

- **Auditor-ready posture**: 12 concrete controls mapped to 6 compliance frameworks. SOC 2 Type II evidence flows directly from GitHub audit logs + PR review records.
- **Mechanical enforcement**: All rules apply without human intervention. No "we forgot to check" gaps.
- **AI review depth**: Rules #10 + CodeQL #9 ensure every change gets both rule-based (CodeQL) and context-aware (Copilot) review before human approval.
- **Incident containment**: Rules #11 + #12 + signed commits (#6) make history rewriting / branch destruction cryptographically and administratively hard.
- **Small-team scalability**: With only 2 active approvers today (`@ncimino` + `@romandidomizio`), the 2-reviewer rule forces coordination but does not block progress. Post-2026-05-15 handoff expands the approver pool per `CODEOWNERS` and the transition checklist.

### Negative / trade-offs

- **Merge latency**: A PR needs 2 approvers to merge. With distributed teams this may add 12-24h per PR. Mitigation: same-day turnaround culture; urgent hotfixes route through `hotfix/*` with the same ruleset (no bypass) — escalation is a reviewer-availability issue, not a ruleset issue.
- **CodeQL false positives**: Default Setup's "warning and higher" threshold means some low-confidence findings can block merges. Mitigation: reviewer dismisses with justification in the Code Quality tab (this action is itself audit-logged).
- **External contributor friction**: Fork-PRs from outside the org need reviewers to explicitly trigger workflow runs + approve CodeQL. This is the intended posture — external contributions deserve extra scrutiny.
- **Bypass list discipline**: Adding even one role to the bypass list breaks SOC 2 evidence. Any proposal to add a bypass must be documented here as a superseding ADR.

### Neutral

- **GitHub Enterprise plan dependency**: Rulesets are available on GitHub Free (for public repos), Pro, Team, and Enterprise. `WeOwnNetwork` is on Enterprise, so this is a non-issue. If the org ever downgrades, this ADR must be revisited.

---

## Dev Attribution Enforcement Posture

Branch naming (`<type>/<dev>-<description>`) relies on two layers:

1. **Format regex** in `.github/workflows/branch-name-check.yml` — enforced mechanically (required status check #7a above)
2. **`<dev>` identity** = currently reviewer-enforced via `CONTRIBUTING.md` §4 "Known contributor handles" table

### Decision: reviewer-enforced convention (Option B)

We evaluated three postures for the `<dev>` segment:

| Option | Mechanism | Maintenance | External contributor friction | Compliance strength |
|---|---|---|---|---|
| **A. Strict allowlist** | Regex alternation of known handles `(roman\|nik\|mohammed\|...)` | **High** — edit regex + workflow on every onboarding/offboarding | **High** — fork PRs from non-team blocked without regex edit | **Strongest** — mechanical enforcement auditable |
| **B. Reviewer-enforced convention** *(chosen)* | Regex enforces format only; reviewer verifies `<dev>` against table in CONTRIBUTING.md §4 | **Low** — edit one markdown table when adding contributor | **Low** — external PRs accepted as long as reviewer acknowledges | **Acceptable** — audit evidence = PR review records + CODEOWNERS enforcement |
| **C. Hybrid warning layer** | Regex + workflow step checks `<dev>` against YAML allowlist, emits `::warning::` (non-blocking) if unknown | **Medium** — edit YAML allowlist + optional `CONTRIBUTING.md` table sync | **Low** — warnings don't block, reviewer approves with context | **Strong** — warnings captured in Actions logs, reviewer response is an auditable event |

**Current choice: Option B.** Rationale:

- Team size (~6 core contributors as of 2026-04-23) doesn't justify Option A's maintenance cost
- External contributors (audit reviewers, one-time collaborators) are expected occasionally and must remain unblocked
- PR review records + CODEOWNERS enforcement already provide audit-grade attribution
- The 2-reviewer rule (#1) + CODEOWNERS (#3) catch misuse socially
- `auto-pr-to-main.yml` attributes automation activity using `${{ github.triggering_actor || github.actor }}`, so the recorded actor is the GitHub user who triggered the workflow run (push, `workflow_dispatch`, or re-run) when available, or the workflow actor otherwise. Attribution is derived directly from GitHub's event context rather than branch-name parsing, inline handle mapping, or git-author-email fallback — no maintenance, no drift risk, and audit evidence is consistent with GitHub's own audit log

### Upgrade triggers — when to revisit

Move to **Option C (warning layer)** when ANY of:

- Core contributor count exceeds **15**
- A compliance audit (SOC 2, ISO 27001) produces a finding about attribution inconsistency or reviewer-burden on convention enforcement
- Three or more misuse incidents in a single quarter (malformed `<dev>` handles merged without reviewer catching)
- A contributor's identity becomes a material audit concern (e.g., external contributor accidentally gets merged with a misleading handle)

Move to **Option A (strict allowlist)** when ALL of:

- Core contributor count is stable ≥ **15**
- External contributions are formally routed through a separate process (e.g., fork-PR with a different ruleset, or signed CLA flow)
- Compliance mandate specifically requires mechanical handle enforcement (rare; typically only for government/defense contracting or Fed-adjacent tenants)

Either upgrade requires a **superseding ADR** (ADR-00N) documenting the specific trigger observed, the chosen option, regex or YAML changes, and a rollback plan if the upgrade creates unintended friction. Do not silently edit this section.

### Review reminders

- Quarterly ruleset review (per §Review Cadence below) should include a count of:
  - Total PRs merged since last review
  - PRs with non-table `<dev>` handles (if any)
  - Any reviewer time lost correcting branch names (anecdotal signal)
- If the count of non-table `<dev>` usage exceeds 10% of merged PRs, escalate to Option C immediately

---

## Implementation Verification

As of 2026-04-23, this ruleset is verified active via:

```bash
gh api /repos/WeOwnNetwork/ai/rulesets \
  --jq '.[] | select(.target == "branch") | {name, enforcement, bypass_actors}'
```

Expected output: one active ruleset targeting `main`, `enforcement: "active"`, `bypass_actors: []`.

Smoke-test evidence:

- Live run 2026-04-23: `Branch Name Check` correctly failed on push to `maintenance` branch (invalid name per regex) — confirms the workflow is producing the required status check signal.
- CodeQL run 2026-04-23 on merge commit `af9a08c` (PR #7 → `main`): passed Code Quality API evaluation with no warning-or-higher findings.

---

## Review Cadence

This ADR must be reviewed:

1. **Quarterly** by the repo owners as part of regular control review (track in `/CHANGELOG.md`)
2. **On any ruleset modification** (add a superseding ADR; do not silently edit this one)
3. **Pre-audit** (SOC 2 Type II annual; ISO 27001 surveillance cycle)
4. **Post-incident** if a rule is suspected of having failed (incident postmortem template in `.github/INCIDENT_RESPONSE.md`)

Next scheduled review: **2026-07-22** (90 calendar days from 2026-04-23).

---

## Changelog

- 2026-04-23 — ADR accepted; ruleset configured with 12 rules listed above; bypass list empty; CodeQL Default Setup confirmed active for rule #9.
