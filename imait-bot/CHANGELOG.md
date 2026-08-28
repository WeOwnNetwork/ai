# i.MAIT.bot Changelog

## [Unreleased]

### Added

- Initial standalone compose stack: Hermes Agent gateway (`imait-bot:8080`) + Caddy for `i.mait.bot`, Buzz env targeting `wss://dev.weown.buzz`.
- Image build compiles `buzz` CLI from pinned `block/buzz` so the Hermes Buzz adapter can load.
