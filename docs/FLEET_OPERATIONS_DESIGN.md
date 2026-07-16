# Fleet Operations Design — Customer Instances at 100s Scale

**Status:** Design baseline (2026-07-15) — reviewed by CTO; implementation phased.
**Scope:** operating 100s of single-tenant AnythingLLM customer instances
(dedicated droplet + dashboard container each): fleet updates, canary rollouts,
observability with a no-customer-data guarantee, deploy auto-verification, and
the billing-driven lifecycle. Commercial specifics stay out of this public repo.

The design principle throughout: **one instance = one rendered unit of the same
template; the fleet is updated by changing inputs (image tags, Infisical values),
never by hand-editing instances.**

---

## 1. What already exists (build on, don't reinvent)

| Need | Existing asset |
|---|---|
| Run a command/deploy across many droplets | [`scripts/manage-droplets.sh`](../scripts/manage-droplets.sh) — SSH/exec/deploy **by DO tag** via `doctl` |
| Fleet-wide agent rollout precedent | [`scripts/deploy-otel-fleet.sh`](../scripts/deploy-otel-fleet.sh) (`--droplet` or `--tag`) |
| Per-instance config/secrets | One Infisical project per customer; values injected at container start (`infisical run`) — **bump a value + redeploy = change applied** |
| App version pinning | `ANYTHINGLLM_IMAGE` in Infisical (not git) — a version bump is an Infisical edit + redeploy, no repo change |
| Post-deploy verification | `scripts/smoke-test-framework.sh` + per-template `smoke-test-hooks.sh` (already run by `deploy-new-site.sh`) |
| Observability | Per-droplet OTel agent → SigNoz Cloud (host metrics + Caddy access logs), fleet-deployed by tag |
| Idempotent per-instance deploy | Path C ansible (`deploy.yml`) — safe to re-run on every instance any time |
| Tag taxonomy | DO tags (`weown-ai`, per-project, feature tags) — the fleet selector primitive |

## 2. Fleet updates (UI, ALLM version, model) — the three levers

Every fleet-wide change is one of three input types; all roll out with the same
ring mechanism (§3):

| Change | Lever | Mechanism |
|---|---|---|
| **Dashboard UI update** | `DASHBOARD_IMAGE` (Infisical, per site) | Push new image to registry → bulk-set value via Infisical API → ring-rollout redeploy |
| **ALLM version bump** | `ANYTHINGLLM_IMAGE` (Infisical) | Same — already the established pattern |
| **Model change** | `OPENROUTER_MODEL_PREF` — **GAP: currently baked at render time** (compose Jinja), so a fleet model change would require re-rendering every site | **Fix (P1):** move to Infisical-injected env with a rendered default, same as the image refs. Then a fleet model swap = bulk Infisical set + ring redeploy |

Bulk value setting at 100s scale = a small helper looping the Infisical API over
site project IDs from the fleet registry (§6) — never hand-edited.

## 3. Ring rollouts (canary → fleet)

Encode rings as **DO tags** — the selector `manage-droplets.sh` already speaks:

- `ring:canary` — ~5 instances: internal/dogfood boxes + consenting friendlies. **Never a paying customer's only instance.**
- `ring:early` — ~10–20% of fleet.
- `ring:ga` — everyone else.

Rollout algorithm (one wrapper script, `scripts/fleet-rollout.sh` — P1):

1. Set the new input value(s) for ring members' Infisical projects.
2. `manage-droplets.sh --tag ring:canary` → redeploy each (Path C ansible).
3. **Gate:** run the smoke battery (§4) per instance; require N/N pass.
4. **Soak** (configurable, e.g. 24h) watching SigNoz error rates for the ring.
5. Promote to `ring:early` → same gate → `ring:ga`.
6. **Rollback = reset the Infisical value + redeploy the ring** (images are
   pinned tags, so rollback is exact). ⚠️ ALLM **forward-migrates its DB** on
   upgrade — a version *downgrade* after migration is NOT guaranteed safe;
   canary soak is the real protection, and the pre-update backup (§4.0) is the
   recovery path.

## 4. Deploy auto-verification (every instance, every update)

Extend the existing smoke framework into the rollout gate:

0. **Pre-update backup** — run `backup.sh` before touching the instance (GPG-encrypted, offsite). This is the rollback-of-last-resort for DB-migration updates.
1. Containers healthy (`docker compose ps` health states).
2. `/api/ping` 200 **plus a real authenticated API call** (ping lies — verified: it returns 200 with broken auth).
3. A **real chat completion** against a canary workspace (proves LLM key + model + vector store end-to-end).
4. Embed endpoint serves the widget JS.
5. Dashboard login page 200 + version endpoint reports the expected build.
6. Report per-instance pass/fail to the rollout wrapper; any fail halts the ring.

## 5. Observability with a **no-customer-data guarantee**

Ships on the existing OTel→SigNoz stack (fleet agent, shared `otel` reader MI),
with these hard rules (P1 — encode in the otel-agent config, not in prose):

1. **Telemetry allowlist, not blocklist:** host metrics, container states,
   HTTP method/path/status/latency, error **classes**. Never request/response
   **bodies** (chat content, documents), never query strings (drop/redact the
   query component — tokens/params can carry user data), never auth headers.
2. **ALLM app logs are the leak risk** — error traces can embed prompt
   fragments. Ship them through an OTel **redaction processor** (pattern-drop:
   email/SSN-like, long free-text fields) or ship only structured error
   events (class, code, workspace-slug-hash) — not raw stdout.
3. **Pseudonymize the tenant**: telemetry is tagged with the project slug, not
   the customer's business name or domain where avoidable.
4. **Backpressure guard:** the 2026-06 syslog-parser incident (agent error-spam
   feedback loop) is the cautionary tale — keep `on_error: send_quiet` +
   self-filter patterns in every agent config.
5. This guarantee is a **contract term** (the "errors-only vs proactive" support
   options) — the observability config is the evidence; keep it in git.

## 6. Fleet registry + IaC topology (⚠️ structural — REVISED 2026-07-15)

> Revision: the original draft proposed a private repo of **rendered site
> dirs**. Industry research (2025–26) and our own history say otherwise —
> rendered dir-per-tenant is the pattern mature teams migrate *away* from
> (template fix = N-dir churn; git becomes a database whose failure mode is
> merge conflicts; our own retired `sites/s004/` tombstone misled both a human
> PR and an AI reviewer at a fleet size of four). **Do not check in 100s of
> rendered copies.**

The consensus pattern, adopted here:

1. **Git holds exactly two things:** the template/module code (this repo,
   public) and a small **tenant registry** — `tenants.yaml`, one entry per
   customer (~6 params: slug, domain, region, size, ring, plan status +
   droplet/IP/Infisical-project/Stripe ids) — in a **private** `weown-fleet`
   repo. No rendered files. Secrets stay in Infisical, never the registry.
2. **Rendered output is a build artifact, not source:** CI (or the operator
   wrapper) renders the copier template into an **ephemeral workdir** per
   tenant at deploy time, applies, and discards. Deterministic render means
   the rendered tree carries no information the registry + template don't.
3. **State-per-tenant, generated backend config:** each tenant gets its own
   tofu state key in the existing `weown-prod-state` Spaces bucket
   (`tenants/<slug>/terraform.tfstate`, SSE-C). Blast radius = one customer;
   plans stay fast and parallel. (One giant `for_each` state and
   workspace-per-tenant are both dead ends past ~40–50 tenants — plan-time
   growth, single lock, fleet-wide blast radius.)
4. **Day-2 has no inventory at all:** Ansible **dynamic inventory from DO
   tags** (`community.digitalocean` plugin) — the droplet fleet IS the
   inventory; ring tags select rollout cohorts. This is the mature form of
   what `manage-droplets.sh` already does.
5. **Orchestration graduates in steps:** operator wrapper looping the
   registry (now) → **Terragrunt Stacks** (GA 2025 — generated units from a
   stack definition, purpose-built to kill duplicated per-unit files) or
   CI-time render → PR-gated per-tenant applies (Terrateam/Digger — both
   self-hostable) → a DB-backed control plane only when onboarding volume
   demands an API (the Omnistrate-style endgame §7 already assumes).

This aligns with the ecosystem's own in-flight direction: the OpenTofu-MAIT
plan's loop ("render → plan → human approval → exec → **record state →
drift-detect**") treats tofu state as the per-instance record with render as
an ephemeral pipeline step, and the Komodo evaluation's verdict (git holds
truth; thin execution surface; no control plane that can drift from git)
is preserved — the registry is *in git*, the renders are not.

**Existing sites:** the four current `sites/<domain>/` dirs stay as-is
(reference deployments) until migrated; **no new customer site dirs get
committed** — customer #1 onward uses the registry + ephemeral-render path.

## 7. Billing-driven lifecycle (design for automation now)

State machine, driven by Stripe webhooks + a scheduled reconciler (GH Actions
cron in the private repo, or the Phase-2 control plane):

```
 paid ──► ACTIVE ──(payment fails, grace X days)──► PAUSED (droplet off; IP+data kept)
                 ◄──────────(payment succeeds)──────┘   │ (X weeks unpaid)
                                                        ▼
                                     STOPPED (final GPG backup verified; droplet DESTROYED;
                                              reserved IP released; OR key revoked)
                                                        │ (X months unpaid / per retention term)
                                                        ▼
                                     PURGED (Spaces backups deleted; Infisical project deleted;
                                             registry row closed — auditable tombstone)
```

- Provision-on-pay: Stripe `checkout.session.completed` webhook →
  `workflow_dispatch` → `deploy-new-site.sh --auto` (+ dashboard bootstrap) →
  smoke gate → welcome email. Every transition writes the registry + notifies
  support.
- The X values (grace days / stop weeks / purge months) are contract terms —
  configured per plan in the registry, defaulted from the ToS.

## 8. Known scale prerequisites (flag early, cheap now, painful later)

1. **DO account limits** — droplet/volume/reserved-IP quotas need raising ahead
   of growth; ask DO once real volume approaches.
2. **Infisical cost curve** — per-project/identity pricing is already a driver
   internally; at 100s of projects, revisit (OpenBao migration is the standing
   alternative; the store-agnostic tooling pattern keeps this swappable).
3. **Registry/image supply chain** — Minimus tag rotation + per-droplet
   `docker login` state is the fleet-update weak point; resolve the mirror
   licensing question and/or DOCR mirror before 100-instance rollouts.
4. **Transactional email** — dashboard auth, dunning notices, maintenance
   comms all need a sending domain + provider; none exists today.
5. **Restore drills** — at fleet scale, "backups exist" must become "restores
   are rehearsed": scheduled automated restore-verify of a sampled instance.
6. **Per-instance abuse controls** — the embed endpoint is public; rate-limit
   at Caddy (per-IP) so a scripted visitor can't burn the (capped) LLM budget
   or DoS a customer instance.
7. **ToS acceptance capture** — signup must record who accepted which terms
   version when (the attorney will ask for it on day one).

## Phasing

| Phase | Items |
|---|---|
| **P1 (pre-first-customers)** | `OPENROUTER_MODEL_PREF` → Infisical; ring tags + `fleet-rollout.sh`; smoke battery §4; otel redaction/allowlist config; private `weown-fleet` repo + registry; Caddy rate-limit on embed |
| **P2 (with billing automation)** | Stripe webhook → provision; lifecycle reconciler + timers; transactional email; restore drills |
| **P3 (scale hardening)** | DOCR mirror / registry strategy; secrets-store cost decision; control-plane service if GH Actions outgrows the job |

## Related

- [`docs/CUSTOMER_INSTANCE_PROVISIONING.md`](CUSTOMER_INSTANCE_PROVISIONING.md) — per-instance lifecycle + compliance facts
- [`docs/AUTOMATED_DEPLOYMENT.md`](AUTOMATED_DEPLOYMENT.md) — `deploy-new-site.sh` phases
- [`docs/INFRA_BOOTSTRAP_PATTERN.md`](INFRA_BOOTSTRAP_PATTERN.md) — Path C + Layer 2 + tools/layers canon
