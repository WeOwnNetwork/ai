# wordpress-docker Changelog

All notable changes to this template will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](../docs/VERSIONING_WEOWNVER.md).

## [Unreleased]

### Added

- **Layer 1 — DO Spaces Remote State**: `backend.tf.jinja` + `init.sh.jinja` for encrypted remote state backend
- **Layer 2 — Bootstrap-Secret Rotation**: `rotate-bootstrap-secret.sh` embedded in cloud-init (v1 → v2 auto-rotation)
- **Path C — Thin Cloud-Init + Ansible**: Cloud-init handles only first-boot bootstrap; ansible playbook owns all app-layer state
- **Ansible playbook overhaul**: Pre-tasks for bootstrap verification, backup script + cron upload, DO droplet tagging, WordPress health checks
- **Deploy script rewrite**: Thin `ansible-playbook` wrapper requiring `INFISICAL_PROJECT_ID` env var
- **Docker Compose hardening**: Resource limits on all services, WordPress healthcheck, Caddy log bind mount
- **Backup script upgrade**: DO Spaces remote upload via `aws s3 cp`, grandfather-father-son retention policy
- **SSH CIDR restriction**: `ssh_source_cidrs` variable for firewall SSH rule

### Changed

- **Infisical now mandatory**: Removed `enable_infisical` toggle; DB credentials live exclusively in Infisical
- **Infisical CLI install**: Switched from legacy `install-cli.sh` (capped at v0.38) to current `artifacts-cli.infisical.com` apt repo
- **Auth file format**: Replaced `infisical-auth.sh` shell script with `.infisical-auth.env` key-value file (0600)
- **Cloud-init slimmed**: Removed all app-layer content (compose, Caddyfile, backup, cron, Wordfence WAF, `docker compose up`)
- **Terraform variable renames**: `do_token` → `minimus_token`, added `project_name` variable
- **versions.tf → versions.tf.jinja**: Bumped `required_version` to `>= 1.7.0`
- **Monitoring alerts**: Switched from Jinja conditionals to `count =` pattern, removed `load_5` alert
- **Outputs rewritten**: `droplet_ip` uses reserved IP, added `domain` + `infisical_project` outputs
- **copier.yaml aligned**: List-of-tuples choices format, added `backup_do_spaces_bucket` + `backup_do_spaces_region`, removed `backup_retention_days`
- **.gitignore.jinja**: Renamed from `.gitignore`, added Ansible ignores (`*.retry`, `.vault-pass`), stopped ignoring `.terraform.lock.hcl`

### Security

- Bootstrap-secret rotation invalidates v1 Machine Identity secret within minutes of provisioning
- `.infisical-auth.env` written with 0600 permissions (root-only)
- SSH firewall now restricts access via `ssh_source_cidrs` variable
- Docker daemon config added (log rotation, overlay2)

## [4.16.7.1] - 2026-04-20

### Added

- **Copier Template**: Complete templating system for generating new WordPress sites
  - `copier.yaml` with comprehensive configuration options
  - Domain style support: apex (example.com) or www (<www.example.com>)
  - Configurable DigitalOcean region and droplet size
  - Container image customization (Minimus registry)

- **Wordfence WAF Integration** (Discovery #226)
  - Auto-generated `.user.ini` with `auto_prepend_file` directive
  - Required for Caddy + PHP-FPM deployments (unlike Apache/Nginx)
  - Direct web access blocked in Caddyfile
  - Documentation in `template/docker/wordfence-waf/README.md`

- **Skinny Backups** (D189)
  - Volume-based backups replacing 20% DO automated backup cost
  - Database dump + wp-content + config only (not full disk)
  - Configurable retention period (default 30 days)
  - Daily cron job via cloud-init
  - Restore script with remote/local support

- **Infisical Integration** (Discovery #275)
  - Optional secrets management integration
  - Documentation in `docs/INFISICAL_INTEGRATION.md`
  - Cloud-init secret export during bootstrap
  - Zero-downtime credential rotation support

- **Pre-generated Sites** (D130)
  - `sites/burnedout-xyz/`: Production config for burnedout.xyz (apex style)
  - `sites/ptoken-agency/`: Production config for ptoken.agency (www style)
  - Ready to migrate from standalone repositories

- **Infrastructure Templates**
  - OpenTofu main.tf with DigitalOcean droplet, reserved IP, firewall
  - Monitoring alerts (CPU 80%, Memory 90%, Disk 85%, Load 4)
  - Cloud-init bootstrap with Docker, compose, Wordfence WAF
  - Security-hardened Caddyfile with headers and file blocking

### Security

- TLS 1.3 via Caddy auto-HTTPS
- Security headers: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy
- Blocked access to sensitive files (*.sql,*.log, *.bak, wp-config.php)
- PHP execution blocked in wp-content/uploads
- `.user.ini` blocked from direct web access
- Credentials never committed (comprehensive .gitignore)

### Changed

- **Backup Strategy**: Replaced DO automated backups with volume-based skinny backups
  - 20% cost reduction on droplet billing
  - Faster backup/restore cycles
  - Portable backup format (tar.gz)

### Migrated From

- `/Users/nik/projects/burnedout.xyz` → `sites/burnedout-xyz/`
- `/Users/nik/projects/ptoken.agency` → `sites/ptoken-agency/`

### References

- D130: IaC Repo Consolidation
- D189: Stop DO Backups → Implement Skinny Backups
- Discovery #226: Wordfence WAF .user.ini for Caddy
- Discovery #275: Infisical Integration Pattern
