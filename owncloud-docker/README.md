# owncloud-docker

Copier template for ownCloud Infinite Scale (oCIS) deployments on DigitalOcean droplets.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`template/terraform/init.sh.jinja`](template/terraform/init.sh.jinja). |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1, mints v2 via Infisical API, atomically swaps the auth file, revokes v1. |
| Path C (thin cloud-init + ansible) | **Done** | Cloud-init handles only first-boot bootstrap. [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) owns compose + Caddyfile + backup script + cron + `docker compose up`. [`template/scripts/deploy.sh.jinja`](template/scripts/deploy.sh.jinja) is a thin `ansible-playbook` wrapper. |
| Infisical CLI install | **Current** — uses `artifacts-cli.infisical.com` apt repo. |

## Overview

This template provides a production-ready ownCloud Infinite Scale deployment with:

- **oCIS** - File sync and share platform (Go-based, embedded LDAP)
- **Caddy** - Reverse proxy with automatic TLS
- **OpenTofu** - Infrastructure as Code (DigitalOcean droplets)
- **Ansible** - Server configuration management
- **Infisical** - Secrets management integration

## Directory Structure

```text
owncloud-docker/
├── copier.yaml              # Copier template configuration
├── README.md               # This file
├── CHANGELOG.md            # Changelog
└── template/
    ├── ansible/            # Ansible playbooks and roles
    │   ├── inventories/    # Inventory files
    │   ├── roles/          # Ansible roles
    │   │   ├── common/     # Base server config
    │   │   ├── docker/     # Docker installation
    │   │   └── owncloud/   # oCIS-specific config
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

# Create a new oCIS deployment
cd owncloud-docker
copier copy . ../owncloud-prod --data-file answers.yaml
```

### Configure deployment

Edit `answers.yaml` with your specific values:

```yaml
project_name: owncloud-prod
domain: app.weown.cloud
do_region: atl1
droplet_size: s-2vcpu-4gb-amd
enable_infisical: true
infisical_project_id: your-infisical-project-id
```

### Deploy infrastructure

```bash
cd ../owncloud-prod/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
./init.sh  # Configures DO Spaces backend with SSE-C
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

Secrets are managed via Infisical using the **bounce-to-refresh** pattern.

**What this achieves (ADR-006):**

- **Zero application secrets on disk** — only the Machine Identity reaches the node (Layer 2 rotates even that on first boot); infra creds are injected as `TF_VAR_*` by `itofu.sh`, never written to `terraform.tfvars`.
- **In-container secret fetch** — `infisical run` is the container entrypoint, fetching secrets in-process at every container start. Secrets are NOT in the compose `environment:` block, so they don't appear in `docker inspect`.
- **Bounce-to-refresh** — `docker restart` re-fetches secrets from Infisical (no redeploy needed). This enables consumer-side auto-rotation: rotate a secret in Infisical, bounce the container, it loads the new value.
- **Centralized management** — edit a secret in Infisical; the next `docker restart` picks it up.
- **Multi-container secret duplication** — oCIS sees secrets under their expected env var names (e.g., `OCIS_JWT_SECRET`, `IDM_ADMIN_PASSWORD`). Same values, different names in Infisical.

To refresh secrets after rotating them in Infisical:

```bash
ssh root@your-droplet-ip
cd /opt/owncloud-prod
docker compose restart
```

### Infisical Outage Procedures

If Infisical Cloud becomes unavailable, deployments and backups will fail. See [INFISICAL_OUTAGE_RUNBOOK.md](../docs/INFISICAL_OUTAGE_RUNBOOK.md) for emergency procedures including:

- Manual deployment without Infisical
- Local-only backup creation
- Emergency restore procedures
- Recovery steps when Infisical comes back online

## Idempotency

- **OpenTofu**: Re-running `tofu apply` after infrastructure exists will show no changes
- **Ansible**: Re-running playbooks will only make necessary changes
- **Deploy script**: Re-running will only restart services if compose files changed

## Services to Integrate

This oCIS instance provides file sync and share for:

- WeOwn ecosystem users
- Integration with Keycloak SSO (sso.weown.dev) for authentication
- AnythingLLM for document storage
- Other internal services

## License

See individual component licenses (oCIS: Apache 2.0, Caddy: Apache 2.0)
