# ADR-006: In-Container Infisical Secret Injection — Runtime Delivery Standard for `*-docker` Services

**Status**: Proposed
**Version**: v3.4.5.1 (#WeOwnVer — Season 3, month 4 (May), ISO-week offset 5 of May, iteration 1; per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md))
**Date**: 2026-05-30 (proposed)
**Deciders**: `@ncimino` (CTO, decision owner) — Peter (Sr DevOps, template authoring) — Jason / Yonks (priority sponsor)
**Supersedes**: None
**Superseded by**: None
**Related**:

- Pattern doc: [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) — Layer 1 (remote state) + Layer 2 (bootstrap-secret rotation) + Path C (thin cloud-init + Ansible). This ADR defines the **runtime secret-delivery** half that those layers bootstrap.
- Reference site: [`anythingllm-docker/sites/s004.ccc.bot/`](../anythingllm-docker/sites/s004.ccc.bot/) — pilot target (the live INT-S004 rebuild).
- Reviewer rules: [`.github/copilot-instructions.md`](copilot-instructions.md) §3.8 (Docker/Compose), §3.10 (Infisical), §3.13 (supply chain).
- Upstream decisions: D247 (Infisical-only for secrets, runtime injection), D330 (Docker + Ansible + Infisical operating model), D67/D383 (droplet fleet, INT-P01 retirement).

---

## Context

Today secrets reach `*-docker` services **host-side**: Ansible runs
`infisical run --projectId … -- docker compose up -d`, and `compose.prod.yaml`
interpolates `${VAR}` into each service's `environment:` block. Infisical populates the
`docker compose` CLI process; Compose resolves `${VAR}` at parse time and **bakes the
resolved values into the container at create time**.

Two consequences follow from "baked at create time":

1. **A `docker restart` / `docker compose restart` does NOT pick up a rotated secret.** The
   restarted container keeps the env it was created with. Only a recreate under a fresh
   `infisical run` (`docker compose up -d --force-recreate`) loads new values — which is what
   `ansible/deploy.yml`'s reconcile handler already does, so `./deploy.sh` refreshes secrets
   correctly, but an operator manually bouncing a container does not. The live site READMEs
   (`anythingllm-docker/sites/s004.ccc.bot/README.md`, `ai.weown.agency/README.md`) and the
   `anythingllm-docker/template/` already document this correctly — redeploy refreshes, a bare
   restart does not — which is exactly the operator-facing limitation this ADR removes.
2. **Automatic key rotation has no consumer-side trigger.** If Infisical rotates a credential
   on a schedule, nothing on the droplet reloads it until the next deploy. Auto-rotation is
   only useful if the workload re-reads — which the current model can't do without a redeploy.

Resolved secret values also land in `docker inspect <ctr>` (`Config.Env`) and the compose
process env on the host. On single-tenant, root-owned, firewalled droplets this is a low,
accepted residual — but it is a residual.

We want: **update a secret in Infisical → bounce the container → it loads the new value**,
with each workload scoped to exactly its own project, minimal downtime, no image rebuilds,
and a clean path to auto-rotation and to the eventual K8s/K3s move.

## Decision

**Move secret resolution from the host into the container.** Each service authenticates to
Infisical at its own startup with a **project-scoped Machine Identity** and fetches only that
project's secrets, via `infisical run` as the container entrypoint. A plain `docker restart`
then re-authenticates and re-fetches, making **bounce-to-refresh** the supported runtime
path.

This composes with the existing bootstrap layers rather than replacing them. Layer 2 already
leaves two things on every droplet: the Infisical CLI at `/usr/bin/infisical` and the
**rotated v2** Machine Identity at `/opt/<project>/.infisical-auth.env` (`0600 root`). The
container **reuses both** — no rebuilt image, no new credential:

- Bind-mount (read-only) the host CLI binary and a container-readable copy of the auth file.
- Override the compose `entrypoint:` to authenticate from the auth file, then
  `exec infisical run --projectId=<id> --env=<slug> -- <original entrypoint/cmd>`.
- **Remove secret `${VAR}` lines from `environment:`** (now fetched in-process); keep
  non-secret config there. The host-side compose invocation drops its `infisical run` wrapper.

### Blast radius (the load-bearing point)

In our **one-service-per-droplet** topology the credential a container holds is scoped to a
single Infisical project — **identical** scope to today's host identity, and better isolated:
each workload's identity is independent and separately revocable/rotatable. The earlier
concern that "putting Infisical in containers multiplies blast radius" only applies to a
*shared or broad* identity across many workloads, which is explicitly **not** this design.
For any future multi-service host, mint one scoped identity (and one auth file) **per
service** — never a shared one.

## Consequences

**Positive**

- `docker restart` loads updated secrets — minimal downtime, no redeploy.
- App secrets no longer appear in the committed compose `environment:` block or in
  `docker inspect … Config.Env` (closer to §3.10's "no real values in `environment:`"). Also
  fixes existing drift where required secrets (e.g. `OPENROUTER_API_KEY`) were listed in a
  comment but never interpolated.
- Per-workload, per-project identity — clean least-privilege (NIST PR.AC-4).
- Enables **auto-rotation** consumer-side (see below) and maps cleanly to K8s (see below).

**Negative / tradeoffs (accepted, with mitigations)**

- **Availability coupling:** a bounce *during an Infisical outage* won't recover until
  Infisical is reachable (a *running* container is unaffected). Mitigation: cache last-known
  secrets to tmpfs and fall back on fetch failure, or accept the coupling at current scale.
- **Auth-file readability:** the auth file is `0600 root`; if the image runs as a non-root
  UID it can't read the bind-mount. Mitigation: deploy renders a container-readable copy
  (e.g. `0640`, group-matched) — never loosen the original.
- **CLI presence:** the container needs the `infisical` binary. We bind-mount the host's
  (already installed by cloud-init), so upstream Minimus images stay unmodified (preserves
  §3.13). A rebuilt wrapper image is explicitly rejected (below).

## How the related capabilities come together

- **Auto-reload (no manual bounce).** Two options once secrets are fetched in-container:
  `infisical run --watch` restarts the wrapped process when secrets change (Infisical
  documents this as **development-oriented, not recommended for production**); or the
  **Infisical Agent** (one process on the host, reusing the same Machine Identity) watches,
  re-templates a file, and runs a reload/`--force-recreate` hook. For us, deploy-time
  recreate + on-demand bounce is the prod path; `--watch`/agent is opt-in for dev.
- **Automatic key rotation.** Rotation is only useful if consumers reload. In-container fetch
  is the minimum enabler (rotate in Infisical → bounce → new value); the Agent closes the
  loop fully (rotate → agent detects → reload, no human). This is *why* the in-container move
  is a prerequisite for any auto-rotation program — it gives rotation a consumer-side trigger.
- **One-time / wrapping token on deploy.** Infisical Machine Identity **Token Auth** (and
  Universal Auth client secrets) support a **"Max Number of Uses"** and a TTL; setting uses
  to **1** yields a single-use token. The deploy embeds a single-use, short-TTL token that the
  workload exchanges **once** at first boot for a working credential; a later read of that
  token from state/metadata/the container is useless (already consumed or expired). This is
  the Infisical-native realization of the "response-wrapping" idea already listed under
  *future hardening* in `INFRA_BOOTSTRAP_PATTERN.md`, and it tightens the Layer-2 window
  (minutes of v1 exposure) toward zero. End-state on cloud/K8s is **native identity
  federation** (no embedded bearer secret at all — see below).

## K8s / K3s forward-compatibility

The **concept** carries over unchanged — each workload fetches its own project-scoped
secrets, supports auto-reload, and embeds no long-lived bearer credential. Only the
**mechanism** changes, and K8s makes it *easier*:

| Concern | Compose era (this ADR) | K8s / K3s |
|---|---|---|
| Delivery | bind-mount CLI + `infisical run` entrypoint | **Infisical Secrets Operator** (`InfisicalSecret` CRD) syncs → native `Secret`; or CSI/file mount |
| Auth | reused host Machine Identity (Universal Auth) | **Kubernetes-native auth** — projected ServiceAccount token; **no static client secret in-cluster** (realizes the one-time-token goal natively) |
| Auto-reload | `infisical run --watch` / Agent | operator annotation `secrets.infisical.com/auto-reload: "true"` (zero-downtime pod restart on change) |
| Rotation | rotate → bounce / Agent | operator reconcile loop reloads dependent Deployments automatically |

Our reviewer rules already mandate `InfisicalSecret` for K8s (§3.10), so the migration is
"swap the entrypoint wrap for the operator + native auth," and the per-service-scoped
identity established here becomes the per-ServiceAccount binding there. **No conceptual
rework.** This ADR is written so the Compose pattern and the K8s pattern are the same story.

## Alternatives considered

1. **Status quo (host-side `infisical run` wrapper).** Rejected as the *runtime* standard
   because it can't do bounce-to-refresh or consumer-side rotation; retained as the
   deploy-time recreate path. Both remain blessed by §3.8/§3.10.
2. **Rebuilt wrapper image per service (CLI baked into a `FROM upstream` image).** Rejected —
   abandons the unmodified-upstream-Minimus-image property and adds supply-chain/maintenance
   surface (§3.13) for no benefit over bind-mounting the host CLI.
3. **Agent sidecar per service.** Viable but heavier (a container per service on
   single-service droplets). Kept as the auto-reload option, not the default delivery.
4. **File-based compose `secrets:` (`/run/secrets`).** Best `docker inspect` hygiene; deferred
   because it needs per-app `_FILE` support and an agent to keep files fresh. Revisit if env
   exposure becomes a concern.

## Rollout

Pilot on `anythingllm-docker/sites/s004.ccc.bot/` end-to-end (with a real bounce test as the
acceptance gate), then promote into `anythingllm-docker/template/`. The other seven
`*-docker` services adopt the pattern in focused follow-up PRs (same ordering as the
`INFRA_BOOTSTRAP_PATTERN.md` migration table). This ADR is the standard they migrate toward.

## Compliance mapping

| Control | Addressed by |
|---|---|
| NIST CSF 2.0 PR.AC-4 (least privilege) | Per-workload, per-project Machine Identity; no shared identity. |
| NIST CSF 2.0 PR.DS-1 (data protection) | App secrets out of committed config and `docker inspect`; single-use token roadmap shrinks the Layer-2 exposure window. |
| CIS Controls v8 5.3 (credential rotation) | In-container fetch gives rotation a consumer-side trigger (bounce / Agent). |
| ISO/IEC 27001:2022 A.5.17 (authentication information) | No app secrets in config files; Infisical-backed at runtime. |
| ISO/IEC 42001 (AI mgmt) / SOC 2 CC6.1 | Scoped identities + auditable rotation align with the §3 framework checklist. |
