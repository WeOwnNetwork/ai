# wordpress-docker

Copier template for WordPress deployments on DigitalOcean droplets with Docker, Caddy, and OpenTofu.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`template/terraform/init.sh.jinja`](template/terraform/init.sh.jinja). |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1, mints v2 via Infisical API, atomically swaps the auth file, revokes v1. |
| Path C (thin cloud-init + ansible) | **Done** | Cloud-init handles only first-boot bootstrap. [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) owns compose + Caddyfile + Wordfence WAF + backup script + cron + `docker compose up`. [`template/scripts/deploy.sh.jinja`](template/scripts/deploy.sh.jinja) is a thin `ansible-playbook` wrapper. |
| Infisical CLI install | **Current** — uses `artifacts-cli.infisical.com` apt repo. |

## Overview

This template generates production-ready WordPress infrastructure with:

- **Docker Compose** stack (WordPress + MariaDB + Caddy)
- **OpenTofu/Terraform** for DigitalOcean provisioning
- **Caddy** reverse proxy with automatic TLS (Let's Encrypt)
- **Wordfence WAF** auto-configuration for Caddy + PHP-FPM
- **Skinny backups** (database + wp-content only, not full disk)
- **Infisical integration** for secrets management (required)
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
enable_skinny_backups: true
enable_monitoring: true
alert_email: alerts@awesome.com
infisical_project_id: "your-project-id"
infisical_environment: "prod"
```

## Template Features

### Domain Styles

| Style | Primary URL | Behavior |
|-------|-------------|----------|
| `apex` | `https://example.com` | <www>. redirects to apex |
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

Required secrets management via Infisical:

- Store database credentials in Infisical (MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, DOMAIN)
- Cloud-init installs Infisical CLI and writes Machine Identity auth file
- Layer 2 bootstrap-secret rotation (v1 → v2) happens automatically on first boot
- Ansible playbook uses `.infisical-auth.env` for runtime secret injection
- Zero-downtime credential rotation

See [Infisical Integration](docs/INFISICAL_INTEGRATION.md) for setup instructions.

## Directory Structure

```text
wordpress-docker/
├── copier.yaml              # Template configuration
├── README.md                # This file
├── docs/
│   └── INFISICAL_INTEGRATION.md
└── template/
    ├── README.md.jinja      # Generated site README
    ├── CHANGELOG.md.jinja
    ├── .gitignore.jinja
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
    │   ├── restore.sh.jinja
    │   └── pull-prod.sh.jinja
    └── terraform/
        ├── backend.tf.jinja
        ├── init.sh.jinja
        ├── main.tf.jinja
        ├── variables.tf.jinja
        ├── outputs.tf.jinja
        ├── monitoring.tf.jinja
        ├── versions.tf.jinja
        ├── terraform.tfvars.example.jinja
        └── templates/
            └── cloud-init.yaml.jinja
```

## Generated Site Structure

After running `copier copy`, you'll have:

```text
my-new-site/
├── README.md                 # Site-specific documentation
├── CHANGELOG.md              # Version history
├── .gitignore.jinja
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
│   ├── restore.sh            # Restore from backup
│   └── pull-prod.sh          # Pull production data to local dev
├── terraform/
│   ├── backend.tf             # DO Spaces remote state backend
│   ├── init.sh                # Reads Spaces creds from tfvars, runs tofu init
│   ├── main.tf                # Infrastructure
│   ├── variables.tf
│   ├── outputs.tf
│   ├── monitoring.tf
│   ├── versions.tf.jinja
│   ├── terraform.tfvars.example
│   └── templates/
│       └── cloud-init.yaml
├── backups/                  # Local backup storage
└── logs/                     # Local logs (gitignored)
```

## Day-to-Day Operations

Every generated site includes four scripts under `scripts/`. Here's when to use each:

### `pull-prod.sh` — Pull Production to Local Dev

**Use when**: Starting local development, debugging a production issue, or validating
a change before applying it to production.

```bash
# Full pull: DB + wp-content (overwrites local stack)
./scripts/pull-prod.sh

# DB only (faster; skips large wp-content transfer)
./scripts/pull-prod.sh --db-only

# wp-content only
./scripts/pull-prod.sh --content-only

# Download dump but don't import (local stack may be down)
./scripts/pull-prod.sh --no-import
```

How it works:

1. SSHes to production and dumps the DB using `docker inspect` to get the **real**
   container password (not `.env` — they can diverge if `.env` was updated after
   the container started)
2. SCPs the dump to `./wordpress.sql` (gitignored)
3. Streams `wp-content` directly from prod container to local container
4. Imports the DB and rewrites `siteurl`/`home` to `http://localhost:8080`

### `backup.sh` — Snapshot Backup

**Use when**: Before any risky change, or on a schedule (cron).
Creates a compressed archive of DB + wp-content + config on the droplet.

```bash
# From your machine — prompts to download after
./scripts/backup.sh root@your-droplet-ip

# On the droplet directly (cron job)
./scripts/backup.sh
```

> The backup script reads the DB password from `docker inspect` on the running
> container, not from `.env`. This ensures the dump succeeds even if `.env`
> was changed after the container was started.

### `restore.sh` — Restore from Backup

**Use when**: Disaster recovery, rolling back after a bad deployment, or testing
a backup before applying it to production.

```bash
# Restore to production
./scripts/restore.sh root@your-droplet-ip ./backups/backup-20260501.tar.gz

# Restore to local stack (test the backup first)
./scripts/restore.sh local ./backups/backup-20260501.tar.gz
```

Local restore automatically:

- Imports the DB using local `.env` credentials
- Rewrites `siteurl`/`home` to `http://localhost:8080`
- Restores wp-content into the running container

### `deploy.sh` — Deploy Updates

**Use when**: Pushing code changes, config updates, or image upgrades to production.

```bash
INFISICAL_PROJECT_ID=<id> ./scripts/deploy.sh root@your-droplet-ip
```

The deploy script is a thin wrapper around `ansible-playbook`. It:

- Requires `INFISICAL_PROJECT_ID` env var
- Auto-installs `community.docker==3.13.0` collection if missing
- Executes `ansible/deploy.yml` which uploads compose + Caddyfile + backup script + cron and reconciles the stack

### Script Quick Reference

| Script | Runs on | When to use |
|--------|---------|-------------|
| `pull-prod.sh` | Local | Local dev with real data; debug prod issues locally |
| `backup.sh` | Local or droplet | Before risky changes; scheduled snapshots |
| `restore.sh` | Local or droplet | Disaster recovery; rollback; test a backup |
| `deploy.sh` | Local | Deploy changes to production |

---

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

### Infisical Outage Procedures

If Infisical Cloud becomes unavailable, deployments and backups will fail. See [INFISICAL_OUTAGE_RUNBOOK.md](../docs/INFISICAL_OUTAGE_RUNBOOK.md) for emergency procedures including:

- Manual deployment without Infisical
- Local-only backup creation
- Emergency restore procedures
- Recovery steps when Infisical comes back online

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
