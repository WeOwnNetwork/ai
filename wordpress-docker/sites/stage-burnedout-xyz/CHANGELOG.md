# stage-burnedout-xyz Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial deployment from wordpress-docker template
- Docker Compose stack (WordPress + MariaDB + Caddy)
- OpenTofu infrastructure provisioning
- DigitalOcean droplet with reserved IP
- DigitalOcean firewall rules
- Monitoring alerts (CPU, memory, disk, load)
- Wordfence WAF auto-configuration (.user.ini)
- Skinny backup system (database + wp-content only)
- Daily automated backup cron job
- 30-day backup retention
- Infisical secrets management integration

### Security

- TLS 1.3 via Caddy auto-HTTPS
- Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
- Blocked access to sensitive files (*.sql,*.log, wp-config.php)
- PHP execution blocked in uploads directory
- Wordfence WAF ready for activation
