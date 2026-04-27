# Migration Plan: WordPress Sites → AI Repo Templates

## Overview

This document outlines the migration path for existing WordPress deployments (`ptoken.agency`, `burnedout.xyz`) to align with the standardized templates in the `ai` repository.

**⚠️ CRITICAL: Do NOT apply these changes directly. This is a planning document for coordinated migration.**

## Current State Analysis

### ptoken.agency
| Attribute | Current | Template Target |
|-----------|---------|-----------------|
| Droplet Name | `ptoken-agency` | `ptoken-agency` ✅ |
| Size | `s-2vcpu-2gb-amd` | `s-2vcpu-2gb-amd` ✅ |
| Region | `atl1` | `atl1` ✅ |
| Image | `ubuntu-24-04-x64` | `ubuntu-24-04-x64` ✅ |
| Backups | `true` | `false` ⚠️ |
| Monitoring | CPU, Memory, Disk, Load | CPU, Memory only ⚠️ |
| Firewall | SSH, HTTP, HTTPS, QUIC | SSH, HTTP, HTTPS, QUIC ✅ |
| Tags | `["ptoken-agency", "wordpress"]` | `["ptoken-agency", "wordpress"]` ✅ |
| State | Local `.tfstate` | Spaces backend ⚠️ |
| Infisical | Not configured | Optional ⚠️ |

### burnedout.xyz
| Attribute | Current | Template Target |
|-----------|---------|-----------------|
| Droplet Name | `burnedout-xyz` | `burnedout-xyz` ✅ |
| Size | `s-2vcpu-2gb-amd` | `s-2vcpu-2gb-amd` ✅ |
| Region | `atl1` | `atl1` ✅ |
| Image | `ubuntu-24-04-x64` | `ubuntu-24-04-x64` ✅ |
| Backups | `true` | `false` ⚠️ |
| Monitoring | CPU, Memory, Disk, Load | CPU, Memory only ⚠️ |
| Firewall | SSH, HTTP, HTTPS, QUIC | SSH, HTTP, HTTPS, QUIC ✅ |
| Tags | `["burnedout-xyz", "wordpress"]` | `["burnedout-xyz", "wordpress"]` ✅ |
| State | Local `.tfstate` | Spaces backend ⚠️ |
| Infisical | Not configured | Optional ⚠️ |

## Migration Steps

### Phase 1: State Migration (No Downtime)

1. **Create Spaces Backend**
   ```bash
   # Generate SSE-C encryption key
   openssl rand -base64 32
   
   # Store in Infisical (exec-only for executives)
   # Path: /weown-ai/terraform/spaces-encryption-key
   ```

2. **Import Existing State**
   ```bash
   cd wordpress-docker/sites/ptoken-agency/terraform
   
   # Configure backend
   cat > backend.tf << 'EOF'
   terraform {
     backend "s3" {
       endpoint         = "https://atl1.digitaloceanspaces.com"
       bucket           = "weown-dev-backup"
       key              = "wordpress/ptoken-agency.tfstate"
       region           = "us-east-1"
       encrypt          = true
       acl              = "private"
       sse_customer_key = var.spaces_encryption_key
       access_key       = var.spaces_access_key
       secret_key       = var.spaces_secret_key
     }
   }
   EOF
   
   # Initialize and migrate state
   tofu init -migrate-state
   ```

3. **Verify State Upload**
   ```bash
   tofu state list
   tofu show
   ```

### Phase 2: Configuration Alignment (No Downtime)

1. **Update Monitoring**
   - Add Disk and Load alerts to template OR
   - Remove Disk and Load alerts from existing (if not needed)
   
   **Decision needed:** Do we want 4 alerts (current) or 2 alerts (template)?

2. **Backup Configuration**
   - Current: `backups = true` (DigitalOcean automated backups)
   - Template: `backups = false`
   
   **Decision needed:** Keep DO backups or rely on custom backup scripts?

3. **Tag Alignment**
   - Current tags are already aligned ✅

### Phase 3: Infisical Integration (Optional, Requires Planning)

1. **Prerequisites**
   - Infisical project setup
   - Machine identity configuration
   - Secret migration from tfvars to Infisical

2. **Migration Steps**
   ```bash
   # Install Infisical agent on droplet
   # Configure docker-compose to use Infisical
   # Migrate secrets from .env to Infisical
   ```

3. **Risk Assessment**
   - **High Risk:** Secret rotation requires application restart
   - **Mitigation:** Staged rollout with rollback plan

### Phase 4: Validation

1. **Plan Verification**
   ```bash
   tofu plan
   # Should show: No changes (if fully migrated)
   # Or: Expected changes (if aligning configuration)
   ```

2. **Drift Detection**
   ```bash
   # Set up scheduled drift detection
   tofu plan -detailed-exitcode
   ```

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| State corruption during migration | High | Low | Backup state first, test in staging |
| Infisical misconfiguration | High | Medium | Test in staging first, have rollback plan |
| Backup data loss | High | Low | Maintain DO backups until custom backups verified |
| Firewall rule changes | Medium | Low | Apply during maintenance window |

## Rollback Plan

1. **State Rollback**
   ```bash
   # If Spaces backend fails
   tofu init -backend=false
   # Restore local state from backup
   ```

2. **Configuration Rollback**
   ```bash
   # Revert to previous terraform.tfvars
   git checkout terraform.tfvars
   tofu apply
   ```

## Timeline

| Phase | Duration | Downtime |
|-------|----------|----------|
| State Migration | 30 min | None |
| Config Alignment | 1 hour | None |
| Infisical Integration | 4 hours | 15 min (restart) |
| Validation | 30 min | None |

## Decision Log

| Decision | Status | Date |
|----------|--------|------|
| Keep 4 monitoring alerts vs 2 | Pending | - |
| Keep DO backups vs custom only | Pending | - |
| Infisical integration priority | Pending | - |
| SSE-C encryption for WordPress state | Approved | 2026-04-26 |

## Next Steps

1. **Immediate:**
   - [ ] Decide on monitoring alert count
   - [ ] Decide on backup strategy
   - [ ] Generate SSE-C encryption key
   - [ ] Test state migration in staging

2. **Short-term:**
   - [ ] Migrate ptoken.agency state to Spaces
   - [ ] Migrate burnedout.xyz state to Spaces
   - [ ] Set up drift detection

3. **Long-term:**
   - [ ] Plan Infisical integration
   - [ ] Document secret rotation procedures
   - [ ] Automate backup verification

## References

- [DigitalOcean Spaces SSE-C](https://docs.digitalocean.com/reference/api/spaces-api/)
- [OpenTofu State Migration](https://opentofu.org/docs/cli/commands/init/)
- [Infisical Docker Integration](https://infisical.com/docs/integrations/platforms/docker)
