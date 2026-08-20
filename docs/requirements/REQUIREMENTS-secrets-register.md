# Secrets Register — requirements

**Status:** draft · **Owner:** Nik · **Source:** *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §4

A single source of truth for **which secret belongs to what** — one row per secret path, mapping
agency / platform / instance / service → OpenBao path — so nothing is orphaned across the migration.
It is a **dedicated** register (not rows in the general Resource Registry) and it must be live
**before the first migration wave**.

the live register is *State / Secrets Register* (WeOwn vault).
Capability: [secrets-management](../design/DESIGN-secrets-management.md).

## Why dedicated

| Reason | Detail |
| --- | --- |
| Different lifecycle | Per-secret (`building → active → disabled → retired`) vs per-resource |
| Different columns | Path, consumer identity, source, rotation — not box/IP/purpose |
| Different scale | Grows ~10× the Resource Registry's row count |
| Cross-linked | Both ways with the Resource Registry; the vault doc is canonical |

## Home

- **Canonical:** the WeOwn vault (*State / Secrets Register*) — the vault worker owns edits.
- **Optional mirror:** a generated **names-only** mirror may later land in the fleet repo for
  tooling; the vault doc remains the single source of truth.
- **Never** contains a value — names, paths, and identifiers only.

## Row schema

| Column | Content |
| --- | --- |
| Path | `weown/<tier>/<scope>/<service>/<key>` |
| Tier / Scope | `platform` / `agency` / `infra` + the scope segment |
| Consumer identity | AppRole name (≡ policy name) or OIDC group |
| Service it serves | the instance-service consuming it |
| Source | `migrated-from <Infisical project/path>` or `minted-new` |
| Rotation | owner + cadence |
| Status | `building` / `active` / `disabled` / `retired` (latest-wins, dated notes) |
| Since | date |

## Rules

- **Registry-first:** the row exists (`building`) before the secret does.
- **Path leaf ≡ identity name ≡ register row** — one name across store, identity, and register.
- **No values, ever.**
- A migration wave is DONE only when the register shows **zero `building` rows** for that instance.
- **Orphan sweep (quarterly):** `bao kv list` (names only) diffed against the register in both
  directions; unmatched either way = a finding.

## Acceptance criteria

- [ ] Register document exists with the schema above and is live **before wave 1** of
      [infisical-migration](REQUIREMENTS-infisical-migration.md).
- [ ] **100% of migrated secrets** carry a row (path → agency/platform/instance/service).
- [ ] **Zero orphans**: first orphan sweep (store names vs register, both directions) returns no
      unmatched entries; sweep procedure documented and scheduled quarterly.
- [ ] Every row's path leaf, consumer identity, and policy name are identical strings.
- [ ] No row contains a secret value (checked by review before publish; names/paths/IDs only).
- [ ] Status is latest-wins with dated notes; completed instances show zero `building` rows.
- [ ] Cross-link present in both directions with the Resource Registry.

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Restructured to WeOwn doc conventions: dropped internal taxonomy frontmatter + trace sections, renamed off `CAP-`/`RP-` prefixes | Nik |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
