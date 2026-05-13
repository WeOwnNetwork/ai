# keycloak-docker

Copier template for Keycloak SSO deployments on DigitalOcean droplets.

## Overview

This template provides a production-ready Keycloak SSO deployment with:

- **Keycloak** - Identity provider with OIDC/OAuth2 support
- **Caddy** - Reverse proxy with automatic TLS
- **PostgreSQL** - Persistent database
- **OpenTofu** - Infrastructure as Code (DigitalOcean droplets)
- **Ansible** - Server configuration management
- **Infisical** - Secrets management integration

## Directory Structure

```text
keycloak-docker/
├── copier.yaml              # Copier template configuration
├── README.md               # This file
├── CHANGELOG.md            # Changelog
└── template/
    ├── ansible/            # Ansible playbooks and roles
    │   ├── inventories/    # Inventory files
    │   ├── roles/          # Ansible roles
    │   │   ├── common/     # Base server config
    │   │   ├── docker/     # Docker installation
    │   │   └── keycloak/   # Keycloak-specific config
    │   ├── requirements.yml
    │   └── site.yml
    ├── docker/             # Docker Compose files
    │   ├── compose.local.yaml
    │   ├── compose.prod.yaml
    │   ├── Caddyfile
    │   ├── Caddyfile.local
    │   └── .env*.example
    ├── scripts/            # Deploy, backup, restore scripts
    │   ├── deploy.sh
    │   ├── backup.sh
    │   └── restore.sh
    └── terraform/         # OpenTofu infrastructure
        ├── main.tf
        ├── outputs.tf
        ├── variables.tf
        ├── monitoring.tf
        ├── versions.tf
        └── templates/
            └── cloud-init.yaml
```

## Usage

### Create a new deployment

```bash
# Install copier if not already installed
pip install copier

# Create a new Keycloak deployment
cd keycloak-docker
copier copy . ../keycloak-sso --data-file answers.yaml
```

### Configure deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: keycloak-sso
domain: sso.weown.ai
do_region: nyc3
droplet_size: s-2vcpu-4gb-amd
enable_infisical: true
infisical_project_id: your-infisical-project-id
```

### Deploy infrastructure

```bash
cd ../keycloak-sso/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu plan
tofu apply
```

### Deploy application

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

## Secrets Management

Secrets are managed via Infisical. To update secrets:

```bash
infisical run -- ./scripts/deploy.sh root@your-droplet-ip
```

Or SSH and restart:

```bash
ssh root@your-droplet-ip
cd /opt/keycloak/data
docker compose restart keycloak
```

## Idempotency

- **OpenTofu**: Re-running `tofu apply` after infrastructure exists will show no changes
- **Ansible**: Re-running playbooks will only make necessary changes
- **Deploy script**: Re-running will only restart services if compose files changed

## Services to Integrate

This Keycloak instance can provide SSO/OIDC/OAuth2 for:

- n8n (workflow automation)
- Nextcloud (file sync & collaboration)
- AnythingLLM (AI assistant / RAG)
- WordPress (CMS sites)
- Other internal services

## License

See individual component licenses (Keycloak: Apache 2.0, PostgreSQL: PostgreSQL License)
