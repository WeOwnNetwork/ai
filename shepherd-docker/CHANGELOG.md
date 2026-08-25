# Shepherd Docker — Changelog

> #WeOwnVer: v4.3.5.1

## [Unreleased]

### Added

- **PRJ-435 POC stack (2026-08-25)** — `docker-compose.yml` + Caddy TLS for
  `shepherd.weown.tools`, persistent `shepherd_traces` / Caddy volumes, mock
  provider env, and a thin HTTP surface because upstream has no published web
  image. Public docs use `<DROPLET_PUBLIC_IP>` placeholders only.
