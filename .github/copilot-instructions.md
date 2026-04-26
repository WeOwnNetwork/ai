# WeOwn AI Infrastructure — GitHub Copilot Code Review Instructions

**Scope**: directives for GitHub Copilot's **static, file-based** code review on pull requests to `WeOwnNetwork/ai`.

**Version**: v3.3.4.1 (#WeOwnVer)
**Last Updated**: 2026-04-23
**Maintained by**: `@romandidomizio` + `@ncimino` (post-2026-05-15: `@ncimino` + one of Mohammed/Shahid/Dhruv per [`CODEOWNERS`](CODEOWNERS))
**Roadmap**: [`docs/COMPLIANCE_ROADMAP.md`](../docs/COMPLIANCE_ROADMAP.md)

---

## 1. Scope — What Copilot Reviews (and What It Does Not)

### What Copilot **CAN** do (static analysis of files in the PR diff)

- Read any file in the diff and in the repo tree
- Flag security anti-patterns visible in source (hardcoded secrets, `runAsUser: 0`, weak TLS, missing `NetworkPolicy`, etc.)
- Validate YAML / JSON / TOML / HCL / Dockerfile / shell syntax by inspection
- Verify conformance to documented conventions (branch naming, naming conventions, path layout, required sections)
- Check that required files exist for a change (e.g., every new Helm chart has `values.yaml`, `Chart.yaml`, `NetworkPolicy`, `ServiceAccount`)
- Check cross-references (e.g., a new ADR is linked from relevant READMEs)
- Check documentation completeness (CHANGELOG updated, `#WeOwnVer` bumped, ADR present when architecture changed)
- Recommend specific fixes at specific file paths / line numbers

### What Copilot **CANNOT** do (defer to CI/CD and humans)

- Execute shell commands (`helm lint`, `trivy`, `kubectl apply --dry-run`, `tofu validate`, `ansible-playbook --check`, `ansible-lint`, `npm test`, etc.)
- Run vulnerability scanners, license scanners, or SBOM generators
- Execute unit / integration / E2E tests
- Deploy to clusters or build container images
- Measure performance or do load testing
- Verify secrets are correctly stored outside source (that's a runtime concern)

**Do not include "run `<command>`" steps in review comments.** Commands belong in CI/CD workflows documented in [`.github/CI_CD_WORKFLOWS.md`](CI_CD_WORKFLOWS.md) and [`.github/workflows/README.md`](workflows/README.md). Copilot's role is to find the file-level violation and recommend the fix.

---

## 2. Repository Overview (brief)

- **Visibility: PUBLIC on github.com.** Everything merged here is world-readable, search-indexed, and permanently cached (forks, SW Heritage, GH dataset mirrors). Treat every file as published. See §3.0 for the explicit precaution list.
- **Purpose**: enterprise-grade, production-ready AI infrastructure for WeOwn's decentralized agentic ecosystem
- **Primary stack**: Kubernetes-native (DigitalOcean K8s) with Helm charts; Docker Compose deployments for simpler workloads; **IaC** = OpenTofu (infrastructure provisioning) + Ansible (software / configuration management on top of provisioned infrastructure); Infisical for secret management
- **Applications in this repo**: AnythingLLM, WordPress, Matomo, Vaultwarden, n8n, Nextcloud, plus shared infrastructure in `k8s/`, `llm-d/`, `braintrust-proxy/`, `twilio-bridge/`, `fedarch/`
- **Automation identity**: Automated PRs are authored by the ecosystem-wide service account `weown-bot`. See [`ADR-001`](ADR-001-service-account-pat.md), [`ADR-002`](ADR-002-infisical-github-sync.md), and [`.github/workflows/README.md`](workflows/README.md).
- **Review model**: Every PR to `main` requires Copilot AI review + **2 human approvals** (branch protection + CODEOWNERS). Branches follow **GitHub Flow**: short-lived `feature/*`, `fix/*`, `docs/*`, `hotfix/*` off `main`; enforced by `branch-name-check.yml`.

---

## 3. Code Review Checklist — Multi-Framework Compliance + Ecosystem Best Practices

**This is the PRIMARY checklist.** It combines:

- **§3.0** — Public-repository precautions (critical, read first)
- **§3.1–§3.6** — Six compliance frameworks (NIST CSF, CIS, CSA CCM, ISO 27001, SOC 2, ISO 42001) with the most important file-level-enforceable controls
- **§3.7–§3.13** — Seven ecosystem best-practice checklists (Kubernetes, Docker/Compose, IaC [OpenTofu + Ansible], Infisical, Observability, GitOps, Security/Supply Chain)
- **§3.14** — Documentation & versioning

Every review comment should map to ≥1 item below. Items marked **CRITICAL** block merge. The goal: build security and compliance **by design for every framework simultaneously**, so nothing discovered later forces a rebuild.

---

### ⚠️ 3.0 Public Repository Precautions — READ FIRST, APPLY ALWAYS

**`WeOwnNetwork/ai` is a PUBLIC GitHub repository.** Anything merged into `main` becomes world-readable, search-indexed, and permanently cached (forks, SW Heritage archive, GH dataset mirrors). Even if removed later, the data persists in history, forks, caches, and archives.

**CRITICAL — never commit, reject as a blocker**:

- [ ] **Secrets / credentials** of any kind: API keys, bearer tokens (GitHub PATs, cloud-provider tokens, SaaS tokens), passwords, JWTs, OAuth client secrets, webhook signing secrets, session keys, service-account JSON keys
- [ ] **Private keys**: PEM, PKCS#12, SSH private keys (`id_rsa`, `id_ed25519`), `.p12` / `.pfx`, GPG private keys, TLS private keys, code-signing keys, CA intermediate keys
- [ ] **Connection strings with embedded credentials**: `postgres://user:pass@host`, `mongodb+srv://user:pass@...`, `redis://:password@...`, `mysql://...`, AWS/Azure/GCP connection strings, S3 access-key pairs, SAS tokens
- [ ] **Personal data (PII)**: customer / end-user emails, names, phone numbers, addresses, account IDs, IP addresses tied to individuals
- [ ] **Internal topology**: private IPs (RFC 1918 — 10.x, 172.16–31.x, 192.168.x), VPN hostnames, internal DNS names, management endpoints, non-public admin URLs
- [ ] **Infrastructure identifiers**: real cluster IDs, DOKS cluster names, real domains for non-public services, tenant IDs that leak architecture
- [ ] **Screenshots / images** containing any of the above (UI showing tokens, emails, dashboards with real data, IP addresses)
- [ ] **`.env` files with real values** — always use `.env.example` with placeholder values; `.env` itself must be in `.gitignore`
- [ ] **`kubectl get secret -o yaml` output** pasted into docs / tests / fixtures
- [ ] **Helm `values.yaml` with embedded secret material** — always `InfisicalSecret` / `ExternalSecret` references
- [ ] **Commercially-licensed content** lacking a redistribution license (proprietary code, licensed images, vendor docs)

**Positive patterns to recommend instead**:

- Placeholder tokens: `<REDACTED>`, `<placeholder>`, `sk-EXAMPLE-TOKEN-NOT-REAL`, `$TOKEN`, `${YOUR_TOKEN_HERE}`
- Example domains: `example.com`, `example.org`, `example.net`, `*.test`, `*.local` (RFC 2606)
- Example IPs: `192.0.2.x`, `198.51.100.x`, `203.0.113.x` (RFC 5737 documentation ranges); `2001:db8::/32` (IPv6 docs)
- Example emails: `user@example.com`, `admin@example.com`, `ops@example.com`
- Real secrets → Infisical → Secret Sync → `${{ secrets.* }}` (workflows) or `InfisicalSecret` (manifests)

**Git history considerations**:

- A secret committed in any past commit **persists forever** until purged with `git filter-repo` / `bfg-repo-cleaner` **and** the secret is rotated. Removal from the current diff is NOT enough.
- Flag CRITICAL even on removal-only diffs if the secret's value appears anywhere in git history — require a rotation entry in `.github/INCIDENT_RESPONSE.md` + a purge-history follow-up.
- GitHub push protection is a **safety net**, not a substitute. It has false negatives (custom token formats, partial leaks, secrets inside images, secrets in non-text files). Always lint locally (`pre-commit` + `gitleaks` / `trufflehog`).

---

### 3.1 NIST CSF 2.0 (Primary Vocabulary — Phase 1 Active)

**NIST CSF is the universal language every other framework in §3.2–§3.6 maps into.** Every review comment must map to ≥1 Function below.

#### 🏛️ Govern (GV) — policy, roles, risk strategy

- [ ] **GV.OC CODEOWNERS coverage** — `.github/CODEOWNERS` covers every path touched by this PR
- [ ] **GV.RM ADR present/updated** — new service, secret store, auth flow, deployment model, CI/CD pattern, or framework item has an ADR in `.github/ADR-*.md`
- [ ] **GV.PO Documented rationale** — PR description or linked ADR explains the "why"
- [ ] **GV.OV No bypass** of CODEOWNERS / branch protection; all changes via reviewed PR

#### 🔍 Identify (ID) — asset / risk / supply chain

- [ ] **ID.AM Asset inventoried** — new Helm charts have component lists; images use pinned tags (not `latest`, `main`)
- [ ] **ID.SC Dependencies pinned** — lockfiles present, SHA-pinned Actions, digest-pinned critical images
- [ ] **ID.RA Risk surface noted** — PR description mentions authN/authZ, networking, data flow, external API changes
- [ ] **ID.IM Threat model updated** in `.github/SECURITY_ASSESSMENT.md` if new threat vectors introduced

#### 🛡️ Protect (PR) — IAM, data security, platform security

- [ ] **PR.AA Least-privilege RBAC** — ServiceAccount present, minimum verbs+resources, no `cluster-admin`
- [ ] **PR.AC NetworkPolicy present** on every new Deployment / StatefulSet / Job (deny-all + explicit allow)
- [ ] **PR.DS No `--from-literal` secret creation** anywhere (scripts, workflows)
- [ ] **PR.DS No `/tmp` secret material** — use `$(mktemp)` with `trap 'rm -f "$FILE"' EXIT`
- [ ] **PR.DS No hardcoded secrets** in source, Helm values, Compose env, Tofu vars, Ansible vars / vault files, workflow YAML
- [ ] **PR.DS Infisical for production secrets** — K8s (`InfisicalSecret` CRD), Compose (agent / `infisical run`), CI (Secret Sync → `${{ secrets.* }}`)
- [ ] **PR.DS TLS 1.3 only** on Ingress; strong cipher suites; no `TLSv1.0` / `TLSv1.1`
- [ ] **PR.PS Container security context** — `runAsUser ≥1000`, `runAsNonRoot: true`, `readOnlyRootFilesystem` where feasible, no `privileged: true`, no `allowPrivilegeEscalation: true`, drop all caps
- [ ] **PR.PS Pod Security Standards `restricted`** compatible
- [ ] **PR.AA 2FA / MFA** referenced for any new admin-access flow
- [ ] **PR.AA `automountServiceAccountToken: false`** when unused

#### 🕵️ Detect (DE) — monitoring, logging, anomaly analysis

- [ ] **DE.CM `livenessProbe` + `readinessProbe`** on all containers / `healthcheck:` on Compose services
- [ ] **DE.CM Structured JSON logs**; no secret values in log statements
- [ ] **DE.AE `/metrics` endpoint** (Prometheus format) on new long-running services
- [ ] **DE.AE OpenTelemetry** instrumentation on new HTTP / gRPC services
- [ ] **DE.AE Alerts / SLOs** documented for user-facing or critical-path components

#### 🚨 Respond (RS) — incident management, escalation

- [ ] **RS.MA Runbook snippet** added to `.github/INCIDENT_RESPONSE.md` for new failure modes
- [ ] **RS.CO Escalation path** (who pages whom, via what channel)
- [ ] **RS.MI Rollback documented** for deployment changes

#### ♻️ Recover (RC) — backup, DR, continuity

- [ ] **RC.RP Backup CronJob** for new persistent data (PVC, DB, object storage)
- [ ] **RC.RP Restore procedure** documented (not "we'll figure it out")
- [ ] **RC.CO RTO / RPO** stated for user-facing / critical components

---

### 3.2 CIS Controls v8 IG1 (Essential Cyber Hygiene)

File-level checks for IG1 Safeguards most relevant to this repo:

- [ ] **CIS 1 — Asset inventory**: every new long-running container / StatefulSet / Helm chart has an inventory entry (README component list + CHANGELOG)
- [ ] **CIS 3.3 — Data encryption at rest**: PVC storage class supports encryption; Tofu resources enable encryption flags
- [ ] **CIS 3.10 — Encrypt sensitive data in transit**: TLS 1.3 enforced; no `http://` Ingress in prod
- [ ] **CIS 3.11 — Encrypt sensitive data at rest**: no plaintext secrets in git; Infisical-backed
- [ ] **CIS 4.1 — Establish / maintain secure configuration**: Helm / Compose defaults aligned with hardening benchmarks
- [ ] **CIS 4.6 — Securely manage enterprise assets / software**: images pinned by digest where practical; no EOL base images
- [ ] **CIS 5.1 — Account inventory**: new ServiceAccounts documented; no anonymous access
- [ ] **CIS 5.4 — Restrict administrator privileges**: no `cluster-admin` RoleBindings in new manifests
- [ ] **CIS 6.1 — Access-granting process**: RBAC Role + RoleBinding co-located with workload; reviewed via PR
- [ ] **CIS 6.2 — Access-revoking process**: removal path referenced in `INCIDENT_RESPONSE.md` / runbooks
- [ ] **CIS 7.3 — Automated OS patch management**: base images use current stable, not EOL; Dockerfile references updatable tag lineage
- [ ] **CIS 8.2 — Collect audit logs**: audit logging enabled on new APIs; no `log-level: none` in prod configs
- [ ] **CIS 8.10 — Retain audit logs**: retention ≥ 90 days documented
- [ ] **CIS 12.4 — Architecture diagram** for new systems in the app's README or `docs/`
- [ ] **CIS 12.6 — Secure network management**: NetworkPolicy / Compose networks explicit
- [ ] **CIS 13.1 — Centralized security event alerting**: new alert rules committed alongside the service
- [ ] **CIS 16.1 — Secure application development process**: PR review, not direct push
- [ ] **CIS 16.11 — Vetted modules / components**: no unpinned `git` sources for OpenTofu / Terraform modules, Ansible Galaxy roles / collections (`requirements.yml`), or Helm dependencies
- [ ] **CIS 17.1 — Incident-response personnel designated**: CODEOWNERS names maintainers; escalation clear

---

### 3.3 CSA Cloud Controls Matrix v4 (Cloud-Native — Phase 2 Prep)

Control domains most relevant to this repo's cloud-native workloads:

- [ ] **CCC-01 Cloud change management**: CI/CD workflow for every new deployable
- [ ] **CCC-03 Change detection & drift**: GitOps (Argo/Flux), OpenTofu state-tracked, or Ansible `--check --diff` drift runs — not bare `kubectl apply`
- [ ] **DSI-02 Data classification**: PVCs / databases annotated with sensitivity class in `values.yaml` comments
- [ ] **DSI-03 E-discovery**: log retention / SIEM forwarding referenced for services handling user data
- [ ] **EKM-02 Key generation / ownership**: Infisical is the single key source; no per-service KMS spawned ad-hoc
- [ ] **EKM-04 Key rotation**: cadence documented (90 d for PATs; 1 y TLS via cert-manager; ≤ 1 y for long-lived tokens)
- [ ] **IAM-01 Identity / lifecycle mgmt**: ServiceAccount lifecycle matches its workload (removed together)
- [ ] **IAM-08 Least privilege**: Role verbs / resources minimal; no `*` / `cluster-admin`
- [ ] **IVS-03 Network security**: NetworkPolicy + Ingress rules complete; no flat networks
- [ ] **IVS-06 Environment segmentation**: separate namespaces for dev/staging/prod; no shared secrets across envs
- [ ] **LOG-02 Logging requirements**: structured JSON, correlation IDs, no PII in logs
- [ ] **LOG-07 Log integrity**: logs forwarded to durable external store (Loki / S3 / etc.) — not only pod stdout
- [ ] **STA-04 Supply chain security**: SBOM in CI, image scanning in CI (CI enforces; Copilot flags anti-patterns)
- [ ] **TVM-02 Vulnerability remediation**: base image tags not EOL
- [ ] **TVM-05 Penetration testing**: any new public endpoint referenced in `SECURITY_ASSESSMENT.md` risk register

---

### 3.4 ISO/IEC 27001:2022 Annex A (ISMS — Phase 3 Prep)

Controls enforceable at file level:

- [ ] **A.5.15 Access control policy**: RBAC defined and linked from affected app README
- [ ] **A.5.16 Identity management**: unique identity per workload (ServiceAccount); no shared creds
- [ ] **A.5.17 Authentication information**: no secrets in config files; Infisical-backed
- [ ] **A.5.18 Access rights**: least-privilege Role; no wildcard verbs
- [ ] **A.5.23 Cloud services information security**: DOKS / cloud-specific hardening documented
- [ ] **A.5.24 Incident-management planning**: linked `INCIDENT_RESPONSE.md` entry for new components
- [ ] **A.5.25–27 Assessment / response / learning**: post-mortem referenced when `hotfix/*` branch is used
- [ ] **A.5.37 Documented operating procedures**: runbook in `.github/workflows/README.md` or per-app README
- [ ] **A.8.2 Privileged access rights**: explicitly justified when elevated RBAC appears; limited duration preferred
- [ ] **A.8.5 Secure authentication**: 2FA/MFA referenced; no basic auth; OIDC / SSO where supported
- [ ] **A.8.8 Management of technical vulnerabilities**: image scanning in CI; base image lineage current
- [ ] **A.8.9 Configuration management**: Helm / Compose defaults hardened; deviations documented
- [ ] **A.8.15 Logging**: structured; retention documented (≥ 90 d)
- [ ] **A.8.16 Monitoring activities**: alerts defined; response SLAs stated
- [ ] **A.8.20–22 Network security & segregation**: NetworkPolicy, Ingress TLS, no flat networks
- [ ] **A.8.24 Use of cryptography**: TLS 1.3; AES-256 at rest; no `md5` / `sha1` / `rc4` / `des`
- [ ] **A.8.28 Secure coding**: no `eval`; no shell interpolation with untrusted input; parameterized queries
- [ ] **A.8.32 Change management**: CHANGELOG entry; ADR for architectural shifts; signed commits preferred

---

### 3.5 SOC 2 Type II Trust Services Criteria (Phase 4 Prep)

Common Criteria (CC) + category items checkable at file level:

- [ ] **CC1.1 Integrity / ethics**: CODEOWNERS reflects actual review authority; no sockpuppet reviewers
- [ ] **CC2.1 Communication of information**: README / CHANGELOG updated for operational changes
- [ ] **CC3.1 Risk assessment**: risk impact noted in PR description for security-relevant changes
- [ ] **CC4.1 Ongoing monitoring**: metrics + alerts committed alongside service
- [ ] **CC5.1 Control activities**: deployment manifests enforce documented policy (not only docs-as-policy)
- [ ] **CC6.1 Logical access — restrict access**: RBAC + NetworkPolicy present
- [ ] **CC6.2 Logical access — before access issued**: `weown-bot` PAT rotation + review workflow enforced
- [ ] **CC6.3 Logical access — remove or modify**: deprecation path documented when a ServiceAccount / Role is removed
- [ ] **CC6.6 Logical access — boundary of systems**: Ingress + Egress rules explicit; no `0.0.0.0/0` egress without justification
- [ ] **CC6.7 Logical access — transmission**: TLS 1.3 in transit
- [ ] **CC6.8 Logical access — production data**: no production data in test fixtures / example files
- [ ] **CC7.1 System operations — detect config changes**: GitOps reconciliation, `tofu plan`, or `ansible-playbook --check --diff` catches drift
- [ ] **CC7.2 System operations — security events**: audit logs forwarded; no `log-level: none`
- [ ] **CC7.3 System operations — evaluate security events**: alert runbook referenced
- [ ] **CC8.1 Change management**: PR → review → CI → merge; no direct commits to `main`
- [ ] **A1.1 Availability — capacity planning**: resource requests + limits on production workloads
- [ ] **A1.2 Availability — backup / recovery**: §3.1 RC items satisfied
- [ ] **C1.1 Confidentiality — identify confidential info**: data-classification comments where relevant
- [ ] **C1.2 Confidentiality — retention / disposal**: retention policy documented for persistent data

---

### 3.6 ISO/IEC 42001:2023 (AI Management System — Phase 5 Prep)

Controls that apply when a PR introduces or modifies AI components (LLM integrations, RAG, prompt templates, model deployments, agentic flows):

- [ ] **A.2 AI policy**: reference the AI policy document when a new AI system is introduced
- [ ] **A.4 Resources — data & tooling**: data sources referenced (origin, retention, lawful basis)
- [ ] **A.5 AI risk assessment**: AI-specific risks in PR description (hallucination, prompt injection, data leakage, bias, jailbreak, privacy)
- [ ] **A.6 AI lifecycle — design / development**: minimal model card (model name, version, provider, prompt template hash, training cutoff)
- [ ] **A.6 AI lifecycle — verification / validation**: evaluation method stated (evals, golden-dataset tests, human-in-the-loop gates)
- [ ] **A.6 AI lifecycle — deployment**: staged rollout / rollback plan documented
- [ ] **A.6 AI lifecycle — operation / monitoring**: input / output logging (with PII redaction) + quality metrics
- [ ] **A.7 Data for AI**: no training on customer data without explicit opt-in; no PII in committed prompts or test fixtures
- [ ] **A.8 Information for interested parties**: user-facing AI disclosure (terms, privacy notice) referenced
- [ ] **A.9 Use of AI**: agent / autonomous-action boundaries documented (what the AI can do without human approval)
- [ ] **A.10 Third-party relationships**: third-party model provider (OpenAI, Anthropic, etc.) referenced with DPA / BAA in place
- [ ] **Prompt-injection defense**: prompts composed via template with input sanitization, not raw concatenation of untrusted input
- [ ] **No secrets / PII sent to external LLMs**: review prompts + tests for leakage
- [ ] **Model version pinned**: no `gpt-4` → pin to `gpt-4-turbo-2024-04-09` / named snapshot; document upgrade path

---

### 3.7 Kubernetes — Best Practices Checklist

- [ ] **Pod Security Standards `restricted`** enforced (namespace label or admission controller)
- [ ] **NetworkPolicy** on every workload (deny-all default + explicit allow)
- [ ] **ServiceAccount** per workload; `automountServiceAccountToken: false` when unused
- [ ] **RBAC**: `Role` (not `ClusterRole`) preferred; minimum verbs / resources; no `*` wildcards
- [ ] **Resource `requests` + `limits`** on every container (CPU + memory)
- [ ] **`livenessProbe` + `readinessProbe`** on long-running containers; `startupProbe` for slow starters
- [ ] **`securityContext`**: `runAsNonRoot: true`, `runAsUser ≥ 1000`, `runAsGroup`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- [ ] **`PodDisruptionBudget`** for Deployments with `replicas ≥ 2`
- [ ] **HPA / VPA** for scalable workloads with measurable load
- [ ] **Immutable image tags**: SHA digest (`@sha256:...`) preferred; SemVer tag acceptable; `:latest` / `:main` REJECTED
- [ ] **No `hostNetwork`, `hostPID`, `hostIPC`** unless absolutely required + justified in ADR
- [ ] **`topologySpreadConstraints` / `podAntiAffinity`** for HA workloads (spread across nodes)
- [ ] **Ingress**: NGINX + cert-manager (Let's Encrypt prod issuer); TLS 1.3; HSTS header
- [ ] **Storage**: PVC with explicit `StorageClass`; no `emptyDir` for persistent data
- [ ] **`ConfigMap` for non-secret config only**; secrets always via `InfisicalSecret`
- [ ] **Namespace isolation**: one app per namespace where possible; `ResourceQuotas` for multi-tenant namespaces
- [ ] **Standard labels / annotations**: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`, `app.kubernetes.io/part-of`

---

### 3.8 Docker / Docker Compose — Best Practices Checklist

**Dockerfile**:

- [ ] **Multi-stage build** — build stage + minimal runtime stage; no build tools in final image
- [ ] **Minimal base image** — `distroless`, `alpine`, `scratch`, or vendor slim variant
- [ ] **`USER` directive** — non-root UID (≥ 1000) in Dockerfile
- [ ] **`HEALTHCHECK`** instruction present
- [ ] **No `--build-arg` for secrets** (build args are visible in image history)
- [ ] **No `ADD` from remote URLs** without SHA verification; prefer `COPY` from local context
- [ ] **`.dockerignore`** present to avoid leaking `.git`, `.env`, local dev artifacts into image
- [ ] **Pinned base image** — digest or immutable tag; no `FROM image:latest`

**docker-compose.yml**:

- [ ] **Compose v2-style file (no `version:` key)** or modern v3.8+; never `version: "2"` legacy
- [ ] **`restart: unless-stopped`** (or `on-failure`) on prod services — never `no`
- [ ] **`healthcheck:`** block on long-running services
- [ ] **`user:`** non-root UID (`user: "1000:1000"`)
- [ ] **`cap_drop: [ALL]`** + minimal `cap_add:`
- [ ] **`read_only: true`** where feasible, with explicit `tmpfs:` mounts
- [ ] **`security_opt: [no-new-privileges:true]`**
- [ ] **`deploy.resources.limits`** — CPU + memory caps
- [ ] **Infisical agent for secrets** — sidecar container OR `infisical run -- docker compose up` wrapper; no real values in `.env` or `environment:`
- [ ] **Explicit `networks:`** declaration (no reliance on default bridge in prod)
- [ ] **No `privileged: true`**, no `network_mode: host` without justification + ADR
- [ ] **No volume mounts of `/`, `/etc`, `/var/run/docker.sock`** unless justified
- [ ] **Log driver** configured (`json-file` with size limits, or remote driver)

---

### 3.9 Infrastructure as Code — OpenTofu + Ansible — Best Practices Checklist

**Two-tool model**: OpenTofu provisions **infrastructure** (cloud resources, VMs, DNS, networks, clusters). Ansible configures **software** on the provisioned infrastructure (packages, services, config files, agentic-system runtime). Both flow through Infisical (§3.10) for secrets; both are CI-validated before apply.

#### OpenTofu / Terraform (infrastructure provisioning)

- [ ] **Remote encrypted state backend** — DigitalOcean Spaces / S3-compatible with SSE; never local `terraform.tfstate` committed
- [ ] **State backend credentials** sourced from Infisical or workflow secrets — never hardcoded
- [ ] **`required_providers`** with pinned versions (`~> x.y` min; exact `=` for production)
- [ ] **`required_version`** for OpenTofu / Terraform itself pinned
- [ ] **Modules pinned** — no floating `git` refs; `ref=<sha>` or `ref=vX.Y.Z`
- [ ] **Dependency lock file** committed (`.terraform.lock.hcl`)
- [ ] **Input variables** documented (`description`, `type`, `default` where safe, `sensitive = true` where applicable)
- [ ] **Output values** marked `sensitive = true` when exposing credentials / secrets
- [ ] **`locals {}`** — no plaintext secrets; use `data "external"` or Infisical provider
- [ ] **Plan reviewed in CI** — `tofu plan -out=plan.tfplan` artifact uploaded; apply only after manual approval
- [ ] **Separate state per environment** (dev / staging / prod) — never one state file for everything
- [ ] **Resource tags / labels** — `Environment`, `Project`, `Owner`, `ManagedBy = opentofu`
- [ ] **`.gitignore`** excludes `*.tfstate*`, `.terraform/`, `*.tfvars` (if contains secrets), `plan.tfplan`, `crash.log`
- [ ] **No wildcard cloud IAM** — least privilege on generated roles / policies
- [ ] **Drift detection** — scheduled workflow running `tofu plan` to catch out-of-band changes
- [ ] **No deprecated syntax** — OpenTofu 1.x idioms; no redundant `"${var.x}"` interpolations

#### Ansible (software & configuration management)

- [ ] **Inventory in source** — static YAML/INI under `inventories/<env>/` OR Infisical-backed dynamic inventory; never hosts hardcoded across playbooks
- [ ] **Separate inventories per environment** — `inventories/dev/`, `inventories/staging/`, `inventories/prod/` with distinct group_vars / host_vars
- [ ] **No plaintext secrets in vars / playbooks** — use **Ansible Vault** OR Infisical lookup plugin (`community.hashi_vault`) OR `infisical run -- ansible-playbook`
- [ ] **`.vault-pass` / `.vault-password` never committed** — source via Infisical or CI secret; add to `.gitignore`
- [ ] **Roles per service** — `roles/<service>/{tasks,handlers,templates,defaults,vars,meta,files}/` standard layout
- [ ] **Idempotency verified** — second consecutive `--check` run reports no changes; flag any task that always reports `changed`
- [ ] **`become:` explicit** — `become: true` + `become_user: <named-user>`; no global implicit root escalation
- [ ] **Handlers for restarts** — `notify:` + `handlers:` block; no direct `service: state=restarted` in tasks
- [ ] **Module-first principle** — use proper modules (`ansible.builtin.*`, `community.*`) instead of raw `shell:` / `command:`; if shell is required, add `creates:` / `removes:` for idempotency
- [ ] **`no_log: true`** on tasks handling secrets / credentials (suppresses value leakage in play output)
- [ ] **Pinned collections & roles** in `requirements.yml` — explicit versions (no `main` / unpinned git refs); `ansible-galaxy collection install -r requirements.yml` must be reproducible
- [ ] **`ansible-lint` + `yamllint`** in CI (Copilot flags missing `.ansible-lint` / `.yamllint` config files)
- [ ] **Tags on plays / roles** — documented in role README; supports selective runs (`--tags`, `--skip-tags`)
- [ ] **`--check` + `--diff` in CI** before apply; `--diff` output reviewed on security-relevant changes
- [ ] **No ad-hoc `ansible` commands** in prod runbooks — always via versioned playbook committed to repo
- [ ] **Control node requirements** — documented: Python version, required collections, OS; flag `requirements.txt` / `requirements.yml` drift
- [ ] **Callback plugins vetted** — no third-party `stdout_callback` without security review
- [ ] **Templates** (`*.j2`) validated — no untrusted-input interpolation (SSRF / command injection vectors)

---

### 3.10 Infisical (Secret Management) — Best Practices Checklist

- [ ] **No `.env` files with real secrets** committed anywhere
- [ ] **Kubernetes**: `InfisicalSecret` CRD references specific environment + path; no static `Secret` resource with real values
- [ ] **Docker Compose**: Infisical agent sidecar OR `infisical run -- docker compose up` wrapper; no real values in `environment:` / `.env`
- [ ] **GitHub Actions**: Infisical Secret Sync populates `${{ secrets.* }}`; workflows never hardcode PATs
- [ ] **OpenTofu**: Infisical Terraform provider OR `infisical run -- tofu apply` wrapper
- [ ] **Ansible**: `community.hashi_vault` collection pointed at Infisical OR `infisical run -- ansible-playbook`; Vault files encrypted with `ansible-vault`; never commit `.vault-pass`
- [ ] **Least-privilege machine identities** — per-repo PATs (not org-wide), per-environment service tokens (not project-wide)
- [ ] **Rotation cadence documented** — 90 d for PATs; quarterly review for longer-lived tokens
- [ ] **Expiration reminders set** in Infisical (14 d before rotation)
- [ ] **No secrets in code comments** — ever, including examples
- [ ] **No secrets in test fixtures** — use fake-but-realistic values with `<placeholder>` / `<REDACTED>` pattern
- [ ] **Secret naming convention** — `UPPER_SNAKE_CASE`; repo-scoped secrets use `<PREFIX>__<ORG>_<REPO>`
- [ ] **No secrets in Helm `values.yaml` defaults** — placeholders only; real values via `InfisicalSecret`
- [ ] **Rotation audited** — CHANGELOG entry at minimum when a secret rotates
- [ ] **Post-rotation verification** — workflow / app tested after rotation before old PAT revoked

---

### 3.11 Observability — Best Practices Checklist

- [ ] **`/metrics` endpoint** (Prometheus text format) on every long-running service
- [ ] **Structured logs** — JSON; every line has `level`, `timestamp`, `service`, `trace_id` (if applicable)
- [ ] **No secrets / PII in logs** — redaction policy referenced
- [ ] **OpenTelemetry SDK** initialized at service startup for new HTTP / gRPC services
- [ ] **Trace context propagation** — `traceparent` / `tracestate` headers preserved across service boundaries
- [ ] **Log levels**: `DEBUG` off in prod; `INFO` for business events; `WARN` recoverable; `ERROR` actionable
- [ ] **Alert rules as code** — committed with the service (not centralized out-of-band)
- [ ] **SLO / SLI defined** for user-facing / critical-path services
- [ ] **Dashboards as code** — `ConfigMap` + Grafana sidecar pattern; no UI-only authored dashboards
- [ ] **Error budget policy** referenced if SLOs exist
- [ ] **No silent failures** — errors logged AND counted via metrics
- [ ] **Correlation ID** propagated via header on every incoming request
- [ ] **Retention stated**: metrics ≥ 90 d; logs ≥ 90 d; traces ≥ 7 d (adjust per data sensitivity / cost)
- [ ] **Alertmanager routes**: `severity: critical` → paging channel; `severity: warning` → async channel

---

### 3.12 GitOps (ArgoCD / Flux) — Best Practices Checklist

- [ ] **Declarative manifests in git** — no imperative `kubectl apply` / `helm upgrade` in production runbooks
- [ ] **Application CR** (ArgoCD) or **HelmRelease** (Flux) per deployable
- [ ] **Sync policy**: `automated: { prune: true, selfHeal: true }` or equivalent
- [ ] **Environment overlays**: base chart + `overlays/dev|staging|prod` (Kustomize) or env-specific values files
- [ ] **Secrets excluded from GitOps repo** — only `InfisicalSecret` / `ExternalSecret` references
- [ ] **GitOps repo separate from app repo** (recommended) — avoids circular dependency
- [ ] **Deployment order respected** — CRDs before CRs; `syncWave` / `syncPhase` annotations for dependencies
- [ ] **Scoped RBAC** — Argo / Flux controller has minimum cluster permissions
- [ ] **Repository whitelist** on Argo / Flux — only approved repos can drive deployments
- [ ] **Diff review workflow** — `argocd app diff` or equivalent referenced in PR description for config changes
- [ ] **Rollback path**: git revert + resync; documented in app README
- [ ] **No direct cluster edits** — `kubectl edit` flagged as drift and reconciled away

---

### 3.13 Security / Supply Chain — Best Practices Checklist

> **Note**: Copilot flags file-level patterns; CI enforces via scanners. See §6.8 for CI delineation.

- [ ] **Signed commits** on `main` (`gpg --sign` or SSH signing)
- [ ] **Branch protection** configured per `.github/workflows/README.md` §8.1
- [ ] **CODEOWNERS** enforcement enabled on `main`
- [ ] **2-reviewer minimum** via CODEOWNERS + branch protection
- [ ] **SHA-pinned GitHub Actions** — `uses: actions/checkout@<40-char-sha>` (not `@v4`)
- [ ] **Minimum workflow permissions** — `permissions:` block at job level with only required scopes
- [ ] **No `permissions: write-all`** in workflows
- [ ] **No secrets echoed in workflow logs** — never `echo $SECRET`; use `::add-mask::` if unavoidable
- [ ] **SBOM generated** for release artifacts (CI, not Copilot)
- [ ] **Container signing** (cosign / Notation) for release images (future)
- [ ] **Dependency pinning** — `package-lock.json`, `poetry.lock`, `go.sum`, `Cargo.lock`, etc.
- [ ] **License compliance** — new deps checked against allow-list (CI)
- [ ] **No known-vulnerable versions** — base images / deps refreshed when EOL / CVE published
- [ ] **`.gitignore` completeness** — no build artifacts, no state files, no secrets, no OS-specific files (`.DS_Store`)
- [ ] **Pre-commit hooks recommended** — `gitleaks`, `detect-secrets`, `yamllint`, `shellcheck`, `hadolint`
- [ ] **Third-party webhook signature validation** on incoming webhooks
- [ ] **CORS allowlists specific** — never `Access-Control-Allow-Origin: *` with credentials
- [ ] **Input validation** on user-supplied data (length, type, character class, schema)
- [ ] **Output encoding** for data rendered to users (prevent XSS / injection)
- [ ] **Rate limiting** on public endpoints
- [ ] **SBOM / provenance** attached to release artifacts when feasible

---

### 3.14 Documentation & Versioning (cross-cutting)

- [ ] **CHANGELOG updated** — `/CHANGELOG.md` (repo-level) or per-directory CHANGELOG closest to the change
- [ ] **`#WeOwnVer` bumped** per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) — calendar-driven `vSEASON.MONTH.WEEK.ITERATION`. Current reference: **v3.3.4.1**.
- [ ] **READMEs updated** where behavior / operational steps changed
- [ ] **No broken cross-references** (`docs/`, `.github/`, per-app dirs)
- [ ] **ADR added** for architectural decisions (see §3.1 GV.RM)
- [ ] **Model card added** when AI system changes (see §3.6 A.6)
- [ ] **All Copilot comments addressed or deferred** with rationale in the PR conversation

---

## 4. Compliance Framework Roadmap — BE PHASE-AWARE

This repository follows a **layered, phased** compliance program ([`docs/COMPLIANCE_ROADMAP.md`](../docs/COMPLIANCE_ROADMAP.md)). Every review must be aware of the current baseline AND the next phase, so nothing built now needs rebuilding later.

| Phase | Framework | Status | Implication for reviews |
|---|---|---|---|
| 1 | **NIST CSF 2.0** + **CIS Controls v8 IG1** | Active baseline | Primary review vocabulary (§3) |
| 2 | **CSA Cloud Controls Matrix v4** | Planned | Flag cloud-native anti-patterns (multi-tenancy, storage encryption, inter-service trust) |
| 3 | **ISO/IEC 27001:2022** (ISMS) | Planned | Flag missing policies, risk register entries, access-review artifacts |
| 4 | **SOC 2 Type II** | Planned | Flag missing continuous-evidence hooks (logs, change-mgmt records) |
| 5 | **ISO/IEC 42001:2023** (AIMS) | Planned | Flag AI changes missing model cards, impact assessments, risk register entries |

### Change-Type → Control Mapping (flag the mapping in review comments)

| Change | Map To |
|---|---|
| RBAC / ServiceAccount | NIST PR.AC, CIS 5/6, ISO A.5.15-A.5.18 |
| NetworkPolicy | NIST PR.AC-5, CIS 12, ISO A.8.20-A.8.22, CSA IVS |
| Secrets mgmt | NIST PR.DS, CIS 3/16, ISO A.8.24, CSA EKM/DSI |
| TLS / Encryption | NIST PR.DS-1/2, CIS 3, ISO A.8.24 |
| Pod Security Standards | NIST PR.IP, CIS 4, ISO A.8.9 |
| Logging / Monitoring | NIST DE.CM, CIS 8/13, ISO A.8.15-A.8.16 |
| Backup / DR | NIST RC.RP, CIS 11, ISO A.8.13 |
| Incident runbooks | NIST RS / RC, CIS 17, ISO A.5.24-A.5.27 |
| AI model / prompt changes | ISO 42001 Annex A (future ID.AM for AI assets) |
| IaC — OpenTofu (infra) | NIST PR.IP, CIS 4, ISO A.8.32 (change mgmt), CSA CCC |
| IaC — Ansible (software) | NIST PR.IP, CIS 4/16, ISO A.8.9, A.8.32, CSA CCC |
| Docker Compose | NIST PR.PS, CIS 4, ISO A.8.9 |
| GitOps (Argo/Flux) | NIST GV.SC, CIS 4/16, ISO A.5.37, A.8.32 |
| Observability | NIST DE.CM, CIS 8, ISO A.8.15 |

---

## 5. Forward-Looking Guardrails — DO NOT BUILD TO BE REBUILT

**Reject** (or request changes on) designs that satisfy current phase but create rework for later phases:

- ❌ Single-tenant secret management baked into workflows → use Infisical sync (ISO 27001 A.8.24-ready)
- ❌ Per-repo bespoke log formats → prefer centralized / structured logs (SOC 2 evidence-ready)
- ❌ Policy statements only in code comments → surface into ADRs + policy library (ISO 27001-ready)
- ❌ AI system changes without model-card-style documentation → add minimal model card now (ISO 42001-ready)
- ❌ Access controls ad-hoc per resource → standardize via CODEOWNERS + RBAC templates + branch protection
- ❌ Compliance text scattered across READMEs → reference `docs/COMPLIANCE_ROADMAP.md` consistently
- ❌ Workflow secrets hardcoded or `--from-literal` → Infisical + sync; `$(mktemp)` for temp files
- ❌ Container images tagged `:latest` or floating tags → use immutable tags (digest or SemVer)
- ❌ Hardcoded cluster / namespace in Helm templates → use `.Values` with `default` / `required`
- ❌ Raw `kubectl apply` documented as the production path → prefer GitOps (Flux / Argo) and document GitOps as the canonical path

---

## 6. Ecosystem Awareness — Context for the Checklists

Context for §3.7–§3.13. Flag any PR that introduces a parallel mechanism or diverges from the documented pattern.

### 6.1 Kubernetes (primary runtime — see §3.7)

- **Platform**: DigitalOcean Kubernetes (DOKS)
- **Packaging**: Helm charts, self-contained, **official upstream images only** (no Bitnami)
- **Expected files per chart**: `Chart.yaml`, `values.yaml`, `templates/deployment.yaml` (or `statefulset.yaml`), `templates/service.yaml`, `templates/ingress.yaml`, `templates/networkpolicy.yaml`, `templates/rbac.yaml` (or `serviceaccount.yaml`), `templates/infisicalsecret.yaml` (where applicable)
- **Ingress**: NGINX + cert-manager (Let's Encrypt prod issuer)
- **Storage**: DigitalOcean block (ReadWriteOnce); flag RWX needs as architectural concerns
- **Reference**: [`anythingllm/docs/INFISICAL_INTEGRATION.md`](../anythingllm/docs/INFISICAL_INTEGRATION.md)

### 6.2 Docker Compose (growing footprint — see §3.8)

Used for lightweight production deployments where K8s is overkill (single-host services, dev stacks, edge). Expect **many new `docker-compose.yml` files**. Hardening in §3.8; secrets in §3.10.

### 6.3 Infisical (authoritative secret manager — see §3.10)

- **Kubernetes**: `InfisicalSecret` CRD via the Infisical operator
- **Docker Compose**: agent sidecar OR `infisical run -- <cmd>` wrapper
- **GitHub Actions**: App Connection + Secret Sync → native `${{ secrets.* }}` (see [`.github/workflows/README.md` §4](workflows/README.md#4-infisical-github-sync--initial-setup))
- **OpenTofu**: Infisical TF provider OR `infisical run -- tofu apply`
- **Ansible**: `community.hashi_vault` lookup pointed at Infisical OR `infisical run -- ansible-playbook`; `ansible-vault` files encrypted at rest

Flag any parallel secret mechanism (Vault without justification, AWS SSM for non-AWS workloads, `.env` commits, `--from-literal`, plaintext `.vault-pass`).

### 6.4 IaC — OpenTofu (infrastructure) + Ansible (software & config; see §3.9)

Two-tool declarative lifecycle:

- **OpenTofu** (replaces / supplements Terraform) — **infrastructure provisioning**: DigitalOcean droplets & clusters, DNS, Cloudflare, OCI registries, storage, networks. Expect new `infra/` or `tofu/` directories.
- **Ansible** — **software & configuration management** on top of provisioned infrastructure: package installs, systemd units, TLS cert placement, config templating, agentic-system runtime tuning, post-provisioning hardening. Expect new `ansible/`, `playbooks/`, `roles/`, `inventories/<env>/` directories.

**Typical flow**: OpenTofu provisions the droplet / cluster → outputs feed Ansible inventory → Ansible configures software → app runs. Both CI-validated (`tofu plan`, `ansible-playbook --check --diff`) before apply. Secrets for both come from Infisical (§3.10). Hardening / state / vault / idempotency / anti-rebuild rules in §3.9.

### 6.5 GitOps (canonical deploy path — see §3.12)

ArgoCD / Flux is the canonical production deployment path once mature. Flag PRs documenting `kubectl apply` / `helm upgrade` as the production path without a GitOps alternative.

### 6.6 Observability (buildout in progress — see §3.11)

Stack: **Prometheus** (kube-prometheus-stack) + **Grafana**; **Loki** + promtail/Alloy; **Tempo** or **Jaeger** with OpenTelemetry; **Alertmanager** → email / webhook / PagerDuty.

### 6.7 CI/CD Pipeline (buildout in progress)

Canonical reference: [`.github/CI_CD_WORKFLOWS.md`](CI_CD_WORKFLOWS.md) + [`.github/workflows/README.md`](workflows/README.md).

Current workflows: `auto-pr-to-main.yml` (PRs authored by `weown-bot`), `branch-name-check.yml`, `pat-health-check.yml`.

Planned per compliance phase (see [`docs/COMPLIANCE_ROADMAP.md`](../docs/COMPLIANCE_ROADMAP.md)):

| Phase | Workflows |
|---|---|
| 1 | `cis-kube-bench.yml`, `secret-scan.yml`, `sbom-generate.yml`, `image-scan.yml` |
| 2 | `cloud-config-audit.yml`, `multi-tenancy-check.yml`, `encryption-at-rest.yml` |
| 3 | `policy-drift-check.yml`, `access-review-report.yml`, `change-management-gate.yml` |
| 4 | `evidence-collector.yml`, `access-review-evidence.yml` |
| 5 | `model-card-check.yml`, `ai-risk-assessment-check.yml`, `prompt-injection-test.yml` |

Recommend adding these when a PR lands in the relevant area.

### 6.8 Security Scanning (CI-enforced — not Copilot's job)

Runs in CI, **not** in Copilot review: container scanning (Trivy / Grype), dependency scanning (OSV / `npm audit` / `pip-audit` / `govulncheck`), SBOM (Syft), secret scanning (gitleaks / trufflehog + GitHub push protection), Helm / K8s config scanning (`trivy config`, `kube-bench`).

**Copilot's role**: flag file-level patterns that *would* fail those scans (hardcoded secrets, outdated base images, missing `securityContext`) **before** CI runs, so the author can fix them locally.

### 6.9 Application Portfolio (each dir has its own README + CHANGELOG)

| App | Purpose | Runtime |
|---|---|---|
| `anythingllm/` | AI assistant / RAG | Kubernetes (Helm) |
| `wordpress/`, `wordpress-dev/` | CMS | Kubernetes (Helm) |
| `matomo/` | Analytics | Kubernetes (Helm) |
| `vaultwarden/` | Password manager | Kubernetes (Helm) |
| `n8n/` | Workflow automation | Kubernetes (Helm) |
| `nextcloud/` | File sync & collab | Kubernetes (Helm) |
| `fedarch/` | Federated architecture | Mixed |
| `llm-d/` | LLM distributed inference | Kubernetes |
| `braintrust-proxy/` | LLM evaluation proxy | Container |
| `twilio-bridge/` | SMS / voice bridge | Container |

---

## 7. Anti-Pattern Reference — Concrete REJECT Examples

File-level patterns Copilot must flag **CRITICAL** or **HIGH**. Use alongside the §3 checklists.

### 7.1 Secrets & Credentials

```yaml
# REJECT: hardcoded secret, committed .env, --from-literal, /tmp secret material
env: [{ name: API_KEY, value: "sk-1234567890" }]       # use InfisicalSecret / ${{ secrets.* }}
# POSTGRES_PASSWORD=real-value                          # never commit .env with real values
kubectl create secret generic x --from-literal=k=v     # never; use InfisicalSecret
cat > /tmp/secrets.env                                  # use $(mktemp) + trap 'rm -f "$F"' EXIT
```

### 7.2 Access Control

```yaml
# REJECT: cluster-admin binding, wildcard RBAC, unused SA tokens mounted
roleRef: { kind: ClusterRole, name: cluster-admin }    # use Role + least-privilege verbs
rules: [{ apiGroups: ["*"], resources: ["*"], verbs: ["*"] }]
# Missing: automountServiceAccountToken: false (when token unused)
```

### 7.3 Network & TLS

```yaml
# REJECT: weak TLS, plain HTTP in prod, missing NetworkPolicy alongside new Deployment
nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.0 TLSv1.1"   # TLS 1.3 only
# (no cert-manager / Let's Encrypt annotation on prod Ingress)
# (no templates/networkpolicy.yaml in the chart)
```

### 7.4 Container / Pod Security

```yaml
# REJECT: root user, privilege escalation, missing limits/probes, floating image tag
securityContext: { runAsUser: 0, privileged: true, allowPrivilegeEscalation: true }
resources: {}                                           # define requests AND limits
# missing livenessProbe / readinessProbe on long-running container
image: myapp:latest                                     # use digest @sha256:... or SemVer
image: myapp:main                                       # floating branch ref — reject
```

### 7.5 Helm

```yaml
# REJECT: hardcoded namespace, no default/required, no nil guard
metadata: { namespace: production }                     # use .Release.Namespace
value: {{ .Values.required }}                           # use `required "msg" .Values.x` or `default`
{{ .Values.optional.nested.field }}                     # add nil guard: `(.Values.optional).nested.field`
```

### 7.6 Docker Compose

```yaml
# REJECT: legacy schema, privileged, secrets in env, missing healthcheck, root user, host network
version: "2"                                            # omit `version:` or use v3.8+ features
services:
  app:
    privileged: true                                    # never
    network_mode: host                                  # justify + ADR or omit
    environment: [ "API_KEY=sk-real-value" ]            # use Infisical agent
    # missing: healthcheck:, user: "1000:1000", cap_drop: [ALL]
```

### 7.7 IaC — OpenTofu / Terraform / Ansible

```hcl
# REJECT (OpenTofu/Terraform): committed state, hardcoded creds, unpinned module, non-sensitive credential output
# terraform.tfstate*  — must be in .gitignore (use encrypted remote backend)
provider "digitalocean" { token = "dop_v1_real_value" }       # use Infisical or env var
module "k8s" { source = "github.com/.../modules/k8s" }         # add ref=<sha> or ref=vX.Y.Z
output "db_password" { value = module.db.password }            # missing sensitive = true
# missing: tags/labels on resources for cost attribution
```

```yaml
# REJECT (Ansible): plaintext secrets, non-idempotent tasks, implicit root, no handlers, unpinned roles
- name: set db password
  vars:
    db_password: "real-password-value"          # use ansible-vault or community.hashi_vault → Infisical
- name: append to file
  ansible.builtin.shell: "echo 'line' >> /etc/app.conf"   # non-idempotent; use lineinfile / blockinfile / copy
- name: restart service
  become: true
  ansible.builtin.service: { name: app, state: restarted }  # use handlers + notify, not direct restart
# missing: become_user: <named-user> (don't run everything as root)
# missing: no_log: true on secret-handling tasks
# missing: requirements.yml with pinned role/collection versions (no `main` / unpinned refs)
# REJECT (inventory): committed .vault-pass, real hosts+IPs+creds in inventories/*.yml (use Infisical lookup)
```

### 7.8 GitHub Actions Workflows

```yaml
# REJECT: unpinned Action, secret echoed, overly broad perms, secret as workflow_dispatch input
uses: actions/checkout@v4                   # prefer @<40-char-sha>  # v4.x
run: echo "token is $MY_TOKEN"              # never; use ::add-mask:: if unavoidable
permissions: write-all                       # use least privilege per job
on: { workflow_dispatch: { inputs: { api_key: { description: "API key" } } } }  # inputs echo to logs
```

---

## 8. Documentation & Versioning Standards

Per-PR requirements are in §3.14. Templates below are the single source of truth for format. For #WeOwnVer calculation rules, see [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md).

### CHANGELOG entry template

```markdown
## [v3.3.4.1] — 2026-04-23

### Added
- ...

### Changed
- ...

### Removed
- ...

### Security
- ...
```

### ADR template

```markdown
# ADR-NNN: Title

**Status**: Proposed | Accepted | Superseded
**Version**: v3.3.4.1 (#WeOwnVer)
**Date**: YYYY-MM-DD
**Deciders**: @user1, @user2

## Context
## Decision
## Alternatives Considered
## Consequences
## Related
```

---

## 9. Review Output Guidelines (for Copilot)

When posting review comments:

1. **Cite the file and line number** using the repository's citation convention
2. **Map to ≥1 checklist item from §3** — pick the most specific applicable. Acceptable shapes:
   - A NIST CSF Function (e.g., `§3.1 PR.AC — least-privilege violation`) — always available as universal vocabulary
   - A framework-specific control (e.g., `§3.4 ISO A.8.24 — use of cryptography`, `§3.5 CC6.7 — TLS in transit`)
   - An ecosystem best-practice item (e.g., `§3.7 Kubernetes — missing PDB for replicas ≥2`, `§3.9 IaC — unpinned module`)
   - A public-repo precaution (e.g., `§3.0 — private key committed; CRITICAL`)
   Cross-reference additional frameworks when the same violation maps to multiple (e.g., `§3.1 PR.DS + §3.2 CIS 3.11 + §3.4 ISO A.8.24`).
3. **Reference specific guardrail or anti-pattern** from §5 or §7 when applicable
4. **Recommend a specific fix** — show the replacement code, or refer to a compliant example in the repo (e.g., "Follow the pattern in `anythingllm/helm/templates/networkpolicy.yaml`")
5. **Mark severity**:
   - **CRITICAL** — blocks merge. Any §3.0 violation (committed secret / private key / PII / internal topology), any missing NetworkPolicy on a new workload, any root container, any broken CODEOWNERS, any `cluster-admin` grant without ADR
   - **HIGH** — strongly recommend fix in this PR
   - **MEDIUM** — recommend fix now or as a documented follow-up
   - **LOW** — style / nice-to-have
6. **Do not suggest running shell commands** — that's CI's job. Describe the *file-level* change.
7. **For PUBLIC-repo violations (§3.0)**: in addition to flagging CRITICAL, recommend (a) immediate rotation of any leaked credential via `INCIDENT_RESPONSE.md` SEV-1 runbook and (b) git history purge via `git filter-repo` / `bfg-repo-cleaner`.

---

## 11. Commit Message Conventions

All commit messages in this repository must follow this format:

### Summary Line (required)

- **≤72 characters**
- Format: `<type>(<scope>): <imperative subject>`
- Example: `feat(validation): add pre-commit CI/CD workflow`

### Type Values

| Type | Use |
|------|-----|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation-only change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or correcting tests |
| `chore` | Tooling, CI, dependencies |
| `security` | Security-related fix (may include CVE reference) |

### Body (optional but encouraged)

- Separate from summary with a blank line
- Explain **why**, not what (the diff shows what)
- Wrap at ~72 chars for readability in terminals
- Reference PR, issue, ADR, or CVE numbers when relevant

### Example

```markdown
feat(validation): add pre-commit CI/CD workflow (v3.3.4.1)

Adds GitHub Actions validation workflow running Gitleaks,
Trivy, Helm lint, and compliance checks on every PR.
Blocks merge if any check fails.

Refs: docs/PRECOMMIT.md, .github/workflows/validation.yml
Compliance: SOC 2 CC7.2, NIST DE.CM-7
```

---

## 12. Related Documents

- [`docs/COMPLIANCE_ROADMAP.md`](../docs/COMPLIANCE_ROADMAP.md) — Multi-phase compliance strategy
- [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) — #WeOwnVer spec
- [`docs/PRECOMMIT.md`](../docs/PRECOMMIT.md) — Pre-commit hooks and CI/CD integration
- [`docs/GH_RUNNER_DEBUG.md`](../docs/GH_RUNNER_DEBUG.md) — GitHub Actions debug journal
- [`.github/workflows/README.md`](workflows/README.md) — Authoritative workflow operations reference
- [`.github/CI_CD_WORKFLOWS.md`](CI_CD_WORKFLOWS.md) — CI/CD validation workflow architecture
- [`.github/ADR-001-service-account-pat.md`](ADR-001-service-account-pat.md)
- [`.github/ADR-002-infisical-github-sync.md`](ADR-002-infisical-github-sync.md)
- [`.github/SECURITY_ASSESSMENT.md`](SECURITY_ASSESSMENT.md)
- [`.github/INCIDENT_RESPONSE.md`](INCIDENT_RESPONSE.md)
- [`.github/CODEOWNERS`](CODEOWNERS)
- [`/CHANGELOG.md`](../CHANGELOG.md)
- [`/README.md`](../README.md)
