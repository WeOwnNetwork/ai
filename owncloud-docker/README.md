# owncloud-docker

Docker-based ownCloud Infinite Scale (oCIS) deployment template for DigitalOcean droplets.  
This is the **non-Kubernetes** deployment path — ideal for single-node production or when DOKS is overkill.

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                     │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Caddy     │  │     ownCloud Infinite Scale (oCIS)  │  │
│  │  (Reverse   │  │                                     │  │
│  │   Proxy)    │  │  • File sync & share                │  │
│  │ :80, :443   │  │  • Spaces (project folders)         │  │
│  │             │  │  • Built-in IDM & OIDC              │  │
│  │             │  │  • WebDAV / LibreGraph API           │  │
│  │             │  │  • Full-text search                  │  │
│  └──────┬──────┘  └─────────────────────────────────────┘  │
│         │                                                   │
│         └───────────────────────────────────────────────────┘
│                        owncloudnet                          │
└─────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Docker Compose** (not K8s) — simpler ops, lower cost, no cluster management
- **oCIS single-binary** — built-in IDM, OIDC, and WebDAV; no separate DB container needed
- **Infisical runtime injection** — application secrets never touch disk
- **Caddy** — automatic TLS via Let's Encrypt, HTTP/3, security headers
- **Skinny backups** — volume-based backups with grandfather-father-son retention

## Prerequisites

- [DigitalOcean](https://m.do.co/c/2d7b0b6d4d0d) account with API token
- SSH key uploaded to DigitalOcean (Account → Security → SSH Keys)
- Domain with DNS A record pointing to the droplet IP
- [Infisical](https://infisical.com) account with a Machine Identity

## Quick Start

### 1. Install copier

```bash
pip install copier
```

### 2. Create a new deployment

```bash
cd ai/owncloud-docker
copier copy . ../cloud-weown-dev --data-file answers.yaml
```

Or use interactive prompts:

```bash
copier copy . ../cloud-weown-dev
```

### 3. Configure Infisical secrets

Before deploying infrastructure, create these secrets in your Infisical project:

| Secret Key | Description | Required |
|-----------|-------------|----------|
| `OCIS_JWT_SECRET` | JWT signing secret (`openssl rand -hex 32`) | **Yes** |
| `IDM_ADMIN_PASSWORD` | Initial admin password | **Yes** |
| `IDP_LDAP_BIND_PASSWORD` | LDAP bind password (`openssl rand -hex 32`) | **Yes** |
| `STORAGE_TRANSFER_SECRET` | Storage transfer secret (`openssl rand -hex 32`) | **Yes** |
| `THUMBNAILS_TRANSFER_SECRET` | Thumbnails transfer secret (`openssl rand -hex 32`) | **Yes** |
| `MACHINE_AUTH_API_KEY` | Machine auth API key (`openssl rand -hex 32`) | **Yes** |
| `OCIS_SYSTEM_USER_API_KEY` | System user API key (`openssl rand -hex 32`) | **Yes** |
| `SPACES_ACCESS_KEY` | DO Spaces key for backups | No |
| `SPACES_SECRET_KEY` | DO Spaces secret for backups | No |

### 4. Deploy infrastructure

```bash
cd ../cloud-weown-dev/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (only Infisical Machine Identity + DO token)
tofu init
tofu plan
tofu apply
```

### 5. Deploy application

```bash
cd ../scripts
chmod +x deploy.sh
./deploy.sh root@$(tofu output -raw droplet_ip)
```

## Infisical Security Model

This template uses **runtime secret injection** — the gold standard for Docker deployments:

```text
terraform.tfvars ──► droplet ──► cloud-init ──► Infisical Machine Identity
                                                     │
                                                     ▼
                                             Infisical Cloud API
                                                     │
                                                     ▼
                                             Application Secrets
                                             (OCIS_JWT_SECRET,
                                              IDM_ADMIN_PASSWORD, etc.)
                                                     │
                                                     ▼
                                      `infisical run -- docker compose up`
                                                     │
                                                     ▼
                                             Container Environment
                                             (secrets in RAM only)
```

**What this achieves:**

- **Zero application secrets on disk** — only the Infisical Machine Identity is stored on the node
- **Runtime injection** — secrets fetched at container start, live in process memory only
- **No rebuilds for rotation** — restart container, new secrets flow in
- **Centralized management** — rotate secrets in Infisical, all droplets pick up changes on next deploy

## Directory Structure

```text
owncloud-docker/
├── copier.yaml                    # Copier template configuration
├── template/                      # Template files (rendered by copier)
│   ├── terraform/
│   │   ├── main.tf.jinja          # Droplet, reserved IP, firewall
│   │   ├── variables.tf.jinja     # Input variables (no app secrets)
│   │   ├── outputs.tf.jinja       # Droplet IP, domain, etc.
│   │   ├── monitoring.tf.jinja    # DO monitoring alerts
│   │   ├── versions.tf            # OpenTofu version constraints
│   │   ├── terraform.tfvars.example
│   │   └── templates/
│   │       └── cloud-init.yaml.jinja  # Bootstrap: Docker, Infisical, compose
│   ├── docker/
│   │   ├── compose.prod.yaml.jinja    # Production stack
│   │   └── Caddyfile.jinja            # Reverse proxy + TLS
│   ├── scripts/
│   │   ├── deploy.sh.jinja            # Deploy / update stack
│   │   ├── backup.sh.jinja            # Skinny volume backup
│   │   └── restore.sh.jinja           # Restore from backup
│   ├── .gitignore
│   ├── README.md.jinja
│   └── CHANGELOG.md.jinja
└── README.md                    # This file
```

## Backup Strategy

### Grandfather-Father-Son Retention

| Backup Type | Retention |
|-------------|-----------|
| Daily | 30 days |
| Monthly (1st of month) | 12 months |
| Yearly (Jan 1st) | Forever |

### Execution

Backups run daily via `/etc/cron.daily/owncloud-backup` and are executed **within `infisical run`** so DO Spaces credentials are available from Infisical.

```bash
# Manual backup
./scripts/backup.sh root@your-droplet-ip

# Manual restore
./scripts/restore.sh root@your-droplet-ip owncloud_backup_20260115_120000
```

## Security & Compliance

- **NIST CSF 2.0**: PR.DS (data security), PR.AC (access control), DE.CM (monitoring)
- **CIS Controls v8 IG1**: CIS 3.11 (encrypt sensitive data at rest), CIS 4.1 (secure config)
- **ISO 27001-ready**: A.5.17 (authentication info), A.8.24 (use of cryptography)

### Security Features

- No application secrets in git or on disk
- Firewall: 22 (SSH), 80 (HTTP/ACME), 443 (HTTPS/QUIC)
- Automatic security updates via `unattended-upgrades`
- Docker daemon: log rotation, overlay2, json-file logging
- Caddy: automatic TLS, HTTP/3, security headers

## Related Projects

| Project | Runtime | Purpose |
|---------|---------|---------|
| `ai/nextcloud` | Kubernetes (Helm) | Nextcloud deployment |
| `ai/keycloak-docker` | Docker Compose | SSO / identity provider |
| `ai/wordpress-docker` | Docker Compose | CMS deployments |
| `ai/anythingllm-docker` | Docker Compose | AI assistant deployment |

## Known Limitations

- **External OIDC**: oCIS includes a built-in IDP. To integrate with an external Keycloak instance, additional proxy_role configuration is required. See `ai/keycloak-docker` for our Keycloak deployment.
- **S3 storage backend**: This template uses local filesystem storage. For S3-compatible object storage (DO Spaces, MinIO), additional oCIS environment variables are needed.

## License

MIT — See [LICENSE](../LICENSE) in the repository root.
