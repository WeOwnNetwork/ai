# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to #WeOwnVer (see ADR-005).

## [Unreleased]

### Added

- Initial ownCloud Infinite Scale (oCIS) deployment template
- Docker Compose setup with Caddy and oCIS (embedded LDAP, no PostgreSQL)
- OpenTofu infrastructure configuration for DigitalOcean droplets
- Ansible playbooks for server configuration
- Infisical secrets management integration (ADR-006 in-container injection)
- Backup and restore scripts with GFS retention
- Smoke test hooks for post-deployment validation
- Local development support
