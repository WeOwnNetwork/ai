# ADR-005: INT-P01 Retirement from DOKS — Parallel-Build + DNS Cutover

**Status**: Proposed
**Version**: v3.4.5.1 (#WeOwnVer — Season 3, month 4 of S3 = May, ISO-week offset 5 of May, iteration 1; per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md): 2026-05-25 = ISO W22; first ISO week containing 2026-05-01 = W18; offset = 22 − 18 + 1 = 5)
**Date**: 2026-05-25 (proposed)
**Deciders**: `@ncimino` (CTO, decision owner) — `@mshahid538` (Shahid, execution owner) — Jason / Yonks (staging-soak validators)
**Supersedes**: None
**Superseded by**: None
**Related**:

- Source plan: **D383** — *INT-P01 Migration Plan – DOKS → WeOwnLLM* (operator's private notes, not in this public repo). Decision-of-record is captured here in ADR-005 plus the in-repo runbook below; Tuleap A174 / `#1238` is the operational tracker.
- Pattern reference: [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) — Path C slim cloud-init + Layer 2 bootstrap-secret rotation. Reference implementation: [`anythingllm-docker/sites/s004/`](../anythingllm-docker/sites/s004/).
- Site: [`anythingllm-docker/sites/ai.weown.agency/`](../anythingllm-docker/sites/ai.weown.agency/)
- Runbook: [`anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md`](../anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md)
- Tuleap: A174 / `#1238` (cutover), A175 / `#1239` (Phase 0 inventory), A132 / `#1165` (s004 prereq, done), A131 / `#1164` (template SearXNG support)
- Upstream decisions: D67 (100 droplets, no K8s), D330 (Docker + Ansible + Infisical operating model), D341 (DOCR mirror), D381 (WeOwn hardened image standard), D289 (~90% CVE reduction vs upstream)
- Companion: [`anythingllm/CHANGELOG.md`](../anythingllm/CHANGELOG.md) (Kubernetes deployment — being retired for INT-P01)

---

## Context

`INT-P01` (`ai.weown.agency`) is WeOwn's first AnythingLLM instance and hosts the **Calhoun MetaAgent**. It is currently the **last notable holdout** still running on **DigitalOcean Kubernetes Service (DOKS)** rather than the standardised single-droplet Docker pattern adopted by D67 (2025-Q4) and re-affirmed by D330 (2026-Q1).

Three independent pressures converged in 2026-W21 to make retirement of the DOKS deployment the right move now:

1. **Functional defect on DOKS.** Jason verified (2026-05-21) that **SearXNG web search does not work on INT-P01 for the Calhoun MetaAgent** under Claude Opus 4.7 — only Tavily works (Discovery #598). The same SearXNG configuration succeeds on every other droplet-based instance (#468) and on the dedicated SearXNG instance at `searxng.weown.app`. The fault is the DOKS network/ingress posture, not the application or the SearXNG droplet. Spending dev time isolating a DOKS-specific failure for a deployment pattern we have already chosen to retire is poor allocation.
2. **Cost.** DOKS for this workload runs ≈ **$97/mo** vs ≈ **$48/mo** for a single droplet (#514) — **~$49/mo direct savings**, before any consolidation. Recurring, with no offsetting capability.
3. **Image supply chain.** D381 made the **WeOwnLLM hardened AnythingLLM image** (`reg.mini.dev/anythingllm:latest`) the deployment standard, and it is validated working on `s004.ccc.bot` as of 2026-05-21 (A132 / `#1165`). The DOKS instance still runs upstream `mintplexlabs/anythingllm`, which has ~10× the CVE surface (D289). Retirement aligns INT-P01 with the supply-chain standard.

The migration also addresses operability: bringing INT-P01 onto the same template, backup plumbing, secrets path (Infisical), and config-rollout system (A131) as every other instance means the 20+ instance fleet becomes uniformly manageable — a prerequisite for the planned 100-instance scale-out (D67).

---

## Decision

**Retire the INT-P01 DOKS deployment in favor of a single DigitalOcean droplet generated from the [`anythingllm-docker`](../anythingllm-docker/) copier template, using a parallel-build + DNS-cutover migration pattern.**

The decision has three load-bearing components:

### 1. Parallel build (not in-place migration)

The new droplet is provisioned alongside the running DOKS instance. **DOKS is not modified during Phases 0–6** of the runbook. Migration succeeds (or fails) entirely on the new droplet; rollback at any point before decommission is a single DNS A-record edit. This is non-negotiable for a live instance carrying real company work product — the alternative ("upgrade in place") would couple data-migration risk to platform-migration risk to TLS-issuance risk, and a failure mode in any one of them would cascade.

### 2. Staging via DNS-zone neighbour, not a separate environment

Validation runs against `ai-stage.weown.agency` (a sibling under the same parent zone as `ai.weown.agency`). Caddy is configured **dual-hostname from first boot** (`ai-stage.weown.agency, ai.weown.agency` in one site block). Production cutover is therefore a DNS A-record swap on the same droplet — Caddy already has the cert for `ai.weown.agency` because it sits in the same Caddyfile block as the staging name and Let's Encrypt issues both on first request.

This eliminates the "second droplet for staging, third for production" pattern and its associated coordination cost. The trade-off — staging and production share infra during the soak — is acceptable because INT-P01 is a single-tenant Calhoun instance, not a multi-customer SaaS.

### 3. Data migration via a one-shot bridge script, not a generic tool

We add `anythingllm-docker/sites/ai.weown.agency/scripts/migrate-from-doks.sh` (not a template-level addition — INT-P01 is the last DOKS holdout). The script `kubectl exec`s into the live AnythingLLM pod, streams `/app/server/storage` out as a gzipped tar, and **wraps it in the exact layout the existing `restore.sh` already expects** (a "skinny backup" tarball — see [`anythingllm-docker/template/scripts/backup.sh.jinja`](../anythingllm-docker/template/scripts/backup.sh.jinja)). This means the migration introduces **zero new failure modes** in the restore path: if `restore.sh` works for any droplet-native backup, it works for the DOKS-bridge output.

### Validation gates (two hard human checkpoints)

| Gate | Phase | Validator | Pass criterion |
|---|---|---|---|
| 1 | Phase 4 — staging soak | Jason + Yonks (hands-on) | Verification checklist (§7 of source plan) all PASS — including the SearXNG-works gate that motivated the migration |
| 2 | Phase 6 — production cutover | `@ncimino` (CTO) | Gate 1 passed AND maintenance window agreed |

These gates are not advisory — Phase 5/6 do not begin without explicit go-ahead.

---

## Consequences

### Positive

- **Resolves Discovery #598** (SearXNG broken on DOKS) without dev effort spent debugging a deprecated platform.
- **~$49/mo recurring savings** after DOKS decommission.
- **Image supply-chain consolidation** — every WeOwn AnythingLLM instance on the same hardened image (D381), eliminating ~90% of upstream CVE surface (D289).
- **Operability** — INT-P01 joins the fleet-wide config-rollout path (A131) and the standard skinny-backup + DO Spaces + grandfather-father-son retention pipeline.
- **The migration is repeatable** — the runbook + the `migrate-from-doks.sh` bridge are reusable if any other DOKS workload needs the same treatment.
- **The Caddy dual-hostname trick generalises** — same pattern can be used for any DNS-zone-neighbour staging migration on this template going forward (no second droplet required for staging).

### Negative

- **Brief content freeze** during Phases 0 and 5 — Jason coordinates a short quiet window in `♾️ WeOwn.Dev` Signal so the volume tar captures a consistent snapshot. Mitigated by Phase 5's optional delta-sync.
- **Soak coupling** — during the 7-day post-cutover soak, the staging hostname and production hostname share infrastructure. A defect that hits one hits both. Mitigated by the fact that DOKS remains stopped-but-intact for the entire soak, so rollback restores full isolation.
- **Loss of K8s features** — autoscaling, multi-replica rolling updates, native NetworkPolicy. For INT-P01's workload (single-tenant, single-replica AnythingLLM), none of these are load-bearing today — but if INT-P01 ever needs horizontal scale we will revisit on a per-instance basis (likely via the upstream droplet-fleet pattern, not by re-introducing K8s).

### Neutral / acknowledged risk

- The `migrate-from-doks.sh` bridge is INT-P01-specific. It does not become reusable template infrastructure unless and until another DOKS holdout appears.
- AnythingLLM version drift between the DOKS pod and the WeOwnLLM hardened image must be confirmed before cutover (open question in the runbook). If significantly older, pin the new droplet to the same major/minor first and upgrade after stable cutover.

---

## Implementation Verification

The runbook (`anythingllm-docker/sites/ai.weown.agency/MIGRATION_RUNBOOK.md`) encodes the verification path. The acceptance criteria for closing this ADR are:

1. `tofu apply` against `sites/ai.weown.agency/terraform/` succeeds and produces a droplet reachable on `ai-stage.weown.agency` with a valid Let's Encrypt cert.
2. `scripts/migrate-from-doks.sh` produces a tarball that, when fed to `scripts/restore.sh` on the droplet, yields a working AnythingLLM instance with all DOKS workspaces, embeddings, users, and Calhoun MCP configuration intact.
3. **SearXNG web search works for the Calhoun MetaAgent on the new droplet** (the original trigger).
4. Jason confirms Phase 4 verification checklist all-PASS.
5. Post-cutover DNS swap for `ai.weown.agency` reaches the new droplet, Caddy obtains the cert, and 24-hour error rate is no worse than DOKS baseline.
6. 7-day soak completes without incident; DOKS deployment scaled to 0 then decommissioned.

This ADR moves from **Proposed → Accepted** at the close of step 6 above.

---

## Compliance Mappings

| Framework | Control | How this ADR satisfies it |
|---|---|---|
| **NIST CSF 2.0** | PR.IP-3 (config-change procedures) | Migration is fully scripted + documented in runbook, with hard human gates before each irreversible step |
| | PR.DS-1 (data-at-rest) | Backup encrypted at rest via DO Spaces SSE; restore tarball never written to a host outside `/opt/intp01/backups/` |
| | DE.CM-1 (continuous monitoring) | DO monitoring + Caddy access logs in place from first boot via cloud-init |
| | RC.RP-1 (recovery plan executed) | Runbook §Rollback table covers every phase explicitly |
| **SOC 2** | CC8.1 (change management) | Two human approval gates, parallel-build pattern, runbook signed off by deciders above |
| | CC7.2 (system monitoring) | DO alert policy provisioned by `terraform/monitoring.tf` |
| | CC6.3 (logical access) | Infisical Machine Identity is the only credential on the droplet; no application secrets on disk |
| **ISO/IEC 27001:2022** | A.5.30 (ICT readiness for business continuity) | Rollback documented and tested via Phase 1.5 local dry-run before any production exposure |
| | A.5.23 (cloud service usage) | Cloud-service swap (DOKS → droplet) is documented with rationale + risk analysis in this ADR |
| | A.8.13 (information backup) | Skinny-backup with grandfather-father-son retention is wired up from first boot, not bolted on after |
| **ISO/IEC 42001:2023** | A.6.2.7 (responsible development) | Migration motivated by addressing a verified defect (SearXNG broken on DOKS) — not by speculative refactor |
| | A.9.4 (post-deployment monitoring) | 7-day soak with DOKS retained as rollback codifies post-deployment observation period |
| **CIS Controls v8** | 16.9 (segregation of duties) | Decider (`@ncimino`) is not the executor (`@mshahid538`); validation gate is a third party (Jason) |
| | 18.3 (change-management process) | This ADR + the runbook + the Tuleap action items (#1238, #1239) constitute the documented process trail |

---

## Review Cadence

- **At Gate 1 (Phase 4 pass)**: re-read this ADR against the empirical verification result. If anything has changed materially (e.g. vector DB turned out to be Chroma rather than LanceDB and that broke the bridge), update the ADR before proceeding to Gate 2.
- **At Gate 2 close (Phase 7 soak complete)**: flip Status → Accepted. Add a Decision Log entry summarizing actuals (cost saved, downtime, defects found).
- **Annual review** (next: 2027-05): confirm the parallel-build + DNS-cutover pattern is still the right move for migrations in this stack. If the droplet fleet has moved to something else by then (e.g. native K3s, Nomad, or a managed AnythingLLM service), this ADR should be superseded.

---

## Changelog

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-05-25 | v3.4.5.1 | Initial draft (Proposed). Companion to branch `feature/nik-int-p01-doks-to-docker-migration` and Tuleap A174 / `#1238`. | `@ncimino` |
