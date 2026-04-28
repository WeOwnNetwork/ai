# ADR-002: Infisical as Primary Secret Store (via GitHub Sync) for `WEOWN_BOT_PAT`

**Status**: Accepted
**Version**: v3.3.5.1 (#WeOwnVer)
**Date**: 2026-04-23 (initial) / 2026-04-28 (naming convention revised twice — see Decision Log)
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
┌────────────────────────────────────────────────────────┐
│  Infisical Cloud (Pro tier)                            │
│  Project: "weown-bot GitHub PATs" (env: prod)          │
│  Folders (one per target repo or repo cluster):        │
│    /WeOwnNetwork-ai/                                   │
│        secret: WEOWN_BOT_PAT  <- authoritative         │
│    /<ORG>-<REPO>/                                      │
│        secret: WEOWN_BOT_PAT  <- per-folder leaf       │
└────────────┬───────────────────────────────────────────┘
             │ Infisical → GitHub Sync integration
             │ (one Sync per folder; Source Path scopes the Sync
             │  to a single repo's folder; Key Schema = {{secretKey}})
             ▼
┌────────────────────────────────────────────────────────┐
│  GitHub Actions Secrets (per repo)                     │
│    <Repo A>: WEOWN_BOT_PAT                             │  <- mirrored
│    <Repo B>: WEOWN_BOT_PAT                             │
└────────────┬───────────────────────────────────────────┘
             │ workflows reference native ${{ secrets.WEOWN_BOT_PAT }}
             ▼
┌────────────────────────────────────────────────────────┐
│  Workflows (auto-pr-to-main.yml, etc.)                 │
└────────────────────────────────────────────────────────┘
```

### Naming Convention

- **Infisical project**: `weown-bot GitHub PATs` (single shared project for the entire ecosystem; the same project every repo's `weown-bot` PAT lives in)
- **Infisical folder (per target repo)**: `/<ORG>-<REPO>/` (e.g., `/WeOwnNetwork-ai/`); the folder path is the namespacing axis and is what the Sync's Source Path references
- **Infisical secret name (inside each folder)**: `WEOWN_BOT_PAT` (identity-mapped — the SAME name as the GitHub destination, because the GitHub Sync's "Key Schema" is the only source-to-destination transform and it can only ADD prefixes/suffixes, not strip them)
- **GitHub Actions secret name (per repo)**: `WEOWN_BOT_PAT` (always the same at the consumption site — workflows reference `${{ secrets.WEOWN_BOT_PAT }}`)
- **Sync configuration (per repo)**: one Sync per folder, Source Path = `/<ORG>-<REPO>`, Key Schema = `{{secretKey}}` (identity); see `.github/workflows/README.md` §6.1 for the full Sync Options table

This convention has been revised twice on 2026-04-28 (see [Decision Log](#decision-log)). The original convention (`WEOWN_BOT_PAT__<ORG>_<REPO>` in Infisical, identity-renamed by the Sync to `WEOWN_BOT_PAT` in GitHub) assumed a per-secret rename feature that Infisical's GitHub Sync UI does not provide. The first revision used **project-per-repo** (one Infisical project per target repo). The second revision — the current convention — uses **folder-per-repo inside the single shared project**, which is operationally cleaner for a PAT-only namespacing axis (one project-level RBAC boundary, one expiration-reminder convention, sibling folders discoverable from the same landing page).

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

### Initial setup (done as part of PR #7 operationally; revised twice on 2026-04-28)

1. Use the shared Infisical project `weown-bot GitHub PATs` (single project for the entire ecosystem; create it once if not already present)
2. **Create a folder per target repo** at the `prod` environment root (convention: `/<ORG>-<REPO>/`, e.g., `/WeOwnNetwork-ai/`)
3. Inside that folder, add secret: `WEOWN_BOT_PAT` (no `__<ORG>_<REPO>` suffix per the revised naming convention; folder path replaces the suffix as the namespacing axis)
4. Install Infisical GitHub App on the target repo only
5. Create sync integration: Source Path `/<ORG>-<REPO>` → GitHub Actions secret `WEOWN_BOT_PAT` (Key Schema = `{{secretKey}}` identity transform; full sync option matrix in `.github/workflows/README.md` §6.1)
6. Verify sync by updating Infisical and checking GitHub secret "Last updated" timestamp
7. Test workflow run on a throwaway feature branch (`fix/<dev>-test-rotation`)

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

---

## Decision Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-23 | ADR-002 accepted (v3.3.4.1): Infisical primary, GitHub Sync. Initial naming convention: `WEOWN_BOT_PAT__<ORG>_<REPO>` in Infisical, identity-renamed by the Sync to `WEOWN_BOT_PAT` in GitHub. | Single source of truth for `weown-bot` PATs across the ecosystem. Naming convention assumed that the Infisical GitHub Sync UI exposed a per-secret name override at sync-config time. |
| 2026-04-28 (R17) | Naming convention revised — first iteration (v3.3.5.1): Infisical secret name = `WEOWN_BOT_PAT` (no `__<ORG>_<REPO>` suffix). Namespace across repos via separate Infisical projects (`weown-bot/<org>-<repo>`), not secret-name suffixing. Sync Options Configuration documented in `.github/workflows/README.md` §6.1 (Initial Sync Behavior = Overwrite [forced]; Key Schema = `{{secretKey}}` identity; Disable Secret Deletion = Yes; Auto-Sync Enabled = Yes). | Empirical finding during sync configuration on 2026-04-28: Infisical's "Key Schema" can ADD prefixes/suffixes around the `{{secretKey}}` template but cannot STRIP them. The original convention was therefore unworkable at sync-creation time. Revised convention uses identity-mapping (Key Schema `{{secretKey}}`) and project-per-scope namespacing. **PAT for `WeOwnNetwork/ai` was regenerated 2026-04-28 (90-day expiration: 2026-07-27)** and stored as `WEOWN_BOT_PAT` in the new Infisical project under the new convention. **Status remains "Accepted"**; this is an implementation-detail revision, not a decision reversal — Infisical-primary-with-GitHub-Sync is still the chosen approach. |
| 2026-04-28 (R18) | Naming convention revised — second iteration (v3.3.5.1, same day): namespacing axis changed from **project-per-repo** to **folder-per-repo inside the single shared `weown-bot GitHub PATs` project**. Each repo gets a folder `/<ORG>-<REPO>/` (e.g., `/WeOwnNetwork-ai/`) holding an identity-mapped `WEOWN_BOT_PAT` secret. The Sync's Source Path references the folder; the Key Schema remains `{{secretKey}}` identity. The full Sync Options matrix is unchanged (Initial Sync Behavior = Overwrite [forced]; Key Schema = `{{secretKey}}`; Disable Secret Deletion = Yes; Auto-Sync Enabled = Yes). | User-driven operational simplification while configuring the actual `WeOwnNetwork/ai` Sync on 2026-04-28: a single Infisical project with one folder per target repo is operationally cleaner than N projects — (a) one project-level RBAC boundary instead of N; (b) one expiration-reminder convention; (c) sibling folders discoverable from the same project landing page; (d) the existing `weown-bot GitHub PATs` project absorbs new repos without new project creation. Both patterns produce identical Sync Options; only the Source Path differs (project root `/` vs. per-repo `/<ORG>-<REPO>`). The first iteration (project-per-repo, R17) is preserved in the Decision Log row above for audit trail and remains a valid alternative when project-level RBAC isolation is required (rare for PAT-only secrets). **Status remains "Accepted"**; the architectural decision (Infisical primary + GitHub Sync) and the identity-mapped Key Schema are unchanged. **Lesson codified as a NEW operational rule (R18 close-out)**: when documenting a vendor-feature-driven convention, validate the convention against actual UI configuration before broad cascade — first-cut conventions may need a second-cut revision once the UI's namespacing primitives are exercised in practice. |
