# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [#WeOwnVer](../../../docs/VERSIONING_WEOWNVER.md).

## [Unreleased]

### Added

- Initial Gitea deployment template (cloned from `keycloak-docker`)
- Docker Compose setup with Caddy, Gitea, and PostgreSQL
- Keycloak SSO via OIDC auth source; local registration disabled
- OpenTofu infrastructure configuration for DigitalOcean droplets
- Path C ansible app-layer playbook + Layer-2 bootstrap-secret rotation
- ADR-006 in-container Infisical runtime secret injection
- Backup and restore scripts (DB + `gitea_data` volume, DO Spaces offload)
- Local development support (`compose.local.yaml`, no Infisical)
- `terraform/itofu.sh` — weown-tofu shared-secrets wrapper (A405 pattern from `anythingllm-docker`)
- `ansible/harden.yml` — DevSec CIS-L1 host hardening play (os_hardening +
  ssh_hardening + Lynis measure), ported from `anythingllm-docker`

### Security

- **Hardening (weown-fleet#163 group 6).** Caddy serves TLS 1.3 only (a `tls` block
  with `protocols tls1.3`; certificates stay automatic). `ssh_source_cidrs`, which opens
  the admin sshd, is required: no default, and terraform and copier refuse 0.0.0.0/0 and
  ::/0 (the old default was the whole internet). The deploy play refuses a box that holds
  Gitea volumes under another project name, so a mismatched render can no longer start
  Gitea on new, empty volumes.
- **Manual MI rotation keeps the containers' auth copy in step (weown-fleet#163).** `scripts/rotate-mi-manual.sh` now also replaces the copy the containers read (written by the deploy), preparing both files before replacing either, so revoking v1 cannot strand a restarting container on it and a failed preparation changes nothing.
- **Bootstrap-secret rotation marks done only after v1 is proven revoked (weown-fleet#163).**
  The first-boot rotation wrote `.rotation-complete` even when it could not identify v1 or
  the revoke was not confirmed, and picked "the oldest active secret that is not v2" as v1,
  which revokes the wrong credential when another older secret is active. Ported from
  `gitea-runner-docker`: the marker is written only once a login with v1 (read back from the
  droplet's own user_data) answers 401 "Invalid credentials"; every other active client
  secret of the identity is revoked and recounted; secrets stay off argv. The proof uses the
  bootstrap client id and secret from user_data, and the marker records it (`v1-401 <time>`).
  `ansible/deploy.yml` refuses to deploy without that proof, so an empty marker written by the
  old script no longer passes. New `scripts/rotate-mi-manual.sh` and the README "Manual
  bootstrap-secret rotation" section (the log pointed at a section that did not exist); its
  `--verify` proves v1 dead on droplets built by the old script.
- Secrets managed via Infisical (not in git)
- Automatic TLS via Caddy/Let's Encrypt
- Firewall restricted to 80/443/22 + the git-over-SSH port
- PostgreSQL on the Compose network only (no published port, no firewall rule)

### Fixed

- Terraform state bucket → canonical `weown-prod-state` (was legacy `weown-terraform-state`)
- DO provider token variable renamed `minimus_token` → `do_token` (it is the DO API token, not the Minimus registry token)
- `ssh_key_fingerprints` list aligned to the shared `weown-tofu` `/infra/shared` contract

## [] -
