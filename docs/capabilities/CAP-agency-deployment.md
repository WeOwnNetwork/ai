---
id: 25ef5a7b-68fc-4997-ba26-eab739acdfb8
type: capability
status: draft
owner: Nik
created: 2026-08-19
north_star_goal: G1
okr: O1
source: "ELF Research §1 (vault)"
---

# CAP — Agency Deployment

The capability to deploy the full WeOwn agency stack to *any* agency — repeatably, securely, and
increasingly hands-off — staged from "a human runs the scripts" (S0) to "an agent runs them under a
scoped identity" (S2). Defined as a `deploy-agency` skill contract; executed by Hermes.

Source: *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §1.
Requirement package: [RP-deploy-agent](../requirements/RP-deploy-agent.md).

## The architecture decision: Buzz defines, Hermes executes

Two layers, not two competitors. The interface is a standard skill definition; the only thing
holding power is a dedicated service identity.

| Layer | Owner | What it is |
| --- | --- | --- |
| **Capability definition** | Buzz standard (GUIDE-444): `AGENTS.md` = identity, `SKILL.md` = capability, MCP = transport | A `deploy-agency` `SKILL.md` that *defines* the deployment: inputs, stages, gates, verification contract |
| **Execution** | Hermes (the WeOwn agent service) | The service identity that *runs* the scripts/playbooks; holds scoped AppRole credentials; exposes the skill over MCP |
| **The work itself** | Git-committed scripts / playbooks (this repo's `*-docker` templates, the fleet tooling, the OpenBao ansible role) | Agents INVOKE these; they never improvise infra actions (IaC-first) |

Why this split: a chat-platform-executed deploy puts credentials and prod mutation behind LLM-driven
seats that could self-approve; a bespoke agent would be non-standard on day one. Layered, the
`SKILL.md` is the stable contract and autonomy grows behind it.

## The `deploy-agency` SKILL.md contract

| Element | Contract |
| --- | --- |
| **Inputs** | `agency_slug` (lowercase kebab-case) + `platform_set` (which platform instances to deploy, e.g. chat, sso, git) |
| **Stages** | render → plan/PR → credential-gated apply → verify → register |
| **Gates** | every deploy action exists as a committed script *before* the agent may call it; approval is never inferred from channel text; secrets never enter agent context |
| **Verification contract** | per-stage, agent-readable: health endpoint reports the real contract (app up, not just container running); backup seen landing off-box; restore rehearsal logged |
| **Outputs** | rendered site under version control, PR URL, verification report, register rows flipped to `active` |

## Staged path (each stage is a seam, not a rewrite)

| Stage | What changes | Human role | Gate to advance |
| --- | --- | --- | --- |
| **S0 — script-invoked (today)** | Scripts/playbooks canonical in git; a human runs them | Runs everything credential-gated | Scripts idempotent + verified (largely true already) |
| **S1 — agent-assisted (this quarter)** | Hermes generates config/renders, opens the PR, runs read-only verification; **human executes the credential-gated apply** | Reviews PR, runs apply, holds all secrets | `deploy-agency` `SKILL.md` written; per-stage verification contracts pass agent-readably |
| **S2 — autonomous (aspirational, no date)** | Hermes executes apply itself under a scoped AppRole | Approves via an **external** approval gate (signed human token, not chat parsing) | Audit log live; blast-radius proof (a compromised Hermes reaches exactly one agency's scope); approval gate external to the LLM |

## Constraints that bind every stage

- The agent orchestrates secret *movement* store-to-store; it never holds values in context.
- Approval is never inferred from channel text — chat content is untrusted input by definition.
- Every deploy action is a committed script first; agent privilege is "run known thing X with
  parameter Y", never arbitrary exec.
- Deploys are IaC-first: tofu for hardware, ansible for software; no console clicks, no hand-edits.
- Secrets come from the store via the `SECRET_BACKEND` seam — see
  [CAP-secrets-management](CAP-secrets-management.md).

## Target (from the North Star, G1)

- Cut a full agency-stack deploy from a multi-day human runbook to an agent-assisted push needing
  **≤ 1 hr of human attention**.
- **≥ 1 agency deployed agent-assisted**, then proven repeatable for agency #2.
- Staged: script-callable (now) → agent-assisted (this quarter) → autonomous (no date).

## Trace

Rolls up to OKR **O1 — Deployment is repeatable** → North Star **G1 — Deployment agent**
(*WeOwn North Star — Agency Deployment Platform*, WeOwn vault).

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
