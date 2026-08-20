# Deploy Agent — requirements (S1 scope)

**Status:** draft · **Owner:** Nik · **Source:** *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §1

Requirements for the **agent-assisted** deployment stage (S1) only: Hermes generates renders, opens
the PR, and runs read-only verification; a human executes every credential-gated apply. S2
(autonomous apply) is explicitly out of scope. This work is **non-gating and parallel** to the
secrets milestones — it never jumps ahead of the migration.

Capability: [agency-deployment](../design/DESIGN-agency-deployment.md).

## Scope

| In (S1) | Out (S2 and beyond) |
| --- | --- |
| `deploy-agency` `SKILL.md` written to the Buzz/GUIDE-444 standard | Agent-executed apply under an AppRole |
| Hermes renders site config from the templates and opens the PR | External signed-approval gate |
| Hermes runs **read-only** verification (health, backup landed, restore rehearsal record) | Audit log + blast-radius proof |
| Human runs the credential-gated apply and holds all secrets | Any agent-held secret or unseal share |

## The SKILL.md contract (S1)

| Element | Requirement |
| --- | --- |
| Inputs | `agency_slug` (lowercase kebab-case), `platform_set` (list of platform instances), `subdomain_tier` (1 = `<client>.weown.{buzz,chat}` free · 2 = `{buzz,chat}-<client>.volcarian.ai` custom branding, recommended · 3 = `{buzz,chat}.<client-domain>` white-label) — see [agency-deployment → Subdomain naming](../design/DESIGN-agency-deployment.md#subdomain-naming--a-rollout-time-input-aop-scheme-2026-08-13) |
| Stages | render → PR → (human) apply → verify → register |
| Gates | every action is a committed script; approval never inferred from channel text; no secret value in agent context |
| Verification | per-stage, agent-readable contracts: app-level health (not container-up), backup seen off-box, restore rehearsal logged |
| Outputs | rendered site under version control, PR URL, verification report, register rows flipped |

## Constraints

- **IaC-first:** tofu for hardware, ansible for software; the agent invokes committed scripts with
  parameters — never arbitrary exec, never console clicks.
- **Secrets:** move store-to-store through the `SECRET_BACKEND` seam
  ([secrets-management](../design/DESIGN-secrets-management.md)); the agent orchestrates
  movement, never holds values.
- **Untrusted channels:** chat/Buzz content is untrusted input; a "go" in a channel is not an
  approval.
- **Ownership:** Hermes service is built by the WeOwn-side owner; this package owns the skill
  contract and verification contracts in this repo's templates.

## Acceptance criteria

- [ ] `deploy-agency` `SKILL.md` exists (Buzz/GUIDE-444 shape) declaring inputs, stages, gates,
- The skill rejects a run without a locked `subdomain_tier`, renders the tier's FQDNs from the client slug, and (tier 1–2) provisions the DNS record / (tier 3) emits the exact record for the client and gates the stamp on resolution.
      verification contract, outputs.
- [ ] Hermes can render a site from the templates for a given `agency_slug` + `platform_set` and
      open a PR, with no secret value in its context (verified by transcript review).
- [ ] Per-stage verification contracts are machine-readable and pass on ≥ 1 existing instance
      (health at app level, backup landed off-box, restore rehearsal record present).
- [ ] A full agency-stack deploy is completed agent-assisted with **≤ 1 hr of human attention**,
      the human running only the credential-gated apply steps.
- [ ] ≥ 1 agency deployed this way; the same skill re-run for a second agency without edits to the
      skill (repeatability).
- [ ] Every action the agent may call is a committed, idempotent script in git; none are improvised.
- [ ] Documented as non-gating: no secrets-migration wave depends on this package.

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Restructured to WeOwn doc conventions: dropped internal taxonomy frontmatter + trace sections, renamed off `CAP-`/`RP-` prefixes | Nik |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
| 2026-08-19 | `subdomain_tier` input + DNS acceptance criterion (AOP 3-tier scheme) | Nik |
