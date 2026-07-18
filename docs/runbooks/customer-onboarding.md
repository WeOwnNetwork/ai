# Customer onboarding runbook — dedicated AnythingLLM instance

> Status: draft · Author: ncimino · 2026-07-18
> The operational checklist for taking a signed customer to a live, secured,
> dedicated instance. Technical companion to
> [`CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md)
> (lifecycle detail) and
> [`anythingllm-production.md`](anythingllm-production.md) (day-2 ops).
> Commercial terms (pricing, contracts) live outside this public repo — only
> the two service-level *choices* appear here because they change the build.

## 0. Intake — before any provisioning

- [ ] Customer slug chosen (lowercase, hyphens; used for droplet, Infisical
      project, backup prefix).
- [ ] Domain decided (customer subdomain or WeOwn-provided).
- [ ] **Service option recorded** (contract offers exactly two — no zero-data
      option):
      1. **Error-fix access** — observability/errors only.
      2. **Proactive service** — usage reports + config improvements
         (disclosed info-sharing).
- [ ] Region + droplet size (default `s-2vcpu-4gb-amd`; agent-RAG workloads
      → 8 GB tier — see the s004 OOM history).
- [ ] Check the Resource Registry for reusable resources before minting new.

## 1. Provision (target: same business day)

- [ ] `scripts/deploy-new-site.sh --template anythingllm-docker --site-name
      <slug> --domain <domain> --admin-email <ops-email>` — creates the
      Infisical project + Tier-2 Machine Identity, generates and pushes core
      secrets, renders the site, applies terraform.
      Known gaps to close manually: `ANYTHINGLLM_IMAGE` (pinned tag) and the
      LLM key (next step).
- [ ] Per-customer LLM key: `scripts/provision-openrouter-key.sh --customer
      <slug> --project-id <site-project> --limit-usd <cap>` (budget-capped,
      monthly reset, ZDR-only routing; value never touches the terminal).
- [ ] Verify Layer-2 rotation completed on the droplet
      (`/var/log/<project>-rotation.log` ends `Rotation complete`).
- [ ] Add the droplet to the fleet manifest
      (`docs/runbooks/anythingllm-fleet.txt`) and the runbook fleet map;
      `./scripts/check-fleet-map-drift.sh` must pass.

## 2. Product bootstrap

- [ ] `./scripts/deploy.sh root@<droplet-ip>` (direct IP, never the DNS name).
- [ ] `./scripts/bootstrap-product.sh --base https://<domain> --project-id
      <site-project>` — creates `ws-public`/`ws-private` workspaces, the
      domain-allowlisted embed widget, and the dashboard secrets; then
      **redeploy** so the dashboard picks them up.
- [ ] Role split: WeOwn keeps `admin` + SSH; the customer receives **only**
      the dashboard (`https://<domain>/app/`) credentials.
- [ ] Backups: confirm the daily cron installed, GPG public key present in
      the site project, private key stored operator-side as
      `BACKUP_GPG_PRIVATE_KEY_<project>`; run one manual backup and verify
      the encrypted object lands in `s3://weown-prod-backups/<project>/`.
- [ ] Observability per the service option: OTel agent bootstrap + fleet
      deploy; SigNoz memcg-OOM alert covers the box via the fleet rule.

## 3. Validate (blocking — `/api/ping` is not enough)

- [ ] Real dashboard login; public + private workspace visible.
- [ ] Document upload → vectorize → retrieval hit → chat completion.
- [ ] Embed widget loads from the customer's site origin (allowlist check).
- [ ] DNS + TLS: `curl -sSI https://<domain>/api/ping` → 200 with valid cert.
- [ ] Bounce test: `docker exec <container> kill -9 1` → auto-restart →
      env-hash identical pre/post.

## 4. Handover (target: within 24h of go-live)

- [ ] Walkthrough with the customer (dashboard, upload, embed snippet).
- [ ] Record in the **Resource Registry** (vault): droplet, Infisical
      project, OpenRouter key, GPG keypair, DNS record — what/where/why/status.
- [ ] Per-customer record: site `site.conf` (project ID committed), answers
      file per the site-registry model — rendered dirs stay out of git.
- [ ] First-week check-in scheduled (proactive-service customers: first
      usage report).

## SLAs (technical targets)

| Milestone | Target |
|---|---|
| Signed → instance live | 1 business day |
| Go-live → handover walkthrough | +1 business day |
| Incident response (instance down) | same business day; restore from backup ≤ 4h |
| Secret rotation on demand | ≤ 1h (Infisical update + container bounce) |

## Decommission / suspend

Follow [`CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md) §deprovision:

1. Final backup (verify the encrypted object in Spaces).
2. **Suspend**: power off droplet; keep reserved IP + Infisical project
   (billing continues — off ≠ free; see
   [`off-droplet-audit-2026-07-18.md`](off-droplet-audit-2026-07-18.md)).
3. **Exit**: `itofu.sh` destroy; revoke the customer's OpenRouter key; delete
   the Infisical project + MI; remove from the fleet manifest + runbook map;
   release the reserved IP; Resource Registry rows → status closed.
4. Final backup retained 60 days, then deleted.
