# wordpress-docker

Copier template for WordPress deployments on DigitalOcean droplets with Docker, Caddy, and OpenTofu.

## Overview

This template generates production-ready WordPress infrastructure with:

- **Docker Compose** stack (WordPress + MariaDB + Caddy)
- **OpenTofu/Terraform** for DigitalOcean provisioning
- **Caddy** reverse proxy with automatic TLS (Let's Encrypt)
- **Wordfence WAF** auto-configuration for Caddy + PHP-FPM
- **Skinny backups** (database + wp-content only, not full disk)
- **Infisical integration** for secrets management (optional)
- **DigitalOcean monitoring** alerts

## Quick Start

### Prerequisites

- [Copier](https://copier.readthedocs.io/) >= 9.0
- [OpenTofu](https://opentofu.org/) >= 1.5 (or Terraform)
- [DigitalOcean account](https://cloud.digitalocean.com/)
- [Minimus account](https://mini.dev) (for container images)

### Generate a New Site

```bash
# Install copier if needed
pipx install copier

# Generate a new site
copier copy ./wordpress-docker ../sites/my-new-site

# Or with answers file
copier copy ./wordpress-docker ../sites/my-new-site --data-file answers.yaml
```

### Example Answers File

```yaml
# answers.yaml
project_name: my-awesome-site
domain: awesome.com
domain_style: apex
do_region: nyc3
droplet_size: s-2vcpu-2gb-amd
enable_wordfence_waf: true
enable_infisical: false
enable_skinny_backups: true
backup_retention_days: 30
enable_monitoring: true
alert_email: alerts@awesome.com
```

## Template Features

### Domain Styles

| Style | Primary URL | Behavior |
|-------|-------------|----------|
| `apex` | `https://example.com` | www. redirects to apex |
| `www` | `https://www.example.com` | apex redirects to www. |

### Wordfence WAF

The template auto-configures Wordfence Web Application Firewall for Caddy + PHP-FPM:

- Creates `.user.ini` with `auto_prepend_file` directive
- Blocks direct web access to `.user.ini` in Caddyfile
- Works with Caddy (which doesn't support `.htaccess` like Apache)

See [Wordfence WAF README](template/docker/wordfence-waf/README.md) for details.

### Skinny Backups

Instead of full disk snapshots (20% extra cost on DigitalOcean), this template uses "skinny backups":

- Database dump (MariaDB)
- `wp-content/` (themes, plugins, uploads)
- Configuration files (Caddyfile, .env, compose.yaml)
- Container state information

Backups are compressed, stored locally, and can be pushed to remote storage (DO Spaces, S3).

### Infisical Integration

Optional secrets management via Infisical:

- Store database credentials in Infisical
- Cloud-init exports secrets during bootstrap
- Zero-downtime credential rotation

See [Infisical Integration](docs/INFISICAL_INTEGRATION.md) for setup instructions.

## Directory Structure

```
wordpress-docker/
├── copier.yaml              # Template configuration
├── README.md                # This file
├── docs/
│   └── INFISICAL_INTEGRATION.md
└── template/
    ├── README.md.jinja      # Generated site README
    ├── CHANGELOG.md.jinja
    ├── .gitignore
    ├── docker/
    │   ├── compose.prod.yaml.jinja
    │   ├── compose.local.yaml.jinja
    │   ├── Caddyfile.jinja
    │   ├── Caddyfile.local
    │   ├── .env.example
    │   ├── .env.prod.example
    │   └── wordfence-waf/
    │       ├── .user.ini.jinja
    │       └── README.md
    ├── scripts/
    │   ├── deploy.sh.jinja
    │   ├── backup.sh.jinja
    │   └── restore.sh.jinja
    └── terraform/
        ├── main.tf.jinja
        ├── variables.tf.jinja
        ├── outputs.tf.jinja
        ├── monitoring.tf.jinja
        ├── versions.tf
        ├── terraform.tfvars.example.jinja
        └── templates/
            └── cloud-init.yaml.jinja
```

## Generated Site Structure

After running `copier copy`, you'll have:

```
my-new-site/
├── README.md                 # Site-specific documentation
├── CHANGELOG.md              # Version history
├── .gitignore
├── docker/
│   ├── compose.prod.yaml     # Production Docker Compose
│   ├── compose.local.yaml    # Local development
│   ├── Caddyfile             # Production Caddy config
│   ├── Caddyfile.local       # Local Caddy (HTTP only)
│   ├── .env.example
│   ├── .env.prod.example
│   └── wordfence-waf/
│       ├── .user.ini         # Wordfence WAF config
│       └── README.md
├── scripts/
│   ├── deploy.sh             # Deploy updates
│   ├── backup.sh             # Create backups
│   └── restore.sh            # Restore from backup
├── terraform/
│   ├── main.tf               # Infrastructure
│   ├── variables.tf
│   ├── outputs.tf
│   ├── monitoring.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example
│   └── templates/
│       └── cloud-init.yaml
├── backups/                  # Local backup storage
└── logs/                     # Local logs (gitignored)
```

## Existing Sites

Pre-generated configurations for existing sites:

| Site | Domain | Domain Style | Status |
|------|--------|--------------|--------|
| [burnedout-xyz](sites/burnedout-xyz/) | burnedout.xyz | apex | Production |
| [ptoken-agency](sites/ptoken-agency/) | ptoken.agency | www | Production |

## Migration from Standalone Repos

If you have existing standalone WordPress repos (like the original `burnedout.xyz` and `ptoken.agency`):

1. Generate a new site with matching configuration
2. Copy terraform state files (`terraform.tfstate*`)
3. Update `terraform.tfvars` with existing credentials
4. Deploy to verify compatibility
5. Archive the old repository

## Compliance

This template follows WeOwn AI Infrastructure standards:

- **SOC2**: Encrypted credentials, audit logging, backup procedures
- **ISO/IEC 42001**: Documented deployment, change management
- **Security**: TLS 1.3, security headers, WAF ready, no root containers

## Contributing

When modifying the template:

1. Test with `copier copy . /tmp/test-site --data-file test-answers.yaml`
2. Verify generated files render correctly
3. Run `helm lint` / `tofu validate` on generated output
4. Update documentation if adding features

## Troubleshooting

### Copier Template Errors

```bash
# Validate template syntax
copier copy . /tmp/test --defaults --overwrite
```

### Generated Terraform Invalid

```bash
cd generated-site/terraform
tofu init
tofu validate
```

### Caddyfile Syntax Errors

```bash
# Test Caddyfile locally
docker run --rm -v ./docker/Caddyfile:/etc/caddy/Caddyfile caddy:2 caddy validate --config /etc/caddy/Caddyfile
```

## Related Documentation

- [WeOwn AI Infrastructure](../README.md)
- [DigitalOcean Droplet Docs](https://docs.digitalocean.com/products/droplets/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Wordfence WAF](https://www.wordfence.com/help/firewall/)
