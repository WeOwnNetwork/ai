# Security Assessment — Auto-PR Workflow, `weown-bot` Service Account, and Infisical GitHub Sync

**Scope**: PR #7 architecture — automated PR creation workflow using the `weown-bot` GitHub service account with PATs synced from Infisical Cloud (Pro tier).
**Version**: v3.3.4.1 (#WeOwnVer)
**Date**: 2026-04-23
**Owner**: `@ncimino` + `@romandidomizio` (post-2026-05-15: Mohammed/Shahid/Dhruv)

---

## Assets Being Protected

| Asset | Sensitivity | Location |
|---|---|---|
| `weown-bot` GitHub account credentials (password + 2FA secret + recovery codes) | Critical | Password manager + Yonks-held recovery codes |
| `WEOWN_BOT_PAT__WEOWNNETWORK_AI` (authoritative PAT value) | Critical | Infisical Cloud, project `weown-bot GitHub PATs` |
| `WEOWN_BOT_PAT` (mirrored GitHub Actions secret) | Critical | GitHub repo `WeOwnNetwork/ai`, Settings → Secrets |
| Source code in `WeOwnNetwork/ai` | High | GitHub |
| Workflow files in `.github/workflows/` | High | GitHub |
| Main branch integrity | Critical | GitHub (enforced via branch protection) |
| Infisical project access (RBAC, audit logs) | High | Infisical Cloud |

---

## Threat Model (STRIDE-lite)

| # | Threat | Category | Likelihood | Impact | Risk | Mitigations |
|---|---|---|---|---|---|---|
| T1 | PAT exfiltrated via GitHub Actions log leak | Information Disclosure | Low | High | Medium | `permissions: contents: read, pull-requests: write` (minimum); no `echo $SECRET`; fine-grained scope limits damage |
| T2 | Attacker obtains PAT via Infisical breach | Information Disclosure | Low | High | Medium | Infisical RBAC + 2FA + IP allowlisting; 90-day audit logs; rotation procedure |
| T3 | `weown-bot` account takeover (credential stuffing, phishing) | Spoofing | Low | Critical | Medium | 2FA mandatory; unique email; enterprise-managed; no direct commit access; audit logs |
| T4 | Malicious commit pushed via `weown-bot` (insider threat) | Tampering | Very Low | Critical | Low | Branch protection requires 2 approvals; CODEOWNERS review required; `weown-bot` cannot bypass |
| T5 | PAT expires unrotated, auto-PR stops working | Availability | Medium | Low | Low | 3-layer alert stack (GitHub email, Infisical reminder, scheduled `pat-health-check.yml`) |
| T6 | Infisical Sync misconfigured, wrong PAT synced to repo | Tampering | Low | Medium | Low | Verify in repo Settings → Secrets "Last updated"; test workflow run after setup |
| T7 | Auto-PR workflow used to exfiltrate code via PR body | Information Disclosure | Low | Low | Low | Workflow is OSS in repo; reviewed via normal PR process; body generated from commits |
| T8 | Copilot review bypassed by auto-PR posing as bot | Elevation of Privilege | N/A | N/A | N/A | `weown-bot` is human-type account — Copilot review IS triggered (this is the intent) |
| T9 | Unauthorized rotation / revocation of PAT | Tampering / DoS | Low | Medium | Low | Infisical RBAC restricts who can edit secrets; audit trail shows who did what |
| T10 | Stewardship gap post-2026-05-15 (account orphaned) | Governance | Medium | High | Medium | CODEOWNERS TODO + transition checklist in workflows README |

---

## Trust Boundaries

```
┌───────────────────────────────────────────────────────────────────┐
│  HUMAN AUTHORS                                                    │
│  (developers push to feature/*, fix/*, docs/*, hotfix/*)         │
└──────────────────────────────┬────────────────────────────────────┘
                               │ git push (SSH or HTTPS)
                               ▼  [Trust boundary]
┌───────────────────────────────────────────────────────────────────┐
│  GITHUB REPOSITORY (WeOwnNetwork/ai)                              │
│  - Workflow runner triggered on push                              │
│  - Authenticates to itself using WEOWN_BOT_PAT                    │
│  - Calls gh CLI to create PR attributed to weown-bot              │
└──────────────────────────────┬────────────────────────────────────┘
                               │
                               ▼  [Trust boundary]
┌───────────────────────────────────────────────────────────────────┐
│  GITHUB COPILOT CODE REVIEW                                       │
│  - Triggered by PR authored by human-type account (weown-bot)     │
│  - Performs static analysis per copilot-instructions.md           │
└──────────────────────────────┬────────────────────────────────────┘
                               │
                               ▼  [Trust boundary]
┌───────────────────────────────────────────────────────────────────┐
│  HUMAN REVIEWERS                                                  │
│  - 2 approvals required (branch protection)                       │
│  - @ncimino always + @romandidomizio (or post-handoff specialist) │
└───────────────────────────────────────────────────────────────────┘

Parallel trust path (secret management):

┌─────────────────────────┐    sync (Infisical → GitHub)    ┌─────────────────────────┐
│  Infisical Cloud (Pro)  │ ───────────────────────────────▶│  GitHub Actions Secrets │
│  authoritative          │                                 │  mirror                 │
└─────────────────────────┘                                 └─────────────────────────┘
```

---

## Controls In Place

### Access Control (NIST PR.AC / CIS 5, 6 / ISO A.5.15-A.5.18)

- Fine-grained PAT scoped to a single repo
- PAT permissions minimized: `Contents: R/W`, `Pull requests: R/W`, metadata auto
- 2FA on `weown-bot` GitHub account
- 2FA on Infisical Pro accounts
- CODEOWNERS enforces review assignment
- Branch protection requires 2 approvals (enforced at GitHub layer, not workflow layer)

### Secret Management (NIST PR.DS / CIS 3 / ISO A.8.24)

- PAT stored in Infisical (not in source code, not in GitHub Actions manually)
- Infisical 90-day audit logs capture every secret change
- Infisical RBAC restricts who can view/modify
- GitHub Actions secret is encrypted at rest
- Workflow uses `env:` + GitHub secret expansion (never echoes secret)

### Network Security (NIST PR.AC-5 / CIS 12 / ISO A.8.20-A.8.22)

- Infisical IP allowlisting (if configured) restricts secret management origin
- GitHub Actions runs in GitHub-managed runners (public IPs, ephemeral)
- PAT scope limits damage if runner is compromised

### Monitoring & Detection (NIST DE / CIS 8, 13 / ISO A.8.15-A.8.16)

- `pat-health-check.yml` scheduled weekly → early warning of PAT expiration
- GitHub native email alerts for PAT expiration (7 days before)
- Infisical secret expiration reminders (14 days before)
- GitHub audit log captures all PAT usage events
- Infisical audit log captures all secret access/modification events
- PR creation events visible in repo's Pull Requests tab

### Incident Response (NIST RS / CIS 17 / ISO A.5.24-A.5.27)

- Documented IR scenarios in `.github/INCIDENT_RESPONSE.md`
- RTO/RPO defined per scenario
- Rotation procedure callable in < 15 minutes

### Change Management (NIST GV / CIS 4 / ISO A.5.37, A.8.32)

- All workflow changes go through PR review
- ADRs capture major decisions
- Top-level `/CHANGELOG.md` tracks repository-level changes
- Per-chart CHANGELOGs preserved

---

## Residual Risks (Accepted)

| Risk | Why Accepted | Review Cadence |
|---|---|---|
| 90-day PAT lifetime (vs. 1-hour GitHub App token) | Copilot requires human-type account — GitHub Apps disqualified. Long lifetime mitigated by fine-grained scope + 3-layer alerts + rotation RTO 1h. | Annual |
| Manual PAT creation | GitHub does not expose PAT creation API. Mitigated by documented 13-step procedure + scheduled alerts. | Each rotation |
| Single bot account across ecosystem | Per-repo PATs limit blast radius; account compromise is the only cross-repo risk, mitigated by 2FA + enterprise management. | Annual |

---

## Compliance Mapping

| Framework | Controls Addressed |
|---|---|
| **NIST CSF 2.0** | GV.RM, ID.AM, PR.AC, PR.DS, PR.IP, DE.CM, RS.AN, RS.MI |
| **CIS Controls v8** | 1, 3, 5, 6, 7, 8, 13, 16, 17 |
| **CSA CCM v4** | IAM, CCC, DSI, SEF, TVM, STA |
| **ISO/IEC 27001:2022** | A.5.15, A.5.16, A.5.18, A.5.24-27, A.5.37, A.8.2, A.8.5, A.8.15, A.8.24, A.8.32 |
| **SOC 2 TSC** | CC6.1, CC6.2, CC6.3, CC7.1, CC7.2, CC8.1 |

---

## Review History

| Date | Reviewer | Outcome |
|---|---|---|
| 2026-04-23 | Initial draft (v3.3.4.1) | Document established alongside PR #7 |

**Next review**: 2026-07-23 (90 days) or earlier if incident triggers re-assessment.

---

## Related

- `.github/ADR-001-service-account-pat.md`
- `.github/ADR-002-infisical-github-sync.md`
- `.github/INCIDENT_RESPONSE.md`
- `.github/workflows/README.md`
- `docs/COMPLIANCE_ROADMAP.md`
