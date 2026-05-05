# Migration Plan: Legacy Sites → AI Repo Template Infrastructure

**Date**: 2026-04-26
**Scope**: ptoken.agency, burnedout.xyz, sso.weown.dev, anythingllm Infisical migration
**Status**: Planning — DO NOT APPLY TO PRODUCTION WITHOUT REVIEW

---

## Executive Summary

This document outlines the strategy to migrate existing production DigitalOcean droplets from their legacy standalone repos (`~/projects/ptoken.agency`, `~/projects/burnedout.xyz`) into the standardized copier-template infrastructure in `~/projects/ai/wordpress-docker/`, and to bring `sso.weown.dev` and `anythingllm` into compliance with the project's Infisical-first secrets management standard.

**Critical Rule**: Templates are the target state. We do NOT alter templates to match legacy state. Legacy droplets will be migrated to match templates over time.

---

## 1. Current State Inventory

### 1.1 Legacy Deployments (Source of Truth for Runtime)

| Site | Legacy Path | Droplet ID | Reserved IP | Droplet IP | Region | Size | Backups |
|------|-------------|------------|-------------|------------|--------|------|---------|
| **ptoken.agency** | `~/projects/ptoken.agency/` | `564726817` | `129.212.241.90` | `129.212.186.190` | atl1 | s-2vcpu-2gb-amd | **false** |
| **burnedout.xyz** | `~/projects/burnedout.xyz/` | `564224856` | `129.212.240.206` | `134.199.203.100` | atl1 | s-2vcpu-2gb-amd | **false** |

### 1.2 Template-Generated Deployments (Target State)

| Site | Template Path | Status | Has tfvars? |
|------|--------------|--------|-------------|
| **ptoken.agency** | `ai/wordpress-docker/sites/ptoken-agency/` | Generated, never deployed | ❌ No |
| **burnedout.xyz** | `ai/wordpress-docker/sites/burnedout-xyz/` | Generated, never deployed | ❌ No |
| **sso.weown.dev** | `ai/keycloak-docker/sites/sso.weown.dev/` | Generated, partially configured | ⚠️ Has placeholder tfvars |

### 1.3 AnythingLLM (Infisical Target)

| Component | Path | Infisical Status |
|-----------|------|------------------|
| **anythingllm** | `ai/anythingllm/helm/` | Templates exist, `enabled: false` |

---

## 2. Critical Security Findings

> ⚠️ **§3.0 Public Repository Precautions**: These are CRITICAL violations that must be addressed immediately.

### 2.1 Secrets in Legacy Repos (Git History Risk)

Both `~/projects/ptoken.agency/terraform/terraform.tfvars` and `~/projects/burnedout.xyz/terraform/terraform.tfvars` contain:

| Secret | ptoken.agency | burnedout.xyz | Risk |
|--------|---------------|---------------|------|
| `do_token` | `dop_v1_001a...` | `dop_v1_001a...` | **CRITICAL** — DigitalOcean API token |
| `minimus_token` | `mini_kjet...` | `mini_kjet...` | **CRITICAL** — Registry token |
| `mysql_password` | `1D1owgKw...` | `AX6AK5jY...` | **HIGH** — Database password |
| `mysql_root_password` | `rtXh8Mq4...` | `1o7d+2MR...` | **HIGH** — Database root password |

**Required Actions**:

1. **Rotate ALL secrets immediately** — these are in git history and potentially exposed
2. **Purge git history** using `git filter-repo` or `bfg-repo-cleaner`
3. **Document rotation** in `.github/INCIDENT_RESPONSE.md`

### 2.2 Secrets in sso.weown.dev tfvars

`ai/keycloak-docker/sites/sso.weown.dev/terraform/terraform.tfvars` contains credentials — this file is **gitignored and was never committed** (verified: `git log --all -- terraform.tfvars` and `git log --all -S 'spaces_access_key'` both return no results). **No leak occurred.**

**Required Actions**:

1. **Migrate to Infisical** — move all credentials from `terraform.tfvars` to Infisical
2. **No credential rotation required** unless chosen as part of Infisical onboarding
3. **No git history purge needed** — credentials were never committed

---

## 3. State-to-Template Gap Analysis

### 3.1 ptoken.agency

| Aspect | Legacy State | Template Target | Gap |
|--------|-------------|-----------------|-----|
| **Droplet name** | `ptoken-agency` | `ptoken-agency` | ✅ Match |
| **Image** | `ubuntu-24-04-x64` | `ubuntu-24-04-x64` | ✅ Match |
| **Size** | `s-2vcpu-2gb-amd` | `s-2vcpu-2gb-amd` | ✅ Match |
| **Region** | `atl1` | `atl1` | ✅ Match |
| **Monitoring** | `true` | `true` | ✅ Match |
| **Backups** | `false` | `false` | ✅ Match |
| **SSH key** | `6e:81:86:...` | `var.ssh_key_fingerprint` | ⚠️ Must provide |
| **Tags** | `WordPress`, `ptoken-agency` | `ptoken-agency`, `wordpress`, `weown-ai` | ⚠️ Template adds `weown-ai` |
| **Monitoring alerts** | CPU, Memory, Disk, Load | CPU, Memory | ⚠️ Template missing Disk + Load alerts |
| **domain_style** | N/A (legacy) | `www` or `apex` | ⚠️ New variable — must choose |
| **enable_wordfence_waf** | N/A (legacy) | `true`/`false` | ⚠️ New variable — must choose |
| **Infisical** | N/A (legacy) | Optional | ⚠️ Future migration |

### 3.2 burnedout.xyz

| Aspect | Legacy State | Template Target | Gap |
|--------|-------------|-----------------|-----|
| **Droplet name** | `burnedout-xyz` | `burnedout-xyz` | ✅ Match |
| **Image** | `ubuntu-24-04-x64` | `ubuntu-24-04-x64` | ✅ Match |
| **Size** | `s-2vcpu-2gb-amd` | `s-2vcpu-2gb-amd` | ✅ Match |
| **Region** | `atl1` | `atl1` | ✅ Match |
| **Monitoring** | `true` | `true` | ✅ Match |
| **Backups** | `false` | `false` | ✅ Match |
| **SSH key** | `6e:81:86:...` | `var.ssh_key_fingerprint` | ⚠️ Must provide |
| **Tags** | `WordPress`, `burnedout-xyz` | `burnedout-xyz`, `wordpress`, `weown-ai` | ⚠️ Template adds `weown-ai` |
| **Monitoring alerts** | CPU, Memory | CPU, Memory | ✅ Match |
| **domain_style** | N/A (legacy) | `www` or `apex` | ⚠️ New variable — must choose |
| **enable_wordfence_waf** | N/A (legacy) | `true`/`false` | ⚠️ New variable — must choose |
| **Infisical** | N/A (legacy) | Optional | ⚠️ Future migration |

### 3.3 sso.weown.dev

| Aspect | Current tfvars | Template Target | Gap |
|--------|---------------|-----------------|-----|
| **Droplet name** | `sso` | `sso` | ✅ Match |
| **Image** | `ubuntu-24-04-x64` | `ubuntu-24-04-x64` | ✅ Match |
| **Size** | `s-2vcpu-4gb-amd` | `s-2vcpu-4gb-amd` | ✅ Match |
| **Region** | `atl1` | `atl1` | ✅ Match |
| **Monitoring** | `true` | `true` | ✅ Match |
| **Backups** | `false` | `false` | ✅ Match |
| **SSH key** | `YOUR_SSH_KEY_FINGERPRINT` | `var.ssh_key_fingerprint` | ❌ Not configured |
| **Infisical** | `enable_infisical = false` | `enable_infisical = true` (recommended) | ❌ Disabled |
| **DB passwords** | `CHANGE_ME` | From Infisical | ❌ Not set |
| **Keycloak admin** | `CHANGE_ME_ADMIN` | From Infisical | ❌ Not set |
| **Spaces encryption** | `YOUR_SPACES_ENCRYPTION_KEY` | From Infisical | ❌ Not set |

---

## 4. Migration Strategy

### 4.1 Phase 0: Immediate Security (DO NOT SKIP)

**Before any migration work**:

1. **Migrate all secrets to Infisical**:
   - DigitalOcean API token (`do_token`)
   - Minimus registry token (`minimus_token`)
   - MySQL passwords (both sites)
   - DO Spaces access/secret keys (sso)
   - Note: all credentials are local-only (gitignored `terraform.tfvars`), never committed — no rotation required unless desired

2. **Verify legacy repos** have no committed secrets (check separately per repo):

3. **Document in INCIDENT_RESPONSE.md**:
   - Rotation dates
   - Old secret fingerprints (last 4 chars only)
   - Purge confirmation

### 4.2 Phase 1: Terraform State Migration (Read-Only Plan)

Goal: Import existing droplets into the new template-generated Terraform without applying changes.

#### Step 1.1: Create tfvars for Template Sites

For each site, create `terraform.tfvars` from the template example, using values from legacy state:

**ptoken-agency example**:

```hcl
# terraform.tfvars — NEVER COMMIT WITH REAL VALUES
do_token            = "${{ secrets.DO_TOKEN }}"  # Use Infisical or CI secret
ssh_key_fingerprint = "<YOUR_SSH_KEY_FINGERPRINT>"
minimus_token       = "${{ secrets.MINIMUS_TOKEN }}"
domain              = "ptoken.agency"
domain_style        = "www"  # or "apex" — CHOOSE based on current DNS
region              = "atl1"
droplet_size        = "s-2vcpu-2gb-amd"
mysql_password      = "${{ secrets.MYSQL_PASSWORD }}"  # NEW rotated value
mysql_root_password = "${{ secrets.MYSQL_ROOT_PASSWORD }}"  # NEW rotated value
wp_image            = "reg.mini.dev/1923/wordpress-fluentsmtp:latest"
alert_email         = "alerts@weown.net"
enable_wordfence_waf = true
```

#### Step 1.2: Import State (Read-Only Verification)

```bash
# For ptoken-agency
cd ~/projects/ai/wordpress-docker/sites/ptoken-agency/terraform

# Initialize
tofu init

# Import existing resources (using IDs from legacy state)
tofu import digitalocean_droplet.web 564726817
tofu import digitalocean_reserved_ip.web 129.212.241.90
tofu import digitalocean_reserved_ip_assignment.web 564726817-129.212.241.90-20260413181550485900000001
tofu import digitalocean_firewall.web 0d62b2b9-eb0f-4ca9-bc8c-7b1921233c3b

# Plan only — DO NOT APPLY
tofu plan -out=migration.plan
```

**Expected plan output**:

- `digitalocean_monitor_alert.disk`: **Create** (template missing this — expected)
- `digitalocean_monitor_alert.load_5`: **Create** (template missing this — expected)
- Tags: **Update** (add `weown-ai` — expected)
- Everything else: **No changes** (if tfvars match)

#### Step 1.3: Repeat for burnedout.xyz

```bash
cd ~/projects/ai/wordpress-docker/sites/burnedout-xyz/terraform
tofu init
tofu import digitalocean_droplet.web 564224856
tofu import digitalocean_reserved_ip.web 129.212.240.206
tofu import digitalocean_reserved_ip_assignment.web 564224856-129.212.240.206-...
tofu import digitalocean_firewall.web 9b86d9e0-3e49-4171-b223-ea7cccdcb82b
tofu plan -out=migration.plan
```

### 4.3 Phase 2: AnythingLLM Infisical Integration

This is the priority Infisical migration.

#### Step 2.1: Create Infisical Project

1. Log in to <https://app.infisical.com>
2. Create project: `weown-anythingllm`
3. Create environment: `prod`

#### Step 2.2: Add Secrets to Infisical

| Secret Key | Description | Current Location |
|------------|-------------|------------------|
| `OPENROUTER_API_KEY` | OpenRouter API key | Currently in K8s secret or env |
| `JWT_SECRET` | AnythingLLM JWT secret | Currently in K8s secret or env |
| `ADMIN_EMAIL` | Admin email | Currently in K8s secret or env |

#### Step 2.3: Create Universal Auth in Infisical

1. Go to Project Settings → Machine Identities
2. Create Universal Auth identity
3. Generate Client ID and Client Secret
4. Store in Kubernetes:

   ```bash
   kubectl create secret generic infisical-universal-auth \
     --namespace anything-llm \
     --from-literal=clientId=YOUR_CLIENT_ID \
     --from-literal=clientSecret=YOUR_CLIENT_SECRET
   ```

#### Step 2.4: Enable Infisical in Helm Values

Edit `ai/anythingllm/helm/values.yaml`:

```yaml
infisical:
  enabled: true
  projectSlug: "weown-anythingllm"
  envSlug: "prod"
  secretsPath: "/"
  auth:
    secretName: "infisical-universal-auth"
```

#### Step 2.5: Deploy

```bash
cd ~/projects/ai/anythingllm/helm
helm upgrade --install anythingllm . \
  --namespace anything-llm \
  --set infisical.enabled=true \
  --set infisical.projectSlug=weown-anythingllm
```

### 4.4 Phase 3: sso.weown.dev Infisical Migration

#### Step 3.1: Create Infisical Project

1. Create project: `weown-sso` or `weown-keycloak`
2. Create environment: `prod`

#### Step 3.2: Add Secrets

| Secret Key | Description |
|------------|-------------|
| `DB_PASSWORD` | PostgreSQL password |
| `DB_ROOT_PASSWORD` | PostgreSQL root password |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password |
| `SPACES_ACCESS_KEY` | DO Spaces access key |
| `SPACES_SECRET_KEY` | DO Spaces secret key |
| `SPACES_ENCRYPTION_KEY` | SSE-C encryption key |
| `MINIMUS_TOKEN` | DigitalOcean / registry token |
| `SSH_KEY_FINGERPRINT` | SSH key fingerprint |

#### Step 3.3: Update tfvars to Use Infisical

The template already supports Infisical. Update:

```hcl
enable_infisical      = true
infisical_token       = "${{ secrets.INFISICAL_TOKEN }}"
infisical_project_id  = "weown-sso"
infisical_environment = "prod"
```

For Docker Compose, use Infisical agent sidecar or `infisical run` wrapper.

### 4.5 Phase 4: WordPress Sites Infisical Migration (Future)

**Not recommended until anythingllm and sso are stable.**

When ready:

1. Create Infisical projects: `weown-ptoken`, `weown-burnedout`
2. Add secrets: `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `MINIMUS_TOKEN`
3. Update Docker Compose to use Infisical agent
4. Update Terraform to pass `enable_infisical = true`

---

## 5. Backup Requirements

### 5.1 What Needs Backup

| Site | Data to Backup | Method | Frequency |
|------|---------------|--------|-----------|
| **ptoken.agency** | WordPress uploads, MariaDB database | Volume snapshots + `mysqldump` | Daily |
| **burnedout.xyz** | WordPress uploads, MariaDB database | Volume snapshots + `mysqldump` | Daily |
| **sso.weown.dev** | Keycloak data, PostgreSQL database | Volume snapshots + `pg_dump` | Daily |
| **anythingllm** | Vector DB (LanceDB), uploads, config | PVC snapshots + `anythingllm/backup` | Daily |

### 5.2 Current Backup Status

| Site | Legacy Backups | Template Backups | Gap |
|------|---------------|------------------|-----|
| ptoken.agency | `backups/` directory exists | Template has `scripts/backup.sh` | Need to verify cron |
| burnedout.xyz | `backups/` directory exists | Template has `scripts/backup.sh` | Need to verify cron |
| sso.weown.dev | Unknown | Template has `scripts/backup.sh` | Need to implement |
| anythingllm | Helm `backup-cronjob.yaml` | Helm `backup-cronjob.yaml` | Verify enabled |

### 5.3 Backup Verification Checklist

- [ ] Verify legacy backup scripts are running and producing valid dumps
- [ ] Test restore from legacy backup to staging environment
- [ ] Implement template backup scripts in new infrastructure
- [ ] Configure off-site backup storage (DO Spaces or S3)
- [ ] Document RTO/RPO for each service

---

## 6. Copier Template Enhancement Recommendations

### 6.1 Password Generation

> **Question**: Can copier generate passwords using PGP or other commands?

**Answer**: Copier supports Jinja2 filters but NOT arbitrary shell commands. However, you can:

1. **Use a post-generation script** in `copier.yaml`:

   ```yaml
   _tasks:
     - "python3 scripts/generate_secrets.py"
   ```

2. **Generate secrets in the script**:

   ```python
   # scripts/generate_secrets.py
   import secrets
   import string
   
   def generate_password(length=32):
       alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
       return ''.join(secrets.choice(alphabet) for _ in range(length))
   
   # Generate and write to .env file
   ```

3. **Or use OpenSSL in a task**:

   ```yaml
   _tasks:
     - "openssl rand -base64 32 > .db_password"
   ```

**Recommendation**: Add a `_tasks` section to `wordpress-docker/copier.yaml` and `keycloak-docker/copier.yaml` that generates secure passwords and writes them to a `.env` file (which is in `.gitignore`).

### 6.2 Template Improvements (Do Not Break Existing)

| Improvement | Template | Impact |
|-------------|----------|--------|
| Add `_tasks` for password generation | `copier.yaml` | New sites get secure defaults |
| Add `enable_infisical` default to `true` | `copier.yaml` | Align with project standards |
| Add monitoring alerts for disk + load | `monitoring.tf` | Match legacy alerting |
| Add `.gitignore` for `terraform.tfvars` | Template root | Prevent secret commits |
| Add `terraform.tfvars.example` with placeholders | Template | Clear documentation |

---

## 7. Execution Checklist

### Immediate (This Week)

- [ ] **Migrate all secrets to Infisical** (do_token, minimus_token, mysql passwords, spaces keys) — gitignored, never committed
- [ ] **Purge git history** in legacy repos and `sso.weown.dev` if committed
- [ ] **Document rotation** in `.github/INCIDENT_RESPONSE.md`
- [ ] **Create Infisical project** for `anythingllm`
- [ ] **Migrate anythingllm secrets** to Infisical
- [ ] **Enable Infisical** in anythingllm Helm values

### Short Term (Next 2 Weeks)

- [ ] **Create tfvars** for `ptoken-agency` and `burnedout-xyz` template sites
- [ ] **Import state** for both sites (read-only plan)
- [ ] **Review plan output** — document expected differences
- [ ] **Create Infisical project** for `sso.weown.dev`
- [ ] **Migrate sso.weown.dev secrets** to Infisical
- [ ] **Update sso.weown.dev tfvars** with real SSH key and Infisical config

### Medium Term (Next Month)

- [ ] **Plan WordPress sites Infisical migration**
- [ ] **Implement backup verification** for all sites
- [ ] **Add copier password generation tasks**
- [ ] **Update templates** with Infisical-by-default
- [ ] **Document RTO/RPO** for each service

### Long Term (Future)

- [ ] **Apply Terraform changes** to WordPress sites (after thorough testing)
- [ ] **Migrate WordPress sites to Infisical**
- [ ] **Decommission legacy repos** once migration verified
- [ ] **Add drift detection** CI workflow for Terraform

---

## 8. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Secret rotation causes downtime | Medium | High | Rotate during maintenance window; test in staging |
| Terraform import corrupts state | Low | High | Backup state before import; use `-out` plans only |
| Infisical sync fails | Medium | Medium | Keep K8s secrets as fallback during transition |
| Legacy backup incompatible | Medium | Medium | Test restore before relying on new backups |
| DNS disruption during migration | Low | High | Reserved IPs don't change; DNS unaffected |

---

## 9. Compliance Mapping

| Activity | NIST CSF | CIS | ISO 27001 | SOC 2 |
|----------|----------|-----|-----------|-------|
| Secret rotation | PR.DS | CIS 3.11 | A.8.24 | CC6.2 |
| Git history purge | PR.DS | CIS 3.11 | A.8.24 | CC6.8 |
| Infisical migration | PR.DS | CIS 16.11 | A.5.17 | CC6.2 |
| State import with plan review | PR.IP | CIS 4.1 | A.8.32 | CC8.1 |
| Backup verification | RC.RP | CIS 11 | A.8.13 | A1.2 |
| Password generation in templates | PR.DS | CIS 16.11 | A.8.24 | CC6.2 |

---

## 10. Appendix: Useful Commands

### Terraform State Import

```bash
# General pattern
tofu import digitalocean_droplet.web DROPLET_ID
tofu import digitalocean_reserved_ip.web IP_ADDRESS
tofu import digitalocean_reserved_ip_assignment.web DROPLET_ID-IP_ADDRESS-...
tofu import digitalocean_firewall.web FIREWALL_ID
tofu import digitalocean_monitor_alert.cpu ALERT_ID
```

### Git History Purge

```bash
# Using git-filter-repo (recommended)
pip install git-filter-repo
git filter-repo --path terraform/terraform.tfvars --invert-paths

# Using BFG Repo-Cleaner
java -jar bfg.jar --delete-files terraform.tfvars
```

### Infisical CLI

```bash
# Login
infisical login

# Set secrets
infisical secrets set DB_PASSWORD="$(openssl rand -base64 32)" --env=prod

# Run with secrets
infisical run --env=prod -- docker compose up -d
```

---

*Document version: v3.3.4.1 (#WeOwnVer)*
*Generated: 2026-04-26*
*Next review: After Phase 1 completion*
