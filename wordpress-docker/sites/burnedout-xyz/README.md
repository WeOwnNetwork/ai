# burnedout-xyz

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

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5
- [DigitalOcean API token](https://cloud.digitalocean.com/account/api/tokens) (custom scopes — see below)
- SSH key added to your DO account
- [Minimus](https://mini.dev) account with registry token
- Docker installed locally (for local dev)

### DigitalOcean API Token Scopes

Create a **Custom Scopes** token with these minimum permissions:

| Scope | Permission | Used By |
|-------|-----------|--------|
| **Droplet** | Create, Read, Update, Delete | Provision and manage the droplet |
| **Reserved IP** | Create, Read, Update, Delete | Static IP that survives rebuilds |
| **Firewall** | Create, Read, Update, Delete | SSH + HTTP/HTTPS rules |
| **Tag** | Create, Read, Delete | Droplet tags (`burnedout-xyz`, `wordpress`) |
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

### 2. Local Development (fresh install)

```bash
cd docker
cp .env.example .env
# Edit .env — change MYSQL_PASSWORD and MYSQL_ROOT_PASSWORD to anything (local only)

COMPOSE_PROJECT_NAME=burnedout-local docker compose -f compose.local.yaml up -d
```

> **Note**: The WordPress image (`reg.mini.dev/wordpress`) is **PHP-FPM only** — it has no
> built-in web server. Caddy (also in the compose file) handles HTTP and proxies to FPM.
> Do not expose the `wordpress` service directly on port 80.

Visit **<http://localhost:8080>** to complete the WordPress install, or run `pull-prod.sh`
to import real production data instead (see [Pull Production for Local Dev](#pull-production-for-local-dev) below).

### 3. Provision the Droplet

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values
# ⚠️ NEVER commit terraform.tfvars

tofu init
tofu plan
tofu apply
```

### 4. Deploy Updates

```bash
./scripts/deploy.sh root@burnedout.xyz
```

---

## Day-to-Day Operations

### Pull Production for Local Dev

**When**: You want to work with real production data locally — debugging an issue,
testing a plugin update, or validating a migration before touching prod.

```bash
# Full pull: DB + wp-content
./scripts/pull-prod.sh

# DB only (faster, skips large wp-content transfer)
./scripts/pull-prod.sh --db-only

# wp-content only (e.g. after manually restoring the DB)
./scripts/pull-prod.sh --content-only

# Download only — don't import (useful if local stack is down)
./scripts/pull-prod.sh --no-import

# Override prod host
./scripts/pull-prod.sh root@134.199.203.100
```

The script:

1. SSHes to production and dumps the DB using the **real container password**
   (reads from `docker inspect`, not from `.env` — these can diverge)
2. SCPs the dump to `./wordpress.sql` (gitignored)
3. Streams `wp-content` directly from the prod container into the local container
4. Imports the DB and rewrites `siteurl`/`home` to `http://localhost:8080`

After the pull, log in at **<http://localhost:8080/wp-admin>** with your **production credentials**.

> **Security note**: `wordpress.sql` is gitignored (`*.sql` in `.gitignore`).
> Never commit it — it contains all production data including user records.

---

### Backup Production

**When**: Scheduled (set up a cron job or run before any risky change).
Creates a compressed archive of the DB + wp-content + config on the droplet,
then optionally downloads it to your machine.

```bash
# Run backup on production, then prompts to download
./scripts/backup.sh root@burnedout.xyz

# Run backup directly on the droplet (e.g. from a cron job on the droplet)
./scripts/backup.sh
```

Backups are stored at `/opt/burnedout/backups/` on the droplet and locally at
`./backups/` (gitignored). Retention: 30 days.

> **How the password is retrieved**: The backup script reads the DB password from
> `docker inspect` on the running container — not from `.env`. This is reliable
> even if `.env` was updated after the container started.

---

### Restore from Backup

**When**: Disaster recovery, or rolling back after a bad deployment.

```bash
# Restore to production
./scripts/restore.sh root@burnedout.xyz ./backups/burnedout-backup-20260501-161537.tar.gz

# Restore to local stack (for testing a backup before applying to prod)
./scripts/restore.sh local ./backups/burnedout-backup-20260501-161537.tar.gz
```

Local restore automatically:

- Imports the DB using local `.env` credentials
- Rewrites `siteurl`/`home` to `http://localhost:8080`
- Restores wp-content into the running container

---

### Deploy Updates to Production

**When**: Pushing code changes, config updates, or image upgrades.

```bash
./scripts/deploy.sh root@burnedout.xyz
```

---

### Script Reference

| Script | When to use |
|--------|-------------|
| `pull-prod.sh` | Local dev with real data; debugging prod issues locally |
| `backup.sh` | Before risky changes; scheduled snapshots |
| `restore.sh` | Disaster recovery; rollback; testing a backup |
| `deploy.sh` | Deploying changes to production |

## Monitoring

DigitalOcean monitoring alerts are configured for:

- CPU usage > 80% for 5 minutes
- Memory usage > 90% for 5 minutes
- Disk usage > 85% for 5 minutes
- Load average > 2× vCPUs for 5 minutes

## DNS Configuration

Point your DNS to the reserved IP address:

| Type | Host | Value |
|------|------|-------|
| A | @ | `<reserved_ip>` |
| A | www | `<reserved_ip>` |

---

**Generated by**: [wordpress-docker template](../../README.md) via copier
