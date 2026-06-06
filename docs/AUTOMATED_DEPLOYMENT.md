# Automated Site Deployment

This document describes the automated deployment system for new sites across all docker templates.

## Overview

The `scripts/deploy-new-site.sh` script automates the complete deployment workflow from template to running application, implementing a tiered Machine Identity security model that balances automation with security best practices.

## Security Model

### Tiered Machine Identities

**Tier 1 MI (Bootstrap Identity)**

- **Privileges:** Can create Infisical projects, create Machine Identities, push initial secrets
- **Scope:** Limited to project creation operations only
- **Storage:** Stored in `operator-tools` Infisical project
- **Rotation:** Monthly (manual or automated)
- **Access:** Used only by deployment script, never by deployed sites

**Tier 2 MI (Site Identity)**

- **Privileges:** Can read secrets from its own project only
- **Scope:** Site-scoped, cannot access other projects
- **Storage:** Written to `terraform.tfvars` (gitignored), rotated on first boot
- **Rotation:** Layer 2 rotation on first boot (v1 → v2, v1 revoked)
- **Access:** Used by deployed site for runtime secret injection

### Security Guarantees

1. **Least Privilege:** Each site's MI can only access its own project
2. **Credential Rotation:** Tier 2 MI credentials rotated on first boot
3. **No Cross-Contamination:** Sites cannot access each other's secrets
4. **Audit Trail:** All project creation logged with Tier 1 MI identity
5. **Credential Isolation:** Tier 1 MI never exposed to deployed sites

## Usage

### Basic Deployment

```bash
./scripts/deploy-new-site.sh \
  --template keycloak-docker \
  --site-name sso \
  --domain sso.weown.dev \
  --admin-email admin@weown.dev
```

### Options

- `--auto` — Skip human review checkpoints (for CI/CD)
- `--dry-run` — Preview actions without executing
- `--skip-infra` — Skip infrastructure provisioning (assume exists)
- `--skip-deploy` — Skip application deployment (stop after infra)

### Examples

**Dry run to preview actions:**

```bash
./scripts/deploy-new-site.sh \
  --template wordpress-docker \
  --site-name blog \
  --domain blog.weown.dev \
  --admin-email admin@weown.dev \
  --dry-run
```

**Automated deployment (no checkpoints):**

```bash
./scripts/deploy-new-site.sh \
  --template keycloak-docker \
  --site-name auth \
  --domain auth.weown.dev \
  --admin-email admin@weown.dev \
  --auto
```

**Infrastructure only (deploy app later):**

```bash
./scripts/deploy-new-site.sh \
  --template anythingllm-docker \
  --site-name ai \
  --domain ai.weown.dev \
  --admin-email admin@weown.dev \
  --skip-deploy
```

## Deployment Phases

### Phase 1: Validation

- Validates site name (lowercase alphanumeric with hyphens)
- Validates domain format
- Checks template exists
- Ensures site doesn't already exist
- Verifies all prerequisites (infisical CLI, copier, tofu, ansible)

### Phase 2: Infisical Setup

1. Retrieves Tier 1 MI credentials from `operator-tools` project
2. Authenticates with Tier 1 MI
3. Creates new Infisical project: `{site-name}-{template-name}`
4. Generates secrets:
   - `JWT_SECRET` (random 32-byte hex)
   - `ADMIN_EMAIL` (from input)
5. Copies shared secrets from `operator-tools`:
   - `SPACES_ACCESS_KEY`
   - `SPACES_SECRET_KEY`
6. Creates site-specific Machine Identity (Tier 2 MI)
7. **Checkpoint:** Displays project ID and MI credentials, pauses for review

### Phase 3: Site Rendering

1. Renders site from template using copier
2. Writes `site.conf` with:
   - `INFISICAL_PROJECT_ID`
   - `INFISICAL_ENV=prod`
3. Writes `terraform/terraform.tfvars` with MI credentials (gitignored)
4. Generates site-specific files (deploy.sh, backup.sh, etc.)

### Phase 4: Infrastructure Provisioning

1. `cd terraform`
2. `tofu init` — Initialize providers
3. `tofu plan -out=tfplan` — Generate execution plan
4. **Checkpoint:** Displays plan summary, pauses for review
5. `tofu apply tfplan` — Provision infrastructure
6. Extracts droplet IP from tofu output
7. Waits for cloud-init to complete (polls for `.bootstrap-complete` marker)
8. Cleans up temporary files (tfplan, terraform.tfvars)

### Phase 5: Application Deployment

1. `cd {site-dir}`
2. `./site.sh deploy` — Deploy application via ansible
3. Waits 10 seconds for services to start
4. `./site.sh health` — Validate deployment
5. Reports success or failure with troubleshooting hints

### Phase 6: Reporting

Generates `DEPLOYMENT_REPORT.md` with:

- Site information (name, domain, template)
- Infrastructure details (droplet IP, site directory)
- Infisical details (project ID, MI client ID)
- Deployment status (infra, app, health check)
- Next steps (DNS, HTTPS, testing)
- Support commands (logs, health, backup, restore)

## Prerequisites

### Required Tools

- `infisical` CLI — Infisical secret management
- `copier` — Template rendering (pip install copier)
- `tofu` — Infrastructure provisioning
- `ansible` — Application deployment
- `doctl` — DigitalOcean CLI (authenticated)
- `jq` — JSON processing

### Required Infisical Setup

**operator-tools project must contain:**

- `TIER1_MI_CLIENT_ID` — Tier 1 Machine Identity client ID
- `TIER1_MI_CLIENT_SECRET` — Tier 1 Machine Identity client secret
- `SPACES_ACCESS_KEY` — Shared DigitalOcean Spaces access key
- `SPACES_SECRET_KEY` — Shared DigitalOcean Spaces secret key

**Tier 1 MI must have permissions:**

- Create Infisical projects
- Create Machine Identities within projects
- Push secrets to projects
- **Cannot** access existing projects (scope limitation)

### Required DigitalOcean Setup

- `doctl` authenticated with API token
- SSH key added to DigitalOcean account
- Domain DNS managed (for A record creation)

## Setting Up Tier 1 Machine Identity

### Step 1: Create Tier 1 MI in Infisical

1. Go to Infisical dashboard
2. Navigate to **Machine Identities** → **Create Machine Identity**
3. Name: `deployment-bootstrap-mi`
4. Description: "Tier 1 MI for automated site deployment"
5. Permissions:
   - **Projects:** Create
   - **Machine Identities:** Create (within own projects)
   - **Secrets:** Create, Read, Update (within own projects)
6. Save the Client ID and Client Secret

### Step 2: Add to operator-tools Project

1. Navigate to `operator-tools` project in Infisical
2. Add secrets:
   - `TIER1_MI_CLIENT_ID` = (from step 1)
   - `TIER1_MI_CLIENT_SECRET` = (from step 1)

### Step 3: Test Tier 1 MI

```bash
# Retrieve Tier 1 credentials
TIER1_CLIENT_ID=$(infisical secrets get TIER1_MI_CLIENT_ID --projectId=operator-tools --env=prod --plain)
TIER1_CLIENT_SECRET=$(infisical secrets get TIER1_MI_CLIENT_SECRET --projectId=operator-tools --env=prod --plain)

# Authenticate with Tier 1 MI
export INFISICAL_CLIENT_ID="$TIER1_CLIENT_ID"
export INFISICAL_CLIENT_SECRET="$TIER1_CLIENT_SECRET"
infisical login --method=universal-auth

# Test project creation (optional)
infisical projects create --name="test-project" --json
```

## Workflow Examples

### Deploying a New Keycloak Site

```bash
# 1. Run deployment script
./scripts/deploy-new-site.sh \
  --template keycloak-docker \
  --site-name sso \
  --domain sso.weown.dev \
  --admin-email admin@weown.dev

# 2. Review Infisical project creation (checkpoint)
#    - Note the project ID
#    - Save the MI client secret securely
#    - Press Enter to continue

# 3. Review infrastructure plan (checkpoint)
#    - Verify resources to be created
#    - Press Enter to apply

# 4. Wait for deployment to complete
#    - Script waits for cloud-init (5-10 minutes)
#    - Script deploys application via ansible
#    - Script validates health check

# 5. Review deployment report
cat keycloak-docker/sites/sso/DEPLOYMENT_REPORT.md

# 6. Create DNS A record
#    - Point sso.weown.dev to droplet IP from report
#    - Wait for DNS propagation (5-15 minutes)

# 7. Verify HTTPS certificate
curl -I https://sso.weown.dev

# 8. Test application
#    - Navigate to https://sso.weown.dev
#    - Login with admin credentials from Infisical
```

### Deploying Multiple Sites in Batch

```bash
# Create a sites.txt file with site definitions
cat > sites.txt <<EOF
wordpress-docker blog blog.weown.dev admin@weown.dev
keycloak-docker auth auth.weown.dev admin@weown.dev
anythingllm-docker ai ai.weown.dev admin@weown.dev
EOF

# Deploy each site
while read template name domain email; do
  echo "Deploying $name..."
  ./scripts/deploy-new-site.sh \
    --template "$template" \
    --site-name "$name" \
    --domain "$domain" \
    --admin-email "$email" \
    --auto
  echo ""
done < sites.txt
```

### CI/CD Integration

```yaml
# .github/workflows/deploy-site.yml
name: Deploy Site

on:
  workflow_dispatch:
    inputs:
      template:
        description: 'Template name'
        required: true
      site_name:
        description: 'Site name'
        required: true
      domain:
        description: 'Domain'
        required: true
      admin_email:
        description: 'Admin email'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install prerequisites
        run: |
          pip install copier
          # Install infisical, tofu, ansible, doctl...
      
      - name: Deploy site
        run: |
          ./scripts/deploy-new-site.sh \
            --template "${{ github.event.inputs.template }}" \
            --site-name "${{ github.event.inputs.site_name }}" \
            --domain "${{ github.event.inputs.domain }}" \
            --admin-email "${{ github.event.inputs.admin_email }}" \
            --auto
```

## Troubleshooting

### Tier 1 MI Authentication Failed

**Error:** `Failed to authenticate with Tier 1 MI`

**Solution:**

1. Verify Tier 1 credentials in `operator-tools` project
2. Check that MI is not expired or revoked
3. Ensure MI has correct permissions (create projects, create MIs)

### Project Creation Failed

**Error:** `Failed to create Infisical project`

**Solution:**

1. Check Tier 1 MI has "Create Projects" permission
2. Verify project name doesn't already exist
3. Check Infisical API status

### Cloud-Init Timeout

**Error:** `Timeout waiting for cloud-init to complete`

**Solution:**

1. SSH to droplet: `ssh root@{droplet-ip}`
2. Check cloud-init logs: `tail -100 /var/log/cloud-init-output.log`
3. Verify droplet has internet access
4. Check Infisical API is reachable from droplet

### Health Check Failed

**Error:** `Health check failed`

**Solution:**

1. Check application logs: `ssh root@{ip} 'docker compose logs'`
2. Verify all required secrets are in Infisical project
3. Check droplet resources (CPU, memory, disk)
4. Review ansible deployment logs

### Site Already Exists

**Error:** `Site already exists: {site-dir}`

**Solution:**

1. Choose a different site name
2. Or remove existing site: `rm -rf {template}/sites/{site-name}`
3. Or use `--skip-infra` if infrastructure already exists

## Security Considerations

### Tier 1 MI Credential Protection

- **Never commit** Tier 1 credentials to git
- **Store only** in `operator-tools` Infisical project
- **Rotate monthly** or after suspected compromise
- **Limit access** to deployment operators only

### Tier 2 MI Credential Lifecycle

- **Generated** during deployment (Phase 2)
- **Written** to `terraform.tfvars` (gitignored)
- **Used** by cloud-init for initial authentication
- **Rotated** on first boot (Layer 2 rotation)
- **v1 revoked** after successful rotation
- **v2 stored** on droplet at `/opt/{project}/.infisical-auth.env`

### Audit Trail

All project creation operations are logged in Infisical with:

- Tier 1 MI identity
- Timestamp
- Project name
- IP address

Review logs periodically for unauthorized project creation attempts.

### Rate Limiting

The script includes built-in rate limiting:

- Maximum 5 site deployments per hour
- Prevents accidental mass site creation
- Logs all deployment attempts

## Maintenance

### Rotating Tier 1 MI

1. Create new Tier 1 MI in Infisical
2. Update `operator-tools` project with new credentials
3. Revoke old Tier 1 MI
4. Test deployment with new MI

### Updating Shared Secrets

1. Update `SPACES_ACCESS_KEY` and `SPACES_SECRET_KEY` in `operator-tools`
2. New deployments will use updated credentials
3. Existing sites continue using their own copies (no impact)

### Cleaning Up Failed Deployments

```bash
# Destroy infrastructure
cd {template}/sites/{site-name}/terraform
tofu destroy

# Remove site directory
rm -rf {template}/sites/{site-name}

# Delete Infisical project (manual)
# Go to Infisical dashboard → Projects → Delete {project-name}
```

## Future Enhancements

### Planned Features

- **Rollback capability:** Automatic cleanup on deployment failure
- **Parallel deployments:** Deploy multiple sites concurrently
- **Custom secrets:** Support for template-specific secrets via config file
- **DNS automation:** Automatic A record creation via doctl
- **Slack notifications:** Deployment status notifications
- **Deployment dashboard:** Web UI for managing deployments

### Contributing

To extend the deployment script:

1. Add new phase in `deploy-new-site.sh`
2. Update this documentation
3. Add tests in `scripts/test-deploy.sh`
4. Submit PR with description of changes

## Related Documentation

- [INFISICAL_OUTAGE_RUNBOOK.md](INFISICAL_OUTAGE_RUNBOOK.md) — Emergency procedures
- [INFRA_BOOTSTRAP_PATTERN.md](INFRA_BOOTSTRAP_PATTERN.md) — Bootstrap pattern details
- [Template READMEs](../anythingllm-docker/README.md) — Template-specific documentation
