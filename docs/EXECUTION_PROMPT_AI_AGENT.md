# Execution Prompt: AI Agent — Keycloak Launch + Phase 1 Implementation

**Date**: 2026-04-28  
**Version**: v3.3.4.1 (#WeOwnVer)  
**Scope**: `sso.weown.dev` Keycloak launch, template alignment, fedarch compliance, code review  
**Authority**: This prompt supersedes all prior instructions for the execution agent.  
**CRITICAL SAFETY RULE**: This is a PUBLIC GitHub repository. Never commit secrets. Never run `tofu apply` without explicit human approval. Read-only plans only.

---

## 1. CURRENT STATE — Where We Are

### 1.1 Templates (UPDATED — Source of Truth)

The `keycloak-docker` template has been fully refactored to use **Infisical runtime injection** as the ONLY secrets mode:

| Template File | Status | Key Change |
|-------------|--------|-----------|
| `copier.yaml` | ✅ Updated | Removed `enable_infisical` toggle; added `enable_skinny_backups`, backup config, `disk_alert_threshold` |
| `template/terraform/variables.tf.jinja` | ✅ Updated | No app secrets; only `infisical_client_id`, `infisical_client_secret`, Machine Identity vars |
| `template/terraform/main.tf.jinja` | ✅ Updated | Passes Infisical vars + backup vars to cloud-init; `backups = var.enable_skinny_backups ? false : true` |
| `template/terraform/templates/cloud-init.yaml.jinja` | ✅ Updated | No `.env` file; compose written via `write_files`; Infisical auth + cron wrapper; backup script with GFS retention |
| `template/docker/compose.prod.yaml.jinja` | ✅ Updated | Uses `${VAR}` for runtime injection; no hardcoded secrets |
| `template/scripts/deploy.sh.jinja` | ✅ Updated | Uses `infisical run --projectId=xxx --env=prod -- docker compose up -d` |
| `template/scripts/backup.sh.jinja` | ✅ Updated | Volume-based; GFS retention; DO Spaces upload; runs inside `infisical run` |
| `template/scripts/restore.sh.jinja` | ✅ Updated | DO Spaces fetch; volume restore; Infisical injection |
| `template/terraform/terraform.tfvars.example.jinja` | ✅ Updated | Documents Infisical-only model; clear "what goes here vs Infisical" |

### 1.2 Site Files (LEGACY — Need Updating)

The actual deployment files for `sso.weown.dev` do NOT match the updated templates:

| Site File | Status | Problem |
|-----------|--------|---------|
| `sites/sso.weown.dev/terraform/terraform.tfvars` | ❌ LEGACY | Has `db_password`, `db_root_password`, `keycloak_admin_password`, `spaces_access_key`, `spaces_secret_key` — **CRITICAL: leaked credentials** |
| `sites/sso.weown.dev/terraform/variables.tf` | ❌ LEGACY | Has `db_password`, `db_root_password`, `enable_infisical` toggle, conditional logic |
| `sites/sso.weown.dev/terraform/main.tf` | ❌ LEGACY | Hardcoded `"sso"` name; conditional Infisical logic; missing backup vars |
| `sites/sso.weown.dev/docker/compose.prod.yaml` | ❌ EMPTY | File is empty (was deleted in recent changes) |
| `sites/sso.weown.dev/scripts/deploy.sh` | ⚠️ PARTIAL | Uses `infisical run --env=prod` but hardcodes project values, no `--projectId` flag |

### 1.3 Security Findings

**Action Required**:

1. **DO Spaces credentials** in `sites/sso.weown.dev/terraform/terraform.tfvars`:
   - This file is **gitignored and was never committed to git** — no leak occurred
   - `git log --all -- terraform.tfvars` returns no results; `git log --all -S 'spaces_access_key'` returns no results
   - **Action**: Migrate these credentials to Infisical as part of the standard migration plan

2. **Legacy secret variables** still in site `variables.tf`:
   - `db_password`, `db_root_password`, `keycloak_admin_password`
   - **Action**: Remove from `variables.tf`; migrate values to Infisical

3. **Empty compose.prod.yaml**:
   - The production Docker Compose file is empty
   - **Action**: Regenerate from template or restore from droplet

### 1.4 AnythingLLM Docker Template (NEW — Phase 1 Complete)

A complete `anythingllm-docker` template was created with the same Infisical runtime injection pattern:

- LanceDB embedded (no separate vector DB)
- OpenRouter integration
- Caddy reverse proxy with security headers
- Skinny backups with GFS retention
- All files created and documented

---

## 2. EXACT PLAN — What Needs to Happen

### Phase 0: Infisical Migration Prep

| Step | Action | Verification |
|------|--------|------------|
| 0.1 | Verify DO Spaces credentials not in git history (already confirmed) | `git log --all -S 'spaces_access_key' --oneline` returns no results |
| 0.2 | Create Infisical project for `sso.weown.dev` | Project exists with correct environment and paths |
| 0.3 | Add all `terraform.tfvars` secrets to Infisical | Secrets in Infisical; tfvars replaced with placeholders |

### Phase 1: Align Site Files to Templates

| Step | Action | Files to Modify |
|------|--------|----------------|
| 1.1 | Update `sites/sso.weown.dev/terraform/variables.tf` to match template | Remove `db_password`, `db_root_password`, `keycloak_admin_password`, `enable_infisical`; add `infisical_client_id`, `infisical_client_secret`, backup vars |
| 1.2 | Update `sites/sso.weown.dev/terraform/main.tf` to match template | Remove conditional Infisical logic; pass all Infisical + backup vars to cloud-init; use `var.project_name` not hardcoded `"sso"` |
| 1.3 | Regenerate `sites/sso.weown.dev/docker/compose.prod.yaml` from template | Use `${VAR}` syntax; no hardcoded secrets; include healthchecks |
| 1.4 | Update `sites/sso.weown.dev/scripts/deploy.sh` to match template | Add `--projectId` and `--env` flags to `infisical run` |
| 1.5 | Create new `sites/sso.weown.dev/terraform/terraform.tfvars` from template example | Only Machine Identity + DO token; NO app secrets; NO Spaces keys |

### Phase 2: Infisical Setup

| Step | Action | Details |
|------|--------|---------|
| 2.1 | Create Infisical project for `sso.weown.dev` | Project name: `weown-keycloak` or `weown-sso` |
| 2.2 | Add required secrets to Infisical project | `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `KEYCLOAK_ADMIN_USERNAME`, `KEYCLOAK_ADMIN_PASSWORD`, `MINIMUS_TOKEN`, `SPACES_ACCESS_KEY`, `SPACES_SECRET_KEY` |
| 2.3 | Create Machine Identity in Infisical | Organization Settings → Machine Identities; add to project with read access |
| 2.4 | Copy Machine Identity Client ID and Secret | Shown ONCE at creation — save to password manager |
| 2.5 | Populate `terraform.tfvars` with real values | `infisical_client_id`, `infisical_client_secret`, `ssh_key_fingerprint`, `minimus_token` |

### Phase 3: Terraform Plan (Read-Only)

| Step | Action | Safety Check |
|------|--------|-------------|
| 3.1 | `cd sites/sso.weown.dev/terraform && tofu init` | Verify provider downloads |
| 3.2 | `tofu plan -out=sso.plan` | **READ-ONLY** — verify NO droplet replacement |
| 3.3 | Review plan output | Expected: tag changes, monitoring alert additions; NOT: droplet replacement |
| 3.4 | If plan shows droplet replacement, STOP | Investigate `lifecycle { ignore_changes = [user_data] }` block |
| 3.5 | Save plan output to file for human review | `tofu show -no-color sso.plan > sso-plan-review.txt` |

### Phase 4: Code Review — feature/roman-update-main-ruleset-docs

| Step | Action | Files to Review |
|------|--------|----------------|
| 4.1 | Checkout branch locally | `git fetch origin feature/roman-update-main-ruleset-docs` |
| 4.2 | Review `.github/ADR-003-main-branch-ruleset.md` | New ADR for branch protection ruleset |
| 4.3 | Review `.github/ADR-004-copilot-auto-review-ruleset.md` | New ADR for Copilot auto-review ruleset |
| 4.4 | Review `.github/CODEOWNERS` changes | Verify coverage for all paths |
| 4.5 | Review `.github/workflows/README.md` | Updated workflow documentation |
| 4.6 | Review `.github/workflows/auto-pr-to-main.yml` | Updated auto-PR workflow |
| 4.7 | Review `CONTRIBUTING.md` changes | Updated contribution guidelines |
| 4.8 | Review `CHANGELOG.md` | Verify `#WeOwnVer` bump and entries |
| 4.9 | Post review comments mapping to §3 checklist | Cite NIST CSF, CIS, ISO controls |

### Phase 5: Fedarch Doc Summary & Alignment Verification

| Step | Action | Reference |
|------|--------|-----------|
| 5.1 | Read `~/projects/fedarch/_PROJECTS_/PRJ-003.md` | Keycloak SSO requirements |
| 5.2 | Read `~/projects/fedarch/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md` | Infisical architecture |
| 5.3 | Read `~/projects/fedarch/_PROJECTS_/PRJ-032_OpenTofu-IaC.md` | OpenTofu + DO Spaces state |
| 5.4 | Verify alignment between our implementation and PRJ-003 | ATL1 primary ✅, NYC3 backup ⚠️ (not in template), TLS 1.3 ✅, PostgreSQL 16 ✅ (PRJ says 15+), RBAC ✅, audit logging ⚠️ (needs CCC-ID) |
| 5.5 | Verify alignment between our Infisical model and PRJ-024 | Our Docker runtime injection is MORE secure than PRJ-024's init container approach; document this |
| 5.6 | Verify alignment with PRJ-032 | OpenTofu ✅, DO Spaces state backend ⚠️ (credentials still in tfvars), Infisical provider ✅ |
| 5.7 | Write alignment summary document | `docs/FEDARCH_ALIGNMENT.md` |

---

## 3. TERMINATION REQUIREMENTS — When Is "Done"

The execution agent MUST NOT terminate until ALL of the following are true:

### 3.1 Phase 0 Complete

- [ ] DO Spaces credentials added to Infisical (no rotation required — never committed to git)
- [ ] `terraform.tfvars` placeholders verified

### 3.2 Phase 1 Complete

- [ ] `sites/sso.weown.dev/terraform/variables.tf` matches template (no app secret vars)
- [ ] `sites/sso.weown.dev/terraform/main.tf` matches template (no conditional Infisical logic)
- [ ] `sites/sso.weown.dev/docker/compose.prod.yaml` regenerated with `${VAR}` syntax
- [ ] `sites/sso.weown.dev/scripts/deploy.sh` updated with `--projectId` flag
- [ ] `sites/sso.weown.dev/terraform/terraform.tfvars` recreated with ONLY Machine Identity + DO token

### 3.3 Phase 2 Complete

- [ ] Infisical project created for `sso.weown.dev`
- [ ] All required secrets added to Infisical project
- [ ] Machine Identity created and added to project
- [ ] `terraform.tfvars` populated with real Machine Identity credentials

### 3.4 Phase 3 Complete

- [ ] `tofu init` succeeds
- [ ] `tofu plan` runs without errors (read-only)
- [ ] Plan output saved to `sso-plan-review.txt`
- [ ] Plan reviewed by human — NO droplet replacement expected

### 3.5 Phase 4 Complete

- [ ] All 12 changed files in `feature/roman-update-main-ruleset-docs` reviewed
- [ ] Review comments posted with §3 checklist mappings
- [ ] CRITICAL/HIGH/MEDIUM/LOW severity assigned to each finding
- [ ] ADR-003 and ADR-004 specifically reviewed for completeness

### 3.6 Phase 5 Complete

- [ ] `docs/FEDARCH_ALIGNMENT.md` created with:
  - Summary of PRJ-003, PRJ-024, PRJ-032 requirements
  - Alignment status for each requirement (✅ aligned / ⚠️ gap / ❌ not met)
  - Gaps documented with remediation plan
  - Infisical strategy comparison (our runtime injection vs PRJ-024's init container)

### 3.7 Documentation Complete

- [ ] `docs/EXECUTION_STATUS.md` created with:
  - What was accomplished
  - What remains pending
  - Next steps with owners
  - Blockers and risks

---

## 4. SCRIPTS & TOOLS — Helper Utilities

### 4.1 Credential Rotation Script

Create `scripts/rotate-do-spaces-keys.sh`:

```bash
#!/usr/bin/env bash
# Rotate DO Spaces credentials and update Infisical
# Usage: ./rotate-do-spaces-keys.sh <old-access-key>
set -euo pipefail

OLD_KEY="${1:-}"
if [[ -z "$OLD_KEY" ]]; then
  echo "Usage: $0 <old-access-key-id>"
  echo "Example: $0 <YOUR_ACCESS_KEY_ID>"
  exit 1
fi

echo "==> Rotating DO Spaces credentials..."
echo "    Old key: ${OLD_KEY:0:8}..."
echo ""
echo "Manual steps required:"
echo "  1. Go to https://cloud.digitalocean.com/account/api/spaces"
echo "  2. Delete old key: $OLD_KEY"
echo "  3. Generate new key pair"
echo "  4. Add new secrets to Infisical:"
echo "       SPACES_ACCESS_KEY = <new-access-key>"
echo "       SPACES_SECRET_KEY = <new-secret-key>"
echo "  5. Update backup scripts if they reference old keys"
echo ""
echo "  6. Document rotation in .github/INCIDENT_RESPONSE.md"
```

### 4.2 Template Diff Checker

Create `scripts/check-template-alignment.sh`:

```bash
#!/usr/bin/env bash
# Compare site files against templates
set -euo pipefail

TEMPLATE_DIR="keycloak-docker/template"
SITE_DIR="keycloak-docker/sites/sso.weown.dev"

echo "==> Checking template alignment for sso.weown.dev"
echo ""

# Check variables.tf
echo "--- variables.tf ---"
diff -u "$TEMPLATE_DIR/terraform/variables.tf.jinja" "$SITE_DIR/terraform/variables.tf" || true

# Check main.tf
echo "--- main.tf ---"
diff -u "$TEMPLATE_DIR/terraform/main.tf.jinja" "$SITE_DIR/terraform/main.tf" || true

# Check deploy.sh
echo "--- deploy.sh ---"
diff -u "$TEMPLATE_DIR/scripts/deploy.sh.jinja" "$SITE_DIR/scripts/deploy.sh" || true

echo ""
echo "==> Review diffs above. Site files should match template patterns."
```

### 4.3 Infisical Secret Validator

Create `scripts/verify-infisical-secrets.sh`:

```bash
#!/usr/bin/env bash
# Verify all required Infisical secrets are present
set -euo pipefail

PROJECT_ID="${1:-}"
ENV="${2:-prod}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <infisical-project-id> [environment]"
  exit 1
fi

REQUIRED_SECRETS=(
  "DB_NAME"
  "DB_USER"
  "DB_PASSWORD"
  "DB_ROOT_PASSWORD"
  "KEYCLOAK_ADMIN_USERNAME"
  "KEYCLOAK_ADMIN_PASSWORD"
  "MINIMUS_TOKEN"
  "SPACES_ACCESS_KEY"
  "SPACES_SECRET_KEY"
)

echo "==> Verifying Infisical secrets for project: $PROJECT_ID (env: $ENV)"

for secret in "${REQUIRED_SECRETS[@]}"; do
  if infisical secrets get "$secret" --projectId="$PROJECT_ID" --env="$ENV" &>/dev/null; then
    echo "  ✅ $secret"
  else
    echo "  ❌ $secret — MISSING"
  fi
done
```

### 4.4 Plan Safety Checker

Create `scripts/verify-plan-safety.sh`:

```bash
#!/usr/bin/env bash
# Verify tofu plan does not contain destructive changes
set -euo pipefail

PLAN_FILE="${1:-}"

if [[ -z "$PLAN_FILE" ]]; then
  echo "Usage: $0 <plan-file>"
  exit 1
fi

echo "==> Checking plan safety: $PLAN_FILE"

# Check for droplet replacement (destructive)
if tofu show -json "$PLAN_FILE" | jq -e '.resource_changes[] | select(.type == "digitalocean_droplet") | select(.change.actions | contains(["delete"]))' &>/dev/null; then
  echo "  ❌ CRITICAL: Plan contains droplet replacement (delete+create)"
  echo "     STOP — Do not apply. Investigate lifecycle blocks."
  exit 1
fi

# Check for reserved IP replacement (destructive)
if tofu show -json "$PLAN_FILE" | jq -e '.resource_changes[] | select(.type == "digitalocean_reserved_ip") | select(.change.actions | contains(["delete"]))' &>/dev/null; then
  echo "  ❌ CRITICAL: Plan contains reserved IP replacement"
  exit 1
fi

echo "  ✅ No destructive changes detected"
echo "  Plan is safe for human review."
```

---

## 5. FEDARCH REFERENCES — Documentation to Use

### 5.1 Local Files (on this machine)

| Document | Path | Purpose |
|----------|------|---------|
| PRJ-003 | `~/projects/fedarch/_PROJECTS_/PRJ-003.md` | Keycloak SSO requirements — ATL1 primary, NYC3 backup, TLS 1.3, OIDC/SAML, PostgreSQL 15+, RBAC, audit logging with CCC-ID |
| PRJ-024 | `~/projects/fedarch/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md` | Infisical architecture — K8s operator, Docker SDK/init container, rotation automation |
| PRJ-032 | `~/projects/fedarch/_PROJECTS_/PRJ-032_OpenTofu-IaC.md` | OpenTofu + DO Spaces state backend + Infisical provider |
| GUIDE-014 | `~/projects/fedarch/_GUIDES_/GUIDE-014.md` | SEEK:META + #TriMETA #ContextVolley strategy |

### 5.2 GitHub URLs (for reference)

| Document | URL |
|----------|-----|
| PRJ-003 | <https://github.com/CCCbotNet/fedarch/blob/main/_PROJECTS_/PRJ-003.md> |
| PRJ-024 | <https://github.com/CCCbotNet/fedarch/blob/main/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md> |
| PRJ-032 | <https://github.com/CCCbotNet/fedarch/blob/main/_PROJECTS_/PRJ-032_OpenTofu-IaC.md> |

### 5.3 Alignment Notes

**Our Infisical Runtime Injection vs PRJ-024**:

| Aspect | PRJ-024 (Documented) | Our Implementation (Better) |
|--------|---------------------|----------------------------|
| Docker method | Init container + `.env` file | `infisical run` — no file on disk |
| Secret exposure | `.env` file readable on disk | Only in process memory |
| Rotation | Requires container restart | Requires container restart |
| Compliance | Good | Better — no secrets at rest on node |

**Document this in `docs/FEDARCH_ALIGNMENT.md`**: Our implementation exceeds PRJ-024's security model by eliminating the `.env` file entirely.

---

## 6. COMPLIANCE CHECKLIST — Map Every Action

Every change must map to ≥1 framework control. Use these mappings:

| Change Type | Framework Mapping |
|-------------|------------------|
| Secret rotation | NIST PR.DS, CIS 3.11, ISO A.8.24, SOC 2 CC6.2 |
| Infisical runtime injection | NIST PR.DS, CIS 3.11, ISO A.5.17, SOC 2 CC6.8 |
| No secrets in tfvars | NIST PR.DS-2, CIS 3.11, SOC 2 CC6.8 |
| GFS backup retention | NIST RC.RP, CIS 11.1, ISO A.8.13 |
| TLS 1.3 / Caddy | NIST PR.DS-1, CIS 3.10, ISO A.8.24 |
| RBAC / least privilege | NIST PR.AC, CIS 5/6, ISO A.5.15-A.5.18 |
| CODEOWNERS update | NIST GV.OC, CIS 5.1, ISO A.5.15 |
| ADR documentation | NIST GV.RM, ISO A.8.32, SOC 2 CC8.1 |
| Branch protection ruleset | NIST GV.OV, CIS 16.1, SOC 2 CC1.1 |

---

## 7. KNOWN BLOCKERS & RISKS

| Blocker | Impact | Mitigation |
|---------|--------|------------|
| Empty `compose.prod.yaml` | Cannot deploy without compose file | Regenerate from template or copy from droplet |
| DO Spaces keys in local-only terraform.tfvars | Gitignored, never committed — no breach | Migrate to Infisical as part of standard migration |
| No Infisical project for sso.weown.dev | Cannot use runtime injection | Create project before any deployment |
| feature/roman-update-main-ruleset-docs not reviewed | May merge non-compliant docs | Complete code review before this branch merges |
| PRJ-003 requires NYC3 backup | Template only has ATL1 | Document as Phase 2 gap; add NYC3 droplet later |
| PRJ-003 requires audit logging with CCC-ID | Not in template | Document as Phase 2 gap; add Keycloak event listener |

---

## 8. EXECUTION ORDER — Do Not Deviate

```text
Phase 0: Security Lockdown
    ↓
Phase 1: Align Site Files to Templates
    ↓
Phase 2: Infisical Setup
    ↓
Phase 3: Terraform Plan (Read-Only)
    ↓
Phase 4: Code Review (Parallel with Phase 3)
    ↓
Phase 5: Fedarch Alignment (Parallel with Phase 3-4)
    ↓
Phase 6: Documentation + Status Report
    ↓
STOP — Wait for human approval before ANY apply
```

---

## 9. COMMUNICATION PROTOCOL

### 9.1 When to Ask for Human Input

- **Before rotating credentials**: Confirm which services use the old keys
- **Before creating Infisical project**: Confirm project naming convention
- **Before running `tofu plan`**: Confirm tfvars values are correct
- **If plan shows droplet replacement**: STOP — ask for investigation
- **Before posting code review**: Confirm review is complete and thorough

### 9.2 Status Updates

After completing each phase, report:

- Phase name
- Completion status (✅ / ❌ / ⚠️ partial)
- Files modified
- Blockers encountered
- Next phase ready (yes/no)

---

## 10. APPENDIX: File Paths on This Machine

```text
# Workspace root
/Users/nik/projects/ai/

# Templates (source of truth)
/Users/nik/projects/ai/keycloak-docker/template/
/Users/nik/projects/ai/anythingllm-docker/template/

# Site files (need updating)
/Users/nik/projects/ai/keycloak-docker/sites/sso.weown.dev/

# Docs
/Users/nik/projects/ai/docs/
/Users/nik/projects/ai/.github/

# Fedarch (reference)
/Users/nik/projects/fedarch/

# Scripts
/Users/nik/projects/ai/scripts/
```

---

*This prompt was generated for execution by an AI agent. All actions must comply with `.github/copilot-instructions.md` §3.0 (Public Repository Precautions). Never commit secrets. Never apply Terraform without human approval.*
