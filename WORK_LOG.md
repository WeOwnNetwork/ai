# Work Log — Docker Template Improvements

**Last Updated:** 2026-06-08
**Status:** Phase 2 complete — 5 PRs submitted and ready for review
**Phase 2.5 Status:** ✅ Complete — ADR-006 implementation merged into PR #68

**Related Documents:**

- [GOVERNANCE.md](GOVERNANCE.md) - Working principles, decisions, chores, conditionals
- [ADR-006-IMPLEMENTATION-SUMMARY.md](ADR-006-IMPLEMENTATION-SUMMARY.md) - Technical details of ADR-006 implementation

---

## Overview

This document tracks all work related to docker template improvements across the WeOwnNetwork/ai repository. The goal is to maintain clear visibility into completed work, in-progress tasks, and planned features.

**Strategy:** Complete all work first, then consolidate into logical batched PRs to reduce reviewer burden.

---

## Current State

**Open PRs:** 6 (5 from Phase 2 + 1 from Phase 2.5)
**Branches with completed work:** 6 (all submitted)
**Branches with in-progress work:** 1 (ADR-006 bug fixes)
**Planned work:** 4 items
**Next milestone:** Phase 3 — Keycloak deployment (after PRs merge)

**Pending Review:**

- PR #62: site.conf for all docker templates
- PR #63: site.sh convenience wrapper
- PR #64: Infisical outage runbook
- PR #66: automated site deployment
- PR #67: branch setup utility
- PR #68: ADR-006 in-container Infisical injection (supersedes #62-#67)
  - ⚠️ **CRITICAL BUGS FOUND** - entrypoint auth missing, Keycloak DB name missing
  - Fix strategy documented in GOVERNANCE.md
  - Awaiting approval to proceed with fixes

---

## Phase 2.5: ADR-006 In-Container Infisical Injection (Completed 2026-06-08)

**Branch:** `feature/mot-adr006-in-container-infisical`  
**PR:** #68 (supersedes PRs #62-#67)  
**Status:** ✅ Complete — all 7 templates updated, READMEs updated, implementation summary written  
**Time spent:** ~40 minutes (2026-06-08)  
**Reference:** `.github/ADR-006-in-container-infisical-injection.md` (Nik's branch `docs/nik-adr006-infisical-injection`)  
**Goal:** Implement ADR-006 standard across all 7 docker templates — move secret resolution from host-side wrap to in-container entrypoint, enabling bounce-to-refresh and consumer-side auto-rotation.

### What ADR-006 Changes

**Old pattern (host-side wrap):**

- Ansible runs `infisical run -- docker compose up -d`
- Secrets baked into container at create time via `${VAR}` interpolation
- `docker restart` does NOT pick up rotated secrets (only redeploy does)

**New pattern (ADR-006 in-container entrypoint):**

- Container's `entrypoint:` is `infisical run --projectId=<id> --env=<slug> --`
- Secrets fetched in-process at every container start
- `docker restart` re-fetches secrets (bounce-to-refresh)
- Secrets removed from `environment:` block (not visible in `docker inspect`)
- Host-side `infisical run` wrapper dropped from ansible deploy

### Multi-Container Env Var Naming Solution

For stacks where multiple containers expect secrets under different env var names (e.g., PostgreSQL expects `POSTGRES_PASSWORD`, Keycloak expects `KC_DB_PASSWORD`), **duplicate the secret in Infisical under each app's expected name**. This keeps compose files clean, avoids wrapper scripts, and maintains ADR-006's bounce-to-refresh property.

**Example (Keycloak stack):**

- Infisical stores: `POSTGRES_PASSWORD` and `KC_DB_PASSWORD` (same value, two names)
- PostgreSQL reads `POSTGRES_PASSWORD` from its process env
- Keycloak reads `KC_DB_PASSWORD` from its process env
- Both containers use `infisical run` entrypoint, no `${VAR}` interpolation

### Implementation Completed

**Templates updated (7):**

1. ✅ `anythingllm-docker` — single app container (pilot, cleanest case)
2. ✅ `searxng-docker` — single app + Valkey (Valkey has no secrets)
3. ✅ `sandbox-docker` — single app container
4. ✅ `openclaw-docker` — single app container
5. ✅ `wordpress-docker` — multi-container (MariaDB + WordPress + Caddy), needs `MYSQL_*` + `WORDPRESS_DB_*` duplication
6. ✅ `keycloak-docker` — multi-container (PostgreSQL + Keycloak + Caddy), needs `POSTGRES_*` + `KC_DB_*` + `KEYCLOAK_*` duplication
7. ✅ `signoz-docker` — multi-container but shared `CLICKHOUSE_PASSWORD` (easy)

**Per-template changes:**

- ✅ `template/docker/compose.prod.yaml.jinja` — added `entrypoint:` with `infisical run`, added bind-mounts for CLI + auth file, removed secret `${VAR}` lines from `environment:`
- ✅ `template/ansible/deploy.yml.jinja` — added task to create container-readable auth file (`.infisical-auth.env.container`, mode 0640), dropped `infisical run` wrapper from `docker compose up` tasks
- ✅ `README.md` — updated to document bounce-to-refresh as the supported runtime path, removed references to host-side wrap

**Live sites to update (deferred — can be re-rendered after merge):**

- `anythingllm-docker/sites/ai.weown.agency/`
- `anythingllm-docker/sites/s004.ccc.bot/`
- `keycloak-docker/sites/sso.weown.dev/`
- `wordpress-docker/sites/burnedout-xyz/`
- `wordpress-docker/sites/ptoken-agency/`
- `wordpress-docker/sites/stage-burnedout-xyz/`
- `openclaw-docker/sites/claw-weown-tools/`

**Scripts to update (deferred — follow-up PR):**

- `scripts/deploy-new-site.sh` — update Infisical secret names to match app env var names (e.g., `POSTGRES_PASSWORD` instead of `DB_PASSWORD`)

### Compliance Mapping

| Control | Addressed by |
|---|---|
| NIST CSF 2.0 PR.AC-4 (least privilege) | Per-workload, per-project Machine Identity; no shared identity |
| NIST CSF 2.0 PR.DS-1 (data protection) | Secrets out of committed config and `docker inspect` |
| CIS Controls v8 5.3 (credential rotation) | In-container fetch gives rotation a consumer-side trigger (bounce) |
| ISO/IEC 27001:2022 A.5.17 (authentication information) | No app secrets in config files; Infisical-backed at runtime |
| FedArch PRJ-024 (Secrets Management) | Exceeds PRJ-024's init container approach; aligns with runtime injection standard |
| FedArch PRJ-032 (OpenTofu IaC) | Complements IaC pattern with runtime secret delivery |

### Related Documents

- ADR-006: `.github/ADR-006-in-container-infisical-injection.md` (on Nik's branch `docs/nik-adr006-infisical-injection`)
- Bootstrap pattern: `docs/INFRA_BOOTSTRAP_PATTERN.md` (Layer 1 + Layer 2 + Path C)
- FedArch secrets: `CCCbotNet/fedarch/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md`
- FedArch IaC: `CCCbotNet/fedarch/_PROJECTS_/PRJ-032_OpenTofu-IaC.md`
- Implementation summary: `ADR-006-IMPLEMENTATION-SUMMARY.md`
- PR: https://github.com/WeOwnNetwork/ai/pull/68

---

## PR Submission Status (2026-06-08)

All 5 PRs have been submitted to upstream and are ready for review:

| PR | Title | Branch | Threads | CI | Signed | Merge Order |
|----|-------|--------|---------|----|----|-------------|
| #62 | site.conf for all docker templates | `feature/mot-docker-site-conf` | 0/31 ✅ | ✅ | ✅ | 1st |
| #63 | site.sh convenience wrapper | `feature/mot-docker-site-sh` | 0/22 ✅ | ✅ | ✅ | 2nd |
| #64 | Infisical outage runbook | `feature/mot-outage-runbook` | 0/9 ✅ | ✅ | ✅ | 3rd |
| #66 | automated site deployment | `feature/mot-automated-site-deployment` | 0/19 ✅ | ✅ | ✅ | 4th |
| #67 | branch setup utility | `feature/mot-branch-setup-tool` | 0/44 ✅ | ✅ | ✅ | 5th |

**All PRs include:**

- Testing sections (what was validated)
- Reviewer notes (where to start, what's critical)
- Related PRs (dependencies)
- Merge order (explicit sequence)

**Merge sequence:** #62 → #63 → #64 → #66 → #67

**Next steps:**

1. Get human approval on each PR
2. Merge in sequence
3. Begin Phase 3: Keycloak deployment

---

## Phase 1: Fix Blockers (Completed 2026-06-07)

Fixed all critical issues identified by Copilot review across 5 branches:

**PR #62 (site.conf):**

- ✅ Fixed unclosed Jinja block in wordpress terraform main.tf.jinja
- ✅ Removed minimus_token from cloud-init user_data (security)
- ✅ Fixed project_name normalization in wordpress cloud-init
- ✅ Wired ssh_source_cidrs into firewall rules (wordpress, keycloak)
- ✅ Fixed get_tfvar crash under set -euo pipefail (wordpress, keycloak)
- ✅ Added optional docker login for reg.mini.dev in ansible deploy (4 templates)
- ✅ Re-added reserved_ip output alias (wordpress)

**PR #63 (site.sh):**

- ✅ Fixed cmd_restore() to detect IP vs backup-name from first argument (all 7 templates + 2 live sites)
- ✅ Added missing lib.sh and site.conf to live sites (s004.ccc.bot, ai.weown.agency)

**PR #64 (outage runbook):**

- ✅ Used Statuspage JSON API instead of HTML grep
- ✅ Clarified container env persistence during outage
- ✅ Replaced AnythingLLM-specific references with template-agnostic placeholders
- ✅ Added volume clear step before restore extraction
- ✅ Scoped Spaces credentials to single aws invocation

**PR #66 (automated deployment):**

- ✅ Fixed dry-run mode: guard $PROJECT_ID and skip report generation
- ✅ Redacted MI_CLIENT_SECRET in --auto mode (CI/CD safety)
- ✅ Fixed EXIT trap to clean correct tfplan/tfvars paths
- ✅ Added jq prerequisite check
- ✅ Added BatchMode=yes to SSH polling
- ✅ Set chmod 600 on terraform.tfvars
- ✅ Fixed truncated plan message
- ✅ Fixed prerequisites list (remove doctl, add jq)
- ✅ Fixed docs: remove test-deploy.sh ref, pin actions SHA

**PR #67 (branch setup tool):**

- ✅ Guarded --task against missing value (unbound variable crash)
- ✅ Checked for clean working tree before branch operations
- ✅ Used --ff-only on git pull to avoid accidental merges
- ✅ Made grep pipelines tolerant of no matches (set -euo pipefail)
- ✅ Continued gracefully when WORK_LOG.md is missing
- ✅ Removed hardcoded 'mot' prefix from branch normalization

---

## Phase 2: Submit PRs (Completed 2026-06-08)

Pushed all 5 branches to upstream and created PRs:

1. **Pushed branches** to `upstream` remote
2. **Created PRs** via `gh pr create` (auto-pr workflow had expression length limit error)
3. **Added reviewer summaries** to each PR with testing, notes, dependencies, merge order
4. **Resolved all Copilot review threads** (84 total across 5 PRs)
5. **Fixed commit signing** — added SSH signing key to GitHub account, added MOT@weown.net email
6. **Updated PR bodies** to include testing sections, reviewer notes, related PRs, merge order

**Result:** All 5 PRs ready for human review and merge.

---

## Completed Work (On Branches, Not Yet PR'd)

### 1. site.conf Implementation

**Branch:** `feature/mot-docker-site-conf`  
**Completed:** 2026-06-06  
**What:** Implemented site.conf pattern across all 7 docker templates  
**Why:** Eliminate env var juggling for operators  
**Key Features:**

- site.conf.jinja template (INFISICAL_PROJECT_ID, INFISICAL_ENV)
- lib.sh.jinja with safe config reader (load_site_conf function)
- Updated deploy.sh, backup.sh, restore.sh to read from site.conf
- Env vars still work as overrides
- Added to live sites (s004.ccc.bot, ai.weown.agency)
- lint-site-conf.sh to catch accidental secret commits
- answers.yaml.example for anythingllm-docker

**Templates affected:** anythingllm, wordpress, keycloak, searxng, signoz, sandbox, openclaw

### 2. site.sh Implementation

**Branch:** `feature/mot-docker-site-sh`  
**Completed:** 2026-06-06  
**What:** Added site.sh convenience wrapper to all 7 docker templates  
**Why:** Simplify daily workflow for operators  
**Key Features:**

- Auto-detects droplet IP from tofu output
- Unified command interface (deploy, backup, restore, logs, health, ip)
- Reads INFISICAL_PROJECT_ID from site.conf
- Added to live sites (s004.ccc.bot, ai.weown.agency)

**Templates affected:** anythingllm, wordpress, keycloak, searxng, signoz, sandbox, openclaw

### 3. Infisical Outage Runbook

**Branch:** `feature/mot-outage-runbook`  
**Completed:** 2026-06-06  
**What:** Created comprehensive outage runbook and added references to all docker templates  
**Why:** Document emergency procedures for when Infisical is unavailable  
**Key Features:**

- 405-line runbook (docs/INFISICAL_OUTAGE_RUNBOOK.md) covering:
  - Detection and verification procedures
  - Impact assessment (what breaks, what works)
  - Emergency deployment without Infisical (temporary .env)
  - Emergency backup (local-only, no Spaces upload)
  - Emergency restore from local or Spaces
  - Container restart procedures
  - Recovery steps when Infisical comes back online
  - Prevention and mitigation strategies
- References added to all 7 docker template READMEs

**Templates affected:** anythingllm, wordpress, keycloak, searxng, signoz, sandbox, openclaw

### 4. Automated Deployment System

**Branch:** `feature/mot-automated-site-deployment`  
**Completed:** 2026-06-06  
**What:** Created automated site deployment script with tiered Infisical security  
**Why:** Automate the complete deployment workflow while maintaining security best practices  
**Key Features:**

- scripts/deploy-new-site.sh (503 lines) — automated deployment script
- docs/AUTOMATED_DEPLOYMENT.md (460 lines) — comprehensive guide
- Tiered Machine Identity security model:
  - Tier 1 MI (bootstrap): High privilege, limited scope, stored in operator-tools project
  - Tier 2 MI (site): Low privilege, site-scoped, rotated on first boot
- 6 deployment phases: validation → Infisical setup → rendering → infrastructure → deployment → reporting
- Dry-run mode, auto mode, skip flags
- Human review checkpoints at critical decision points
- Comprehensive logging and error handling

**Files:** scripts/deploy-new-site.sh, docs/AUTOMATED_DEPLOYMENT.md

### 5. Branch Setup Tool

**Branch:** `feature/mot-branch-setup-tool`  
**Completed:** 2026-06-06  
**What:** Created automated branch setup script that integrates completed work  
**Why:** Ensure new tasks always start with the right foundation by automatically merging relevant completed work  
**Key Features:**

- scripts/setup-feature-branch.sh (344 lines) — automated branch creation with integrated work
- Reads WORK_LOG.md to identify completed branches
- Auto-detects task type from branch name (deployment, template, docs, infrastructure)
- Suggests appropriate merges based on task type
- Dry-run mode to preview actions
- Interactive confirmation before making changes
- Comprehensive logging to branch-setup.log

**Files:** scripts/setup-feature-branch.sh

---

## In Progress

### Keycloak Deployment (Phase 3)

**Status:** Blocked — waiting for PRs #62-#67 to merge  
**Branch:** (will create `feature/mot-keycloak-deployment`)  
**Goal:** Deploy live keycloak instance for platform-wide ID/access management  
**Tasks:**

- [ ] Set up Tier 1 MI in Infisical (manual, one-time)
- [ ] Test deploy-new-site.sh with keycloak-docker template
- [ ] Render keycloak site from template
- [ ] Provision infrastructure (tofu)
- [ ] Deploy application (ansible)
- [ ] Test and validate
- [ ] Document deployment

**Dependencies:**

- PR #62 (site.conf) — must merge first
- PR #63 (site.sh) — must merge second
- PR #66 (automated deployment) — must merge fourth
- All 5 PRs merged before starting Phase 3

---

## Planned Work

### Template Update Workflow

**Status:** Not started  
**Goal:** Document how to bring existing sites up to date when template changes  
**Why:** Currently no documented process for updating rendered sites  
**Deliverable:** Section in DEPLOYMENT_GUIDE.md or separate doc

### SECRETS.md Template

**Status:** Not started  
**Goal:** Create single source of truth for required secrets per template  
**Why:** Secrets are documented in scattered places  
**Deliverable:** SECRETS.md.jinja template rendered with each site

### Onboarding Guide

**Status:** Not started  
**Goal:** Create GETTING_STARTED.md for new developers  
**Why:** Current docs are scattered across multiple files  
**Deliverable:** docs/GETTING_STARTED.md with step-by-step walkthrough

### Infisical Monitoring

**Status:** Not started  
**Goal:** Set up proactive monitoring for Infisical availability  
**Why:** Currently only find out Infisical is down when deploy fails  
**Deliverable:** UptimeRobot or similar monitoring setup

---

## PR Batching Plan

When all work is complete, consolidate into these batched PRs:

### Batch 1: site.conf for all docker templates

**Branch:** `feature/mot-docker-site-conf` (already exists)  
**Scope:** site.conf pattern + lib.sh + lint script + answers.yaml.example  
**Templates:** all 7 docker templates

### Batch 2: site.sh for all docker templates

**Branch:** `feature/mot-docker-site-sh` (already exists)  
**Scope:** site.sh convenience wrapper  
**Templates:** all 7 docker templates

### Batch 3: outage runbook + references

**Branch:** `feature/mot-outage-runbook` (already exists)  
**Scope:** INFISICAL_OUTAGE_RUNBOOK.md + README references  
**Templates:** all 7 docker templates

### Batch 4: automated deployment system

**Branch:** `feature/mot-automated-site-deployment` (already exists)  
**Scope:** deploy-new-site.sh + AUTOMATED_DEPLOYMENT.md  
**Note:** May evolve based on keycloak deployment testing

### Batch 5: branch setup tool

**Branch:** `feature/mot-branch-setup-tool` (already exists)  
**Scope:** setup-feature-branch.sh script  
**Note:** Utility script for managing feature branches

### Batch 6: keycloak deployment (if applicable)

**Branch:** `feature/mot-keycloak-deployment` (not yet created)  
**Scope:** Rendered keycloak site + deployment documentation  
**Note:** Depends on keycloak deployment being completed

### Batch 7: documentation improvements

**Branch:** (not yet created)  
**Scope:** Template update workflow, SECRETS.md template, onboarding guide  
**Note:** Depends on planned work being completed

---

## Closed PRs (For Reference)

The following PRs were closed on 2026-06-06 to consolidate into batched PRs:

**Original PRs (closed):**

- PR #44: feat(wordpress-docker): complete Path C + Layer 2 migration
- PR #45: feat(searxng-docker): complete Path C + Layer 2 migration
- PR #46: feat(keycloak-docker): complete Path C + Layer 2 migration
- PR #47: feat(signoz-docker): complete Path C + Layer 2 migration
- PR #50: feat(anythingllm-docker): site.conf
- PR #51: docs: add Infisical outage runbook
- PR #52: feat(sandbox-docker): site.conf
- PR #53: feat(openclaw-docker): site.conf
- PR #54: docs: add outage runbook references
- PR #55: feat(anythingllm-docker): site.sh
- PR #56: feat(sandbox-docker): site.sh
- PR #57: feat(openclaw-docker): site.sh
- PR #58: feat(wordpress-docker): site.sh
- PR #59: feat(keycloak-docker): site.sh
- PR #60: feat(searxng-docker): site.sh
- PR #61: feat(signoz-docker): site.sh

**Consolidated PRs (also closed, will be re-batched later):**

- PR #62: feat: site.conf for all docker templates
- PR #63: feat: site.sh for all docker templates
- PR #64: docs: Infisical outage runbook + references for all docker templates
- PR #65: feat: automated site deployment with tiered Infisical security

**Reason:** Decided to wait until all work is complete before submitting any PRs, to allow for iteration and proper batching.

---

## Branch Inventory

**Branches with completed work (5):**

- `feature/mot-docker-site-conf` — site.conf for all templates
- `feature/mot-docker-site-sh` — site.sh for all templates
- `feature/mot-outage-runbook` — outage runbook + references
- `feature/mot-automated-site-deployment` — automated deployment system
- `feature/mot-branch-setup-tool` — branch setup utility script

**Cleanup completed (2026-06-06):**

- Deleted 16 redundant individual branches (7 site-conf, 7 site-sh, 2 outage-runbook)
- All work preserved in consolidated branches
- Cleaned up local, origin (fork), and upstream (WeOwnNetwork/ai) remotes
- Repository now has clean, organized branch structure

**Original branches (preserved for reference, 16):**

- feature/mot-anythingllm-site-conf
- feature/mot-sandbox-site-conf
- feature/mot-openclaw-site-conf
- fix/mot-wordpress-docker-deployment-template
- fix/mot-searxng-docker-migration
- fix/mot-keycloak-docker-migration
- fix/mot-signoz-docker-migration
- feature/mot-anythingllm-site-sh
- feature/mot-sandbox-site-sh
- feature/mot-openclaw-site-sh
- feature/mot-wordpress-site-sh
- feature/mot-keycloak-site-sh
- feature/mot-searxng-site-sh
- feature/mot-signoz-site-sh
- docs/mot-infisical-outage-runbook
- docs/mot-outage-runbook-references

**Future branches (not yet created):**

- feature/mot-keycloak-deployment
- feature/mot-template-updates
- feature/mot-onboarding-guide

---

## Notes

### PR Batching Strategy

- Complete all work first, then batch into logical PRs
- Aim for 3-6 PRs total, not 16+
- Consider reviewer's experience
- Group by logical feature, not by file/directory
- Allow time for iteration and refinement before submitting

### Testing Strategy

- Fill in INFISICAL_PROJECT_ID in live site.conf files
- Test ./site.sh deploy on live deployment
- Test deploy-new-site.sh with keycloak deployment
- Validate end-to-end workflow before creating PRs

### Documentation Strategy

- Update READMEs as part of feature branches
- Create standalone docs for cross-cutting concerns
- Keep WORK_LOG.md updated as work progresses
- Document decisions and rationale for future reference
