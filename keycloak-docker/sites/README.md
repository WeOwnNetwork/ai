# keycloak-docker/sites

This directory contains **deployed site instances** generated from the [keycloak-docker template](../../).

Each subdirectory is a complete, independently deployed Keycloak SSO instance.

## Directory Structure

```text
sites/
├── .gitignore                    # Global gitignore for all sites
├── sso.example.com/              # Example site (gitignored state)
│   ├── .gitignore               # Site-specific overrides
│   ├── README.md                # Site-specific documentation
│   ├── docker/                  # Docker Compose files & env examples
│   ├── terraform/               # OpenTofu infrastructure (gitignored state)
│   ├── ansible/                  # Ansible playbooks for server config
│   └── scripts/                 # Deploy, backup, restore scripts
└── [other-sites]/               # Additional deployed sites
```

## Creating a New Site

```bash
cd keycloak-docker

# Generate a new site from the template
copier copy . ../sites/my-sso --data project_name=my-sso --data domain=sso.weown.ai

# Or use interactive mode
copier copy . ../sites/my-sso
```

## State File Management

Terraform/OpenTofu state files (`*.tfstate`) contain sensitive infrastructure information and **MUST NEVER be committed to git**.

### Why State Files Are Sensitive

- Droplet IP addresses
- Internal network configuration
- API tokens (if stored in state)
- Resource IDs that could be used for social engineering

### How We Manage State

| Environment | Backend | Location |
|-------------|---------|----------|
| Production | DigitalOcean Spaces (S3-compatible) | `s3://weown-terraform-state/` |
| Staging | DigitalOcean Spaces | `s3://weown-terraform-state/staging/` |
| Local Dev | `file` backend (gitignored) | `./.terraform/` |

### State Backend Configuration

Each site's terraform directory contains a `backend.tf` (generated from template). The backend is configured to use DigitalOcean Spaces with SSE encryption.

### Workflow for Multiple Developers

1. **First deploy**: Developer runs `tofu init` then `tofu apply`
   - State is uploaded to Spaces
   - Lock is acquired (via Spaces object locking)

2. **Subsequent deploys**:

   ```bash
   tofu init  # Pulls state from Spaces
   tofu plan  # Shows what would change
   tofu apply # Applies changes, state updated in Spaces
   ```

3. **Conflict prevention**:
   - OpenTofu uses Spaces object locking to prevent concurrent applies
   - If you see a lock error, another developer is applying changes
   - Wait and retry

4. **After merge conflicts** (if someone else modified state):

   ```bash
   tofu init
   tofu plan  # Shows if your local state diverged
   # If divergent, coordinate with the other developer
   ```

### State File Recovery

If local state is lost (e.g., laptop crash):

```bash
cd terraform
tofu init
tofu apply  # Will pull latest state from Spaces, then show "no changes"
```

### Viewing State

```bash
# Show current state
tofu show

# List resources
tofu state list

# Pull state to local (for debugging)
tofu state pull > backup.tfstate
```

## Adding a New Site

1. Generate from template:

   ```bash
   cd keycloak-docker
   copier copy . ../sites/my-new-sso --data project_name=my-new-sso --data domain=sso.myproject.com
   ```

2. Configure terraform backend (already done in template):

   ```bash
   cd ../sites/my-new-sso/terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit with your DO API token and Spaces bucket
   ```

3. Initialize and deploy:

   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

4. Run the deploy script:

   ```bash
   cd ../scripts
   ./deploy.sh root@<droplet-ip>
   ```

## Secrets Management

See [Infisical Integration docs](../../docs/INFISICAL_INTEGRATION.md) for secrets management.

**NEVER commit `.env` or `.env.prod` files.** Use `.env.example` as a template.

## Backup & Restore

```bash
# Create backup (run on droplet or via SSH)
./scripts/backup.sh root@<droplet-ip>

# Restore from backup
./scripts/restore.sh root@<droplet-ip> /path/to/backup.tar.gz
```

## Related Documentation

- [keycloak-docker template README](../../README.md)
- [INFISICAL_INTEGRATION docs](../../docs/INFISICAL_INTEGRATION.md)
- [OpenTofu/DigitalOcean docs](https://opentofu.org/docs/providers/digitalocean/)
