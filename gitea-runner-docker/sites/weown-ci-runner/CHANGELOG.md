# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [#WeOwnVer](../docs/VERSIONING_WEOWNVER.md).

## [Unreleased]

### Added

- Initial Gitea Actions runner template, with the Path C bootstrap cloned from `gitea-docker`
- `act_runner` + Docker-in-Docker sidecar; jobs never touch the host Docker
- Exact image pins (`act_runner_image`, `dind_image`, `job_image`)
- Admin-SSH-only firewall; the CIDR is a required tofu variable, never in git
- ADR-006 Infisical injection of `GITEA_RUNNER_REGISTRATION_TOKEN` (runner's own project)
- Weekly prune of job images inside dind
