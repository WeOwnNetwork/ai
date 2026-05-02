# sso - Keycloak SSO Deployment

Production-ready Keycloak SSO deployment using Docker Compose on DigitalOcean droplets.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Caddy     │  │  Keycloak  │  │    PostgreSQL       │  │
│  │  (Reverse   │  │   (SSO)    │  │    (Database)      │  │
│  │   Proxy)    │  │            │  │                    │  │
│  │ :80, :443   │  │  :8080     │  │     :5432          │  │
│  └──────┬──────┘  └──────┬─────┘  └──────────┬──────────┘  │
│         │                │                   │              │
│         └────────────────┴───────────────────┘              │
│                      keycloaknet                            │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Keycloak SSO** - Full-featured identity provider with OIDC/OAuth2 (minimus.dev registry)
- **Caddy Reverse Proxy** - Automatic TLS via Let's Encrypt
- **PostgreSQL** - Persistent database for Keycloak data
- **Infisical Integration** - Secrets management for credentials
- **Idempotent Deployments** - Re-running deploy scripts is a no-op if nothing changed
- **Local Development** - Run Keycloak locally for testing
- **Backup/Restore** - Database and volume backup scripts

## Prerequisites

- DigitalOcean account with API token
- SSH key for droplet access
- Domain configured with DNS A record pointing to droplet IP
- Infisical account (optional, for secrets management)

## Quick Start

### 1. Create a new deployment from template

```bash
# Install copier if not already installed
pip install copier

# Create a new Keycloak deployment
cd keycloak-docker
copier copy . ../keycloak-sso --data-file answers.yaml
```

### 2. Configure your deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: keycloak-sso
domain: sso.weown.ai
do_region: nyc3
droplet_size: s-2vcpu-4gb-amd
enable_infisical: true
infisical_project_id: your-project-id
```

### 3. Deploy infrastructure

```bash
cd ../keycloak-sso/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu plan
tofu apply
```

### 4. Deploy application

```bash
cd ../scripts
chmod +x deploy.sh
./deploy.sh root@your-droplet-ip
```

## Local Development

```bash
cd docker
cp .env.example .env.local
# Edit .env.local with your values
docker compose -f compose.local.yaml up
```

Keycloak will be available at `http://localhost:8080`

## Infisical Integration

When `enable_infisical: true`, secrets are fetched from Infisical:

1. Create a project in Infisical
2. Add secrets:
   - `DB_PASSWORD` - PostgreSQL password
   - `DB_ROOT_PASSWORD` - PostgreSQL root password
   - `KEYCLOAK_ADMIN_PASSWORD` - Keycloak admin password
3. Sync secrets before deployment:

```bash
infisical run -- ./scripts/deploy.sh root@your-droplet-ip
```

## Secrets Update Process

To update secrets without rebuilding:

```bash
# Option 1: Use Infisical sync
infisical run -- ./scripts/deploy.sh root@your-droplet-ip

# Option 2: SSH and restart containers
ssh root@your-droplet-ip
cd /opt/keycloak/data
docker compose restart keycloak
```

## Backup

```bash
./scripts/backup.sh root@your-droplet-ip
```

Backups are stored in `/opt/keycloak/data/backups/` on the droplet.

## Restore

```bash
./scripts/restore.sh root@your-droplet-ip backup-name
```

## Idempotency

Both OpenTofu and Ansible are idempotent:

- **OpenTofu**: Re-running `tofu apply` after infrastructure exists will show no changes
- **Ansible**: Re-running playbooks will only make necessary changes
- **Deploy script**: Re-running will only restart services if compose files changed

## Security

- Secrets stored in Infisical, never in git
- TLS automatically managed by Caddy (Let's Encrypt)
- Firewall restricts access to ports 80, 443, 22
- PostgreSQL only accessible from within VPC (10.0.0.0/8)
- Non-root container users
- Resource limits on all containers

## Monitoring

DigitalOcean monitoring alerts are configured for:

- CPU usage > 80%
- Memory usage > 90%

## Support

For issues or questions, open a GitHub issue.
