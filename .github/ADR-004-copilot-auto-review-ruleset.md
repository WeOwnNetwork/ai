# ADR-004: `~ALL` Branches Ruleset (Copilot Auto-Review + Force-Push / Deletion Protection) — Repo-Level + Enterprise-Level Defense-in-Depth

**Status**: Accepted
**Version**: v3.3.5.1 (#WeOwnVer)
**Date**: 2026-04-23 (repo-level) / 2026-04-27 (enterprise-level added) / 2026-04-28 (R13 clarification on auto-trigger timing)
**Deciders**: `@romandidomizio`, `@ncimino`
**Supersedes**: None
**Superseded by**: None
**Related**:
- [`ADR-001`](ADR-001-service-account-pat.md) — `weown-bot` service account + PAT posture
- [`ADR-002`](ADR-002-infisical-github-sync.md) — Infisical → GitHub secret sync
- [`ADR-003`](ADR-003-main-branch-ruleset.md) — `main`-only strict ruleset (12 rules)
- [`.github/workflows/auto-pr-to-main.yml`](workflows/auto-pr-to-main.yml) — consumes `non_fast_forward` enforcement to make `Opened by:` attribution stable across pushes
- [`.github/workflows/README.md` §3](workflows/README.md#3-branch-naming-convention--developer-attribution) — three-tier PR-body attribution depends on the immutability guarantees in this ADR

---

## Context

ADR-003 covers the strict `main`-only ruleset. But there are repo-wide invariants that must hold on **every branch**, not just `main`:

1. **Deletion protection on `~ALL` branches** — feature branches must not be deletable mid-PR (audit-trail loss; CI/CD broken; reviewer history orphaned).
2. **`non_fast_forward` (force-push block) on `~ALL` branches** — required so that `auto-pr-to-main.yml` can rely on the FIRST commit of any branch being immutable. The workflow's `Opened by:` field (see §3 of the workflows README) is computed from `git rev-list --reverse "${GIT_RANGE[@]}" | head -1` → `gh api /repos/.../commits/{first-sha} --jq .author.login`, and is documented as "stable across pushes" only because the first commit cannot be rewritten.
3. **`copilot_code_review` on `~ALL` branches** — every **newly-created** PR (regardless of base branch) gets Copilot AI review automatically **after ruleset enablement**. This is the WeOwn baseline AI safety pattern (one of two enforcement mechanisms; the other is `weown-bot` being a "human-type" account so legacy auto-trigger fires). **Note**: Copilot evaluates auto-review eligibility at PR-creation time, so PRs that already existed before the ruleset was applied (e.g., PR #13) do **not** retroactively gain auto-review — they must be triggered manually for the duration of their open lifecycle. See § Empirical Validation Results below for the controlled experiment confirming this PR-creation-time caching behavior.

These can't go in ADR-003 because they target `~ALL`, not `~DEFAULT_BRANCH`. They warrant a separate ADR because:
- Their compliance mappings differ (focus on data integrity + AI safety + deletion protection, not change-management gating)
- They have a defense-in-depth pairing with an **enterprise-level** ruleset that mirrors the same rules at a broader scope
- Their pruning criteria (when to retire either layer) are distinct from ADR-003's review cadence

---

## Decision

**Two stacked rulesets enforce the same 3 rules on `~ALL` branches**, providing defense-in-depth:

### Layer 1 — Repo-level "Copilot auto-review" ruleset (id `12131972`, configured 2026-04-23)

- **Scope**: `WeOwnNetwork/ai` repository, all branches (`include: ["~ALL"]`)
- **Enforcement status**: Active
- **Bypass list**: empty
- **Rules (3)**:
  1. **`deletion`** — block branch deletion (preserves audit trail of merged + abandoned branches)
  2. **`non_fast_forward`** — block force-push and rebase that would rewrite history (makes first-commit identity immutable on every branch, which `auto-pr-to-main.yml` depends on for the `Opened by:` attribution; also prevents post-review tampering of reviewed commits)
  3. **`copilot_code_review`** with `review_draft_pull_requests: true, review_on_push: true` — auto-request Copilot review on every PR (draft + ready) and on every push to an open PR

### Layer 2 — Enterprise-level ruleset (configured 2026-04-27)

- **Scope**: WeOwn enterprise → all organizations → all repositories → all branches
- **Rules**: identical 3 rules to Layer 1
- **Why it exists**: Copilot Business entitlement is licensed at the enterprise level. The repo-level `copilot_code_review` rule on Layer 1 silently no-ops for `weown-bot`-authored PRs because the entitlement isn't visible at repo scope. The enterprise-level ruleset is configured at the same scope as the entitlement, which is where Copilot is expected to honor the auto-trigger for service accounts with Business seats.

### Defense-in-depth rationale (why both, not one)

| Failure mode | Layer 1 (repo) | Layer 2 (enterprise) | Net protection |
|---|---|---|---|
| Enterprise admin misconfigures Layer 2 | ✓ Layer 1 still enforces | ✗ | ✓ Repo still protected |
| Repo admin deletes Layer 1 (e.g., during cleanup) | ✗ | ✓ Layer 2 still enforces | ✓ All branches still protected |
| `WeOwnNetwork/ai` migrates to a new enterprise / org | ✓ Layer 1 still enforces | Possibly orphaned | ✓ Repo invariants survive migration |
| Enterprise migrates to a different SKU (e.g., switches from Business to Enterprise) | ✓ | TBD | ✓ |
| Both layers misconfigured simultaneously | ✗ | ✗ | ✗ — out of scope; would require two independent admin errors |

This pattern mirrors WeOwn's existing defense-in-depth practices:
- Branch-name regex enforced in `branch-name-check.yml` AND `auto-pr-to-main.yml` step 1
- Ruleset `non_fast_forward` AND ADR-003 / `main` ruleset signed-commit enforcement
- Secrets-in-Infisical AND secrets-in-GitHub-Actions (with PAT health check workflow comparing them)

### Operational cost: zero

Both rulesets enforce **identical rules**. There is no rule-sync burden because we only ever modify in one direction (rule additions / removals get propagated to both rulesets in the same PR, governed by ADR-003-style review cadence). GitHub's enforcement is union-of-rules: a violation that any layer would block is blocked. No rule contradictions are possible since the rules are the same.

---

## Compliance Mappings

| Framework / Control | Rule(s) | How this ADR satisfies it |
|---|---|---|
| **SOC 2 CC6.1** (logical access — privileged operations) | `deletion`, `non_fast_forward` | Branch deletion + history rewriting are privileged-by-design and require explicit ruleset bypass (none granted) |
| **SOC 2 CC7.1** (system monitoring — anomaly detection) | `copilot_code_review` | Every PR gets AI-assisted code review with security-aware suggestions; commit-time anomaly detection layer beyond pre-commit hooks |
| **SOC 2 CC7.2** (system change monitoring) | `copilot_code_review`, `non_fast_forward` | All branch changes reviewed before merge; history immutability prevents silent post-review tampering |
| **SOC 2 CC8.1** (change management — formal review) | `copilot_code_review` | AI review on every push to every PR (draft + ready) is the first line of structured review (human review enforced separately by ADR-003 on `main`) |
| **ISO/IEC 27001:2022 A.8.32** (change management) | All 3 rules | Branches cannot be deleted (audit preservation), history cannot be rewritten (review integrity), AI review is enforced (change scrutiny) |
| **ISO/IEC 27001:2022 A.8.13** (information backup — branches as audit) | `deletion` | Even abandoned branches are preserved for change-history reconstruction |
| **ISO/IEC 42001:2023 A.6.2.7** (AI system development — review) | `copilot_code_review` | AI-assisted review on every code change to AI infrastructure; meets the "appropriate review" bar for AI lifecycle management |
| **ISO/IEC 42001:2023 A.6.2.8** (AI deployment review) | `copilot_code_review` | All deployment-related code (Helm, K8s, CI) gets AI review before merge to `main` |
| **NIST CSF 2.0 PR.IP-3** (configuration change control) | `non_fast_forward` | Configuration changes (workflow YAML, Helm values, K8s manifests) cannot be silently rewritten after review |
| **NIST CSF 2.0 DE.CM-1** (continuous monitoring of network) | `copilot_code_review` | AI continuously monitors PR diffs for security regressions |
| **CIS Controls v8 18.3** (development security — code review) | `copilot_code_review` | Automated security-aware review on all PRs (defense-in-depth alongside CodeQL + branch-name + 2-reviewer rule) |

Audit evidence cross-reference:
- Ruleset config exportable via `gh api /repos/WeOwnNetwork/ai/rulesets/12131972` (Layer 1) and the enterprise rulesets API (Layer 2)
- `~ALL` scope visible in the ruleset's `conditions.ref_name.include` field
- Bypass list emptiness verifiable via `gh api .../rulesets/12131972 --jq .bypass_actors`

---

## Rules Intentionally NOT Enabled on `~ALL`

| Rule | Why not on `~ALL` |
|---|---|
| `pull_request` (require PR before merge) | `~ALL` includes feature branches themselves — requiring a PR to push to a feature branch is nonsensical (the branch IS the PR target). Enforced on `main` only via ADR-003. |
| `required_signatures` | Currently enforced on `main` only via ADR-003. Could be expanded to `~ALL` in a future ADR if external contributor signing becomes mandatory; for now, signing is reviewer-enforced on feature branches and ruleset-enforced on `main`. |
| `required_status_checks` | Status checks are PR-scoped and enforced via ADR-003 on the merge gate. Adding them to `~ALL` would block intermediate pushes during work-in-progress, harming developer velocity. |
| `code_quality` | Same reasoning as status checks — enforce at merge time on `main` only. |

---

## Layer 1 Pruning Criteria — When to Delete the Repo-Level Ruleset

**Default posture**: KEEP both layers indefinitely (defense-in-depth has zero operational cost).

**Pruning is acceptable only after ALL of the following are satisfied:**

1. **5+ consecutive bot-authored PRs** auto-trigger Copilot review via Layer 2 alone (i.e., temporarily disable Layer 1 for testing, observe Copilot fires on every push to every PR, re-enable Layer 1, then schedule pruning).
2. **No enterprise-level migration is planned** in the next 6 months (org restructure, billing change, SKU change).
3. **Layer 2 deletion + non_fast_forward enforcement is verified** via a deliberate test (e.g., attempt force-push from a fresh fork; confirm rejection with the expected enterprise-ruleset error message).
4. **Reviewer (`@ncimino` + `@romandidomizio` minimum) signs off** on a "drop Layer 1" PR with explicit ADR-004 update marking Layer 1 as "Removed YYYY-MM-DD".

If any criterion fails, KEEP Layer 1.

**Conservative recommendation (current)**: do NOT prune. The two layers cost nothing to maintain (rules are identical), and the defense-in-depth posture meaningfully improves audit narrative under SOC 2 CC8.1 + ISO 27001 A.8.32 ("multiple independent enforcement mechanisms").

---

## Verification Procedure

### Verify Layer 1 (repo-level) configuration

```bash
gh api /repos/WeOwnNetwork/ai/rulesets/12131972 --jq '{
  name: .name,
  enforcement: .enforcement,
  target: .conditions.ref_name.include,
  bypass: .bypass_actors,
  rules: [.rules[].type]
}'
```

Expected output:

```json
{
  "name": "Copilot auto-review",
  "enforcement": "active",
  "target": ["~ALL"],
  "bypass": [],
  "rules": ["deletion", "non_fast_forward", "copilot_code_review"]
}
```

### Verify Layer 2 (enterprise-level) configuration

```bash
# Requires enterprise-admin token; replace <enterprise-slug> with the WeOwn enterprise slug
gh api /enterprises/<enterprise-slug>/rulesets --jq '.[] | select(.name | contains("Copilot")) | {
  name, enforcement,
  target: .conditions.repository_name.include,
  rules: [.rules[].type]
}'
```

Expected: identical 3 rules, scope = all repos in all orgs.

### End-to-end auto-trigger validation

After this ADR is committed, the next **newly-created** bot-authored PR (or a close-and-reopen cycle on an existing PR) is the live test. **Important**: Copilot auto-review eligibility is evaluated **at PR-creation / reopen time**, not at push time (see [Empirical Validation Results](#empirical-validation-results) below). Pushes to PRs that already existed before ruleset enablement will NOT retroactively auto-trigger, and running this procedure against a pre-existing PR WILL produce false negatives.

1. Trigger the test via ONE of:
   - **(a) New PR path** — push `weown-bot`-authored commits to a fresh branch so `auto-pr-to-main.yml` opens a brand-new PR (auto-trigger evaluated at creation).
   - **(b) Close+reopen path** — on an existing PR, run `gh pr close <N>` then `gh pr reopen <N>`; Copilot re-evaluates auto-trigger eligibility on the reopen event.
2. Within ~60 seconds of the creation/reopen event, confirm via `gh pr view <N> --json reviews --jq '.reviews | sort_by(.submittedAt) | reverse | .[0]'` that `copilot-pull-request-reviewer` has submitted a new review with no manual intervention.
3. If yes → record the run number + timestamp in this ADR's [Decision Log](#decision-log) as a confirmed enterprise-level auto-trigger (in-repo tracking; avoids dependency on the gitignored operational checklist).
4. If no → debug Layer 2 ruleset configuration; potentially file a GitHub support ticket asking why Copilot Business entitlement isn't honored at enterprise-ruleset scope. **Do not** retry against a pre-existing PR via plain push — that path is known-unreliable per § Empirical Validation Results.

---

## Trade-offs Considered

### Alternative: Single ruleset (Layer 1 only, no enterprise layer)

**Rejected because**: prior to 2026-04-27, Layer 1 alone did not auto-trigger Copilot review for `weown-bot`-authored PRs across rounds 1–5 of PR #13's review cycle. Roman manually triggered every Copilot review during that period. Hypothesis originally framed as "Copilot Business entitlement is enterprise-scoped" — see the round-7 update below for the empirically-confirmed refinement.

### Alternative: Single ruleset (Layer 2 only, delete Layer 1)

**Rejected because**: Layer 1 provides defense-in-depth that survives enterprise migrations / SKU changes / enterprise-admin misconfigurations. Pruning criteria (see above) require 5+ consecutive auto-triggers under Layer 2 alone before Layer 1 retirement is even discussed.

### Alternative: Add Layer 2 rules to ADR-003 instead of new ADR

**Rejected because**: ADR-003 is scoped to `main` (`~DEFAULT_BRANCH`). Layer 1 + Layer 2 target `~ALL` (every branch). Mixing scopes in one ADR would obscure the change-management evidence narrative ("which rules apply to which branches?") and make compliance auditor reviews harder. Separation of concerns favored.

---

## Upgrade Triggers — When to Revisit

Re-open this ADR for review if **any** of the following:

1. **Auto-trigger fails after Layer 2 is added** — first push under Layer 2 does not result in Copilot review without manual intervention. Investigate; possibly file GitHub support ticket; document findings here.
2. **Layer 1 vs. Layer 2 enforcement diverges** — e.g., GitHub changes the union-of-rules semantics; one layer accepts a violation the other rejects. Document the divergence, decide which layer is authoritative.
3. **New compliance requirement** — e.g., SOC 2 auditor requests `required_signatures` on `~ALL`. Add to both layers in same PR.
4. **Layer 1 pruning criteria all met** — proceed with pruning per the criteria section above; archive this ADR as "Layer 1 removed YYYY-MM-DD".
5. **Enterprise migration / restructure** — re-validate Layer 2 still applies post-migration; possibly re-elevate Layer 1 priority.
6. **Copilot Business → Copilot Enterprise SKU change** — Layer 2 rule semantics may change; verify via reproducibility test.

**Default review cadence**: piggy-back on ADR-003's 90-day cadence (next review 2026-07-22).

---

## Empirical Validation Results (round-7, 2026-04-27)

After Layer 2 was configured and 6 commits were pushed to PR #13 without any auto-trigger firing, Roman ran a controlled experiment:

1. **Control group**: PR #13 (created 2026-04-23, before Copilot Business + enterprise ruleset were configured). 6+ pushes observed after Layer 2 configuration. **Result**: zero auto-triggers. Every Copilot review was manually requested.
2. **Test group**: A fresh PR opened 2026-04-27 from an old branch (`velero-restic` Helm chart work), authored by `weown-bot` via `gh pr create`. **Result**: `Copilot AI review requested due to automatic review settings` — auto-trigger fired immediately at PR creation. No manual action needed.

**Empirical conclusion**: The Layer 2 ruleset + Copilot Business entitlement DO work correctly. The issue is that **Copilot auto-trigger is evaluated at PR-creation time, not push time** — despite the `review_on_push: true` setting on the ruleset rule. `review_on_push: true` means "re-review on push for PRs that had Copilot auto-requested at creation", not "request Copilot on every push for every PR". Pre-existing PRs (those created before Copilot Business + enterprise ruleset were provisioned) will never auto-trigger; the only remediation for those is to close + re-open, which is usually not worth the cost (loses review history, URL, reviewer state).

**Forward-looking posture**:
- All NEW PRs after 2026-04-27 will auto-trigger Copilot without manual intervention. Validates the Layer 2 hypothesis.
- PR #13 and any other pre-existing open PRs remain manual-review-only until merged.
- No workflow changes needed — the auto-PR workflow's `gh pr create` is the correct mechanism and gets the auto-trigger at creation time.
- The `copilot_code_review` rule in both Layer 1 and Layer 2 stays configured as-is (`review_draft_pull_requests: true, review_on_push: true`) because both semantics are desirable for future PRs.

This validation also refines the pruning criteria for Layer 1: the "5+ consecutive auto-triggers" bar now starts counting from NEW PRs only; PR #13's 6+ pushes-without-trigger do not count as failures.

---

## Decision Log

| Date | Author | Change |
|---|---|---|
| 2026-04-23 | `@romandidomizio` | Layer 1 ("Copilot auto-review" ruleset, id 12131972) configured at repo level |
| 2026-04-27 | `@romandidomizio` | Layer 2 (enterprise-level ruleset) added after rounds 1–5 of PR #13 confirmed Layer 1 alone does not auto-trigger Copilot for `weown-bot`. Hypothesis: Copilot Business entitlement requires enterprise-scoped enforcement |
| 2026-04-27 | `@romandidomizio` | This ADR authored as part of v3.3.4.2 round-6 close-out; documents both layers + defense-in-depth rationale + pruning criteria |
| 2026-04-27 | `@romandidomizio` | **ADR updated to v3.3.5.1 (round-7 close-out)**. Added "Empirical Validation Results" section with controlled-experiment findings: Layer 2 + Copilot Business entitlement work correctly; PR-creation-time caching is what prevents auto-trigger on pre-existing PR #13. First confirmed enterprise-level auto-trigger: the fresh PR opened on 2026-04-27 for the `velero-restic` branch (PR number + workflow run + timestamp to be filled in after merge). Resolved Copilot R7 comment #5 (retargeted this validation step from `PR7_HANDOFF_CHECKLIST.md` to this Decision Log). |
