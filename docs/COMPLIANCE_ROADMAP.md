# WeOwn AI Infrastructure — Compliance Framework Roadmap

**Status**: Strategic roadmap — no per-control implementations yet
**Version**: v3.3.4.1 (#WeOwnVer)
**Owner**: `@ncimino` + `@romandidomizio` (post-2026-05-15: Mohammed / Shahid / Dhruv per CODEOWNERS)
**Last Updated**: 2026-04-23

---

## Purpose

This document defines a **layered, phased compliance program** for the WeOwn AI infrastructure repository, progressing from free/universal frameworks to industry-specific certifications. It establishes:

1. **The vocabulary and mental model** (NIST CSF 2.0 Functions) used across all phases
2. **Each phase's goals, scope, controls, CI/CD integration, and success metrics**
3. **Forward-looking guardrails** so work done now (including PR #7) does not need rebuilding later
4. **The integration contract** between Copilot reviews, human reviews, branch protection, and CI/CD

Everything in this document is **strategic / directional**. Per-control implementations (e.g., mapping every Helm chart to CSA CCM domains) live in follow-up PRs.

---

## Executive Summary

| Phase | Framework | Start | Cost | Duration |
|---|---|---|---|---|
| 1 | NIST CSF 2.0 + CIS Controls v8 IG1 | Now (PR #7) | Free | Ongoing baseline |
| 2 | CSA Cloud Controls Matrix v4 | ~Month 2-3 | Free | Ongoing baseline |
| 3 | ISO/IEC 27001:2022 (ISMS) | ~Month 4-9 | Paid audit (external) | Annual recertification |
| 4 | SOC 2 Type II | Year 2 | Paid auditor | Annual attestation |
| 5 | ISO/IEC 42001:2023 (AIMS) | Year 2+ | Paid audit (external) | Annual recertification |

**Why this order**: Each layer complements (not replaces) the previous. NIST CSF gives the Function vocabulary; CIS gives the prescriptive safeguards; CSA adapts for cloud; ISO 27001 formalizes an ISMS that absorbs NIST/CIS/CSA; SOC 2 leverages ISO 27001 evidence directly; ISO 42001 extends ISO 27001 for AI.

---

## Phase 1 — Foundation: NIST CSF 2.0 + CIS Controls v8 IG1

**Start**: Now (roadmap lands in PR #7; per-control mappings in follow-up PRs)

### Goals

- Establish the 6 NIST CSF Functions (Govern, Identify, Protect, Detect, Respond, Recover) as the organizing vocabulary for all security work
- Implement CIS IG1 safeguards (56 controls) — foundational cyber hygiene
- Produce audit evidence (scan reports, logs, SBOMs) consumable by later phases without rework

### Control Plan — NIST CSF 2.0 Functions

| Function | Key Subcategories | Existing Controls | Gap Actions (follow-up PRs) |
|---|---|---|---|
| **Govern (GV)** | Organizational context, risk mgmt strategy, roles, policy, oversight | `.github/copilot-instructions.md`, ADR-001, ADR-002, CODEOWNERS | Policy index doc; formalized risk appetite statement; quarterly governance review |
| **Identify (ID)** | Asset mgmt, business environment, governance, risk assessment, supply chain | Helm charts document app components; per-app READMEs | Asset inventory doc; SBOM per release; risk register; supplier register |
| **Protect (PR)** | Identity/access, awareness, data security, info protection, platform security, technology | RBAC in Helm, NetworkPolicies, TLS 1.3, Infisical for secrets, Pod Security `restricted` | CIS kube-bench gate in CI/CD; automated secret scan; training tracker |
| **Detect (DE)** | Continuous monitoring, adverse event analysis | Prometheus/Grafana referenced; k8s/monitoring/ stack | Centralized logging (Loki); alerting rules; dashboard catalog |
| **Respond (RS)** | Incident mgmt, analysis, mitigation, reporting, recovery | `.github/INCIDENT_RESPONSE.md` | Runbook library per service; post-mortem template; on-call rotation |
| **Recover (RC)** | Recovery planning, improvement, communications | n8n, WordPress, Matomo backup CronJobs; Vaultwarden backups | DR drill schedule; recovery metrics (RTO/RPO); annual DR test |

### Control Plan — CIS Controls v8 IG1 (56 safeguards)

Per-safeguard status (Implemented / Partial / Planned) is produced in a follow-up PR. The Controls:

1. **CIS 1** Inventory of Enterprise Assets
2. **CIS 2** Inventory of Software Assets
3. **CIS 3** Data Protection
4. **CIS 4** Secure Configuration of Enterprise Assets and Software
5. **CIS 5** Account Management
6. **CIS 6** Access Control Management
7. **CIS 7** Continuous Vulnerability Management
8. **CIS 8** Audit Log Management
9. **CIS 9** Email and Web Browser Protections *(N/A for this infra repo)*
10. **CIS 10** Malware Defenses
11. **CIS 11** Data Recovery
12. **CIS 12** Network Infrastructure Management
13. **CIS 13** Network Monitoring and Defense
14. **CIS 14** Security Awareness and Skills Training
15. **CIS 15** Service Provider Management
16. **CIS 16** Application Software Security
17. **CIS 17** Incident Response Management
18. **CIS 18** Penetration Testing *(planned Year 2)*

### CI/CD Integration — Phase 1

| Workflow File | Status | Purpose | Frameworks |
|---|---|---|---|
| `.github/workflows/auto-pr-to-main.yml` | ✅ Updated in PR #7 | Auto-PR creation with NIST CSF review checklist | NIST GV, CIS 14, 16 |
| `.github/workflows/pat-health-check.yml` | ✅ New in PR #7 | Scheduled PAT expiration alerts | NIST PR.AC, CIS 5, 6, 8 |
| `.github/workflows/cis-kube-bench.yml` | 🔜 Follow-up | K8s CIS Benchmark per Helm release | CIS 4 |
| `.github/workflows/secret-scan.yml` | 🔜 Follow-up | gitleaks/trufflehog on every PR | CIS 3, 16; NIST PR.DS |
| `.github/workflows/sbom-generate.yml` | 🔜 Follow-up | Syft SBOM per release | CIS 2; NIST ID.AM |
| `.github/workflows/image-scan.yml` | 🔜 Follow-up | Trivy container scanning | CIS 7; NIST PR.IP |

### Success Metrics — Phase 1

- [ ] Every PR checklist references ≥1 NIST CSF Function
- [ ] 100% of CIS IG1 safeguards tagged Implemented / Partial / Planned
- [ ] ≥4 scheduled CI workflows producing compliance evidence
- [ ] All infrastructure decisions captured as ADRs (Architecture Decision Records)
- [ ] Asset inventory doc covers all Helm charts + supporting infrastructure

---

## Phase 2 — Cloud-Specific: CSA Cloud Controls Matrix v4

**Start**: ~Month 2-3

### Goals

- Address cloud-native threats specifically (K8s, DigitalOcean, multi-tenancy, inter-service trust)
- Bridge NIST/CIS to cloud-specific contexts with concrete control guidance
- Prepare for CSA STAR Level 1 self-assessment (free, public registry)

### Control Plan — CSA CCM v4 (17 Domains, 197 Controls)

| Abbr | Domain |
|---|---|
| AIS | Application & Interface Security |
| AAC | Audit Assurance & Compliance |
| BCR | Business Continuity & Operations Resilience |
| CCC | Change Control & Configuration Management |
| DSI | Data Security & Information Lifecycle Management |
| DCS | Datacenter Security |
| EKM | Encryption & Key Management |
| GRM | Governance & Risk Management |
| HRS | Human Resources |
| IAM | Identity & Access Management |
| IVS | Infrastructure & Virtualization Security |
| IPY | Interoperability & Portability |
| MOS | Mobile Security |
| SEF | Security Incident Management |
| STA | Supply Chain Management, Transparency & Accountability |
| TVM | Threat & Vulnerability Management |
| UEM | Universal Endpoint Management |

Each Helm chart will receive a `CSA-MAPPING.md` file listing the relevant CCM controls the chart implements.

### CI/CD Integration — Phase 2

| Workflow File | Purpose | CCM Domains |
|---|---|---|
| `.github/workflows/cloud-config-audit.yml` | Validate Helm values vs CCM checks | IVS, DSI, EKM |
| `.github/workflows/multi-tenancy-check.yml` | Namespace isolation + NetworkPolicy validation | IVS, IAM |
| `.github/workflows/encryption-at-rest.yml` | Verify StorageClass encryption | EKM, DSI |

### Success Metrics — Phase 2

- [ ] Each Helm chart has a `CSA-MAPPING.md` with domain coverage
- [ ] CSA STAR Level 1 self-assessment submitted and accepted
- [ ] Cloud-specific risk register started (separate from ISO 27001 risk register in Phase 3)

---

## Phase 3 — ISMS Formalization: ISO/IEC 27001:2022

**Start**: ~Month 4-9

### Goals

- Formalize policies and procedures into an ISMS structure aligned with ISO 27001:2022
- Produce a Statement of Applicability (SoA) covering all 93 Annex A controls
- Maintain a risk register with treatments, acceptance, and periodic reviews
- Prepare organizationally for external certification audit (when business requires)

### Control Plan — ISO/IEC 27001:2022 Annex A (93 controls, 4 themes)

- **A.5 Organizational controls (37 controls)** — Information security policies, roles, threat intelligence, supplier relationships, info sec in project mgmt, asset inventory, privacy
- **A.6 People controls (8 controls)** — Screening, terms and conditions of employment, awareness, disciplinary process, responsibilities after termination, confidentiality, remote working, event reporting
- **A.7 Physical controls (14 controls)** — Physical security perimeters, secure areas, equipment siting, cabling, maintenance, clear desk/screen
- **A.8 Technological controls (34 controls)** — Endpoint devices, privileged access, authentication, capacity mgmt, malware protection, vulnerability mgmt, network controls, crypto, secure development, testing

### Prerequisites from Phases 1 & 2

- NIST CSF Function mapping complete (feeds directly into A.5 and A.8)
- CIS IG1 baseline implemented (evidence for A.8 technological controls)
- CSA CCM cloud controls mapped (evidence for cloud-specific A.8 controls)

### CI/CD Integration — Phase 3

| Workflow File | Purpose | Controls |
|---|---|---|
| `.github/workflows/policy-drift-check.yml` | Alert when infra diverges from policy docs | A.5.1, A.5.36 |
| `.github/workflows/access-review-report.yml` | Monthly RBAC review automation | A.5.15, A.5.16, A.5.18 |
| `.github/workflows/change-management-gate.yml` | Enforce change control on every PR | A.5.37, A.8.32 |

### Success Metrics — Phase 3

- [ ] Statement of Applicability (SoA) published
- [ ] Risk register with ≥50 risks, treatments, and residual risk acceptance
- [ ] Policy library covering all required A.5 topics
- [ ] Internal audit schedule operational (quarterly)
- [ ] Certification audit (if business justifies) scheduled

---

## Phase 4 — External Attestation: SOC 2 Type II

**Start**: Year 2 (6–12 months of evidence collection before audit)

### Goals

- Obtain SOC 2 Type II report for US enterprise B2B customer trust
- Demonstrate continuous control effectiveness (vs. Type I point-in-time)
- Reuse ISO 27001 evidence (high overlap; efficiency multiplier)

### Trust Services Criteria — all 5 applied

1. **Security (common criteria)** — required for all SOC 2 reports
2. **Availability** — uptime, capacity, backup, DR
3. **Processing Integrity** — complete, accurate, valid, timely processing
4. **Confidentiality** — protecting information designated as confidential
5. **Privacy** — collection, use, retention, disclosure of personal information (if applicable)

### Prerequisites from Phases 1–3

- NIST CSF Functions = the control framework most SOC 2 evaluators are familiar with
- CIS IG1 = hygiene baseline evidence (logs, scans, SBOMs)
- ISO 27001 ISMS = the policy and risk management engine SOC 2 auditors need
- CSA CCM = cloud-specific controls feeding Security and Availability

### CI/CD Integration — Phase 4

| Workflow File | Purpose | TSC |
|---|---|---|
| `.github/workflows/evidence-collector.yml` | Daily archival of logs/reports/metrics to tamper-evident storage | Security, Processing Integrity |
| `.github/workflows/change-management-gate.yml` (reused from Phase 3) | Enforce change control | Security |
| `.github/workflows/access-review-evidence.yml` | Quarterly access review artifacts | Security |

### Success Metrics — Phase 4

- [ ] 6–12 months of continuous evidence collection in place before audit
- [ ] Type II audit report obtained
- [ ] Customer-facing trust/compliance page published (`trust.weown.xyz` or similar)
- [ ] Bridge letter process established for interim reporting

---

## Phase 5 — AI Governance: ISO/IEC 42001:2023

**Start**: Year 2+ (after ISO 27001 is stable)

### Goals

- Extend the ISMS with AI-specific management system controls (AIMS)
- Produce AI risk register, model cards, and impact assessments
- Govern lifecycle of LLMs, RAG pipelines, and agentic systems (AnythingLLM, future agents)

### Key AI-Specific Additions (structurally built on ISO 27001)

- **AI system lifecycle** (ISO 5338) — design, development, deployment, monitoring, retirement
- **AI impact assessment** (ISO 42005) — societal, ethical, environmental stakeholder analysis
- **AI risk management** (ISO 23894 + ISO 31000) — specific risks: data quality, model failure, privacy, adversarial, ethical
- **AI ethics and societal considerations** (ISO 24368) — fairness, accountability, transparency
- **Model versioning**, **training data lineage**, **bias audits**
- **Human oversight** (already present via Copilot + 2 required reviewers + CODEOWNERS)

### CI/CD Integration — Phase 5

| Workflow File | Purpose |
|---|---|
| `.github/workflows/model-card-check.yml` | Require model card for any change touching AI components |
| `.github/workflows/ai-risk-assessment-check.yml` | Require impact assessment for AI-system-level changes |
| `.github/workflows/prompt-injection-test.yml` | Red-team prompts against deployed AnythingLLM/agents |

### Success Metrics — Phase 5

- [ ] All AI systems (AnythingLLM, future agents) have current model cards
- [ ] AI risk register integrated with ISO 27001 risk register
- [ ] ISO 42001 certification audit passed

---

## Cross-Framework Integration — How Everything Connects

### Framework Relationships

```
┌──────────────────────────────────────────────────────────┐
│  NIST CSF 2.0 (vocabulary & Functions)                   │
│  └─> CIS v8 IG1 (prescriptive safeguards)                │
│      └─> CSA CCM v4 (cloud-specific extensions)          │
│          └─> ISO/IEC 27001:2022 (formal ISMS)            │
│              ├─> SOC 2 Type II (customer attestation)    │
│              └─> ISO/IEC 42001:2023 (AI extension)       │
└──────────────────────────────────────────────────────────┘
```

### Why Nothing Gets Re-Built

1. **NIST CSF Functions** = the universal vocabulary in PR checklists, Copilot reviews, and ADRs. This vocabulary is stable across all 5 phases.
2. **CIS and CSA evidence** (scan reports, SBOMs, CCM mappings) flows directly into ISO 27001 A.8 and SOC 2 Security TSC evidence without rework.
3. **ISO 27001 policies** become SOC 2 system description inputs almost verbatim.
4. **ISO 42001** structurally extends ISO 27001, so having the ISMS first eliminates AI-specific duplicate work.

---

## Copilot, Human Review, and CI/CD Integration Contract

### Copilot Reviews (`.github/copilot-instructions.md`)

- **Phase-aware**: Copilot knows all 5 phases and flags changes that would conflict with future phases
- **NIST CSF Function mapping**: every Copilot review maps the change to ≥1 Function
- **CIS Controls awareness**: Copilot flags weakening of any IG1 safeguard
- **Forward-looking guardrails**: Copilot rejects patterns that would need rebuilding for ISO 27001 / SOC 2 / ISO 42001

### Human Review (auto-generated PR body)

- Checklist structured by **NIST CSF Functions** (Govern, Identify, Protect, Detect, Respond, Recover)
- Each checklist item tagged with framework refs (e.g., "Least privilege IAM → NIST PR.AC, CIS 6, ISO A.5.15")
- 2 required reviewers enforced via branch protection (1 from CODEOWNERS always includes `@ncimino`)

### CI/CD Workflows (`.github/workflows/`)

- Per-phase workflow additions (see tables above)
- Each workflow produces audit evidence consumable by subsequent phases
- No workflow is phase-specific in a way that blocks later phases

---

## Ownership & Transition

- **Current Owner (pre-2026-05-15)**: `@romandidomizio` + `@ncimino`
- **Post-2026-05-15**: `@ncimino` remains; primary steward transitions to one of Mohammed / Shahid / Dhruv per CODEOWNERS handoff (placeholders in `.github/CODEOWNERS`)
- **Transition checklist**: `.github/workflows/README.md` → "Transition Checklist 2026-05-15"

---

## References

- **NIST CSF 2.0**: https://www.nist.gov/cyberframework
- **CIS Controls v8**: https://www.cisecurity.org/controls/v8
- **CSA Cloud Controls Matrix v4**: https://cloudsecurityalliance.org/research/cloud-controls-matrix
- **ISO/IEC 27001:2022**: https://www.iso.org/standard/27001
- **SOC 2 TSC**: https://www.aicpa-cima.com/topic/audit-assurance/audit-and-assurance-greater-than-soc-2
- **ISO/IEC 42001:2023**: https://www.iso.org/standard/42001

---

## Related Repository Documents

- `.github/copilot-instructions.md` — Copilot AI review directives (phase-aware)
- `.github/workflows/README.md` — Workflow architecture, PAT rotation, transition checklist
- `.github/ADR-001-service-account-pat.md` — Service account rationale
- `.github/ADR-002-infisical-github-sync.md` — Secret management rationale
- `.github/SECURITY_ASSESSMENT.md` — Threat model and risk register
- `.github/INCIDENT_RESPONSE.md` — IR runbook
- `.github/CODEOWNERS` — Review assignment with handoff TODOs
- `/CHANGELOG.md` — Repository-level change history (index to all per-dir CHANGELOGs)
