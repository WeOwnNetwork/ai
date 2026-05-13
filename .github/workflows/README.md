# GitHub Actions Workflows — WeOwnNetwork/ai

**Scope**: Authoritative reference for all workflows in `.github/workflows/`, the ecosystem-wide `weown-bot` service account, PAT rotation, alert stack, and the 2026-05-15 transition checklist.

**Version**: v3.3.5.1 (#WeOwnVer)
**Last updated**: 2026-04-28
**Owners**: `@ncimino` + `@romandidomizio` (post-2026-05-15: Mohammed/Shahid/Dhruv — see CODEOWNERS)

---

## Table of Contents

1. [Workflow Inventory](#1-workflow-inventory)
2. [`weown-bot` Ecosystem Service Account](#2-weown-bot-ecosystem-service-account)
   - [2A. What `auto-pr-to-main.yml` Does (Step-by-Step)](#2a-what-auto-pr-to-mainyml-does-step-by-step)
3. [Branch Naming Convention & Developer Attribution](#3-branch-naming-convention--developer-attribution)
4. [Infisical GitHub Sync — Initial Setup](#4-infisical-github-sync--initial-setup)
5. [Replicating `weown-bot` for a New Repository](#5-replicating-weown-bot-for-a-new-repository)
6. [PAT Rotation Procedure](#6-pat-rotation-procedure)
7. [PAT Alert Stack](#7-pat-alert-stack)
8. [Required Branch Protection & Naming Enforcement](#8-required-branch-protection--naming-enforcement)
9. [Reviewer Rotation Procedure](#9-reviewer-rotation-procedure)
10. [Transition Checklist 2026-05-15](#10-transition-checklist-2026-05-15)
11. [Troubleshooting — Symptom → Cause → Verification](#11-troubleshooting--symptom--cause--verification)
12. [Related Documents](#12-related-documents)

---

## 1. Workflow Inventory

| Workflow | Trigger | Purpose | Owner |
|---|---|---|---|
| `auto-pr-to-main.yml` | push to `feature/*`, `fix/*`, `docs/*`, `hotfix/*` | Creates/updates PR to `main` authored by `weown-bot`; triggers Copilot review; auto-assigns 1 human reviewer (`@ncimino`) with optional second reviewers at `@ncimino`'s discretion | Infra team |
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
3. **Centralized storage** — all PATs in one Infisical project: **`weown-bot GitHub PATs`**, with one folder per target repo (e.g., `/WeOwnNetwork-ai`)
4. **Consistent naming** (revised 2026-04-28 per ADR-002 Decision Log — see §6.1):
   - Infisical secret (per folder): `WEOWN_BOT_PAT` (identity-mapped; the Sync's Key Schema is `{{secretKey}}` identity transform and cannot strip prefixes/suffixes)
   - Namespace across repos: **folder-per-repo** inside the shared project (`/WeOwnNetwork-ai`, `/<ORG>-<REPO>`, …); the Sync's Source Path scopes each Sync to a single folder
   - GitHub Actions secret (per repo): `WEOWN_BOT_PAT` (always the same name at consumption site)
5. **Documented usage** — authoritative table in §2.4 below
6. **Human oversight** — every auto-PR gets 2 required human reviewers (branch protection, §8)
7. **2FA mandatory** on the account + Infisical
8. **No direct commit access** — bot only opens PRs; branch protection prevents direct pushes to `main`

### Account Security Requirements

- ✅ 2FA mandatory (administration, recovery, and custody tracked per internal runbook — no credential details in this public repo)
- ✅ Unique email (service account email managed per internal runbook; rotation + transfer tracked internally, not in this public repo)
- ✅ No direct commit access to protected branches
- ✅ Enterprise-managed — member of `WeOwnNetwork` org, not a free-floating account
- ✅ Documented ownership and transition plan (this file + CODEOWNERS + ADR-001)

### 2.4 Usage Table (authoritative)

| Org / Repo | Workflows Automated | PAT Secret (Infisical) | PAT Scope (GitHub) | Expiration | Last Rotated | Owner |
|---|---|---|---|---|---|---|
| `WeOwnNetwork/ai` | `auto-pr-to-main.yml`, `pat-health-check.yml`, `branch-name-check.yml` | `WEOWN_BOT_PAT` (Infisical project: `weown-bot GitHub PATs`, folder: `/WeOwnNetwork-ai`) | Contents: R, PRs: R/W, metadata | 2026-07-27 | 2026-04-28 | `@romandidomizio` → TODO(2026-05-15): Mohammed/Shahid/Dhruv |
| _placeholder_ `WeOwnNetwork/<next-repo>` | _TBD_ | `WEOWN_BOT_PAT` (Infisical project: `weown-bot GitHub PATs`, folder: `/WeOwnNetwork-<next>`) | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| _placeholder_ `<future-org>/<repo>` | _TBD_ | `WEOWN_BOT_PAT` (Infisical project: `weown-bot GitHub PATs`, folder: `/<ORG>-<REPO>`) | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

> **Update this table** whenever `weown-bot` is enabled on a new repo or whenever a PAT is rotated.
>
> **PAT scope rationale** (NIST PR.AC-3 / CIS 5.4, least privilege):
> - `Contents: Read` — sufficient because no workflow pushes commits via the PAT. Developers push from local; workflows only clone + call the PRs API.
> - `Pull requests: R/W` — required by `auto-pr-to-main.yml` (`gh pr create`, `gh pr edit --body-file`, `gh pr edit --add-reviewer`).
> - `Metadata: Read` (auto) — required by GitHub for any fine-grained PAT.
> - **Not on the PAT**: `Issues: Write`. `pat-health-check.yml` opens/edits rotation reminder issues using the ephemeral per-run `GITHUB_TOKEN` (workflow-level `permissions: issues: write`), which expires at job end. This keeps the 90-day PAT minimally scoped; if a new workflow needs issue write via the PAT, document the change here and in ADR-001.
> - **Adding scopes**: treat as a reviewed governance change — update ADR-001 §Decision key property 3, this table, `SECURITY_ASSESSMENT.md`, and `CHANGELOG.md` in the same PR.

---

## 2A. What `auto-pr-to-main.yml` Does (Step-by-Step)

This section is the authoritative narrative walkthrough of `auto-pr-to-main.yml`. Each numbered step corresponds to the numbered comment banners in the workflow source so contributors can cross-reference line-by-line.

### Trigger matrix

| Trigger | When it fires | Purpose |
|---|---|---|
| `on: push` (branches: `feature/*`, `fix/*`, `docs/*`, `hotfix/*`) | Every push to a convention-conforming branch | Primary path: create-or-update PR to `main` |
| `on: workflow_dispatch` | Manual click from Actions tab | Re-run debugging / refresh PR body after secret / ruleset changes without needing an empty commit |
| `concurrency: group: auto-pr-${{ github.ref }}, cancel-in-progress: true` | Multiple rapid pushes on same branch | Cancels older in-flight runs; only latest creates / updates PR |

### Step-by-step walkthrough

| # | Banner | What it does | Failure modes |
|---|---|---|---|
| **1** | Defense-in-depth branch-name regex | Re-validates the `^(feature\|fix\|docs\|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$` regex even though `branch-name-check.yml` runs first. Safe no-op on `main` / unconventional branches (exits 0). | Branch name doesn't match regex → workflow exits 0 silently. Verify with `echo "$BRANCH_NAME"` in Actions log. |
| **2** | Canonicalize refs | Resolves `SOURCE_REF` + `TARGET_BRANCH` from env context; handles tag/branch/SHA ambiguity. | Ref resolution failure → `git rev-parse` errors. Check `github.ref` + `github.ref_name` in Actions logs. |
| **3** | Blob-base URL | Builds `${BLOB_BASE}=https://github.com/$GITHUB_REPOSITORY/blob/$TARGET_BRANCH` for absolute doc links in the PR body. | Always succeeds (pure string concat). |
| **4** | `mktemp` temp files | Creates `$PR_BODY`, `$PR_TITLE`, `$CONTRIBUTORS_FILE` in `$TEMP_DIR` (NEVER `/tmp`; WeOwn security policy). `trap rm -f` on EXIT. | Disk full (unlikely on runner). Temp files not cleaned up if workflow is killed before trap fires. |
| **5** | PR title from latest commit | Parses latest commit subject (`git log -1 --format=%s`) for PR title. Falls back to `Merge <branch> into <target>` if no commits or subject parsing fails. | Empty commit history → fallback path. |
| **6** | Three-tier attribution — `Opened by:` + `Last pushed by:` | `Opened by:` resolved via `git rev-list --reverse | head -n 1` → `gh api /repos/.../commits/{first-sha} --jq .author.login`, with fallbacks `.committer.login` then `LAST_PUSHED_BY`. `Last pushed by:` = `${{ github.triggering_actor || github.actor }}`. Stable-vs-mutable split so the PR body shows both who started and who most recently pushed. | `gh api` rate-limited → check `WEOWN_BOT_PAT` rate-limit status / scopes / rotation state (the workflow runs all `gh` calls under `GH_TOKEN=${{ secrets.WEOWN_BOT_PAT }}`, not the ephemeral `GITHUB_TOKEN`). Unlinked email → null login → falls through to last-pusher. |
| **7** | Contributors aggregation | For each commit SHA in the branch range: `gh api /repos/.../commits/$sha --jq '.author.login // .committer.login // ""'`. Non-empty → `@login`. Empty → fallback to `git log -1 --format=%an` (NAME ONLY — no email, PII-safe). Then `sort | uniq -c | sort -rn | awk` to produce `- @handle (N commits)` with correct plural / singular rendering. `awk` (not `read -r count handle`) is used so multi-word names like `Jane Doe` aren't truncated to `Jane`. | `gh api` rate-limited → per-commit fallback fires; result is still valid names-with-counts. |
| **8** | PR body build | Shell `{ echo ...; cat $CONTRIBUTORS_FILE; echo ...; git log ...; }` → `$PR_BODY` file. Includes NIST CSF 2.0 review checklist, Recent Commits (full bodies for Copilot AI context; `%an` only — no email), and Copilot auto-review note. | `head -c 60000` truncates long commit histories; reviewers can still click through to the commit list in the UI. |
| **9** | Create-or-update PR (idempotent) | `gh pr list --head $BRANCH_NAME --state open --json number --jq '.[0].number'`. If found → `gh pr edit $N --body-file $PR_BODY` (preserves the existing title — PR titles are set once at creation, not refreshed on subsequent pushes), followed by a separate `gh pr edit $N --add-reviewer ncimino,romandidomizio`. If not → `gh pr create --base main --head $BRANCH_NAME --title $(cat $PR_TITLE) --body-file $PR_BODY` followed by the same `--add-reviewer` call. Same reviewer assignment in both paths. | PAT invalid → `Bad credentials (HTTP 401)`. Missing `pull_request:write` scope → `HTTP 403`. |

### Why the team benefits

- **SOC 2 CC8.1 evidence at a glance** — every PR body has three independent attribution views (opener, last pusher, per-commit contributors). No more "who owns this PR?" ambiguity during audits.
- **Zero-friction onboarding** — new contributors add themselves to the Known contributor handles table in `CONTRIBUTING.md` §4; the workflow picks up attribution automatically on their first push. No workflow edits; no case-statement maintenance.
- **Copilot AI review quality** — Recent Commits section embeds full commit bodies (not just subjects) into the PR description so Copilot has full rationale context when reviewing.
- **Production-grade defense-in-depth** — branch-name regex enforced in both `branch-name-check.yml` and step 1 of this workflow; `non_fast_forward` enforced by both Layer 1 (repo) and Layer 2 (enterprise) rulesets (see [ADR-004](../ADR-004-copilot-auto-review-ruleset.md)); `mktemp` not `/tmp`; emails stripped from PR body (PII minimization).

### Failure modes & signatures (quick reference)

Consolidated in [§11 Troubleshooting](#11-troubleshooting--symptom--cause--verification).

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
| **PR body `Contributors on this branch:` list** | GitHub @handles with commit counts | `- @romandidomizio (4 commits)` | Complete attribution audit trail; supports per-contributor review load assessment |

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
3. **Create a folder per target repo** — for this repo, create **`/WeOwnNetwork-ai`**. Going forward, every new repo onboarded to `weown-bot` gets its own sibling folder (e.g., `/WeOwnNetwork-<next-repo>`, `/<ORG>-<REPO>`). This is the namespacing axis — NOT the secret name (the Sync's Key Schema is `{{secretKey}}` identity transform; see §6.1).
4. Inside the `/WeOwnNetwork-ai` folder, add secret:
   - **Key**: `WEOWN_BOT_PAT` (identity-mapped — NO `__<ORG>_<REPO>` suffix; folder scoping replaces the old suffix convention per the 2026-04-28 ADR-002 Decision Log revision)
   - **Value**: the fine-grained PAT value from the `weown-bot` GitHub account
   - Set an **expiration reminder** on the secret for **14 days before the PAT's GitHub expiration** (Infisical → secret → Reminder)
5. Save.

### 4.5 Step C — Create the Secret Sync (map + push)

1. In the Infisical project: **Integrations → Secret Syncs → Create → GitHub**
2. **Step 1 — Source**:
   - **Source environment**: `prod`
   - **Source secret path**: `/WeOwnNetwork-ai` (the per-repo folder you created in §4.4; this is the scoping axis — every future repo's Sync uses its own sibling folder path, e.g., `/WeOwnNetwork-<next-repo>`)
   - **Optional secret filter**: leave empty — the folder already scopes the Sync to this repo's single `WEOWN_BOT_PAT` secret
3. **Step 2 — Destination**:
   - **App Connection**: select the `weown-bot GitHub App` you created in §4.3
   - **Scope**: choose **Repository** (not Organization, not Repository Environment) — matches the use case of a per-repo PAT for this workflow
   - **Organization**: `WeOwnNetwork`
   - **Repository**: `ai`
4. **Step 3 — Sync options** (see §6.1 for the full rationale table):
   - **Initial Sync Behavior**: **Overwrite Destination Secrets** (forced — only supported option)
   - **Key Schema**: **`{{secretKey}}`** (identity transform — the Infisical key `WEOWN_BOT_PAT` passes through unchanged to the GitHub secret name `WEOWN_BOT_PAT`; the Key Schema CANNOT strip prefixes/suffixes, only add them, which is why the source secret must already be named `WEOWN_BOT_PAT` and namespacing uses folder paths instead)
   - **Disable Secret Deletion**: **Yes** (defense-in-depth; prevents Infisical-side accidental deletion from cascading to a GitHub secret deletion that would break `auto-pr-to-main.yml` until the next rotation)
   - **Auto-Sync Enabled**: **Yes** (rotation source-of-truth pattern — mandatory)
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
2. **Store in Infisical** (shared project, folder-per-repo):
   - Open the shared Infisical project **`weown-bot GitHub PATs`** (the same project every repo's PAT lives in — one project for the entire ecosystem)
   - **Create a new folder** at the `prod` environment root named for the target repo (convention: `/<ORG>-<REPO>`, e.g., `/WeOwnNetwork-<next>`). The folder path IS the namespacing axis — it scopes the Sync to this repo's secret only.
   - Inside that folder, add secret with key `WEOWN_BOT_PAT` (identity-mapped; NO `__<ORG>_<REPO>` suffix). The original ADR-002 design used one shared project with secret-name suffixes (`WEOWN_BOT_PAT__<ORG>_<REPO>`), but that pattern is unworkable because Infisical's GitHub Sync Key Schema is identity-only and cannot strip prefixes/suffixes (see ADR-002 Decision Log 2026-04-28).
   - Set expiration reminder 14 days before GitHub expiration
3. **Extend the Infisical GitHub App** to the new repo:
   - GitHub org → Settings → Applications → Installed GitHub Apps → Infisical → Configure → **Repository access** → add the new repo to the allowed list
4. **Create a new Secret Sync** in Infisical (one Sync per folder / per target repo):
   - Reuse the existing **`weown-bot GitHub App`** App Connection (created once per Infisical org in §4.3)
   - **Source Path**: `/<ORG>-<REPO>` (the folder you just created — this is what scopes the Sync to this repo only; sibling folders are untouched)
   - **Source secret**: `WEOWN_BOT_PAT` (identity-mapped; single secret in the folder)
   - **Destination**: Repository scope → new repo
   - **Sync Options** — see [§6.1 Sync Options Configuration](#61-sync-options-configuration) for full rationale; summary:
     - Initial Sync Behavior: **Overwrite Destination Secrets** (forced — only option)
     - Key Schema: **`{{secretKey}}`** (identity transform; secret syncs as-is, no prefix added)
     - Disable Secret Deletion: **Yes** (defense-in-depth; prevents Infisical-side accidental deletion from cascading to GitHub)
     - Auto-Sync Enabled: **Yes** (rotation source-of-truth pattern — mandatory)
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
6. Open Infisical → project **`weown-bot GitHub PATs`** → folder **`/WeOwnNetwork-ai`** → secret `WEOWN_BOT_PAT` (renamed 2026-04-28 from legacy `WEOWN_BOT_PAT__WEOWNNETWORK_AI` per ADR-002 Decision Log; namespacing shifted from secret-name suffixes to folder paths in the same shared project)
7. **Update value** → save → Infisical Sync pushes to GitHub within ~60s
8. **Verify** in GitHub repo Settings → Secrets → `WEOWN_BOT_PAT` "Last updated" timestamp reflects the change
9. **Test** workflow run:
   - Push a commit to a throwaway branch `fix/<dev>-test-rotation`
   - Confirm auto-PR is created by `weown-bot` with Copilot review triggered
10. **Update** §2.4 Usage Table "Last Rotated" and "Expiration" columns in this file
11. **Close** the rotation reminder issue (if opened by `pat-health-check.yml`)
12. **Log** the rotation in `/CHANGELOG.md` under the `### Changed` section for that date
13. **Commit** the `/CHANGELOG.md` + this file updates via PR (will be auto-reviewed by Copilot, approved by 1 human)

### 6.1 Sync Options Configuration

The Infisical → GitHub Secret Sync requires specific options for the `weown-bot` rotation pattern. Set these at sync creation time (or update an existing sync via Infisical UI → Sync details → Sync Options).

| Option | Value | Rationale |
|---|---|---|
| **Initial Sync Behavior** | Overwrite Destination Secrets | Forced — only option GitHub Sync supports. Acceptable because Infisical is the source of truth (per ADR-002). |
| **Key Schema** | `{{secretKey}}` (identity transform) | The Key Schema can ADD prefixes/suffixes around `{{secretKey}}` but cannot STRIP them. To get GitHub destination name `WEOWN_BOT_PAT`, the Infisical secret MUST already be named `WEOWN_BOT_PAT` (no `__<ORG>_<REPO>` suffix). Use Infisical's **folder structure** (one folder per target repo inside the shared `weown-bot GitHub PATs` project, scoped via the Sync's Source Path) for cross-repo namespacing instead of secret-name suffixing. |
| **Disable Secret Deletion** | **Yes** (set to "yes" / disable) | Defense-in-depth. Prevents an accidental Infisical-side deletion from cascading to a GitHub secret deletion (which would break `auto-pr-to-main.yml` until the next rotation). Trade-off: intentional deletions in Infisical require a manual cleanup pass in GitHub. For our single-secret-per-sync pattern this is preferred. |
| **Auto-Sync Enabled** | **Yes** | The whole point of the integration is that Infisical is the rotation source of truth. Disabling auto-sync would require a manual sync trigger after every rotation, defeating the purpose and re-introducing the drift class documented in [§11](#11-troubleshooting) ("GitHub Secret `WEOWN_BOT_PAT` drifts from Infisical stored value"). |

**Naming convention update (2026-04-28, captured in ADR-002 Decision Log)**: the original ADR-002 architecture used `WEOWN_BOT_PAT__<ORG>_<REPO>` as the Infisical secret name, with the assumption that the GitHub Sync UI exposed a per-secret rename feature at sync-config time. **It does not.** The Key Schema is the only source-to-destination transform, and it cannot strip prefixes. Therefore the Infisical secret name must equal the desired GitHub destination name. To namespace across repos in the ecosystem, create a **folder per target repo** inside the shared `weown-bot GitHub PATs` Infisical project (e.g., `/WeOwnNetwork-ai`, `/<ORG>-<REPO>`, …), each holding one identity-mapped `WEOWN_BOT_PAT` secret + one Sync integration whose Source Path is the folder.

**Why folder-per-repo, not project-per-repo**: the 2026-04-28 ADR-002 Decision Log initially documented a project-per-repo pattern (one Infisical project per target repo). That still works, but folder-per-repo inside the existing shared project is operationally cleaner: (a) one project-level RBAC boundary to manage instead of N; (b) one expiration-reminder convention to maintain; (c) sibling folders discoverable from the same project landing page; (d) existing Infisical "GitHub PATs" project can absorb new repos without new project creation. Both patterns produce identical Sync Options — only the Source Path differs (project root `/` vs. per-repo `/<ORG>-<REPO>`). Choose folder-per-repo unless you need project-level RBAC isolation (rare for PAT-only secrets).

**Migration steps for the existing `WeOwnNetwork/ai` PAT (2026-04-28)**:

1. In the shared Infisical project **`weown-bot GitHub PATs`**, **create folder** `/WeOwnNetwork-ai` at the `prod` environment root (if not already present).
2. **Add secret** `WEOWN_BOT_PAT` (no suffix) inside that folder with the freshly-regenerated PAT value.
3. **Delete or archive** the legacy `WEOWN_BOT_PAT__WEOWNNETWORK_AI` secret in the project root once the new Sync is verified green.
4. **Update the GitHub Sync's Source Path** to `/WeOwnNetwork-ai` (was `/`); confirm Sync Options per the table above (Initial Sync Behavior = Overwrite; Key Schema = `{{secretKey}}`; Disable Secret Deletion = Yes; Auto-Sync Enabled = Yes).
5. **Verify** in the GitHub repo Settings → Secrets → `WEOWN_BOT_PAT` "Last updated" timestamp reflects the sync.
6. **Test** by dispatching `pat-health-check.yml` manually — a green run confirms the new PAT authenticates as `weown-bot`.

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
- **Recipient**: email on `weown-bot` GitHub account (managed per internal runbook)
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
| 1 | **Require a pull request before merging** with **1 reviewer** | SOC 2 CC6.3; CIS 16.9; NIST PR.AC-4 |
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
- The ruleset's "1 reviewer + Code Owners review" is the *enforcement* layer. Both are needed: request for discoverability, ruleset for gating.
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

1. **Update CODEOWNERS**: assign the new specialist to the affected paths — `@ncimino` remains as universal reviewer on all paths. ✅ **done 2026-05-15** (PR #17): `@romandidomizio` and `@dhruvmalik007` removed; `@ncimino` is now sole assigned reviewer; `@iamwaseem18`/`@mshahid538` assignable at `@ncimino`'s discretion.
2. ~~Replace `@<name>-TODO` placeholders with real GitHub usernames~~ ✅ **done 2026-04-23** (v3.3.4.2): `@iamwaseem18`, `@mshahid538`. `@YonksTEAM` added to CODEOWNERS header as executive stakeholder (not a path reviewer — avoids notification noise).
3. **Update workflow reviewer list** in `auto-pr-to-main.yml`:
   ```bash
   gh pr edit "$pr_number" --add-reviewer ncimino
   ```
   - `@ncimino` always stays in the list
4. **Verify branch protection** requires 1 approval + Code Owners review (§8)
5. **Document** the change in `/CHANGELOG.md`

---

## 10. Transition Checklist 2026-05-15

**Roman's departure date**: May 15, 2026.
**PAT expiration (scoped to `WeOwnNetwork/ai`)**: **July 22, 2026** (90 days from 2026-04-23 issuance; ~2 months after Roman leaves).
**Implication**: full handoff must complete before May 15.

| # | Item | Action | Owner |
|---|---|---|---|
| 1 | **PAT stewardship** | ✅ `@ncimino` is primary PAT rotation lead as of 2026-05-15. `@iamwaseem18`/`@mshahid538` available as secondary at `@ncimino`'s discretion. | `@ncimino` |
| 2 | **`weown-bot` account access** | Transfer 2FA administration per internal runbook to enterprise admin + rotation lead | `@YonksTEAM` |
| 3 | **Bot email** | Update the service account's email to the permanent bot email (details tracked per internal runbook) | `@YonksTEAM` |
| 4 | **CODEOWNERS update** | ✅ done 2026-05-15 (PR #17): `@romandidomizio` removed from all paths; `@ncimino` is sole assigned reviewer. | `@ncimino` |
| 5 | **Workflow reviewer update** | ✅ done 2026-05-15 (PR #17): `--add-reviewer ncimino` only (was `ncimino,romandidomizio`). | `@ncimino` |
| 6 | **Infisical project access** | Transfer admin role on project `weown-bot GitHub PATs` to rotation lead + `@YonksTEAM` | `@YonksTEAM` |
| 7 | **Branch protection check** | Verify `main` branch protection enforces 1 reviewer + Code Owners review | `@ncimino` |
| 8 | **Alert routing** | Update GitHub native email recipient for `weown-bot` to rotation lead's email | New rotation lead |
| 9 | **Knowledge transfer session** | Walk rotation lead through the full rotation procedure (§6) live | `@ncimino` |
| 10 | **Documentation review** | Rotation lead reads this README, ADR-001, ADR-002, SECURITY_ASSESSMENT, INCIDENT_RESPONSE, COMPLIANCE_ROADMAP end-to-end | Rotation lead |

### Automated Safety Nets (in place regardless of handoff)

- `pat-health-check.yml` will open a GitHub issue 14 days before PAT expires — visible to all reviewers
- Infisical reminder emails project admins 14 days before rotation date
- GitHub native email warns 7 days before

These three layers protect against short-term gaps even if human handoff is imperfect.

---

## 11. Troubleshooting — Symptom → Cause → Verification

Consolidated reference for the most common failure signatures across all workflows (`auto-pr-to-main.yml`, `branch-name-check.yml`, `pat-health-check.yml`). For workflow-specific failure modes see also [§2A "What `auto-pr-to-main.yml` Does"](#2a-what-auto-pr-to-mainyml-does-step-by-step) and [ADR-004](../ADR-004-copilot-auto-review-ruleset.md).

| Symptom | Likely cause | First-response verification |
|---|---|---|
| **PAT / authentication** |  |  |
| `fatal: could not read Username for 'https://github.com'` | PAT invalid / expired / revoked | Dispatch `PAT Health Check` workflow manually; inspect output |
| `Bad credentials (HTTP 401)` | Same as above | Verify GitHub Secret `WEOWN_BOT_PAT` matches Infisical stored value; if drift → follow [§6](#6-pat-rotation-procedure) |
| `Resource not accessible by integration (HTTP 403)` | PAT missing fine-grained scopes | Regenerate PAT with ONLY the required least-privilege scopes: `Contents: Read`, `Pull requests: Read/Write`, `Metadata: Read` (see [§2.4 Usage Table](#24-usage-table-authoritative) and [ADR-001](../ADR-001-service-account-pat.md)). Do NOT add `Issues: Write` to the PAT — issue actions run under the ephemeral `GITHUB_TOKEN` via `permissions: issues: write` on the workflow job. |
| `PAT Health Check` alerts 14-day countdown | Normal — rotation reminder | Follow [§6 PAT Rotation Procedure](#6-pat-rotation-procedure) |
| `PAT Health Check` hard-fails at 3 days | Critical — rotation window closing | Immediate rotation; consider emergency bypass only if absolutely necessary |
| **Auto-PR workflow** |  |  |
| Workflow doesn't run after push | Branch name doesn't match `push.branches` filter | Verify branch starts with `feature/`, `fix/`, `docs/`, or `hotfix/` |
| Workflow runs but exits 0 silently (no PR created) | Branch name passed `push.branches` but fails the defense-in-depth regex in step 1 | Check regex: `^(feature\|fix\|docs\|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$` |
| PR body shows wrong attribution | Usually expected — see [§3 three-tier attribution model](#3-branch-naming-convention--developer-attribution) for semantics | Read the field labels: `Opened by:` = first commit author; `Last pushed by:` = most recent pusher; `Contributors on this branch:` = everyone |
| PR body contributors truncates multi-word names | **Bug before v3.3.5.1**: fixed via `awk` rewrite | Verify `.github/workflows/auto-pr-to-main.yml` step 7 uses `awk` not `read -r count handle` |
| PR body contains email addresses | **Regression** — all emails should be stripped per v3.3.5.1 | Check `git log --format='...'` invocations in workflow; must use `%an` only, never `%ae` |
| **Branch-name-check** |  |  |
| "Branch Name Check" shows red ✗ on PR | Branch doesn't match regex or uses `<dev>` <2 chars / `<description>` <3 chars | Rename the branch locally; force-push is BLOCKED by `non_fast_forward` ruleset — open a NEW branch with a compliant name instead |
| **Copilot auto-review** |  |  |
| No Copilot review after push to existing PR | PR was created before Copilot Business entitlement was provisioned (2026-04-27). Auto-trigger is PR-creation-time. | Manual trigger via `gh api --method POST /repos/WeOwnNetwork/ai/pulls/<N>/requested_reviewers -f reviewers[]=copilot-pull-request-reviewer` (canonical GitHub Copilot reviewer login — same value referenced by [ADR-004](../ADR-004-copilot-auto-review-ruleset.md)) or the "Request review" button in GitHub UI. For the long-term fix (new PRs auto-trigger correctly) see [ADR-004](../ADR-004-copilot-auto-review-ruleset.md). |
| No Copilot review on first commit of auto-created PR | **Expected behavior specific to `auto-pr-to-main.yml`.** The workflow pushes commits to the branch *before* creating the PR, so there is no new push delta when the PR is opened — Copilot's `review_on_push: true` only fires on pushes made *while the PR is open*. For manually-created PRs (PR opened before commits are pushed), Copilot fires at PR-creation time. | Make any follow-up push to the same branch. Copilot will review the new push automatically. All subsequent pushes on an open PR are reviewed. See [ADR-004 § Empirical Validation Results](../ADR-004-copilot-auto-review-ruleset.md#empirical-validation-results). |
| No Copilot review on brand-new PR (post-2026-04-27) | Either (a) `weown-bot` Copilot Business seat revoked, or (b) rulesets misconfigured | Verify via `gh api /repos/WeOwnNetwork/ai/rulesets/12131972` → rules include `copilot_code_review`; verify enterprise-level ruleset still active in Enterprise Settings |
| **Branch protection / rulesets** |  |  |
| `Push rejected: non-fast-forward` on feature branch | Normal — force-push blocked on `~ALL` branches by Layer 1 + Layer 2 rulesets (see [ADR-004](../ADR-004-copilot-auto-review-ruleset.md)) | Don't force-push. Open a new branch or use merge instead of rebase. |
| Merge to `main` blocked with "requires 1 approval" | Normal — `main` ruleset requires 1 human reviewer | Request review from `@ncimino` per [CODEOWNERS](../CODEOWNERS) |
| Merge blocked with "requires signed commits" | One or more commits in the PR are unsigned | Configure commit signing per [CONTRIBUTING.md §3](../../CONTRIBUTING.md#3-commit-signing-required); adding a new signed commit does **not** fix earlier unsigned commits. Because retroactive signing would rewrite history and `non-fast-forward` is blocked, recreate the branch/PR with all commits signed, or otherwise ensure every commit in the PR is signed. |
| **Infisical sync** |  |  |
| GitHub Secret `WEOWN_BOT_PAT` drifts from Infisical stored value | Infisical sync integration deleted / paused OR manual update in GitHub bypassed Infisical | See [ADR-002](../ADR-002-infisical-github-sync.md) §4 + [§6 recovery](#6-pat-rotation-procedure) |
| `pat-health-check.yml` green but auto-PR fails with 401 | Sync drift: Infisical has stale value and just overwrote GitHub | Update Infisical secret with current valid PAT; trigger manual sync |

---

## 12. Related Documents

- `.github/copilot-instructions.md` — Copilot AI review directives (phase-aware per `COMPLIANCE_ROADMAP.md`)
- `.github/ADR-001-service-account-pat.md` — Why service account + PATs (not a GitHub App)
- `.github/ADR-002-infisical-github-sync.md` — Why Infisical primary via GitHub Sync
- `.github/SECURITY_ASSESSMENT.md` — Threat model, risk register, mitigations
- `.github/INCIDENT_RESPONSE.md` — Incident scenarios, RTO/RPO, runbooks
- `.github/CODEOWNERS` — Review assignment (`@ncimino` universal reviewer; `@iamwaseem18`/`@mshahid538` assignable at `@ncimino`'s discretion)
- `.github/CI_CD_WORKFLOWS.md` — Broader CI/CD strategy (validation workflows, not auto-PR)
- `docs/COMPLIANCE_ROADMAP.md` — Multi-phase compliance strategy (NIST/CIS/CSA/ISO/SOC 2/ISO 42001)
- `/CHANGELOG.md` — Repository-level change history
