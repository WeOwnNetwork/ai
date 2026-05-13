# stage-burnedout-xyz

WordPress site on a DigitalOcean droplet with Caddy reverse proxy, provisioned via OpenTofu. Docker images sourced from Minimus (`reg.mini.dev`).

## Architecture

```text
Internet → Caddy (TLS termination) → WordPress (PHP-FPM) → MariaDB
```

All three services run as Docker containers on a single droplet.

### Security: Wordfence WAF

This deployment includes automatic Wordfence Web Application Firewall (WAF) configuration:

- `.user.ini` auto-created with `auto_prepend_file` directive
- Required for Caddy + PHP-FPM setups (Apache/Nginx use `.htaccess`/`php.ini`)
- Direct web access to `.user.ini` blocked in Caddyfile

### Secrets Management: Infisical

Database credentials and sensitive configuration are managed via Infisical:

- Project ID: ``
- Environment: `prod`
- Zero-downtime credential rotation supported

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5
- [DigitalOcean API token](https://cloud.digitalocean.com/account/api/tokens) (custom scopes — see below)
- SSH key added to your DO account
- [Minimus](https://mini.dev) account with registry token
- Docker installed locally (for local dev)

- [Infisical CLI](https://infisical.com/docs/cli/overview) configured

### DigitalOcean API Token Scopes

Create a **Custom Scopes** token with these minimum permissions:

| Scope | Permission | Used By |
|-------|-----------|--------|
| **Droplet** | Create, Read, Update, Delete | Provision and manage the droplet |
| **Reserved IP** | Create, Read, Update, Delete | Static IP that survives rebuilds |
| **Firewall** | Create, Read, Update, Delete | SSH + HTTP/HTTPS rules |
| **Tag** | Create, Read, Delete | Droplet tags (`stage-burnedout-xyz`, `wordpress`) |
| **Monitoring** | Create, Read, Update, Delete | CPU/memory/disk alert policies |
| **SSH Key** | Read | Look up key by fingerprint |

## Project Structure

```text
├── docker/
│   ├── compose.local.yaml    # Local development stack
│   ├── compose.prod.yaml     # Production stack
│   ├── Caddyfile             # Production Caddy config
│   ├── Caddyfile.local       # Local Caddy config (HTTP only)
│   ├── .env.example          # Local env template
│   └── .env.prod.example     # Production env template
├── scripts/
│   ├── deploy.sh             # Deploy/update script
│   ├── backup.sh             # Skinny backup script
│   └── restore.sh            # Backup restore script
├── terraform/
│   ├── main.tf               # Droplet + firewall resources
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Droplet IP, SSH command
│   ├── versions.tf           # Provider config
│   ├── monitoring.tf         # Alert policies
│   ├── terraform.tfvars.example
│   └── templates/
│       └── cloud-init.yaml   # Droplet bootstrap script
└── README.md
```

## Quick Start

### 1. Authenticate Docker to Minimus

```bash
docker login reg.mini.dev -u minimus -p YOUR_MINIMUS_TOKEN
```

Verify image access:

```bash
docker pull reg.mini.dev/wordpress:latest
docker pull reg.mini.dev/caddy:2
```

### 2. Local Development

```bash
cd docker
cp .env.example .env
# Edit .env with your desired passwords

docker compose -f compose.local.yaml up -d
```

Visit <http://localhost> to complete the WordPress install.

### 3. Provision the Droplet

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values
# ⚠️ NEVER commit terraform.tfvars to version control

tofu init
tofu plan
tofu apply
```

OpenTofu will:

- Create a droplet with Docker pre-installed
- Log Docker into `reg.mini.dev` with your Minimus token
- Start the WordPress stack automatically

- Configure Wordfence WAF `.user.ini` for PHP-FPM

### 4. Deploy Updates

```bash
./scripts/deploy.sh root@<droplet-ip>
```

## Backup & Recovery

### Creating Backups

Skinny backups capture only essential data (database + wp-content + config):

```bash
# Remote backup (from your machine)
./scripts/backup.sh root@<droplet-ip>

# Local backup (on the droplet)
./scripts/backup.sh
```

Backups are stored in `/opt/stageburnedoutxyz/backups/` and can be pulled locally.

### Restoring from Backup

```bash
./scripts/restore.sh root@<droplet-ip> /path/to/backup.tar.gz
```

## Monitoring

DigitalOcean monitoring alerts are configured for:

- CPU usage > 80% for 5 minutes
- Memory usage > 90% for 5 minutes
- Disk usage > 85% for 5 minutes
- Load average > 2× vCPUs for 5 minutes

Alerts are sent to: `mwk@weown.net`

## DNS Configuration

Point your DNS to the reserved IP address output by OpenTofu:

```bash
tofu output reserved_ip
```

| Type | Host | Value |
|------|------|-------|
| A | @ | `<reserved_ip>` |
| A | www | `<reserved_ip>` |

## Security Considerations

- **Credentials**: Never commit `.env`, `.env.prod`, or `terraform.tfvars` to version control
- **SSH**: Consider restricting SSH access to specific IP ranges in `main.tf`
- **Firewall**: DigitalOcean firewall is configured; consider additional hardening

- **WAF**: Wordfence WAF is pre-configured; activate the plugin in WordPress admin

- **Secrets**: Database credentials managed via Infisical — rotate regularly

## Troubleshooting

### Check container status

```bash
ssh root@<droplet-ip> "cd /opt/stageburnedoutxyz && docker compose ps"
```

### View logs

```bash
ssh root@<droplet-ip> "cd /opt/stageburnedoutxyz && docker compose logs -f"
```

### Restart stack

```bash
ssh root@<droplet-ip> "cd /opt/stageburnedoutxyz && docker compose restart"
```

---

**Generated by**: [wordpress-docker template](../README.md) via copier
**WeOwn AI Infrastructure**: SOC2/ISO42001 compliant deployment
