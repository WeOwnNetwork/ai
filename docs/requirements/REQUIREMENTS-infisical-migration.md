# Infisical → OpenBao Migration — requirements

**Status:** draft · **Owner:** Nik · **Source:** *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §3

A **partial, staged, rollback-first** migration: machine identities move to free OpenBao AppRoles
(the cost driver); Infisical stays for human/dev UX until it costs nothing to leave. Every instance
cuts over through the `SECRET_BACKEND` seam; rollback is flipping the variable back.

Capability: [secrets-management](../design/DESIGN-secrets-management.md).

## Pre-flight (blocks wave 1)

| Gate | Package / owner |
| --- | --- |
| Governance plan published | [secrets-governance](REQUIREMENTS-secrets-governance.md) |
| Unseal custody decided + drilled once | owner decision |
| POC store backup restore-rehearsed | [openbao-deploy](REQUIREMENTS-openbao-deploy.md) |
| Secrets Register live | [secrets-register](REQUIREMENTS-secrets-register.md) |
| `SECRET_BACKEND` seam built and dispatch-tested | seam ticket — **critical path** |

## Wave order (cost-first, blast-radius-ordered)

| Wave | What moves | Why this order | Target |
| --- | --- | --- | --- |
| 0 | POC box, synthetic secrets only | Proves playbook + seam + policies; zero risk | — |
| 1 | **One non-critical instance** — recommended `weown/agency/weown/chat/sales` | Real instance, lowest blast radius | **2026-08-23** |
| 2 | Remaining per-instance machine identities + their app-project secrets, one instance at a time (billing → gitea-git → sso last) | Billable identities are the cost driver; SSO last because it is the auth root | **2026-08-31** (cliff) |
| 3 | `infra/` tofu variables + provider tokens | Dev-facing, unhurried; or stays on a free tier | after the cliff |
| — | **Never in a wave: half an instance** | The seam flips whole instances only | — |

Cliff contingency (active): wave 2 orders **highest-cost identities first**, and handover artifacts
(governance plan, register, unseal runbook + drill record, this recipe) take priority over breadth.

## Per-instance cutover recipe (repeated N times, boring by design)

1. **Register rows** (`building`) for every path the instance will own — enumerated from an
   Infisical export of **names only** (an agent may see names, never values).
2. **Playbook mints policy + AppRole** from the governance templates.
3. **Blind store-to-store copy** — a script on the box or operator machine pipes Infisical export →
   `bao kv put`; values never in an agent context, never in scrollback.
4. **Verify by names + hash** — compare key lists and server-side digests of values via a script
   that prints digests only (agent-runnable).
5. **Flip `SECRET_BACKEND=openbao`** for the instance; redeploy; health probe **plus** a real
   secret-consuming probe (the app is actually up, not just the container).
6. **Soak 48 h** → flip register rows to `active`; mark the Infisical machine identity
   **disabled (not deleted)**.
7. **Day 30**: delete the Infisical identity + project folder (the rollback window closes).

**Rollback at any point** = `SECRET_BACKEND=infisical` + redeploy (the identity is still
disabled-not-deleted; one API call re-enables it). This is why the seam precedes wave 1.

## Zero-downtime + cost verification

- Per-instance container restart is the fleet's existing deploy unit; stagger instances; schedule
  the SSO instance in a window because everything authenticates against it.
- Before wave 2, obtain the actual invoice axis from the Infisical portal. Success is **cost removed,
  measured on the next invoice** — not assumed.

## Acceptance criteria

- [ ] All five pre-flight gates recorded as passed before wave 1 starts.
- [ ] Wave 1 instance running on `SECRET_BACKEND=openbao` by 2026-08-23, with health + a real
      secret-consuming probe green.
- [ ] A rollback (flip back to `infisical` + redeploy) rehearsed once on the wave-1 instance and
      logged before wave 2.
- [ ] Every cutover step 4 verification shows identical key lists and digests; no value ever appears
      in an agent transcript or terminal scrollback.
- [ ] 100% of migrated machine identities on OpenBao AppRoles by 2026-08-31; Infisical
      machine-identity overage measured at zero on the following invoice.
- [ ] No instance is ever half-migrated; register shows zero `building` rows per completed instance.
- [ ] Disabled Infisical identities retained 30 days before deletion.
- [ ] Handover artifacts complete by 2026-08-31 (governance plan, register, unseal runbook + drill
      record, this recipe).

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Restructured to WeOwn doc conventions: dropped internal taxonomy frontmatter + trace sections, renamed off `CAP-`/`RP-` prefixes | Nik |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
