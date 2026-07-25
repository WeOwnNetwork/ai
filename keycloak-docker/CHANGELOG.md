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
- `terraform/itofu.sh` — weown-tofu shared-secrets wrapper (A405 pattern from `anythingllm-docker`)
- `ansible/harden.yml` — DevSec CIS-L1 host hardening play (os_hardening +
  ssh_hardening + Lynis measure), ported from `anythingllm-docker`

### Fixed

- Keycloak 26 migration: image pinned 26.7.0 (24.0 tag no longer published), `KC_PROXY`->`KC_PROXY_HEADERS: xforwarded`, health on the :9000 management port (loopback publish + ansible probe + smoke check), tmpfs for the non-root resource cache, container healthcheck removed (image has no probe tooling)
- Production-proven fixes ported from the live deploys (2026-07-21..24): Caddyfile empty `tls {}` removed (did not parse; Caddy never listened) and dead admin vhost dropped; host CA bundle mounted for the Infisical CLI (containers crash-looped without it); Caddy log dir bind mount; headless `infisical login --plain` pattern (bare login hangs); backup/restore aligned to `POSTGRES_*` secret names and the canonical `weown-prod-backups` bucket; health-probe retries 20->40; entrypoint wrapper 0755 for non-root hardened images
- Terraform state bucket → canonical `weown-prod-state` (was legacy `weown-terraform-state`)
- DO provider token variable renamed `minimus_token` → `do_token` (it is the DO API token, not the Minimus registry token)
- `ssh_key_fingerprints` list aligned to the shared `weown-tofu` `/infra/shared` contract
