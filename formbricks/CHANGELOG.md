# Formbricks Changelog

## [Unreleased]

### Added

- Initial Formbricks Docker Compose stack for `forms.weown.tools` (web + pgvector Postgres + Redis + Hub + Cube + Caddy), server-side secret generation via `scripts/deploy.sh`, and sanitized `.env.example`.

### Fixed

- Formbricks Next.js OOM on 2 GB droplets: raise app mem limit to 1400M and set `NODE_OPTIONS=--max-old-space-size=1024` (V8 otherwise caps heap at ~half the cgroup limit).
