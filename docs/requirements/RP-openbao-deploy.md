---
id: b200cf9c-8039-47a5-b14b-d35a8a8d0804
type: requirement-package
status: draft
owner: Nik
created: 2026-08-19
north_star_goal: G2
okr: O1
source: "ELF Research §2 + ai DESIGN doc (vault + repo)"
---

# RP — Reusable OpenBao Deploy (G2)

Turns Part A of the design proposal — a reusable ansible role that stamps OpenBao onto any box —
into checkable acceptance criteria. House standard: **tofu provisions the hardware, ansible installs
the software.** OpenBao is the trust root, so it runs as a host systemd service, not a container.

Extends: [DESIGN — reusable OpenBao deploy + secret-store POC](../DESIGN-openbao-reusable-deploy-and-secret-store-poc.md) (Part A, §2).
Source: *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §2.
Capability: [CAP-secrets-management](../capabilities/CAP-secrets-management.md).

## Implementation

The Wave-0 implementation lives in the dedicated **WeOwnCloud/openbao** repository (re-homed from
this repo on 2026-08-17, the first instance of the monorepo split). That repo owns the role itself and
the WeOwn deployment; this package owns the *requirements* the role must satisfy.

| Deliverable | Where |
| --- | --- |
| Ansible role `openbao` (install → configure → systemd → init/unseal → verify) | WeOwnCloud/openbao `ansible/roles/openbao/` |
| Main-store playbook + unseal-vault playbook | WeOwnCloud/openbao `ansible/` |
| Four policy shapes + governance bootstrap | WeOwnCloud/openbao `governance/` |
| Store-agnostic seam (`SECRET_BACKEND` dispatcher) | WeOwnCloud/openbao `seam/` |

## Required properties (priority order)

| # | Property | Why |
| --- | --- | --- |
| 1 | **Idempotent** — re-running against an initialised box converges; never re-inits or orphans data | A "reusable" playbook that re-inits is a data-loss tool |
| 2 | **Fails closed on init state** — storage present but node sealed and no shares supplied → the play STOPS; never starts an empty server | The Keycloak empty-volumes-behind-green-healthchecks class, worse blast radius |
| 3 | **Asserts the real contract** — success = `/v1/sys/health` initialised + unsealed **and** a write→read round-trip, not "systemd says active" | Proxies lie |
| 4 | **Storage on the encrypted volume** | Same rule as every stateful fleet service |
| 5 | **Backed up before trusted** — nothing real enters it until a restore rehearsal has passed | "Backups exist" ≠ "restores rehearsed" |

## Deploy modes

| Mode | Use | Unseal |
| --- | --- | --- |
| **Shamir** (POC default) | Wave 0 / dev posture: TLS off, 1-of-1, synthetic secrets only; the role prints a POC warning on every run | A human unseals |
| **Transit auto-unseal** (production) | Self-hosted unseal vault unwraps the master key; main store reboots unattended | Unseal vault is itself Shamir (3-of-5 for WeOwn); prod posture refuses 1-of-1 or TLS-off |

Standing production rules (from the topology verdict): never restart the main store while the unseal
vault is down (enforced by a systemd `ExecStartPre` preflight and the role's restart handler); P1
alert on the unseal vault sealed/down; nightly snapshot of the unseal vault to offsite storage;
rotate wrapping key → snapshot immediately; renew the unwrap token daily, re-mint quarterly
(mint-before-revoke).

## Acceptance criteria

- [ ] `ansible-playbook` deploys OpenBao to a fresh tofu-provisioned box in **≤ 15 minutes**
      wall-clock, measured and recorded.
- [ ] **Working + tested on ≥ 1 box by 2026-08-23**; the run log shows health initialised+unsealed
      and a write→read round-trip.
- [ ] Second run against the same box converges with zero changes to init state (idempotency proven
      on a live node, not only by syntax check).
- [ ] Fail-closed gate demonstrated: sealed node + no shares → play stops with an explicit message.
- [ ] Data directory is on the encrypted block volume.
- [ ] A snapshot is taken and restored to a scratch node before any non-synthetic secret is written.
- [ ] Governance bootstrap mounts `weown/`, renders one policy per the four shapes, and asserts the
      no-`weown/data/*` invariant ([RP-secrets-governance](RP-secrets-governance.md)).
- [ ] POC posture warning prints on every successful Shamir-mode run; prod posture refuses 1-of-1
      or TLS-off.
- [ ] In-repo validation green: `ansible-playbook --syntax-check`, `bash -n` + `shellcheck`, seam
      dispatch tests.
- [ ] Each deployed store (and unseal vault) has a Resource Registry row: box, engagement, quorum
      scheme, holder names (never shares), snapshot path.

## Out of scope (gated elsewhere)

- Real secrets → unseal custody decision ([RP-secrets-governance](RP-secrets-governance.md) §5).
- Per-instance AppRole / secret-id issuance → the provisioner at provision time.
- The Infisical→OpenBao migration itself → [RP-infisical-migration](RP-infisical-migration.md).

## Work items (to be filed) and release tags

`WeOwnNetwork/ai` has issues disabled, so the package carries its own work-item list; the WeOwn
vault holds the mirror. File on the owning repo where issues exist; dedupe first.

| # | Work item | Owning repo | Notes |
| --- | --- | --- | --- |
| W1 | RP-secrets-governance — lock + publish the §2 plan (`secrets-governance-v1`) | this repo (docs) | governance is a doc release, not code |
| W2 | RP-openbao-deploy — reusable role, transit auto-unseal, acceptance criteria met on ≥1 box | `WeOwnCloud/openbao` | **dedupe against A572** — that ticket stays *the* G2 playbook ticket; Wave-0 branch implements it |
| W3 | `seam: SECRET_BACKEND dispatcher` — the store-agnostic entrypoint seam | `WeOwnCloud/openbao` (seam) + this repo (ADR-006 entrypoint) | **critical path — gates wave 1** |
| W4 | RP-infisical-migration — wave plan + per-instance cutover recipe | this repo + `weown-fleet` | rollback = `SECRET_BACKEND` flip |
| W5 | RP-secrets-register — register live, 0 orphans, before wave 1 | this repo / WeOwn vault State | |
| W6 | RP-deploy-agent — S1 skill contract | this repo | non-gating, parallel |
| W7 | `custody: unseal quorum decision + drill` | **Nik / Jason** (decision, not engineering) | runbook: `WeOwnCloud/openbao docs/runbooks/wave0-start-and-custody-drill.md` |

Release tags, in order: `secrets-governance-v1` (G5 lock) → `openbao-poc` (Wave 0) →
`migration-w1` (target 2026-08-23) → `migration-complete` (target 2026-08-31).

## Trace

Rolls up to OKR **O1 — Deployment is repeatable** (KR2) → North Star **G2 — OpenBao deployment**
(*WeOwn North Star — Agency Deployment Platform*, WeOwn vault).

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
| 2026-08-19 | Added *Work items (to be filed) and release tags* so the package is self-contained (issues disabled on this repo) | Nik |
