# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial Keycloak SSO deployment template
- Docker Compose setup with Caddy, Keycloak, and PostgreSQL
- OpenTofu infrastructure configuration for DigitalOcean droplets
- Ansible playbooks for server configuration
- Infisical secrets management integration
- Backup and restore scripts
- Local development support

### Security
- Non-root container users
- Secrets managed via Infisical (not in git)
- Automatic TLS via Caddy/Let's Encrypt
- Firewall with restricted port access
- PostgreSQL VPC-only access

## [] - 
