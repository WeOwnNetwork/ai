# Incident Response Runbook — Auto-PR Workflow & `weown-bot`

**Scope**: Incidents related to the auto-PR workflow, `weown-bot` service account, `WEOWN_BOT_PAT`, or Infisical GitHub Sync integration.
**Version**: v3.3.4.1 (#WeOwnVer)
**Date**: 2026-04-23
**Primary Owner**: `@ncimino` (permanent) + `@romandidomizio` → post-2026-05-15: Mohammed/Shahid/Dhruv per CODEOWNERS

---

## Severity Definitions

| Severity | Definition | Initial Response |
|---|---|---|
| **SEV-1 (Critical)** | PAT compromise confirmed; bot account compromise confirmed; active malicious PR opened | Immediate — within minutes |
| **SEV-2 (High)** | Suspected compromise (indicators, no confirmation); Infisical breach suspected; unauthorized rotation | < 1 hour |
| **SEV-3 (Medium)** | PAT will expire in < 3 days; workflow is failing on expiration | < 24 hours |
| **SEV-4 (Low)** | Rotation reminder; configuration drift alert | Next business day |

**SLAs**:

- RTO (Recovery Time Objective): **1 hour** for all scenarios below
- RPO (Recovery Point Objective): **0** (no data is at stake in auto-PR workflow specifically)

---

## Scenario 1 — PAT Compromise Confirmed (SEV-1)

**Indicators**: PAT value leaked (pastebin, GitHub issue, chat, third-party log); unauthorized PR opened by `weown-bot`; GitHub security alert.

### Response

1. **Immediately revoke PAT** in `weown-bot` GitHub account:
   - Settings → Developer settings → Personal access tokens → Fine-grained → Revoke `WeOwnNetwork/ai-PR-Automation`
2. **Notify**: Post in infrastructure channel + email `@ncimino` + `@romandidomizio` (or current stewards)
3. **Audit**: Review GitHub audit log for bot activity in the past 90 days (filter by `actor:weown-bot`)
4. **Check repository**:
   - Any unauthorized commits? (`git log --author=weown-bot` + `git log --committer=weown-bot`)
   - Any unauthorized PRs? (`gh pr list --author weown-bot --state all --limit 50`)
   - Branch protection intact? (`gh api repos/WeOwnNetwork/ai/branches/main/protection`)
5. **Rotate**:
   - Generate new PAT (see workflows README "PAT Rotation Procedure")
   - Update Infisical `WEOWN_BOT_PAT__WEOWNNETWORK_AI`
   - Verify GitHub secret syncs
   - Test workflow with throwaway branch
6. **If unauthorized changes found**:
   - `git revert` the offending commits
   - Open SEV-1 PR for review
   - Trigger full repo security review
7. **Post-mortem**: Write and file post-mortem within 5 business days

---

## Scenario 2 — `weown-bot` Account Compromise (SEV-1)

**Indicators**: Unauthorized login alert; password change you didn't make; unauthorized 2FA changes; unauthorized team/org membership changes.

### Response

1. **Immediately contact GitHub Support** (Enterprise line): request account lockout
2. **Revoke all active sessions** (if you still have access): Settings → Security → Sign out all other sessions
3. **Rotate password** and re-enroll 2FA (use recovery codes held by Yonks)
4. **Revoke all active PATs** for the account (every PAT across every WeOwn repo):
   - Iterate over all PATs in Settings → Developer settings → Personal access tokens
5. **Rotate email** if email account is compromised
6. **Check GitHub enterprise audit log**: filter by `actor:weown-bot` for last 90 days
7. **Regenerate all PATs** and update Infisical (one at a time per repo using rotation procedure)
8. **Branch protection check**: verify no bot-mediated changes to protection rules
9. **Post-mortem**: write within 10 business days; update IR procedures if gaps identified

---

## Scenario 3 — Infisical Breach Suspected (SEV-1 or SEV-2)

**Indicators**: Infisical security advisory; unauthorized secret access in audit log; unexplained secret value changes.

### Response

1. **Confirm breach scope** with Infisical Support
2. **If project `weown-bot GitHub PATs` affected**:
   - Treat as **all PATs compromised**
   - Execute Scenario 1 response for every affected PAT (rotate in parallel where possible)
3. **Temporarily disable Infisical Sync** integration (decouple from GitHub until resolved)
4. **Restore PATs to GitHub manually** (one at a time) until Infisical is trusted again
5. **Review Infisical RBAC**:
   - Who had access to the project?
   - Were IP allowlists in place?
   - Were Machine Identities compromised?
6. **Re-enable Sync** only after Infisical confirms remediation
7. **Post-mortem**: update threat model and audit controls

---

## Scenario 4 — PAT Expired Unrotated (SEV-3)

**Indicators**: Workflow fails with HTTP 401; auto-PRs stop being created; `pat-health-check.yml` hard-fails (≤3 days).

### Response

1. **Open issue** in repo (or use auto-opened by `pat-health-check.yml`):
   - Title: `[PAT ROTATION] WEOWN_BOT_PAT expired — workflow failing`
   - Labels: `security`, `pat-rotation`, `weown-bot`
2. **Execute rotation procedure** (workflows README "PAT Rotation Procedure")
3. **Verify workflow resumes** by pushing a test commit to a throwaway branch
4. **Update `/CHANGELOG.md`** with rotation entry
5. **Update `weown-bot` usage table** in workflows README ("Last Rotated" column)
6. **Root cause review**: why didn't the 14-day warning trigger action? Improve alert routing if needed.

---

## Scenario 5 — Unauthorized Auto-PR Opened (SEV-2)

**Indicators**: PR from `weown-bot` not corresponding to any legitimate push; PR with malicious content.

### Response

1. **Do NOT merge** the PR
2. **Investigate**:
   - Check commits: `gh pr view <N> --json commits`
   - Check branch: does the head branch exist? Who pushed to it?
   - Check workflow run: `gh run list --workflow=auto-pr-to-main.yml`
3. **If legitimate** (push happened, workflow fired correctly): close PR, understand why it was unexpected
4. **If malicious** (no legitimate push, or malicious commit pushed via compromised PAT):
   - Escalate to SEV-1 (PAT compromise — Scenario 1)
   - Do not close PR yet — preserve for audit
   - Revoke PAT first, then close PR with explanation
5. **Verify branch protection** was not bypassed (check merge commit if merged): if merged, execute post-merge revert + full security audit

---

## Scenario 6 — Stewardship Gap (SEV-4 Preventive)

**Indicators**: Primary steward unavailable (Roman departed, replacement not assigned); no response to rotation reminders; `pat-health-check.yml` issues not addressed.

### Response

1. **Escalate to `@ncimino`** (permanent reviewer/owner)
2. **Assign new primary steward** from Mohammed / Shahid / Dhruv per CODEOWNERS placeholder TODOs
3. **Update CODEOWNERS** with real GitHub username (replace `@<name>-TODO`)
4. **Update workflow `--add-reviewer`** line with new reviewer username
5. **Update workflows README** "Usage Table" Owner column
6. **Verify new steward has Infisical access** (project `weown-bot GitHub PATs`)

---

## Contact & Escalation

| Situation | Contact |
|---|---|
| Any SEV-1 | `@ncimino` (primary) + current stewards + Yonks (enterprise admin) |
| PAT rotation operational | Current stewards (Roman → Mohammed/Shahid/Dhruv) |
| Infisical support | Infisical Cloud support portal |
| GitHub Enterprise support | WeOwnNetwork enterprise admin (Yonks) → GitHub support |

---

## Post-Mortem Requirements (all SEV-1 and SEV-2)

Within 10 business days:

1. **Timeline** of events (detection → containment → eradication → recovery)
2. **Root cause analysis** (5-whys or equivalent)
3. **What went well** / **what didn't**
4. **Corrective actions** with owners and due dates
5. **Update this runbook** if gaps identified
6. **Update SECURITY_ASSESSMENT.md** threat model if new threats emerged

---

## Related

- `.github/ADR-001-service-account-pat.md`
- `.github/ADR-002-infisical-github-sync.md`
- `.github/SECURITY_ASSESSMENT.md`
- `.github/workflows/README.md`
- `docs/COMPLIANCE_ROADMAP.md` (Phase 1 RS Function, CIS 17)
