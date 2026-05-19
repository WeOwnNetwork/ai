# wordpress-docker Changelog

All notable changes to this template will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](../docs/VERSIONING_WEOWNVER.md).

## [4.16.7.1] - 2026-04-20

### Added

- **Copier Template**: Complete templating system for generating new WordPress sites
  - `copier.yaml` with comprehensive configuration options
  - Domain style support: apex (example.com) or www (www.example.com)
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
- Blocked access to sensitive files (*.sql, *.log, *.bak, wp-config.php)
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
