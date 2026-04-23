# ADR-002: Infisical as Primary Secret Store (via GitHub Sync) for `WEOWN_BOT_PAT`

**Status**: Accepted
**Version**: v3.3.4.1 (#WeOwnVer)
**Date**: 2026-04-23
**Deciders**: `@romandidomizio`, `@ncimino`
**Related**: ADR-001 (service account and PATs)
**Supersedes**: None
**Superseded by**: None

---

## Context

The auto-PR workflow (`.github/workflows/auto-pr-to-main.yml`) needs access to the `weown-bot` service account's Personal Access Token at runtime via `${{ secrets.WEOWN_BOT_PAT }}`. Across the ecosystem, **many repositories** will eventually need per-repo PATs for `weown-bot` (see ADR-001).

### Where should the PAT live as the source of truth?

Options:

1. **GitHub Actions Secrets only** — a copy per repo, managed manually in each repo's Settings → Secrets
2. **Infisical only** — authoritative in Infisical; workflow fetches at runtime via Infisical CLI or GitHub Action
3. **Infisical primary, GitHub Sync** — authoritative in Infisical; Infisical pushes to each repo's GitHub Actions Secrets continuously

WeOwn already runs Infisical Pro for Kubernetes secret management (e.g., AnythingLLM's `infisical-secret.yaml`, n8n rotation workflows) with 90-day audit logs, version history, RBAC, and IP allowlisting.

---

## Decision

**Adopt Option 3: Infisical primary, GitHub Sync integration.**

### Architecture

```
┌──────────────────────────────────────────────────────┐
│  Infisical Cloud (Pro tier)                          │
│  Project: "weown-bot GitHub PATs"                    │
│  Secrets (one per repo/org):                         │
│    - WEOWN_BOT_PAT__WEOWNNETWORK_AI                  │  <- authoritative
│    - WEOWN_BOT_PAT__WEOWNNETWORK_<REPO>              │
│    - WEOWN_BOT_PAT__<ORG>_<REPO>                     │
└────────────┬─────────────────────────────────────────┘
             │ Infisical → GitHub Sync integration
             │ (per-integration: maps Infisical secret → target repo)
             ▼
┌──────────────────────────────────────────────────────┐
│  GitHub Actions Secrets (per repo)                   │
│    <Repo A>: WEOWN_BOT_PAT                           │  <- mirrored
│    <Repo B>: WEOWN_BOT_PAT                           │
└────────────┬─────────────────────────────────────────┘
             │ workflows reference native ${{ secrets.WEOWN_BOT_PAT }}
             ▼
┌──────────────────────────────────────────────────────┐
│  Workflows (auto-pr-to-main.yml, etc.)               │
└──────────────────────────────────────────────────────┘
```

### Naming Convention

- **Infisical secret name**: `WEOWN_BOT_PAT__<ORG>_<REPO>` (double underscore separates the constant prefix from the scope)
- **GitHub Actions secret name (per repo)**: `WEOWN_BOT_PAT` (always the same at the consumption site)

This allows one Infisical project to hold PATs for many repos without collision, while workflows stay simple and consistent across the ecosystem.

---

## Alternatives Considered

### Alternative 1: GitHub Secrets Only

- ✅ Zero extra infrastructure; GitHub native
- ❌ Each PAT rotation requires manually updating each repo — does not scale
- ❌ No unified audit trail — each repo's secret history is isolated
- ❌ No consolidation across orgs
- ❌ Rotation errors (missed repos, typos) become operational incidents

### Alternative 2: Infisical at Runtime (no sync)

Use the Infisical CLI or GitHub Action to fetch the PAT in every workflow run.

- ✅ PAT never lives in GitHub Secrets
- ❌ Adds workflow runtime dependency on Infisical uptime and authentication (Machine Identity)
- ❌ Every workflow must include Infisical setup steps (more surface area)
- ❌ Risk of CI flakiness when Infisical is degraded
- ❌ More complex to reason about for new engineers

### Alternative 3 (Chosen): Infisical Primary, GitHub Sync

- ✅ **Single source of truth**: rotate once in Infisical, all repos update within seconds
- ✅ **Unified audit trail**: 90-day logs in Infisical show who rotated what and when
- ✅ **Workflow simplicity**: native `${{ secrets.WEOWN_BOT_PAT }}`, no runtime dependency on Infisical
- ✅ **Matches existing K8s secret management pattern** (reuses mental model)
- ✅ **Ecosystem-ready**: scales to any number of repos/orgs

---

## Consequences

### Positive

- ✅ One place to rotate, revoke, or audit any PAT across the entire ecosystem
- ✅ Version history and rollback in Infisical
- ✅ RBAC and IP allowlisting on the Infisical project
- ✅ SOC 2 / ISO 27001 audit evidence centralized (90-day logs)
- ✅ Clear replication recipe when adding new repos (see `.github/workflows/README.md`)

### Negative / Tradeoffs

- ⚠️ **One-time setup per repo** — install Infisical GitHub App + create sync integration
  - *Mitigation*: recipe documented in workflows README; <10 minutes per repo
- ⚠️ **Sync latency** — GitHub secret lags Infisical updates by up to ~60 seconds
  - *Impact*: negligible; not in the workflow runtime path
- ⚠️ **Dependency on Infisical uptime** for **rotation**, not for runtime
  - *Impact*: workflow keeps running on the last-synced value; rotation may be delayed if Infisical is down

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Infisical project breach | Low | High | RBAC, 2FA, IP allowlisting, audit logs; rotate all PATs if detected |
| Sync integration misconfigured | Medium (setup) | Medium | Verify in repo Settings → Secrets → Last updated; verify workflow run |
| Infisical Cloud outage during rotation | Low | Low | Rotation can wait; existing secret keeps workflows running |
| Accidental secret exposure in Infisical audit log | Very Low | Low | Infisical redacts secret values in logs; only metadata is logged |

---

## Implementation Notes

### Initial setup (done as part of PR #7 operationally)

1. Rename/confirm Infisical project: `weown-bot GitHub PATs`
2. Add secret: `WEOWN_BOT_PAT__WEOWNNETWORK_AI`
3. Install Infisical GitHub App on `WeOwnNetwork/ai` only
4. Create sync integration: Infisical secret → GitHub Actions secret `WEOWN_BOT_PAT`
5. Verify sync by updating Infisical and checking GitHub secret "Last updated" timestamp
6. Test workflow run on a throwaway feature branch

### Replication for a new repo

Full steps in `.github/workflows/README.md` → "Replicating `weown-bot` for a New Repository".

### Rotation

Full steps in `.github/workflows/README.md` → "PAT Rotation Procedure".

### Alerts

Three-layer alert stack described in `.github/workflows/README.md` → "PAT Alert Stack":
- GitHub native email (7 days before expiry)
- Infisical secret reminder (14 days before rotation date)
- Scheduled GitHub Action `pat-health-check.yml` (opens issue 14 days before; hard-fails 3 days before)

---

## Related

- **ADR-001**: Why we use a service account + fine-grained PATs in the first place
- **`.github/SECURITY_ASSESSMENT.md`**: Threat model
- **`.github/INCIDENT_RESPONSE.md`**: Incident scenarios including Infisical breach
- **`.github/workflows/README.md`**: All operational procedures
- **`docs/COMPLIANCE_ROADMAP.md`**: How this decision supports compliance phases

---

## References

- Infisical docs: https://infisical.com/docs
- Infisical GitHub integration: https://infisical.com/docs/integrations/cicd/githubactions
- NIST CSF 2.0 PR.DS (Data Security) and PR.AC (Access Control)
- CIS Controls v8: Control 3 (Data Protection), Control 6 (Access Control Mgmt)
- ISO/IEC 27001:2022 Annex A.5.15, A.8.2, A.8.24 (cryptographic controls, secret mgmt)
