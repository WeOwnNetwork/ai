# i.MAIT.bot Changelog

## [Unreleased]

### Changed

- Keep git `imait-bot/` as shared gateway infrastructure. Teammates add **i.MAIT.bot** from the Buzz channel UI; do not pin channel UUIDs in git or `.env`.

### Added

- Initial standalone compose stack: Hermes Agent gateway (`imait-bot:8080`) + Caddy for `i.mait.bot`. Buzz community is chosen per instance via host `.env`.
- Image build compiles `buzz` CLI from pinned `block/buzz` so the Hermes Buzz adapter can load.
