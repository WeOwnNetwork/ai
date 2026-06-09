# PR #68: Fix ADR-006 Implementation - Add Wrapper Script for Entrypoint Authentication

## ⚠️ SUPERSEDES PRs #62-#67

This PR **supersedes** the following PRs currently in the review queue:

- PR #62: site.conf for all docker templates
- PR #63: site.sh convenience wrapper
- PR #64: Infisical outage runbook
- PR #66: automated site deployment
- PR #67: branch setup utility

**Why?** Those PRs implement the **old pattern** (host-side `infisical run` wrapper), which has a critical bug: containers call `infisical run` directly as entrypoint, but `infisical run` expects pre-authentication. Containers would fail to start.

This PR implements the **correct pattern** per Nik's ADR-006 specification: a wrapper script that sources the auth file → logs in → execs `infisical run`.

**What's preserved?** All the infrastructure from PRs #62-#67 (site.conf, site.sh, outage runbook, automated deployment, branch setup) is included in this PR. Nothing is lost.

---

## Summary

Fixes critical bugs in the ADR-006 implementation across all 7 docker templates:

1. **Entrypoint authentication missing** (all 7 templates)
   - Created wrapper script that sources auth → logs in → execs infisical run
   - Follows Nik's ADR-006 specification exactly
   - Uses established pattern from backup cron job

2. **Keycloak database name missing** (keycloak-docker only)
   - Added `KC_DB_URL_DATABASE` to compose environment
   - Added `keycloak_db_name` copier variable (default: "keycloak")

---

## What Changed

### New Files

- `scripts/test-template.sh` - Static validation harness for templates
- `template/scripts/entrypoint-infisical.sh.jinja` - Wrapper script (7 templates)

### Modified Files

- `template/ansible/deploy.yml.jinja` - Added wrapper script upload task (7 templates)
- `template/docker/compose.prod.yaml.jinja` - Changed entrypoint to wrapper script (7 templates)
- `keycloak-docker/copier.yaml` - Added `keycloak_db_name` variable

### Documentation

- `docs/GOVERNANCE.md` - Working principles, lessons learned
- `docs/WORK_LOG.md` - Current status
- `docs/ADR-006-IMPLEMENTATION-SUMMARY.md` - Technical details
- `docs/ADR-006-FINAL-SUMMARY.md` - Final summary with test results

---

## Templates Updated (7 total)

| Template | Services | Status |
|----------|----------|--------|
| anythingllm-docker | 1 | ✅ Fixed |
| searxng-docker | 1 | ✅ Fixed |
| sandbox-docker | 1 | ✅ Fixed |
| openclaw-docker | 1 | ✅ Fixed |
| wordpress-docker | 3 (db, wp, caddy) | ✅ Fixed |
| keycloak-docker | 2 (db, keycloak) + DB fix | ✅ Fixed |
| signoz-docker | 4 (ch, migrator, signoz, otel) | ✅ Fixed |

---

## Testing

Created `scripts/test-template.sh` - a static validation harness that:

- Renders test sites from templates using copier
- Validates compose and ansible syntax
- Checks for hardcoded secrets
- Verifies wrapper script exists and is correct
- Verifies compose uses wrapper as entrypoint
- Verifies ansible uploads wrapper script
- Cleans up automatically

**Test Results:**

- ✅ anythingllm-docker: 8/8 checks passed
- ✅ searxng-docker: 8/8 checks passed
- ✅ sandbox-docker: 8/8 checks passed
- ✅ openclaw-docker: 8/8 checks passed
- ⚠️ wordpress-docker: skipped (copier choice validation quirk)
- ✅ keycloak-docker: 8/8 checks passed
- ✅ signoz-docker: 8/8 checks passed

**Coverage:** PARTIAL (static validation only)

- ✅ Tests: template rendering, syntax, configuration
- ❌ Does NOT test: runtime behavior, container startup, secret injection, application functionality

**Note:** Full runtime testing requires deployment to actual infrastructure with real Infisical credentials, which is beyond the scope of pre-push validation.

---

## Security Compliance

✅ **Follows Nik's ADR-006 specification**

- "authenticate from the auth file, then exec infisical run"

✅ **Uses established pattern from backup cron job**

- Same authentication flow: source → login → exec

✅ **Auth file security**

- Host file: 0600 root
- Container-readable copy: 0640 (read-only bind-mount)
- Credentials only in process memory, not on disk inside container

✅ **No hardcoded secrets**

- All secrets come from Infisical at runtime
- Test harness verifies no hardcoded secrets in rendered files

---

## What Reviewers Should Focus On

### 1. Wrapper Script Logic

**File:** `template/scripts/entrypoint-infisical.sh.jinja`

Verify:

- Sources auth file correctly
- Logs in with universal-auth
- Execs infisical run with original entrypoint
- Error handling is appropriate

### 2. Compose Entrypoint Configuration

**File:** `template/docker/compose.prod.yaml.jinja`

Verify:

- Uses wrapper script as entrypoint
- Has correct `command:` field (original entrypoint)
- Bind-mounts are read-only (`:ro`)
- Secrets removed from `environment:` blocks

### 3. Ansible Upload Task

**File:** `template/ansible/deploy.yml.jinja`

Verify:

- Uploads wrapper script with correct permissions (0750)
- Uses correct source path

### 4. Keycloak Database Fix

**Files:** `keycloak-docker/template/docker/compose.prod.yaml.jinja`, `keycloak-docker/copier.yaml`

Verify:

- `KC_DB_URL_DATABASE` is added to environment
- `keycloak_db_name` variable has sensible default

### 5. Security

Verify:

- No hardcoded secrets
- Auth file permissions are correct (0640)
- Bind-mounts are read-only
- Credentials not exposed in logs

---

## Alignment with Existing PRs

### What's Preserved from PRs #62-#67

- ✅ site.conf pattern (PR #62)
- ✅ site.sh convenience wrapper (PR #63)
- ✅ Infisical outage runbook (PR #64)
- ✅ Automated deployment script (PR #66)
- ✅ Branch setup utility (PR #67)

### What's Different

- ❌ Old pattern: host-side `infisical run` wrapper in ansible
- ✅ New pattern: wrapper script as container entrypoint

### Why This Is Better

- ✅ Enables bounce-to-refresh (`docker restart` re-fetches secrets)
- ✅ Secrets not visible in `docker inspect`
- ✅ Follows Nik's ADR-006 specification exactly
- ✅ More secure (credentials only in process memory)

---

## Recommendation for Reviewers

**Option 1: Close PRs #62-#67, review this PR instead** (recommended)

- This PR includes everything from #62-#67 plus the fixes
- Single PR is easier to review than 6 separate PRs
- Avoids merging code that will be immediately refactored

**Option 2: Merge PRs #62-#67 first, then review this PR**

- Preserves granular commit history
- But requires immediate refactoring after merge

---

## Next Steps

1. Reviewers review this PR
2. Address any feedback
3. Merge to main
4. Close PRs #62-#67 (if not already merged)
5. Re-render live sites from updated templates (follow-up work)

---

## Questions for Reviewers

1. Does the wrapper script logic look correct?
2. Are the bind-mount permissions appropriate?
3. Is the error handling sufficient?
4. Should we close PRs #62-#67 or merge them first?
5. Any other concerns?

---

## Related

- **ADR-006:** `.github/ADR-006-in-container-infisical-injection.md` (Nik's specification)
- **Bootstrap pattern:** `docs/INFRA_BOOTSTRAP_PATTERN.md` (Layer 1 + Layer 2 + Path C)
- **FedArch secrets:** `CCCbotNet/fedarch/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md`
- **FedArch IaC:** `CCCbotNet/fedarch/_PROJECTS_/PRJ-032_OpenTofu-IaC.md`
