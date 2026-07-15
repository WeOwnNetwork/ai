# Provisioning a Single-Tenant Customer Instance

**Audience:** WeOwn operators standing up (and later tearing down) a **dedicated,
single-tenant AnythingLLM instance for one paying customer** — "nobody else on
that server." This is the technical lifecycle only; the commercial/sales flow
(pricing, purchase, onboarding, subscription lifecycle) is tracked separately in
the WeOwn engagement runbooks and intentionally kept out of this public repo.

> **This doc adds nothing new to the deploy mechanics** — it sequences the
> existing pieces into a per-customer lifecycle and adds the one missing step
> (per-customer LLM key provisioning). The authoritative deploy reference remains
> [`anythingllm-docker/DEPLOYMENT_GUIDE.md`](../anythingllm-docker/DEPLOYMENT_GUIDE.md).

## Why single-tenant

A dedicated instance per customer is not just an isolation nicety — it is what
makes the product work at all. AnythingLLM's **shared**-instance multi-tenancy
cannot scope document management to one tenant (`upload` / `update-embeddings`
are `[admin, manager]` and manager is instance-wide; the doc library is global).
On a **dedicated** instance that ceiling disappears — the whole instance is the
customer's, so a `manager`-role account gives them the full native feature set
with zero custom code:

- **Secure login** — AnythingLLM multi-user mode + password (self-service reset is
  via **recovery codes** saved on first login; there is **no email "forgot
  password"** flow — resets are an operator action).
- **Private document upload + RAG** — `manager` can upload + manage their own corpus.
- **Embeddable chat widget** — native Embedded Chat Widget; paste the snippet on
  their site (see the chat-embed recipe in the engagement SOPs).

**Managed-service role split (native, no custom layer):** WeOwn holds the `admin`
account (system LLM/embedder/vector settings, the OpenRouter key, infra — never
exposed to the customer); the customer gets a `manager` account (their documents,
workspaces, and team, but cannot change LLM/infra config or break the instance).

Everything below is the existing hardened stack from
[`anythingllm-docker/`](../anythingllm-docker/): dedicated droplet + reserved IP,
Caddy auto-TLS, app bound to `127.0.0.1`, Infisical runtime secret injection (no
secrets on disk), GFS backups to DO Spaces, and OTel → SigNoz observability.

---

## Lifecycle at a glance

```
  provision infra  ──►  mint per-customer LLM key  ──►  deploy app  ──►  validate  ──►  DNS
  (itofu.sh)            (provision-openrouter-key.sh)   (deploy.sh)      (real login)   (A record)
        │                                                                                  │
        └──────────────────────────  suspend / deprovision  ◄──────────────────────────────┘
                                      (final backup + tofu destroy + Infisical cleanup)
```

## 1. Provision the instance

Render a site from the template and provision it per
[`DEPLOYMENT_GUIDE.md` §6.1–6.4](../anythingllm-docker/DEPLOYMENT_GUIDE.md).
One dedicated Infisical **app project** + Machine Identity per customer (least
privilege — a compromise of one box cannot read another customer's project).

The **automated** path is [`scripts/deploy-new-site.sh`](../scripts/deploy-new-site.sh)
(`--template anythingllm-docker`), which creates the Infisical project + Tier-2
Machine Identity, renders the site, and runs `tofu` + ansible. See
[`docs/AUTOMATED_DEPLOYMENT.md`](AUTOMATED_DEPLOYMENT.md).

> **Known gap for the scripted path:** `deploy-new-site.sh` currently pushes
> `JWT_SECRET`, `ADMIN_EMAIL`, and the Spaces backup creds, but **not**
> `OPENROUTER_API_KEY` or `ANYTHINGLLM_IMAGE` — both are `fail-loud`-required or
> the container refuses to boot. Until that script learns them, provision the LLM
> key with step 2 below and set `ANYTHINGLLM_IMAGE` via the per-site
> `bootstrap-*-infisical.sh` (or the Infisical UI). The **manual**
> `DEPLOYMENT_GUIDE.md` flow already handles both.

## 2. Mint the customer's own LLM key

Each customer instance gets its **own** OpenRouter key with a **hard monthly
spend cap**, so cost is attributable per customer and a runaway/compromised box
cannot burn the shared account. This replaces the manual "create a key in the
OpenRouter dashboard and paste it" step in the per-site bootstrap scripts.

```bash
bash scripts/provision-openrouter-key.sh \
  --customer <slug> \
  --project-id <customer's site Infisical project id> \
  --limit-usd 50
```

The helper mints a capped, `limit_reset: monthly` key via the OpenRouter
Management API and writes it straight into the customer's Infisical project as
`OPENROUTER_API_KEY` — the value never touches the terminal, disk, or shell
history. It refuses to overwrite an existing key without `--force` (so a re-run
can't silently orphan a live key). The provisioning key it authenticates with
lives in the operator Infisical project as `OPENROUTER_PROVISIONING_KEY` and is
consumed in-process. See the script header for the full security model.

> There is no OpenTofu resource for this — OpenRouter has no Terraform provider,
> so key provisioning is an API/script step in the deploy flow, not IaC. Per-key
> minting + capping IS the automation; you do **not** hand-create keys.

## 3. Deploy + validate

Deploy the app layer and **validate a real login + a real chat**, per
[`DEPLOYMENT_GUIDE.md` §6.5–6.7](../anythingllm-docker/DEPLOYMENT_GUIDE.md)
(`/api/ping` alone is not sufficient — it returns 200 even when auth is broken).
Then point DNS at the reserved IP (§6.8); Caddy issues the cert within ~30–60s.

Enable multi-user mode and create **two** accounts before handover: the
WeOwn-held **`admin`** (system/LLM/infra — WeOwn only) and the customer's
**`manager`** (their documents/workspaces/team). Hand over only the manager
credentials. Multi-user mode has **no email "forgot password"** flow — the
customer saves **recovery codes** on first login, and operator support handles
resets (there are known reset bugs, so prefer recovery codes).

## 4. Operate

Ongoing changes never require Terraform — edit the Infisical value or the
compose/Caddy files and re-run `./scripts/deploy.sh root@<ip>` (recreates the
container so injected secrets refresh). Full matrix in
[`DEPLOYMENT_GUIDE.md` §11](../anythingllm-docker/DEPLOYMENT_GUIDE.md).

## 5. Suspend / deprovision

When a customer pauses or leaves:

1. **Final backup** — `./scripts/backup.sh root@<ip>` (lands in
   `s3://weown-prod-backups/<project>/`; retained per GFS).
2. **Suspend** (recoverable) — power the droplet off, or stop the container; keep
   the reserved IP + Infisical project so it can resume.
3. **Deprovision** (final) — `cd sites/<domain>/terraform && ./itofu.sh` destroy
   the droplet + reserved IP + firewall, **revoke the customer's OpenRouter key**
   in the dashboard (it's per-customer, so revoking is clean), and delete the
   customer's Infisical project + Machine Identity. Keep the final backup for the
   agreed retention window before deleting it from Spaces.

See [`docs/AUTOMATED_DEPLOYMENT.md` → Cleaning Up](AUTOMATED_DEPLOYMENT.md) for
the teardown commands.

---

## Compliance & data handling (per customer instance)

Technical facts that back the customer-facing terms (the legal documents
themselves — ToS / AUP / DPA — are maintained outside this repo):

| Property | Fact |
|---|---|
| **Tenancy** | Single-tenant: dedicated droplet, dedicated Infisical project + Machine Identity, dedicated LLM key. No shared compute, storage, or credentials between customers. |
| **Data locality** | Documents, embeddings (LanceDB), and chat history live on a dedicated **DO block-storage data volume** attached to the customer's droplet (`data_volume_size_gb`, default 50 GB) — block storage is **platform-encrypted at rest**, unlike droplet local disk. The Docker data-root and local backup tarballs both live on it. Backups offload to DO Spaces under a per-project prefix. Region chosen at provisioning. |
| **Encryption** | TLS 1.3 in transit (Caddy/Let's Encrypt). **Backups are client-side encrypted** (OpenPGP/GPG, per-customer ed25519/cv25519 keypair, keyring-free `--recipient-file` encrypt) before upload — objects in Spaces are ciphertext to DigitalOcean; the private key lives only in the operator secret store, never on the droplet. Tofu state SSE-C encrypted. Secrets never on disk (Infisical runtime injection). |
| **LLM processing** | Chat prompts + retrieved document context are sent to the configured LLM provider (OpenRouter) at question time — per-customer key, hard monthly cap, under the account-level **Zero-Data-Retention guardrail** (routing restricted to ZDR-only endpoints: providers that neither retain nor train on the data; OpenRouter itself retains nothing). Model choice is pinned by WeOwn (`admin`-held config). |
| **Access** | Customer holds a `manager` account (their data/team). WeOwn holds `admin` + SSH (ops keys via `OPS_AUTHORIZED_KEYS`, auditable + revocable per deploy). |
| **Host hardening** | CIS-aligned baseline via `ansible/harden.yml` (DevSec `os_hardening` + `ssh_hardening` ≈ CIS Ubuntu L1: kernel/sysctl, auth policy, SSH key-only + strong crypto), measured with **Lynis** each run. Phase A keeps root key-only SSH (fleet tooling); Phase B (pre-first-customer) moves to the ops-user/root-off model. Run after provisioning: `ansible-galaxy collection install -r ansible/requirements.yml && ansible-playbook ansible/harden.yml -i 'root@<ip>,'`. |
| **Backups & retention** | Daily GFS backups (30d/12mo/yearly), client-side encrypted per the Encryption row (`BACKUP_GPG_PUBLIC_KEY` in the site project; private key in operator-tools as `BACKUP_GPG_PRIVATE_KEY_<project>` — generated automatically by `deploy-new-site.sh`). Restores fetch the private key in-process from the operator store, stage it into droplet **tmpfs** for the run (ephemeral GNUPGHOME), and shred it. On cancellation: final backup retained **60 days**, then deleted from Spaces; droplet, reserved IP, Infisical project, and the customer's OpenRouter key destroyed/revoked at deprovision. |
| **Monitoring** | Host metrics + reverse-proxy access logs → SigNoz (operational telemetry only; document contents are not shipped). DO resource alerts. |
| **Subprocessors** | DigitalOcean (compute/storage/backups), Infisical (secret management), OpenRouter → underlying model providers (LLM inference), SigNoz (telemetry), Let's Encrypt (TLS issuance). |
| **Framework mapping** | Controls map to NIST CSF 2.0 (PR.DS, PR.AC, DE.CM), CIS v8 IG1 (3.11, 4.1), ISO 27001-ready (A.5.17, A.8.24) — see [`docs/COMPLIANCE_ROADMAP.md`](COMPLIANCE_ROADMAP.md) for the phased program. |

## Related

- [`anythingllm-docker/DEPLOYMENT_GUIDE.md`](../anythingllm-docker/DEPLOYMENT_GUIDE.md) — authoritative deploy reference.
- [`docs/AUTOMATED_DEPLOYMENT.md`](AUTOMATED_DEPLOYMENT.md) — the `deploy-new-site.sh` tiered-MI automation.
- [`scripts/provision-openrouter-key.sh`](../scripts/provision-openrouter-key.sh) — per-customer LLM key minting.
- [`docs/INFRA_BOOTSTRAP_PATTERN.md`](INFRA_BOOTSTRAP_PATTERN.md) — Path C + Layer 2 bootstrap architecture.
