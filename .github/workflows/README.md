# GitHub Actions Workflows — WeOwnNetwork/ai

**Scope**: Authoritative reference for all workflows in `.github/workflows/`, the ecosystem-wide `weown-bot` service account, PAT rotation, alert stack, and the 2026-05-15 transition checklist.

**Version**: v3.3.5.1 (#WeOwnVer)
**Last updated**: 2026-04-23
**Owners**: `@ncimino` + `@romandidomizio` (post-2026-05-15: Mohammed/Shahid/Dhruv — see CODEOWNERS)

---

## Table of Contents

1. [Workflow Inventory](#1-workflow-inventory)
2. [`weown-bot` Ecosystem Service Account](#2-weown-bot-ecosystem-service-account)
3. [Branch Naming Convention & Developer Attribution](#3-branch-naming-convention--developer-attribution)
4. [Infisical GitHub Sync — Initial Setup](#4-infisical-github-sync--initial-setup)
5. [Replicating `weown-bot` for a New Repository](#5-replicating-weown-bot-for-a-new-repository)
6. [PAT Rotation Procedure](#6-pat-rotation-procedure)
7. [PAT Alert Stack](#7-pat-alert-stack)
8. [Required Branch Protection & Naming Enforcement](#8-required-branch-protection--naming-enforcement)
9. [Reviewer Rotation Procedure](#9-reviewer-rotation-procedure)
10. [Transition Checklist 2026-05-15](#10-transition-checklist-2026-05-15)
11. [Related Documents](#11-related-documents)

---

## 1. Workflow Inventory

| Workflow | Trigger | Purpose | Owner |
|---|---|---|---|
| `auto-pr-to-main.yml` | push to `feature/*`, `fix/*`, `docs/*`, `hotfix/*` | Creates/updates PR to `main` authored by `weown-bot`; triggers Copilot review; auto-assigns 2 human reviewers | Infra team |
| `branch-name-check.yml` | push (any branch except `main`) | Validates branch follows `<type>/<dev>-<description>` convention; blocks merge if non-conforming | Infra team |
| `pat-health-check.yml` | schedule: weekly (Mondays 09:00 UTC) + manual dispatch | Checks `WEOWN_BOT_PAT` validity + days-to-expiration; opens issue at 14 days; hard-fails at 3 days | Infra team |

---

## 2. `weown-bot` Ecosystem Service Account

### Why a Service Account Exists

**Technical reason**: GitHub Copilot code review is triggered only by PRs authored by a human-type account. PRs authored by GitHub Apps are not auto-reviewed by Copilot. An automated PR workflow therefore needs a human-type GitHub account.

**Compliance reason**: Tying automation to a personal account violates SOC 2 access control and creates a service-continuity single point of failure. A dedicated service account with documented ownership, scoped PATs, and centralized secret management provides a clean audit trail that separates machine-initiated changes from human-initiated ones while still enabling Copilot's AI review layer.

See **ADR-001** for the full decision record.

### Scope & Principles

1. **One GitHub account** (`weown-bot`) reused across the entire WeOwn ecosystem
2. **Per-repo PATs** — each repo gets its own fine-grained, repo-scoped PAT
3. **Centralized storage** — all PATs in one Infisical project: **`weown-bot GitHub PATs`**
4. **Consistent naming**:
   - Infisical secret: `WEOWN_BOT_PAT__<ORG>_<REPO>` (double underscore separator)
   - GitHub Actions secret (per repo): `WEOWN_BOT_PAT` (always the same name at consumption site)
5. **Documented usage** — authoritative table in §2.4 below
6. **Human oversight** — every auto-PR gets 2 required human reviewers (branch protection, §8)
7. **2FA mandatory** on the account + Infisical
8. **No direct commit access** — bot only opens PRs; branch protection prevents direct pushes to `main`

### Account Security Requirements

- ✅ 2FA mandatory (TOTP + recovery codes held by Yonks as enterprise admin)
- ✅ Unique email (currently temp `roman@weown.email`; Yonks providing permanent bot email)
- ✅ No direct commit access to protected branches
- ✅ Enterprise-managed — member of `WeOwnNetwork` org, not a free-floating account
- ✅ Documented ownership and transition plan (this file + CODEOWNERS + ADR-001)

### 2.4 Usage Table (authoritative)

| Org / Repo | Workflows Automated | PAT Secret (Infisical) | PAT Scope (GitHub) | Expiration | Last Rotated | Owner |
|---|---|---|---|---|---|---|
| `WeOwnNetwork/ai` | `auto-pr-to-main.yml`, `pat-health-check.yml`, `branch-name-check.yml` | `WEOWN_BOT_PAT__WEOWNNETWORK_AI` | Contents: R, PRs: R/W, metadata | 2026-07-22 | 2026-04-23 | `@romandidomizio` → TODO(2026-05-15): Mohammed/Shahid/Dhruv |
| _placeholder_ `WeOwnNetwork/<next-repo>` | _TBD_ | `WEOWN_BOT_PAT__WEOWNNETWORK_<NEXT>` | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| _placeholder_ `<future-org>/<repo>` | _TBD_ | `WEOWN_BOT_PAT__<ORG>_<REPO>` | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

> **Update this table** whenever `weown-bot` is enabled on a new repo or whenever a PAT is rotated.
>
> **PAT scope rationale** (NIST PR.AC-3 / CIS 5.4, least privilege):
> - `Contents: Read` — sufficient because no workflow pushes commits via the PAT. Developers push from local; workflows only clone + call the PRs API.
> - `Pull requests: R/W` — required by `auto-pr-to-main.yml` (`gh pr create`, `gh pr edit --body-file`, `gh pr edit --add-reviewer`).
> - `Metadata: Read` (auto) — required by GitHub for any fine-grained PAT.
> - **Not on the PAT**: `Issues: Write`. `pat-health-check.yml` opens/edits rotation reminder issues using the ephemeral per-run `GITHUB_TOKEN` (workflow-level `permissions: issues: write`), which expires at job end. This keeps the 90-day PAT minimally scoped; if a new workflow needs issue write via the PAT, document the change here and in ADR-001.
> - **Adding scopes**: treat as a reviewed governance change — update ADR-001 §Decision key property 3, this table, `SECURITY_ASSESSMENT.md`, and `CHANGELOG.md` in the same PR.

---

## 3. Branch Naming Convention & Developer Attribution

The auto-PR workflow uses **GitHub event context and the commits API** to attribute PRs — it does **not** parse the branch name for attribution. Branch naming is enforced for regex format only (see [branch-name-check.yml](branch-name-check.yml)).

### Convention

```
<type>/<dev>-<short-description>

Examples:
  feature/roman-add-pat-health-check
  fix/nik-resolve-tls-warning
  docs/mohammed-update-compliance-roadmap
  hotfix/shahid-patch-auth-bypass
```

### Parsing Rules (branch name → regex validation only)

1. Split branch on first `/` to get `<type>` and `<remainder>` (validated against the type allowlist)
2. Split `<remainder>` on first `-` to get `<dev>` and `<description>` (regex enforces 2+ char `<dev>`, 3+ char first `<description>` segment)
3. Reject any branch that doesn't match the regex before the workflow runs any git plumbing or PR-body work

The `<dev>` segment is a **human-readability convention for branch naming only**. It is never used for PR attribution or reviewer routing.

### PR body attribution — three-tier model (by design)

The PR body shows three distinct attribution fields, each with a specific audit purpose:

| Field | Value | Source | Updates on each push? |
|---|---|---|---|
| **Opened by** | GitHub @handle of the first commit's author on this branch | `git rev-list --reverse` → `gh api /repos/.../commits/{sha}` | **No** — stable across pushes because the **"Copilot auto-review" ruleset** (id 12131972, see [ADR-004](../ADR-004-copilot-auto-review-ruleset.md)) enforces `non_fast_forward` on `~ALL` branches in this repo, blocking the rebase / force-push that would change the first-commit identity |
| **Last pushed by** | GitHub @handle of whoever pushed or dispatched THIS run | `${{ github.triggering_actor \|\| github.actor }}` | **Yes** — reflects most recent push |
| **Contributors on this branch** | All GitHub @handles with commit counts (falls back to commit author NAME ONLY \[no email\] for unlinked external contributors — emails are PII and intentionally not surfaced in the public PR body) | per-commit `gh api` lookup on the branch range | **Yes** — new commits add new contributors / increment counts |

### Branch name vs. PR body — different identifiers for different jobs

| Where it appears | Value shown | Example | Purpose |
|---|---|---|---|
| **Branch name `<dev>` segment** | Short handle or alias (lowercase, first-name style) | `roman`, `nik`, `mohammed` | Human-readable branch names; audit-friendly in `git log`; reviewer-enforced convention |
| **PR body `Opened by:` line** | GitHub @handle | `@romandidomizio` | Pings the PR originator in notifications; stable across pushes |
| **PR body `Last pushed by:` line** | GitHub @handle | `@ncimino` | Shows who last touched the branch; may differ from opener on multi-contributor PRs |
| **PR body `Contributors:` list** | GitHub @handles with commit counts | `- @romandidomizio (4 commits)` | Complete attribution audit trail; supports per-contributor review load assessment |

Contributors don't maintain any mapping — they just push to a branch named per the convention, and GitHub's own knowledge of commit authors drives every attribution field in the PR body. Zero maintenance; no case statements; onboarding / offboarding requires no workflow changes.

### Reserved Types

- `feature/` — new functionality
- `fix/` — bug fix
- `docs/` — documentation only
- `hotfix/` — urgent production fix

Any branch name not matching `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$` is rejected by the `branch-name-check.yml` workflow (see §8.2). The rule: `<dev>` is 2+ alphanumeric chars; the first `<description>` segment is 3+ alphanumeric chars (so `feature/ab-a` is rejected); additional hyphen-separated segments are 1+ chars each.

---

## 4. Infisical GitHub Sync — Initial Setup

**Status**: Complete for `WeOwnNetwork/ai` as of 2026-04-23.

### 4.1 Two separate Infisical resources — BOTH required

Infisical's GitHub integration has **two independent concepts** that together produce a working sync. You need **both**:

| Concept | What it does | Where you configure it | When you create it |
|---|---|---|---|
| **App Connection** | Authenticates Infisical **to** GitHub. It's the credential Infisical uses to push secrets to GitHub. Reusable across many Secret Syncs. | Org → Settings → **App Connections** → GitHub | **Once** per Infisical org (or once per connection method you need) |
| **Secret Sync** | The actual job that maps a source (Infisical project + environment + path) to a destination (GitHub repo secrets, GitHub repo env secrets, or org secrets). Uses an App Connection. | Project → Integrations → **Secret Syncs** → GitHub | **Once per repo** (or per env-scoped sync) |

**Mental model**:
```
App Connection (auth)  ─────────────────┐
                                         ▼
Secret Sync (map + push) ──────►  GitHub Actions Secrets
        ▲
Source: Infisical project + env + path
```

### 4.2 Prerequisites

- Infisical Pro account, logged in as an admin of the org
- Existing or new Infisical project renamed to **`weown-bot GitHub PATs`**
- GitHub organization admin access to `WeOwnNetwork` (to install the Infisical GitHub App)
- The `weown-bot` PAT value to store initially

### 4.3 Step A — Create the App Connection (auth layer, one-time)

Infisical supports three connection methods for GitHub. Choose **GitHub App** (recommended); the others are fallbacks.

| Method | When to use | Pros | Cons |
|---|---|---|---|
| **GitHub App** (recommended) | You have org admin and want least-privilege, per-repo scoping | Scoped to selected repos, audit trail in GitHub, revocable centrally | Requires one-time org admin install |
| **OAuth** | You're syncing from a personal account, not an org | Quick personal setup | Tied to a user; bad for service accounts |
| **Personal Access Token (PAT)** | GitHub App install is blocked or unavailable | No org admin needed | Bound to a user's PAT; weaker audit trail |

**Steps** (GitHub App path):

1. In Infisical: **Organization → Settings → App Connections → Connect → GitHub**
2. Choose connection method: **GitHub App**
3. Click through to GitHub and install the **Infisical GitHub App** with:
   - **Install on**: the `WeOwnNetwork` organization
   - **Repository access**: choose **Only select repositories** → check `ai` (the specific repo we're syncing to). Add more repos here later as you replicate to other repos (§5).
   - **Permissions requested by Infisical** (should be read-only to metadata + read/write to Actions secrets). Approve.
4. Back in Infisical, name the App Connection: **`weown-bot GitHub App`** (this is the name you'll pick in the Secret Sync destination dropdown later).
5. Save. This App Connection is now reusable across every Secret Sync you create in this Infisical org.

> You only do Step A **once per Infisical org**, unless you later need a second App Connection for a different method (e.g., a PAT fallback).

### 4.4 Step B — Add the source secret

1. In Infisical: open project **`weown-bot GitHub PATs`**
2. Choose an environment — recommended: **`prod`** (create it if not already present). Rationale: this is the authoritative production credential.
3. Optionally create a folder/path — recommended: **`/`** root for simplicity, or **`/pats/`** if you plan to co-locate other PATs in the same project.
4. Add secret:
   - **Key**: `WEOWN_BOT_PAT__WEOWNNETWORK_AI` (full `<ORG>_<REPO>` scoping convention)
   - **Value**: the fine-grained PAT value from the `weown-bot` GitHub account
   - Set an **expiration reminder** on the secret for **14 days before the PAT's GitHub expiration** (Infisical → secret → Reminder)
5. Save.

### 4.5 Step C — Create the Secret Sync (map + push)

1. In the Infisical project: **Integrations → Secret Syncs → Create → GitHub**
2. **Step 1 — Source**:
   - **Source environment**: `prod`
   - **Source secret path**: `/` (or the path you used in Step B)
   - **Optional secret filter**: leave empty to sync all secrets in that env+path, OR specify `WEOWN_BOT_PAT__WEOWNNETWORK_AI` to sync only that one key (recommended — tighter scope)
3. **Step 2 — Destination**:
   - **App Connection**: select the `weown-bot GitHub App` you created in §4.3
   - **Scope**: choose **Repository** (not Organization, not Repository Environment) — matches the use case of a per-repo PAT for this workflow
   - **Organization**: `WeOwnNetwork`
   - **Repository**: `ai`
   - **Destination secret name mapping**: map the Infisical key `WEOWN_BOT_PAT__WEOWNNETWORK_AI` → GitHub secret name `WEOWN_BOT_PAT`. Use Infisical's key-rename / template feature so the GitHub secret is referenced as `${{ secrets.WEOWN_BOT_PAT }}` in all workflows, regardless of which repo.
4. **Step 3 — Sync options**:
   - **Initial sync behavior**: **Overwrite** (acceptable since this is the first sync and the existing value is the same token). For subsequent rotations, Infisical overwrites the GitHub value on every update.
   - **Auto-sync**: **Enabled** (sync on every source change)
   - **Import behavior / Delete behavior**: leave default — do NOT delete destination secrets that are not in source (prevents accidental removal of other repo secrets)
5. Name the Secret Sync: **`weown-bot PAT → WeOwnNetwork/ai`**
6. Save.
7. Click **Trigger Sync** (or commit a no-op change to the source secret) to force the first sync.

### 4.6 Step D — Verify

1. Go to **GitHub → WeOwnNetwork/ai → Settings → Secrets and variables → Actions**
2. You should see `WEOWN_BOT_PAT` with **Last updated = just now**
3. Push a throwaway commit to `feature/<dev>-test-infisical-sync`; the `auto-pr-to-main.yml` workflow should run, authenticate with `WEOWN_BOT_PAT`, and create a PR authored by `weown-bot`

If the secret does not appear:
- Check the Infisical Secret Sync status page for errors (right column shows last sync result)
- Verify the App Connection is still authorized (GitHub → org Settings → Applications → Installed GitHub Apps → Infisical)
- Verify the Infisical GitHub App has access to the target repo

---

## 5. Replicating `weown-bot` for Other Repos / Workflows

This section covers **adding `weown-bot` to a new repo**, including cases where the consuming workflow is NOT `auto-pr-to-main.yml`.

### 5.1 Common steps (every replication)

1. **Generate a new PAT** from the `weown-bot` GitHub account scoped **only** to the target repo:
   - `weown-bot` account → Settings → Developer settings → Personal access tokens → Fine-grained → Generate new token
   - Expiration: **90 days**
   - Resource owner: the target org (e.g., `WeOwnNetwork`)
   - Repository access: **Only select repositories** → the single target repo
   - Permissions: **minimum required** for the workflow that will consume it (see §5.2–§5.5 below)
2. **Store in Infisical** (same project, `weown-bot GitHub PATs`):
   - Secret name: `WEOWN_BOT_PAT__<ORG>_<REPO>` (uppercase, double-underscore)
   - Set expiration reminder 14 days before GitHub expiration
3. **Extend the Infisical GitHub App** to the new repo:
   - GitHub org → Settings → Applications → Installed GitHub Apps → Infisical → Configure → **Repository access** → add the new repo to the allowed list
4. **Create a new Secret Sync** in Infisical:
   - Reuse the existing App Connection (`weown-bot GitHub App`)
   - Source: the new `WEOWN_BOT_PAT__<ORG>_<REPO>` secret
   - Destination: Repository scope, new repo
   - Destination secret name: `WEOWN_BOT_PAT` (always the same at the consumption site)
5. **Verify** in the new repo's GitHub secrets
6. **Add a row** to §2.4 "Usage Table"
7. **Configure branch protection & naming enforcement** per §8 (required on every repo)
8. **Add `.github/CODEOWNERS`** with the correct team matrix for that repo

### 5.2 Variant — Auto-PR workflow (same as this repo)

Workflow: `auto-pr-to-main.yml`
- **PAT permissions needed**: `Contents: Read` + `Pull requests: R/W` + metadata (auto). `Contents: Read` is sufficient because the workflow never pushes commits via the PAT — it only clones and calls the PRs API. If your variant also pushes (e.g., auto-commits a CHANGELOG bump), upgrade to `Contents: R/W` and document the reason in your repo's ADR.
- **Issue creation** (e.g., for `pat-health-check.yml` rotation reminders): use the ephemeral per-run `GITHUB_TOKEN` with workflow-level `permissions: issues: write` — do NOT add `Issues: Write` to the PAT.
- **Copy into the new repo**: `.github/workflows/auto-pr-to-main.yml`, `.github/workflows/branch-name-check.yml`, `.github/workflows/pat-health-check.yml`
- **Adapt**:
  - Branch patterns in `auto-pr-to-main.yml` on-push triggers (if the new repo uses a different flow)
  - Reviewer usernames in `gh pr edit --add-reviewer` line per the new repo's CODEOWNERS
  - Issue labels in `pat-health-check.yml` if your team uses different labels

### 5.3 Variant — Auto-merge / release workflow

Workflow: e.g., `release-on-tag.yml` that tags, drafts GitHub releases, publishes OCI artifacts
- **PAT permissions needed**: `Contents: R/W`, `Packages: R/W` (if publishing to GHCR), `Pull requests: Read` (to read PR metadata for release notes)
- **Note**: do NOT grant `Actions: Write` or `Administration: Write` unless strictly required — these widen blast radius

### 5.4 Variant — Cross-repo trigger / dispatch workflow

Workflow: e.g., `dispatch-deploy.yml` that triggers `repository_dispatch` in a downstream repo
- **PAT permissions needed**: `Contents: Read` on source repo, `Actions: Write` on the downstream repo
- **Important**: you may need TWO PATs stored as two Infisical secrets (`WEOWN_BOT_PAT__<ORG>_<SOURCE>` and `WEOWN_BOT_PAT__<ORG>_<TARGET>`), because GitHub fine-grained PATs are scoped to a single repo set. Don't grant one PAT access to many repos — that defeats least-privilege.

### 5.5 Variant — Issue / project automation workflow

Workflow: e.g., `stale-issues.yml`, `label-issues.yml`, project board automation
- **PAT permissions needed**: `Issues: R/W`, `Pull requests: R/W` (no `Contents` write)
- **Note**: consider whether the default `GITHUB_TOKEN` suffices — for issue-only automation within the same repo, you often don't need `weown-bot` at all. Reserve the service account for **cross-repo work** or **Copilot-review-triggering PR creation**.

### 5.6 When NOT to use `weown-bot`

Use the built-in `GITHUB_TOKEN` (not `weown-bot`) when:
- The workflow only needs to write within its own repo **and** does not need Copilot auto-review on the PRs it opens
- The workflow opens PRs that you're fine being attributed to `github-actions[bot]` (no Copilot auto-review)
- You're running a read-only check / test / lint workflow

Reserve `weown-bot` for:
- PRs that must trigger Copilot AI review (`auto-pr-to-main.yml`)
- Cross-repo operations that exceed `GITHUB_TOKEN`'s default scope
- Any workflow where attribution to a named service identity improves auditability

---

## 6. PAT Rotation Procedure

**Rotation cadence**: every 90 days (PAT expiration).
**Lead post-2026-05-15**: ONE of Mohammed / Shahid / Dhruv (to be decided; see Transition Checklist §10).

### Steps (manual — GitHub does not expose PAT creation via API)

1. Log into `weown-bot` GitHub account (2FA required)
2. Navigate to Settings → Developer settings → Personal access tokens → Fine-grained
3. Click **Regenerate** on `WeOwnNetwork/ai-PR-Automation` (preserves name/permissions) — OR create new token with identical configuration
4. Set new expiration: **90 days**
5. Copy the new PAT value (displayed only once — keep the tab open until step 7)
6. Open Infisical → project `weown-bot GitHub PATs` → secret `WEOWN_BOT_PAT__WEOWNNETWORK_AI`
7. **Update value** → save → Infisical Sync pushes to GitHub within ~60s
8. **Verify** in GitHub repo Settings → Secrets → `WEOWN_BOT_PAT` "Last updated" timestamp reflects the change
9. **Test** workflow run:
   - Push a commit to a throwaway branch `fix/<dev>-test-rotation`
   - Confirm auto-PR is created by `weown-bot` with Copilot review triggered
10. **Update** §2.4 Usage Table "Last Rotated" and "Expiration" columns in this file
11. **Close** the rotation reminder issue (if opened by `pat-health-check.yml`)
12. **Log** the rotation in `/CHANGELOG.md` under the `### Changed` section for that date
13. **Commit** the `/CHANGELOG.md` + this file updates via PR (will be auto-reviewed by Copilot, approved by 2 humans)

### If the PAT has already expired

- Workflow fails with HTTP 401; auto-PRs are blocked
- **Existing PRs keep working**; only new PR creation is affected
- Follow the same 13 steps above — no special handling needed
- RTO: **1 hour** (procedure runs in ~15 minutes including testing)

---

## 7. PAT Alert Stack

**Defense in depth** — three independent layers ensure rotation is never missed.

### Layer 1: GitHub Native Email

- **Trigger**: 7 days before PAT expiration
- **Recipient**: email on `weown-bot` GitHub account (currently temp `roman@weown.email`; Yonks providing permanent bot email)
- **Action**: email owner executes rotation procedure

### Layer 2: Infisical Secret Expiration Reminder

- **Trigger**: 14 days before rotation date (configured on the Infisical secret)
- **Recipient**: email + dashboard alert to project admins in Infisical Pro
- **Action**: project admin executes rotation procedure

### Layer 3: Scheduled `pat-health-check.yml`

- **Trigger**: weekly cron (Mondays 09:00 UTC) + manual dispatch
- **Action**:
  - Calls GitHub API using `WEOWN_BOT_PAT` to verify token validity and expiration
  - Opens an issue titled `[PAT ROTATION] WEOWN_BOT_PAT expires in <N> days` if ≤ 14 days
  - Labels: `security`, `pat-rotation`, `weown-bot`
  - Hard-fails the workflow run (`exit 1`) if ≤ 3 days, so the failure is visible in Actions tab
- **Owner**: Infrastructure team (`@ncimino` + current stewards)

### Rationale

GitHub's own alert is often missed because it goes to an email box that may not be monitored daily. Infisical adds a second layer. The scheduled Action adds a third layer that cannot be ignored — it opens a GitHub issue in the repo, visible to reviewers and in the PR workflow.

---

## 8. Required Branch Protection & Naming Enforcement

### 8.1 Branch Ruleset on `main` (configured 2026-04-23)

**Configured via** Settings → Rules → Rulesets → `main` (active). Rulesets are preferred over the legacy Branch Protection Rules UI because they provide org-wide reuse, explicit bypass lists, and granular rule composition.

**Target**: `main` branch. Enforcement: **Active**. Bypass list: **empty**.

**Enabled rules** (all must remain on; each maps to a specific compliance control — see `.github/ADR-003-main-branch-ruleset.md`):

| # | Rule | Compliance control |
|---|---|---|
| 1 | **Require a pull request before merging** with **2 reviewers** | SOC 2 CC6.3; CIS 16.9; NIST PR.AC-4 |
| 2 | **Dismiss stale pull request approvals when new commits are pushed** | SOC 2 CC8.1 (change management integrity) |
| 3 | **Require review from Code Owners** (enforces `.github/CODEOWNERS`) | SOC 2 CC6.3; ISO 27001 A.5.15 |
| 4 | **Require approval of the most recent reviewable push** | Closes approve-then-sneak-bad-commit race condition |
| 5 | **Require conversation resolution before merging** | SOC 2 CC8.1 (every Copilot comment addressed or explicitly deferred) |
| 6 | **Require signed commits** | ISO 27001 A.8.24; SOC 2 CC6.1 (cryptographic authorship) |
| 7 | **Require status checks to pass before merging** (see 7a) | SOC 2 CC7.1; NIST DE.CM |
| 7a | **Required status check**: `Validate Branch Name` (from `branch-name-check.yml`) | Enforces branch naming regex at PR time |
| 8 | **Require branches to be up to date before merging** | Tests against latest `main`; prevents stale-merge surprises |
| 9 | **Require code quality results at warning and higher** | Satisfied by **CodeQL Default Setup** (configured 2026-04-21; scans JS/TS/Python/Actions weekly + on-push + on-PR) |
| 10 | **Automatically request Copilot code review on new pushes and draft PRs** | AI-assisted review depth (ISO/IEC 42001 Annex A.6.2.7 AI-aware controls) |
| 11 | **Restrict deletions** | Protects `main` from accidental/malicious deletion |
| 12 | **Block force pushes** | SOC 2 CC7.1 (audit trail immutability) |

**Not enabled (intentional)**:

- **Require linear history** — team allows merge commits for context preservation
- **Separate "Restrict who can push"** rule — not exposed in the new Rulesets UI; effectively covered by "Require a pull request" + empty bypass list (no direct pushes possible)
- **Require code scanning results** — distinct from #9 above; this specific rule requires SARIF via the Code Scanning API. #9 above covers Code Quality via the Code Quality API, which CodeQL Default Setup satisfies.

**Rationale for empty bypass list**: Under SOC 2 CC6.3 and ISO 27001 A.5.15, reviewers and approvers must be subject to the same controls as contributors. An empty bypass list is the mechanical equivalent of "Include administrators" in the legacy Branch Protection UI. Any ruleset edit by an org owner is captured in the org audit log (retention per GitHub Enterprise plan — verify per `.github/ADR-003`).

**Interaction with workflows**:

- `auto-pr-to-main.yml` runs `gh pr edit --add-reviewer` to *request* a specific reviewer — this is a suggestion, not enforcement.
- The ruleset's "2 reviewers + Code Owners review" is the *enforcement* layer. Both are needed: request for discoverability, ruleset for gating.
- `branch-name-check.yml` is the only workflow currently required as a status check. `pat-health-check.yml` runs on `schedule:` so it cannot be a PR-time required status check; it surfaces red-X independently in the Actions tab when the PAT is ≤3 days from expiration.

### 8.2 Branch Naming Enforcement

**Convention**: `<type>/<dev>-<description>` — see §3.

**Enforcement layers** (both required):

1. **`.github/workflows/branch-name-check.yml`** (portable, plan-agnostic)
   - Triggers on every push (except `main` / `experimental/**`) and every PR event
   - Validates branch against regex: `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`
   - Description segment requires 3+ alphanumeric chars before any hyphen suffix (prevents meaningless names like `feature/ab-a`)
   - Fails the workflow on non-conforming names with clear remediation guidance
   - Must be added as a **required status check** in the `main` branch ruleset so non-conforming branches cannot be merged

2. **GitHub Ruleset — Restrict Branch Creation** (optional, if available on your plan)
   - Settings → Rules → Rulesets → New ruleset
   - Enforcement status: **Active**
   - Target: **All branches**
   - Bypass list: empty (no bypass)
   - Rule: **Restrict creations** and **Restrict updates**
   - In "Restrict creations", allow only refs matching any of:
     - `refs/heads/main`
     - `refs/heads/feature/**`
     - `refs/heads/fix/**`
     - `refs/heads/docs/**`
     - `refs/heads/hotfix/**`
   - **Note**: GitHub's UI-based Rulesets (as of 2026-04) do not expose a regex pattern matcher for the `<dev>-<description>` segment. This layer blocks the wrong **type prefix** at creation time; layer 1 (the workflow) catches everything else, including the `<dev>-` segment and character-class violations.

Together these two layers ensure:
- Branches with the wrong prefix are rejected at creation (ruleset) OR at the status-check gate (workflow)
- Branches with the right prefix but wrong dev/description format fail the status check and cannot be merged to `main`

---

## 9. Reviewer Rotation Procedure

Triggered when a CODEOWNERS path's primary reviewer changes (e.g., Roman → Mohammed for `/anythingllm/`).

1. **Update CODEOWNERS**: replace `@romandidomizio` with the new specialist on the affected paths (per-path assignment — pending decision by `@ncimino` + `@romandidomizio` before 2026-05-15)
2. ~~Replace `@<name>-TODO` placeholders with real GitHub usernames~~ ✅ **done 2026-04-23** (v3.3.4.2): `@iamwaseem18`, `@mshahid538`, `@dhruvmalik007`. `@YonksTEAM` added to CODEOWNERS header as executive stakeholder (not a path reviewer — avoids notification noise).
3. **Update workflow reviewer list** in `auto-pr-to-main.yml`:
   ```bash
   gh pr edit "$pr_number" --add-reviewer ncimino,<new-specialist>
   ```
   - `@ncimino` always stays in the list
4. **Verify branch protection** requires 2 approvals + Code Owners review (§8)
5. **Document** the change in `/CHANGELOG.md`

---

## 10. Transition Checklist 2026-05-15

**Roman's departure date**: May 15, 2026.
**PAT expiration (scoped to `WeOwnNetwork/ai`)**: **July 22, 2026** (90 days from 2026-04-23 issuance; ~2 months after Roman leaves).
**Implication**: full handoff must complete before May 15.

| # | Item | Action | Owner |
|---|---|---|---|
| 1 | **PAT stewardship** | Assign ONE of Mohammed/Shahid/Dhruv as the primary PAT rotation lead | `@romandidomizio` + `@ncimino` |
| 2 | **`weown-bot` account access** | Transfer 2FA administration per internal runbook to enterprise admin + rotation lead | `@romandidomizio` + `@YonksTEAM` |
| 3 | **Bot email** | Replace temp `roman@weown.email` with permanent bot email | Yonks |
| 4 | **CODEOWNERS update** | Replace `@romandidomizio` with per-path specialists (per-path decision pending). Placeholder handles ✅ replaced 2026-04-23 with `@iamwaseem18` / `@mshahid538` / `@dhruvmalik007`. | `@romandidomizio` + `@ncimino` |
| 5 | **Workflow reviewer update** | Update `gh pr edit --add-reviewer` line in `auto-pr-to-main.yml` to reflect new specialist per the paths being changed | New rotation lead |
| 6 | **Infisical project access** | Transfer admin role on project `weown-bot GitHub PATs` to rotation lead + Yonks | `@romandidomizio` + Yonks |
| 7 | **Branch protection check** | Verify `main` branch protection still enforces 2 reviewers + review from Code Owners | `@ncimino` |
| 8 | **Alert routing** | Update GitHub native email recipient for `weown-bot` to rotation lead's email | New rotation lead |
| 9 | **Knowledge transfer session** | Walk rotation lead through the full rotation procedure (§6) live | `@romandidomizio` |
| 10 | **Documentation review** | Rotation lead reads this README, ADR-001, ADR-002, SECURITY_ASSESSMENT, INCIDENT_RESPONSE, COMPLIANCE_ROADMAP end-to-end | Rotation lead |

### Automated Safety Nets (in place regardless of handoff)

- `pat-health-check.yml` will open a GitHub issue 14 days before PAT expires — visible to all reviewers
- Infisical reminder emails project admins 14 days before rotation date
- GitHub native email warns 7 days before

These three layers protect against short-term gaps even if human handoff is imperfect.

---

## 11. Related Documents

- `.github/copilot-instructions.md` — Copilot AI review directives (phase-aware per `COMPLIANCE_ROADMAP.md`)
- `.github/ADR-001-service-account-pat.md` — Why service account + PATs (not a GitHub App)
- `.github/ADR-002-infisical-github-sync.md` — Why Infisical primary via GitHub Sync
- `.github/SECURITY_ASSESSMENT.md` — Threat model, risk register, mitigations
- `.github/INCIDENT_RESPONSE.md` — Incident scenarios, RTO/RPO, runbooks
- `.github/CODEOWNERS` — Review assignment + post-2026-05-15 handoff TODOs
- `.github/CI_CD_WORKFLOWS.md` — Broader CI/CD strategy (validation workflows, not auto-PR)
- `docs/COMPLIANCE_ROADMAP.md` — Multi-phase compliance strategy (NIST/CIS/CSA/ISO/SOC 2/ISO 42001)
- `/CHANGELOG.md` — Repository-level change history
