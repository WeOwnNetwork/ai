# keycloak-docker

Copier template for Keycloak SSO deployments on DigitalOcean droplets.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Partial** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) exists, but no `template/terraform/init.sh.jinja` to forward credentials to `tofu init -backend-config`. The rendered site [`sites/sso.weown.dev/terraform/`](sites/sso.weown.dev/terraform/) has both `backend.tf` + `init.sh` — that's the working pattern; promote it back into the template. |
| Layer 2 (bootstrap-secret rotation) | **Pending** | No `rotate-bootstrap-secret.sh`. Reference: [`s004-deployment/terraform/templates/cloud-init.yaml`](../s004-deployment/terraform/templates/cloud-init.yaml). |
| Path C (thin cloud-init + ansible) | **Partial** | [`template/ansible/site.yml.jinja`](template/ansible/site.yml.jinja) (with roles + inventories scaffolding) is the most ansible-shaped of any *-docker template — uses `community.docker.docker_compose_v2`. But [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja) still embeds compose + Caddyfile + `docker compose up`. **Slim the cloud-init.** |
| Infisical CLI install | **Legacy** — `install-cli.sh` (capped at v0.38). Switch to artifacts-cli apt repo. |

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
