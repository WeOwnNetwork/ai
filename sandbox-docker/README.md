# sandbox-docker

Copier template for deploying [AIO Sandbox](https://github.com/agent-infra/sandbox) on DigitalOcean droplets.

AIO Sandbox is an all-in-one Docker container that provides AI agents with a unified execution environment: browser (VNC/CDP), shell terminal, filesystem, VSCode Server, Jupyter Notebook, and MCP servers — all sharing a single filesystem.

## What Gets Generated

```
your-project/
├── docker/
│   ├── compose.prod.yaml      # Production Docker Compose (Infisical runtime injection)
│   ├── compose.local.yaml     # Local development compose
│   ├── Caddyfile              # Production reverse proxy config
│   ├── Caddyfile.local        # Local development Caddyfile
│   ├── .env.example           # Environment variable reference
│   └── .env.prod.example      # Production env reference
├── terraform/
│   ├── main.tf                # Droplet, reserved IP, firewall
│   ├── variables.tf           # All configurable variables
│   ├── outputs.tf             # IP, domain, endpoint URLs
│   ├── monitoring.tf          # CPU/memory/disk alerts
│   ├── versions.tf            # OpenTofu + DO provider constraints
│   ├── backend.tf             # DO Spaces state backend
│   ├── terraform.tfvars.example
│   └── templates/
│       └── cloud-init.yaml    # Full droplet bootstrapping
├── scripts/
│   ├── deploy.sh              # SCP + SSH deploy with Infisical
│   ├── backup.sh              # Volume backup with GFS retention
│   └── restore.sh             # Restore from local or DO Spaces
├── README.md
├── CHANGELOG.md
└── .gitignore
```

## Usage

```bash
pip install copier

copier copy sandbox-docker/ ../sandbox-agent --data-file answers.yaml
```

### Example answers.yaml

```yaml
project_name: sandbox-agent
domain: sandbox.weown.dev
do_region: atl1
droplet_size: s-4vcpu-8gb-amd
sandbox_image: ghcr.io/agent-infra/sandbox:latest
caddy_image: reg.mini.dev/caddy:2
sandbox_workspace: /home/gem
sandbox_timezone: America/New_York
sandbox_display_width: 1920
sandbox_display_height: 1080
sandbox_homepage: https://google.com
enable_jupyter: true
enable_code_server: true
infisical_client_id: ""
infisical_client_secret: ""
infisical_project_id: ""
infisical_environment: prod
enable_skinny_backups: true
backup_remote_storage: do-spaces
backup_do_spaces_bucket: weown-backups
backup_do_spaces_region: atl1
enable_monitoring: true
alert_email: alerts@example.com
cpu_alert_threshold: 80
memory_alert_threshold: 90
disk_alert_threshold: 85
```

## Requirements

- **Droplet**: Minimum 4 vCPU, 8 GB RAM (sandbox runs ~15 internal services)
- **Docker**: Installed via cloud-init on first boot
- **Infisical**: Machine Identity for runtime secret injection
- **Domain**: DNS A record pointing to the droplet's reserved IP

## Infisical Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `JWT_PUBLIC_KEY` | Yes | Public key for sandbox API authentication |
| `GITHUB_TOKEN` | No | GitHub access token for use inside sandbox |
| `PROXY_SERVER` | No | HTTP proxy server URL |
| `SPACES_ACCESS_KEY` | No | DO Spaces access key (for backup offloading) |
| `SPACES_SECRET_KEY` | No | DO Spaces secret key (for backup offloading) |
