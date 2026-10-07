# Changelog

> #WeOwnVer: v5.1.2.1 · Status: ACTIVE · Scope: the `weown-ci-runner` Gitea Actions runner

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [#WeOwnVer](../../../docs/VERSIONING_WEOWNVER.md).

## [Unreleased]

### Added

- Initial Gitea Actions runner template, with the Path C bootstrap cloned from `gitea-docker`
- `act_runner` + Docker-in-Docker sidecar; jobs never touch the host Docker
- One job per Docker-in-Docker daemon: `runner-cycle.sh` (a systemd service) destroys each
  job's daemon, volumes and certs before the next job, and loads the digest-pinned job image
- Exact image pins (`act_runner_image`, `dind_image`, `job_image`); Docker and the Infisical
  CLI installed from pinned, verified packages
- Admin-SSH-only firewall; the CIDRs and the VPC range are required tofu variables, never in git
- ADR-006 Infisical injection of `GITEA_RUNNER_REGISTRATION_TOKEN` (runner's own project),
  used once, at registration
- First-boot rotation that marks itself complete only when a login with the bootstrap
  secret is refused; a two-phase manual path (`rotate-mi-manual.sh`, then `--verify`)
- Metadata block for container traffic, proven at deploy with a forge control
- CPU, memory and process limits for dind and the runner
