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

- **Backup and restore are consistent and recoverable (weown-fleet#163 group 4).**
  `backup.sh` stops Gitea while it dumps the database and copies the data volume, so
  the two match; a trap restarts it. `restore.sh` accepts only a name `backup.sh`
  produces and passes it to the root-run program as an argument (it was spliced into
  the program, so a crafted name could run commands); the program lands in a `mktemp`
  file instead of a fixed `/tmp` path. The archive is unpacked and checked while Gitea
  still serves; after the stop, the current database and data volume are copied, and a
  restore that fails part-way loads that copy back and restarts Gitea. The database load
  now stops on the first SQL error (`ON_ERROR_STOP`) instead of reporting success.
  Retention keeps a backup whose date does not parse (it read as epoch 0 and was
  deleted), and off-box (DO Spaces) copies get the same policy: reported by default,
  deleted only with `REMOTE_RETENTION=enforce`, newest 7 always kept.
- **Manual MI rotation keeps the containers' auth copy in step (weown-fleet#163).** `scripts/rotate-mi-manual.sh` now also replaces the copy the containers read (written by the deploy), preparing both files before replacing either, so revoking v1 cannot strand a restarting container on it and a failed preparation changes nothing.
- **Pinned installs (weown-fleet#163 group 3).** Cloud-init installs Docker from its
  signed apt repository (key fingerprint checked, exactly one primary key, versions pinned
  and held) instead of running `get.docker.com` as root, and the Infisical CLI from a
  release `.deb` checked against a pinned sha256 instead of `curl | bash`; both ported from
  `gitea-runner-docker`. The non-existent `awscli` apt package is gone: on Ubuntu 24.04 it
  failed the whole package step, so `jq` and `unzip` were never installed. Ansible
  collections are exact pins (community.docker 3.13.0, devsec.hardening 10.6.0); the
  unused community.general is dropped. Cloud-init changes apply on a rebuild only.
- **AWS CLI pinned (weown-fleet#163 group 3).** `ansible/deploy.yml` installs AWS CLI
  2.37.12 exactly, from AWS's versioned zip checked against a recorded sha256 (AWS's PGP
  signature was verified when the pin was taken), and moves a box on any other version to
  it. It installed whatever `awscli-exe-linux-x86_64.zip` was that day, unchecked.
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
- **Hardening (weown-fleet#163 group 6).** Caddy serves TLS 1.3 only (a `tls` block
  with `protocols tls1.3`; certificates stay automatic). `ssh_source_cidrs`, which opens
  the admin sshd, is a required tofu variable with no default (the old default was the
  whole internet); every entry must be a /24 or narrower (IPv6 /64), as in
  `gitea-runner-docker`. It is no longer a copier answer, so an admin CIDR never lands in
  a committed render. The deploy play refuses a box that holds
  Gitea volumes under another project name, so a mismatched render can no longer start
  Gitea on new, empty volumes.

### Fixed

- Terraform state bucket → canonical `weown-prod-state` (was legacy `weown-terraform-state`)
- DO provider token variable renamed `minimus_token` → `do_token` (it is the DO API token, not the Minimus registry token)
- `ssh_key_fingerprints` list aligned to the shared `weown-tofu` `/infra/shared` contract

## [] -
