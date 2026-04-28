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
- **`.github/ADR-004-copilot-auto-review-ruleset.md`** — new ADR (added 2026-04-27 in v3.3.4.2 round-6 close-out) documenting the **two-layer defense-in-depth ruleset** that targets `~ALL` branches with three rules: `deletion`, `non_fast_forward`, and `copilot_code_review`. **Layer 1**: repo-level "Copilot auto-review" ruleset (id 12131972, configured 2026-04-23). **Layer 2**: enterprise-level ruleset configured 2026-04-27 after rounds 1–5 of PR #13's Copilot review cycle confirmed Layer 1 alone did not auto-trigger Copilot for `weown-bot`-authored PRs (hypothesis: Copilot Business entitlement requires enterprise-scoped enforcement). Both layers enforce identical rules; the union-of-rules semantics provides defense-in-depth (one fails / gets misconfigured → other still applies; mirrors WeOwn's branch-name regex defense-in-depth pattern). Compliance mappings: SOC 2 CC6.1, CC7.1, CC7.2, CC8.1; ISO/IEC 27001:2022 A.8.32, A.8.13; ISO/IEC 42001:2023 A.6.2.7, A.6.2.8; NIST CSF 2.0 PR.IP-3, DE.CM-1; CIS Controls v8 18.3. Includes explicit pruning criteria for Layer 1 ("do not delete unless ALL of: 5+ consecutive bot-authored PRs auto-trigger Copilot via Layer 2 alone + no enterprise migration planned + Layer 2 deletion+non_fast_forward verified by deliberate test + reviewer sign-off on a 'drop Layer 1' PR"), end-to-end auto-trigger validation procedure, and decision log. Also closes the documentation gap that caused Copilot review rounds 5–6 to flag the `Opened by:` immutability claim as unverifiable — ADR-004 is now the authoritative reference cited from `auto-pr-to-main.yml` step 6, `workflows/README.md` §3, and `CONTRIBUTING.md` §4.
- **Platform-sourced developer attribution in `auto-pr-to-main.yml` step 6** — the workflow reads `${{ github.triggering_actor || github.actor }}` to attribute PRs, surfacing platform-derived attribution in the PR body via three independent fields (`Opened by:`, `Last pushed by:`, `Contributors on this branch:` — see the v3.3.4.2 round-5 entry below for the three-tier semantic upgrade). Zero maintenance: no case-statement mapping to keep in sync, no onboarding / offboarding workflow edits required, no risk of stale mappings drifting from `CONTRIBUTING.md`. The `<dev>` segment in branch names is preserved for human-readable naming only. Resolves 4 of 6 Copilot round-1 review comments on PR #13 that flagged `@<short-handle>` as potential misattribution. (An intermediate iteration added a case-statement mapping; a subsequent iteration replaced it with `${{ github.triggering_actor || github.actor }}` for correctness-by-default; the v3.3.4.2 round-5 iteration further split the single `Triggered by:` line into the three-tier model for unambiguous PR-body semantics.)

### Changed

- **`.github/workflows/README.md` §8.1** rewritten to reflect the as-configured ruleset (12 enabled rules with compliance column) instead of an aspirational recommendation list. Removes `pat-health-check.yml` from "required status checks" (it is `schedule:` triggered, cannot be a PR-time gate). Clarifies that "Require code quality results at warning and higher" is satisfied by **CodeQL Default Setup** (distinct from "Require code scanning results" which requires SARIF via a different API). Adds explicit note on why linear history is intentionally NOT enabled and how "Restrict who can push" is effectively covered by "Require a PR" + empty bypass list.
- **`CONTRIBUTING.md` §4 Branch Naming** — (a) removed the false-invalid example `feature/add-thing` (which actually DOES pass the regex: `add` = 2+ char `<dev>`, `thing` = 3+ char description) and replaced with genuinely invalid examples (`feature/ab-a`, `feature/roman--double-hyphen`, `random/roman-test`); (b) added a "Convention beyond the regex" note clarifying that `<dev>` is a human-readable short handle (typically first name / alias), not used for PR attribution — attribution is sourced from `${{ github.triggering_actor || github.actor }}` directly; (c) added a "Known contributor handles" table with GitHub handles + branch `<dev>` segments only (extended context such as legal names, tenure, and roles lives in internal onboarding docs, not this public repo); Nik's branch `<dev>` segment changed from `ncimino` to `nik` (shorter, matches first-name convention); placeholder TODO handles replaced with real ones (`@iamwaseem18`, `@mshahid538`); `@YonksTEAM` added as executive stakeholder reference; (d) added an "Enforcement posture" mini-matrix summarizing the three options documented in detail in ADR-003 so contributors understand why convention-not-mechanical is the current choice and what would trigger a change. Self-contained — no separate file.
- **`.github/workflows/README.md` header** — version bumped from `v3.3.4.1` to `v3.3.4.2` per #WeOwnVer pre-merge iteration policy (this is the second merge-event iteration in the same ISO week).
- **`.github/CODEOWNERS`** — replaced placeholder handles `@mohammed-TODO` / `@shahid-TODO` / `@dhruv-TODO` with confirmed real GitHub handles `@iamwaseem18` / `@mshahid538` / `@dhruvmalik007` (active per-path rules unchanged — still `@ncimino @romandidomizio` until 2026-05-15 handoff decisions are finalized). Added `@YonksTEAM` as an executive stakeholder reference in the header (not a path reviewer — avoids notification noise). Header PII minimization: legal names, tenure descriptors, and recovery-credential custody details removed from the public header; extended operational context lives in internal onboarding / security docs.
- **Branch naming example sync** — updated example branch `fix/ncimino-...` → `fix/nik-...` across `.github/workflows/branch-name-check.yml` (error-message output), `.github/workflows/README.md` §3, and root `README.md` §"Branch Strategy" to match Nik's confirmed branch `<dev>` segment in `CONTRIBUTING.md` §4. `auto-pr-to-main.yml` reviewer assignment remains `--add-reviewer ncimino,romandidomizio` — Nik's GitHub handle `@ncimino` is unchanged; only his `<dev>` branch segment changed from `ncimino` to `nik`.
- **`.github/workflows/README.md` §9 + §10** — Reviewer Rotation Procedure step 2 and Transition Checklist row 4 updated to reflect that placeholder-handle replacement is complete (`~~strikethrough~~ + ✅`), leaving only the per-path specialist-assignment decision as pending. Keeps the transition checklist an accurate audit artifact of what's done vs. still open.
- **`.github/INCIDENT_RESPONSE.md` Scenario 6** — Stewardship Gap response steps 2 and 3 updated to reference real GitHub handles (`@iamwaseem18` / `@mshahid538` / `@dhruvmalik007`) instead of `@<name>-TODO` placeholders. Incident playbook accuracy matters for SEV-4 on-call response — no ambiguity about who to page.
- **`CONTRIBUTING.md` §4** now explicitly documents the branch-name-vs-PR-body identifier split: `<dev>` is a human-readable short handle; PR `**Triggered by:**` attribution uses `${{ github.triggering_actor || github.actor }}` automatically. Added a blockquote callout table for quick reference. Resolves a user-facing ambiguity flagged in Copilot round-1 review of PR #13.
- **`.github/workflows/README.md` §3 Parsing Rules** simplified from 5 steps (including a handle-to-username mapping step) down to 3 steps (regex validation + direct `${{ github.triggering_actor || github.actor }}` attribution). Added a "Branch name vs. PR body—two different identifiers (by design)" subsection with a clarity table.
- **`.github/workflows/README.md` §9 Reviewer Rotation Procedure** — stripped contributor legal name in the "placeholder-handle replacement complete" note; kept only the GitHub handles (PII minimization in public runbook, addressing Copilot round-2 review feedback).
- **`.github/CODEOWNERS` PII minimization** — header re-written to remove contributor legal names, tenure descriptors, intern status, executive titles, and recovery-credential custody details. Kept only GitHub handles + minimal functional-area descriptors (IaC, Docker, Agentic AI). Reduces social-engineering surface area on a public repo, addressing Copilot round-2 review feedback.
- **Round-3 consistency + PII follow-ups** (Copilot review, 2026-04-24):
  - `.github/ADR-003-main-branch-ruleset.md` Option A regex example updated from `(roman\|ncimino\|mohammed\|...)` to `(roman\|nik\|mohammed\|...)` to match the current `<dev>` segment convention in `CONTRIBUTING.md` §4.
  - `.github/ADR-003-main-branch-ruleset.md` Option B rationale bullet rewritten: previously described a now-retired inline `<dev>` → GitHub-username mapping + git-author-email fallback; now correctly describes the `${{ github.triggering_actor || github.actor }}` platform-sourced attribution. Keeps the ADR a truthful control-evidence artifact.
  - `CONTRIBUTING.md` §4 — all three references (`<dev>` intro paragraph, blockquote callout table cell, blockquote explanatory paragraph, Known-contributor-handles onboarding paragraph) updated from shortform `github.actor` to the full `${{ github.triggering_actor || github.actor }}` expression to match the workflow env variable exactly.
  - `.github/workflows/README.md` §3 "Branch name vs. PR body" table cell updated to use the full `${{ github.triggering_actor || github.actor }}` expression to match the Parsing Rules step 3 above it.
  - `.github/workflows/README.md` §10 Transition Checklist row 2 softened: `Transfer 2FA (TOTP seed) + recovery codes to enterprise admin (Yonks) + rotation lead` → `Transfer 2FA administration per internal runbook to enterprise admin + rotation lead`. Removes specific credential-type details from a public runbook (social-engineering surface reduction).
- **Round-4 consistency fixes** (Copilot review, 2026-04-27):
  - `.github/workflows/branch-name-check.yml` Invalid examples list — removed the line `feature/add-thing  (missing <dev>-)`. CONTRIBUTING.md §4 documents this branch as regex-valid-but-convention-violating (`add` = 2-char `<dev>`, `thing` = 5-char description, regex passes); listing it under Invalid examples contradicted the docs. Other 5 invalid examples already cover all failure modes; removal eliminates the contradiction.
  - `.github/workflows/README.md` Table of Contents entry — anchor link `#8-required-branch-protection-settings` updated to `#8-required-branch-protection--naming-enforcement` to match the renamed §8 heading (`Required Branch Protection & Naming Enforcement`); visible link text updated correspondingly.
  - `.github/workflows/README.md` §3 Parsing Rules step 3 — dropped the parenthetical "(or manually triggered the workflow)" since `auto-pr-to-main.yml` is currently `on: push` only (no `workflow_dispatch` trigger). Replaced with a forward-compatible note explaining `triggering_actor` is preferred for forward compatibility.
  - `.github/workflows/auto-pr-to-main.yml` §6 `TRIGGERING_USER` comment — reworded to accurately describe today's behavior (push-only resolves both context fields to the pusher) and explain `triggering_actor` choice as forward-compatible, instead of implying `workflow_dispatch` / re-run support that isn't enabled today.
  - `CHANGELOG.md` v3.3.4.2 entries — 4 references updated from shortform `github.actor` to the full `${{ github.triggering_actor || github.actor }}` expression to match the workflow env variable exactly (avoids audit/runbook drift when reviewers cross-reference the changelog vs. the workflow code).
- **PR-body attribution upgrade — three-tier model** (Round-5 Copilot review + UX-clarity refactor, 2026-04-27):
  - **Root issue**: the prior `**Triggered by:** @<user>` line was semantically ambiguous. The workflow runs on every push and updates the PR body via `gh pr edit`, so on multi-commit / multi-contributor PRs the field showed the *most recent pusher*, not the PR opener — but the label implied "opener". This caused legitimate reviewer confusion and was a recurring root cause for Copilot review iterations on attribution wording.
  - **`auto-pr-to-main.yml` step 6 rewritten** — replaced single `**Triggered by:**` line with three distinct, semantically-precise fields:
    - **`**Opened by:**`** — GitHub @handle of the FIRST commit's author on the branch. Resolved via `git rev-list --reverse "${GIT_RANGE[@]}" | head -n 1` → `gh api /repos/$GITHUB_REPOSITORY/commits/$FIRST_SHA --jq '.author.login'`. Idempotent across pushes (the first commit is immutable under the `non_fast_forward` ruleset on `~ALL` branches). Two fallbacks: (1) `.committer.login` if `author.login` is null (unverified email but verified committer), (2) `LAST_PUSHED_BY` if both fail (preserves prior behavior on single-commit PRs where first == last).
    - **`**Last pushed by:**`** — `${{ github.triggering_actor || github.actor }}`. Updates every push. `triggering_actor` is correct on `workflow_dispatch` + re-runs (resolves to whoever clicked Run); `github.actor` is the push-event fallback.
    - **`**Contributors on this branch:**`** (step 7 rewritten) — list now uses GitHub @handles with commit counts (`- @romandidomizio (4 commits)`) instead of `Name <email>` strings. Per-commit `gh api /repos/.../commits/{sha} --jq '.author.login // .committer.login // ""'` resolution; falls back to `name+email` for unlinked external commits (auditable but not pingable).
  - **`auto-pr-to-main.yml` `workflow_dispatch:` trigger added** — enables manual re-run for debugging / PR-body refresh without needing an empty commit. The defense-in-depth branch-name regex (step 1) makes dispatch on `main` or unconventional branches a safe no-op (`exit 0`). Resolves the 2026-04-23 PAT-rotation scenario that required commit `ba6d7ee` (empty re-trigger commit) — going forward this is one click in the Actions tab.
  - **`auto-pr-to-main.yml` `concurrency:` block added** — `group: auto-pr-${{ github.ref }}, cancel-in-progress: true`. Prevents race conditions when developers rapid-push: the older in-flight run is cancelled and only the latest run creates / updates the PR. Per-branch isolation; pushes on different branches don't interfere with each other.
  - **`.github/workflows/README.md` §3 rewritten** — (a) intro sentence corrected to clarify attribution comes from GitHub event context + commits API, **not** branch-name parsing (resolves Copilot round-5 comment #1: prior intro contradicted the Parsing Rules below it); (b) Parsing Rules retitled "Parsing Rules (branch name → regex validation only)" with 3 simplified steps (no attribution step at all); (c) new "PR body attribution — three-tier model (by design)" subsection with Field/Value/Source/Updates table; (d) "Branch name vs. PR body" table expanded from 2 rows to 4 (branch `<dev>` + `Opened by:` + `Last pushed by:` + `Contributors:`).
  - **`CONTRIBUTING.md` §4 rewritten** — (a) `<dev>` paragraph updated to clarify attribution uses commits API + event context, not branch parsing; (b) blockquote callout table expanded to 4 rows (matches workflows/README.md); (c) new explanatory bullets for each of the three PR-body fields with their resolution mechanism; (d) `feature/add-thing` trailing note updated from "the `Triggered by:` line" → "the `Opened by:`, `Last pushed by:`, and `Contributors:` fields"; (e) round-5 Copilot comment #2 fix: attribution paragraph rewritten — dropped misleading "or manually triggered the workflow" phrasing (workflow_dispatch is *now* enabled but the old phrasing conflated push-time and dispatch-time attribution; new prose makes the model crystal clear).
  - **Audit + reviewer benefit**: every PR body now answers three independent questions at a glance: "Who started this work?" (Opened by), "Who's actively pushing right now?" (Last pushed by), "Who has touched this branch and how much?" (Contributors). Supports per-contributor review-load assessment and removes ambiguity for SOC 2 CC8.1 change-management evidence.
- **Round-6 Copilot review + PII minimization + enterprise-level ruleset documentation** (Round-6 Copilot review + user-directed UX polish + ruleset architecture clarification, 2026-04-27):
  - **Round-5 auto-trigger claim REVERTED**: prior session incorrectly inferred from the `2026-04-27T21:59:30Z` Copilot review timestamp on commit `34f28bf` that auto-trigger had succeeded; user clarified the round-5 review was MANUALLY triggered. Memory + checklist + this changelog corrected to reflect that Copilot Business + `weown-bot` seat-assignment alone (Layer 1 ruleset) does NOT auto-trigger Copilot review. Hypothesis (to be validated by next push): Copilot Business entitlement requires enterprise-scoped ruleset enforcement (see new ADR-004 Layer 2).
  - **Copilot round-6 comments addressed (5 items)**:
    - **(A, C, D) Immutability claim under-specified** — `auto-pr-to-main.yml` step 6 comment, `workflows/README.md` §3 table row, and `CONTRIBUTING.md` §4 blockquote each claimed the first commit is "immutable under the `non_fast_forward` ruleset on `~ALL` branches" but did not cite the specific ruleset. Copilot couldn't verify the claim from ADR-003 alone (which is `main`-scoped). **Fix**: each claim now cites the **"Copilot auto-review" ruleset (id 12131972, see ADR-004)** explicitly, making the enforcement chain auditable.
    - **(B) CHANGELOG drift** — the v3.3.4.2 "Added" bullet for platform-sourced attribution still described the workflow as producing `**Triggered by:** @<real-github-username>`, which was true at round-1 but not after the round-5 three-tier refactor. **Fix**: bullet rewritten to describe the three independent fields (`Opened by:`, `Last pushed by:`, `Contributors on this branch:`) currently emitted, with a parenthetical noting the round-5 evolution.
    - **(E) PII in step 7 contributors fallback** — the unlinked-commit fallback emitted `git log -1 --format='%an <%ae>'`, exposing email addresses of external contributors in the public PR body. **Fix**: changed to `%an` only (commit author NAME, no email). Names are already public on GitHub commit pages; emails are PII per GDPR/CCPA + WeOwn's existing PII-minimization posture (already applied to `CONTRIBUTING.md` handle table + `CODEOWNERS`).
  - **Recent Commits section (§8) PII strip** (user-directed extension of the same principle): the per-commit Recent Commits header in step 8 used `git log --format='### %h %s%n%n**Author:** %an <%ae>%n**Date:** %ad...'`. Stripped `<%ae>` to match the contributors fallback; emails no longer appear anywhere in the PR body. Reviewers can still cross-reference via the commit SHA + GitHub web UI.
  - **PR body parenthetical descriptions removed** (user-directed UX polish): the `Opened by:`, `Last pushed by:`, and `Contributors on this branch:` lines previously included italic explanatory parentheticals (`_(stable across pushes)_`, `_(updated every push; ...)_`, `_(GitHub logins where available; name+email otherwise)_`). The labels themselves now convey enough meaning; full semantics live in CONTRIBUTING.md §4 and workflows/README.md §3 for anyone who needs them. Trims visual noise from the PR body without information loss.
  - **`.github/ADR-003-main-branch-ruleset.md` Related section** — added cross-reference to ADR-004 (under Related), making the two-ADR structure discoverable.
  - **Why Layer 2 (enterprise-level ruleset) was added today**: rounds 1–5 of PR #13 each required Roman to manually trigger Copilot review even after Copilot Business entitlement was activated + `weown-bot` seat assigned. Investigation revealed that GitHub's Copilot auto-review docs imply enterprise-scoped configuration is required for service-account auto-trigger (vs. personal Copilot Pro accounts where repo-level config is sufficient). Roman configured the enterprise-level ruleset on 2026-04-27; the next bot-authored push (commit shipping this changelog) is the live validation.

### Fixed

- **`.github/ADR-003-main-branch-ruleset.md` stale path reference** — "Not enabled → Require signed tags" bullet previously pointed to `.pr7-handoff-checklist` (a local-only, gitignored file that does not exist in the repo tree). Replaced with `/CHANGELOG.md` + `docs/VERSIONING_WEOWNVER.md`, both of which are in-repo tracking locations. Resolves 1 of 6 Copilot review comments on PR #13.
- **`.github/ADR-003-main-branch-ruleset.md` date arithmetic** — "Next scheduled review" incorrectly read `2026-07-23`. 2026-04-23 + 90 calendar days = 2026-07-22 (April 30-23=7 remaining days in April, May=31, June=30 → 7+31+30=68 days, 90-68=22 → July 22). Corrected to `2026-07-22` and clarified "90 calendar days" to remove math ambiguity. Resolves 1 of 6 Copilot review comments on PR #13 about date inconsistency.

### Security / Compliance

- **SOC 2 CC6.3 evidence-ready**: §8.1 table maps each of the 12 enabled rules to specific SOC 2 Trust Services Criteria. Auditors can cross-reference the GitHub ruleset config with this table for one-shot coverage proof.
- **ISO 27001 A.5.15 + A.5.37**: path-reviewer binding (CODEOWNERS #3) + change-of-state reset (stale approval dismissal #2) documented and enforced.
- **ISO 42001 AI governance**: rule #10 (auto-request Copilot review) now mapped to Annex A.6.2.7 (AI-aware technical controls) and A.6.2.8 (review + approval of AI-generated output).
- **`WEOWN_BOT_PAT` rotation audit note** — the fine-grained PAT scoped to `WeOwnNetwork/ai` was regenerated on 2026-04-23 during this PR's cycle to restore the `auto-pr-to-main.yml` workflow (prior PAT was invalidated; `PAT Health Check` workflow run `24870414632` confirmed the post-rotation PAT authenticated as `weown-bot` with 89 days to next expiration on 2026-07-22). New PAT is 89-day fine-grained, single-repo scope, stored via Infisical → GitHub Secret sync. The rotation event itself is an auditable control (no sensitive credential material recorded here).
- **Copilot Business entitlement activated for `weown-bot`** (2026-04-27) — GitHub support enabled the **Copilot Business** add-on on the WeOwn enterprise (previously only Enterprise without a Copilot SKU, which silently no-op'd ruleset `copilot_code_review` rules for any actor without entitlement). One Copilot Business seat assigned to `weown-bot`; **code review** capability enabled. This unblocks the previously-deferred ruleset `copilot_code_review` behavior on PR #13 and all future bot-authored PRs: Copilot will now auto-review PRs from `weown-bot` per the existing rulesets (`Copilot auto-review` id 12131972 targets `~ALL`; `main rules` id 12119304 targets `~DEFAULT_BRANCH`). No workflow change required — the explicit `gh api --add-reviewer Copilot` task previously queued for v3.3.4.3 is now redundant with ruleset enforcement and demoted to optional defense-in-depth. Compliance notes: ISO/IEC 42001:2023 A.6.2.7 (AI-aware technical controls) and A.6.2.8 (review of AI-generated output) are now actively enforced for bot-authored PRs in addition to human-authored ones.

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
